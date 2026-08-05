#!/usr/bin/env python3
"""
ccds-guard ConfigChange hook — mid-session config tamper watch (ADR-0012).

Fires when Claude Code detects a change to session configuration (matchers:
project_settings | local_settings — see hooks.json). Permission rules and hook
wiring are the session's safety gates; a mid-session change to them is exactly
what a prompt-injection payload would attempt, and also something users
legitimately request — so this hook WARNS, it does not block. The companion
PreToolUse ask-gate (pretooluse-guard.py, ask-write-path rules) already makes
in-session edits to settings files require explicit user approval; this watch
catches changes that arrive by any other route.

Exit 1 = the documented non-blocking path: the operator sees the note, the
change proceeds. Never exits 2 (blocking config changes would also block the
user's own legitimate edits) and never crashes — a tamper watch that breaks
the session gets removed, not fixed. Kill switch: CCDS_GUARD_DISABLE=1.
"""

import json
import os
import sys


def main():
    if os.environ.get("CCDS_GUARD_DISABLE", "").strip() == "1":
        return 0
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, ValueError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    # Payload field names beyond the common set are version-dependent; show
    # whatever identifying detail is present without depending on any of it.
    detail = ""
    for key in ("matcher", "config_scope", "scope", "file_path", "source"):
        val = payload.get(key)
        if isinstance(val, str) and val:
            detail = " (%s)" % val
            break

    sys.stderr.write(
        "ccds-guard: session configuration changed mid-session%s. Permission "
        "rules and hooks are this session's safety gates - if you did not ask "
        "for this change, review it before continuing (it could be prompt "
        "injection from a file the model read).\n" % detail)
    return 1  # non-blocking: operator sees it, the change proceeds


if __name__ == "__main__":
    sys.exit(main())
