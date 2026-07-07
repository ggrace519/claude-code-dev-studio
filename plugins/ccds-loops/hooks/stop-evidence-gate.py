#!/usr/bin/env python3
"""
ccds-loops Stop hook — the delivery gate (evidence + verdict), python3.

Companion to stop-gate.sh. Where stop-gate.sh runs an arbitrary *command* and
blocks on its exit code, THIS gate enforces the loop-verify contract as a file
invariant: a tracked cycle may not end without a per-cycle evidence artifact
carrying an explicit PASS/FAIL verdict. "Which file enforces this tomorrow?" —
this one. A silent model reroute cannot satisfy it, because the proof lives in
`.claude/evidence/<cycle_id>.json`, not in the model's prose.

Opt-in / cycle-scoped (so it never blocks an ad-hoc session):
  ARMED when an open cycle id is resolvable, in order:
    1. env  CCDS_LOOP_CYCLE
    2. first non-empty line of  .claude/loop-cycle
  DISARMED (exit 0, no-op) when neither is present.

When armed, the gate requires  .claude/evidence/<cycle_id>.json  to:
  - exist and parse as JSON,
  - carry  verdict  in {PASS, FAIL},
  - carry  cycle_id  equal to the open cycle (a stale file from a different
    cycle must not satisfy the gate).
A FAIL verdict PASSES the gate on purpose: honestly recording a failure is
compliance; the anti-pattern this blocks is claiming done with no evidence at
all. Blocking on FAIL would only teach the model to omit the artifact.

Block == exit 2 with a message on stderr (fed back to the model, per the hooks
reference). Everything else == exit 0. Never raises: a gate that crashes is a
gate that's off.

Disarm entirely by removing .claude/loop-cycle and unsetting CCDS_LOOP_CYCLE.
"""

import json
import os
import sys

VALID_VERDICTS = ("PASS", "FAIL")


def _read_stdin_json():
    try:
        raw = sys.stdin.read()
    except Exception:
        return {}
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return {}


def _project_dir(payload):
    # Match stop-gate.sh: CLAUDE_PROJECT_DIR wins; then the Stop payload's cwd;
    # then PWD. All three are the same in normal runs.
    return (os.environ.get("CLAUDE_PROJECT_DIR")
            or payload.get("cwd")
            or os.environ.get("PWD")
            or os.getcwd())


def _resolve_cycle_id(proj):
    env = os.environ.get("CCDS_LOOP_CYCLE", "").strip()
    if env:
        return env
    marker = os.path.join(proj, ".claude", "loop-cycle")
    try:
        with open(marker, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    return line
    except (OSError, UnicodeDecodeError):
        pass
    return None


def _block(msg):
    sys.stderr.write(msg.rstrip("\n") + "\n")
    return 2


def main():
    payload = _read_stdin_json()
    proj = _project_dir(payload)

    cycle_id = _resolve_cycle_id(proj)
    if not cycle_id:
        return 0  # disarmed: not a tracked loop cycle

    evidence = os.path.join(proj, ".claude", "evidence", cycle_id + ".json")
    how = (
        "The delivery gate is armed for cycle '%s' but its evidence is not "
        "acceptable (loop-verify: no done without fresh proof). Write "
        "%s\ncontaining at least: "
        '{"cycle_id": "%s", "verdict": "PASS" or "FAIL", "task": "...", '
        '"proof": {...}, "agent": "..."}. A FAIL verdict is accepted — record '
        "the real outcome, don't omit it. To disarm the gate, remove "
        ".claude/loop-cycle (or unset CCDS_LOOP_CYCLE)."
    ) % (cycle_id, os.path.join(".claude", "evidence", cycle_id + ".json"), cycle_id)

    if not os.path.isfile(evidence):
        return _block("delivery-gate: no evidence artifact for cycle '%s'.\n%s"
                      % (cycle_id, how))

    try:
        with open(evidence, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as e:
        return _block("delivery-gate: evidence for cycle '%s' is unreadable/"
                      "invalid JSON (%s).\n%s" % (cycle_id, e, how))

    if not isinstance(data, dict):
        return _block("delivery-gate: evidence for cycle '%s' is not a JSON "
                      "object.\n%s" % (cycle_id, how))

    verdict = data.get("verdict")
    if verdict not in VALID_VERDICTS:
        return _block("delivery-gate: evidence for cycle '%s' lacks a valid "
                      "verdict field (got %r, need PASS or FAIL).\n%s"
                      % (cycle_id, verdict, how))

    file_cycle = data.get("cycle_id")
    if file_cycle != cycle_id:
        return _block("delivery-gate: evidence cycle_id %r does not match the "
                      "open cycle '%s' — a stale artifact cannot satisfy the "
                      "gate.\n%s" % (file_cycle, cycle_id, how))

    return 0  # evidence present, well-formed, verdict recorded: turn may end


if __name__ == "__main__":
    sys.exit(main())
