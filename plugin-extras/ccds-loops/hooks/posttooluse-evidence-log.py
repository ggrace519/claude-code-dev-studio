#!/usr/bin/env python3
"""
ccds-loops PostToolUse hook (matcher: Write|Edit) — evidence sink, durable tier.

Fires only when a Write/Edit just touched a fast-tier evidence artifact
(.claude/evidence/<cycle_id>.json). For those, it does three things:

  1. VALIDATE the JSON shape (object, verdict in {PASS,FAIL}, cycle_id present).
     Malformed -> exit 2 so the model fixes it before the delivery gate rejects
     it at turn-end.
  2. SECRET-SCAN the artifact. Evidence is proof text, never credentials; a
     high-confidence secret pattern -> exit 2 telling the model to strip it.
     ("Verify nothing sensitive lands in .claude/evidence" — enforced here, at
     the write point.)
  3. MIRROR to Postgres for cross-session failure analysis — OPTIONAL and
     best-effort. No-op unless CCDS_EVIDENCE_DSN is set AND psql is on PATH.
     Values go in via psql's :'var' quoting (injection-safe); the DDL in
     agent-evidence.sql runs idempotently so the table self-provisions.

Exit codes: 2 only for a problem the model should fix (bad shape / secret).
A Postgres outage never blocks the turn — the durable tier is a convenience on
top of the local files, so mirror failures exit 0 with an operator note.
Non-evidence writes exit 0 immediately.

Model-agnostic, secrets via env only, stack-agnostic when the DSN is unset.
"""

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DDL_FILE = os.path.join(HERE, "agent-evidence.sql")
VALID_VERDICTS = ("PASS", "FAIL")

# High-confidence secret shapes only — evidence "proof" legitimately mentions
# words like "token count", so generic password=/token= matching is omitted to
# avoid false positives; these patterns don't occur in honest test output.
SECRET_PATTERNS = [
    (re.compile(r"sk-[A-Za-z0-9]{20,}"), "OpenAI-style API key"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS access key id"),
    (re.compile(r"ghp_[A-Za-z0-9]{20,}"), "GitHub personal access token"),
    (re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"), "Slack token"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "PEM private key"),
    (re.compile(r"[a-z]+://[^/\s:@]+:[^/\s:@]+@"), "URL with inline credentials"),
]

INSERT_SQL = (
    "INSERT INTO agent_evidence (cycle_id, ts, task, verdict, proof, agent) "
    "SELECT x->>'cycle_id', now(), x->>'task', x->>'verdict', "
    "COALESCE(x->'proof', '{}'::jsonb), x->>'agent' "
    "FROM (SELECT :'ev'::jsonb AS x) s;"
)


def _is_evidence_path(file_path):
    if not isinstance(file_path, str):
        return False
    norm = file_path.replace("\\", "/")
    return "/.claude/evidence/" in norm and norm.endswith(".json")


def _block(msg):
    sys.stderr.write(msg.rstrip("\n") + "\n")
    return 2


def _mirror_to_postgres(record):
    """Best-effort durable mirror. Returns a note string, or None on no-op."""
    dsn = os.environ.get("CCDS_EVIDENCE_DSN", "").strip()
    if not dsn:
        return None
    # CCDS_EVIDENCE_PSQL overrides how psql is invoked — a full command line,
    # not just a path, so a wrapper or an interpreter works. Real need: psql is
    # often not on PATH under that exact name (versioned installs, Windows
    # installs under Program Files). Also the test seam, same data-not-logic
    # pattern as CCDS_GUARD_ADJUDICATOR_CMD.
    #
    # Resolve once and invoke the resolved path. A bare "psql" handed to
    # subprocess on Windows goes through CreateProcess, which finds only .exe —
    # a psql shipped as .cmd/.bat is found by which() and then fails to start.
    override = os.environ.get("CCDS_EVIDENCE_PSQL", "").strip()
    if override:
        # posix=False keeps Windows backslashes intact; strip one quote pair so
        # a quoted path does not arrive with its quotes attached.
        parts = shlex.split(override, posix=(os.name != "nt"))
        psql_cmd = [p[1:-1] if len(p) >= 2 and p[0] == p[-1] and p[0] in "\"'"
                    else p for p in parts]
    else:
        resolved = shutil.which("psql")
        if not resolved:
            return "durable tier: psql not on PATH; skipped Postgres mirror"
        psql_cmd = [resolved]
    try:
        with open(DDL_FILE, encoding="utf-8") as f:
            ddl = f.read()
    except OSError:
        ddl = ""  # fall back to insert-only; table may already exist
    ev_json = json.dumps(record, separators=(",", ":"))
    try:
        r = subprocess.run(
            psql_cmd + [dsn, "-v", "ON_ERROR_STOP=1", "-q",
             "--set", "ev=" + ev_json, "-c", ddl + "\n" + INSERT_SQL],
            capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError) as e:
        return "durable tier: psql invocation failed (%s)" % e
    if r.returncode != 0:
        return "durable tier: Postgres mirror failed: " + r.stderr.strip()[:200]
    return None  # success, quiet


def main():
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict):
        return 0

    file_path = (payload.get("tool_input") or {}).get("file_path", "")
    if not _is_evidence_path(file_path):
        return 0  # not an evidence artifact: stay inert

    # Read what actually landed on disk (the source of truth for both tiers).
    try:
        with open(file_path, encoding="utf-8") as f:
            body = f.read()
    except (OSError, UnicodeDecodeError):
        return 0  # can't read it (e.g. deleted); the delivery gate will catch absence

    try:
        data = json.loads(body)
    except (json.JSONDecodeError, ValueError):
        return _block("evidence-log: %s is not valid JSON. The delivery gate "
                      "needs a parseable artifact with a PASS/FAIL verdict."
                      % file_path)

    if not isinstance(data, dict):
        return _block("evidence-log: %s must be a JSON object." % file_path)

    if data.get("verdict") not in VALID_VERDICTS:
        return _block("evidence-log: %s lacks a valid verdict (need PASS or "
                      "FAIL). Fix it before the delivery gate rejects it."
                      % file_path)
    if not data.get("cycle_id"):
        return _block("evidence-log: %s is missing cycle_id." % file_path)

    for rx, label in SECRET_PATTERNS:
        if rx.search(body):
            return _block(
                "evidence-log: %s appears to contain a secret (%s). Evidence "
                "is proof, never credentials — remove it from the artifact "
                "(keep counts/commands/paths, drop tokens/keys)." % (file_path, label))

    note = _mirror_to_postgres(data)
    if note:
        sys.stderr.write("evidence-log: " + note + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
