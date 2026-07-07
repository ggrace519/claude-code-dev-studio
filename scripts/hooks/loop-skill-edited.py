#!/usr/bin/env python3
"""
PostToolUse hook: fire the release-cadence reminder when loop-* wording changes.

The loop-* process skills have two enforcement layers: structural rules are
lint-enforced (check 9), but the LIVE compliance baseline (6/6 scenarios,
eval-loop-compliance.py) is a measured property of the wording and silently
goes stale the moment the wording changes. This hook makes the trigger
deterministic instead of a habit — the loop-compound escalation ratchet applied
to our own process ("third occurrence: promote the prose rule to a hook").

Wired in .claude/settings.json (repo-level, PostToolUse on Edit|Write). Reads
the hook JSON on stdin; if the edited file is a loop-* skill body or one of the
PROMPT-template sources, injects the reminder as additionalContext. Exit 0
always — this is a tripwire, not a gate.
"""

import json
import sys

# Files whose wording the live compliance baseline actually measures. The eval
# injects ONLY loop-* SKILL.md bodies (not their bundled references), plus the
# scenario prompts. So a reference-only edit (references/*.md) is not a baseline
# change and must not trip the reminder.
def _measured(norm):
    if "skills/loop-" in norm and norm.endswith("SKILL.md"):
        return True                    # a loop-* SKILL.md body
    if "evals/loop-compliance/" in norm:
        return True                    # scenario wording is half the measurement
    return False

def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # malformed input: stay silent, never break the edit
    path = (payload.get("tool_input") or {}).get("file_path", "") or ""
    norm = path.replace("\\", "/")
    if not _measured(norm):
        return 0
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": (
                "loop-* wording changed (" + norm + "). The live compliance "
                "baseline is now unmeasured for this wording. Before the next "
                "release: run `python3 scripts/eval-loop-compliance.py "
                "--votes 3 --model haiku` (spends ~18 API calls; release-time "
                "cadence, not per-edit) and record the result. Structural "
                "rules are covered by lint check 9; this reminder exists "
                "because the live baseline is not."
            ),
        }
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
