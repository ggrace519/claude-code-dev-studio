#!/usr/bin/env python3
"""
ccds-loops PreCompact hook — snapshot operational state before compaction.

Context compaction is where "where was I" gets lost. This hook writes a durable
snapshot to .claude/handoff.md just before the window is compacted, so the next
fresh/compacted context can rebuild its bearings from a file instead of from
faded memory. loop-long-horizon's bootstrap ritual reads it back.

Snapshot contents:
  - timestamp + compaction trigger (manual/auto)
  - the open loop cycle id (CCDS_LOOP_CYCLE env or .claude/loop-cycle marker)
  - the last N evidence artifacts (.claude/evidence/*.json) with their verdicts
  - `git status --short`
  - the last 5 commits (`git log --oneline -5`)

Always exit 0: a handoff writer must never block compaction. Best-effort — any
piece that can't be gathered is noted in the file rather than raising. The file
is hook-owned and overwritten each compaction (latest snapshot wins); it carries
no secrets (only cycle ids, verdicts, task labels, git metadata).
"""

import datetime
import glob
import json
import os
import subprocess
import sys

N_EVIDENCE = 5


def _project_dir(payload):
    return (os.environ.get("CLAUDE_PROJECT_DIR")
            or payload.get("cwd")
            or os.environ.get("PWD")
            or os.getcwd())


def _cycle_id(proj):
    env = os.environ.get("CCDS_LOOP_CYCLE", "").strip()
    if env:
        return env
    try:
        with open(os.path.join(proj, ".claude", "loop-cycle"), encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    return line.strip()
    except (OSError, UnicodeDecodeError):
        pass
    return None


def _git(proj, *args):
    try:
        r = subprocess.run(["git", *args], cwd=proj, capture_output=True,
                           text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return r.stdout.rstrip("\n")


def _recent_evidence(proj):
    ev_dir = os.path.join(proj, ".claude", "evidence")
    try:
        paths = glob.glob(os.path.join(ev_dir, "*.json"))
    except OSError:
        return []
    paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    rows = []
    for p in paths[:N_EVIDENCE]:
        try:
            with open(p, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError):
            rows.append((os.path.basename(p), "?", "(unreadable)", ""))
            continue
        if not isinstance(d, dict):
            d = {}
        rows.append((d.get("cycle_id") or os.path.basename(p),
                     d.get("verdict") or "?",
                     (d.get("task") or "").replace("\n", " ")[:100],
                     d.get("ts") or ""))
    return rows


def main():
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, ValueError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    proj = _project_dir(payload)
    trigger = payload.get("trigger", "unknown")
    now = datetime.datetime.now().isoformat(timespec="seconds")
    cycle = _cycle_id(proj)

    lines = []
    lines.append("# Loop handoff — auto-written by ccds-loops PreCompact hook")
    lines.append("")
    lines.append("_Do not edit by hand; overwritten on every compaction. The "
                 "loop-long-horizon bootstrap ritual reads this to rebuild "
                 "bearings after context loss._")
    lines.append("")
    lines.append("- **Written:** %s (compaction trigger: %s)" % (now, trigger))
    lines.append("- **Open cycle:** %s" % (cycle if cycle else "_none declared_"))
    lines.append("")

    lines.append("## Last %d evidence artifacts" % N_EVIDENCE)
    rows = _recent_evidence(proj)
    if rows:
        lines.append("")
        lines.append("| cycle_id | verdict | task | ts |")
        lines.append("|---|---|---|---|")
        for cid, verdict, task, ts in rows:
            lines.append("| %s | %s | %s | %s |" % (cid, verdict, task, ts))
    else:
        lines.append("")
        lines.append("_No evidence artifacts under `.claude/evidence/`._")
    lines.append("")

    lines.append("## git status --short")
    status = _git(proj, "status", "--short")
    lines.append("")
    if status is None:
        lines.append("```\n(not a git repo, or git unavailable)\n```")
    elif status == "":
        lines.append("```\n(clean)\n```")
    else:
        lines.append("```\n%s\n```" % status)
    lines.append("")

    lines.append("## Last 5 commits")
    log = _git(proj, "log", "--oneline", "-5")
    lines.append("")
    lines.append("```\n%s\n```" % (log if log else "(no commits, or git unavailable)"))
    lines.append("")

    out = os.path.join(proj, ".claude", "handoff.md")
    try:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines))
    except OSError as e:
        # never block compaction; surface the miss to the operator only
        sys.stderr.write("precompact-handoff: could not write %s (%s)\n" % (out, e))
    return 0


if __name__ == "__main__":
    sys.exit(main())
