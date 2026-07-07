#!/usr/bin/env python3
"""
ccds-loops PreToolUse hook (matcher: Bash) — reversible-first risk guard.

Reads the tool-call JSON on stdin, matches the Bash command against a pattern
table (risk-deny-list.txt, shipped beside this script), and:

  deny hit -> exit 2: BLOCK the tool call, feed the reason back to the model.
  warn hit -> exit 1: NON-BLOCKING advisory to the operator; the call proceeds
              (the documented PreToolUse "other non-zero" path).
  otherwise -> exit 0: allow silently.

"Which file enforces this tomorrow?" — the deny-list is a file, and the guard
is model-agnostic: a silent model reroute changes nothing, because the block is
decided from the command text, not from the model's judgment.

The pattern table is DATA — edit risk-deny-list.txt to tune the guard; this
logic never changes. Deliberately small and high-signal: a backstop for
catastrophic, irreversible, whole-system / whole-database commands, not a linter
for ordinary risky work.

Fail-open: if the table is missing or unreadable, allow (exit 0). This is a
backstop layered on top of Claude Code's permission modes, not the sole guard;
a guard that hard-fails would block every command the moment its data file
breaks. A broken table is a config bug to fix, not a reason to freeze the shell.
"""

import json
import os
import re
import sys

RULES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "risk-deny-list.txt")


def _load_rules():
    """Return (deny_rules, warn_rules); each a list of (compiled_regex, label).
    Any unparseable line is skipped, not fatal."""
    deny, warn = [], []
    try:
        with open(RULES_FILE, encoding="utf-8") as f:
            lines = f.readlines()
    except (OSError, UnicodeDecodeError):
        return deny, warn
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        for prefix, bucket in (("deny:", deny), ("warn:", warn)):
            if line.startswith(prefix):
                body = line[len(prefix):].strip()
                # inline label after the first " # "
                label = ""
                if " # " in body:
                    body, label = body.split(" # ", 1)
                    body, label = body.strip(), label.strip()
                try:
                    bucket.append((re.compile(body, re.IGNORECASE), label or body))
                except re.error:
                    pass  # a bad pattern disables itself, never the whole guard
                break
    return deny, warn


def _command(payload):
    if payload.get("tool_name") not in (None, "Bash"):
        return None  # matcher should scope to Bash; stay inert otherwise
    ti = payload.get("tool_input") or {}
    cmd = ti.get("command")
    return cmd if isinstance(cmd, str) and cmd.strip() else None


def main():
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, ValueError):
        return 0  # malformed input: never block on our own parse failure
    if not isinstance(payload, dict):
        return 0

    cmd = _command(payload)
    if not cmd:
        return 0

    deny, warn = _load_rules()

    for rx, label in deny:
        if rx.search(cmd):
            sys.stderr.write(
                "risk-guard: BLOCKED — this command matches an irreversible / "
                "blast-radius rule (%s).\n"
                "Command: %s\n"
                "Reversible-first: do not run destructive whole-system or "
                "whole-database commands from the agent loop. If you truly "
                "intend this, hand the exact command to the operator to run "
                "themselves (e.g. a `! %s` line), and prefer a scoped, "
                "reversible alternative.\n" % (label, cmd.strip(), cmd.strip()))
            return 2

    hits = [label for rx, label in warn if rx.search(cmd)]
    if hits:
        sys.stderr.write(
            "risk-guard: WARN — wide blast radius (%s). The call is NOT "
            "blocked; proceeding. Confirm the host list and that the action is "
            "reversible per target before relying on the result.\n"
            % "; ".join(hits))
        return 1  # non-blocking: operator sees it, tool proceeds

    return 0


if __name__ == "__main__":
    sys.exit(main())
