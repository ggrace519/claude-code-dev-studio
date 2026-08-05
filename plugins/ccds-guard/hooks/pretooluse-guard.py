#!/usr/bin/env python3
"""
ccds-guard PreToolUse hook — zero-config security guard (pipeline Gate 1).

One script, two matchers (see hooks.json):
  Bash                          -> dangerous-command deny, secret-path ask,
                                   package-install ask (slopsquatting)
  Read|Write|Edit|NotebookEdit  -> secret-path deny, config-tamper ask

Rules are DATA (guard-rules.txt beside this script, five categories); editing
the table tunes the guard without touching code. Decision paths, per the hooks
reference (exit 2 + stderr blocks and stdout is ignored; JSON needs exit 0):

  deny  -> exit 2, plain-language teaching message on stderr (fed to model).
  ask   -> exit 0, stdout JSON hookSpecificOutput.permissionDecision "ask";
           the reason is shown to the user in the permission prompt.
  allow -> exit 0, silent.

Charter (ADR-0012): protective only, so projects built by people who configure
nothing still refuse to leak secrets, pipe downloads into shells, or install
hallucinated packages. Deny is reserved for actions with no legitimate
in-session form; anything a user might genuinely want asks instead — every
false positive that blocks outright teaches users to uninstall the guard.

Honest threat model: this stops model mistakes and casual prompt injection,
not a determined adversary. The hard boundary is Claude Code's permission
modes + environment; the Gate-2 settings template mirrors the secret-path
denies as harness-enforced permission rules with no runtime dependency.

Fail-open: malformed stdin, unreadable rules, or an unparseable pattern never
block (a guard that hard-fails when its data breaks gets removed, not fixed).
Kill switch for operators: CCDS_GUARD_DISABLE=1 in the session environment.
Hooks fire for subagent tool calls too (verified live 2026-08-04), so domain
agents cannot bypass this guard.
"""

import json
import os
import re
import sys

RULES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "guard-rules.txt")

FILE_TOOLS = ("Read", "Write", "Edit", "NotebookEdit", "Grep")
WRITE_TOOLS = ("Write", "Edit", "NotebookEdit")
CATEGORIES = ("allow-path", "deny-path", "ask-write-path",
              "deny-command", "ask-command")


def _load_rules():
    """Return {category: [(compiled_regex, label), ...]}.
    Unparseable lines/patterns are skipped, never fatal."""
    rules = {c: [] for c in CATEGORIES}
    try:
        with open(RULES_FILE, encoding="utf-8") as f:
            lines = f.readlines()
    except (OSError, UnicodeDecodeError):
        return rules
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        for cat in CATEGORIES:
            prefix = cat + ":"
            if line.startswith(prefix):
                body = line[len(prefix):].strip()
                label = ""
                if " # " in body:
                    body, label = body.split(" # ", 1)
                    body, label = body.strip(), label.strip()
                try:
                    rules[cat].append((re.compile(body, re.IGNORECASE),
                                       label or body))
                except re.error:
                    pass  # a bad pattern disables itself, never the guard
                break
    return rules


def _ask(reasons):
    """Exit-0 JSON path: surface a permission prompt with a teaching reason."""
    sys.stdout.write(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": "ccds-guard: " + " | ".join(reasons),
        }
    }))
    return 0


def _deny(msg):
    sys.stderr.write(msg.rstrip("\n") + "\n")
    return 2


def _guard_bash(cmd, rules):
    for rx, label in rules["deny-command"]:
        if rx.search(cmd):
            return _deny(
                "ccds-guard: BLOCKED — this command is on the security deny "
                "list.\nWhy: %s.\nCommand: %s\nUse a safer form, or if this "
                "is genuinely intended, the operator can run it themselves. "
                "Persistent false positive? The operator can tune "
                "guard-rules.txt in the ccds-guard plugin." % (label, cmd.strip()))

    reasons = [label for rx, label in rules["ask-command"] if rx.search(cmd)]
    # Secret-bearing paths referenced in a shell command: ask, don't deny —
    # `cp .env.example .env` and `source .env` have legitimate uses, but the
    # user should knowingly approve anything that touches a secrets file.
    # Path rules are anchored for file paths, so match them per shell token
    # (`cat .env` puts the path after a space, not a slash). Split on shell
    # metacharacters too — `cat<.env` and `cat .env|grep` glue the path to
    # the operator.
    tokens = [t.strip("\"'`") for t in re.split(r"[\s=<>|&;(){}]+", cmd)]
    if any(rx.search(tok) for tok in tokens if tok
           for rx, _ in rules["deny-path"]):
        reasons.append(
            "this command touches a file that may hold secrets; approve only "
            "if you expect that - secrets a model reads can end up in logs "
            "or transcripts")
    if reasons:
        return _ask(reasons)
    return 0


def _guard_file(tool, path, rules):
    norm = path.replace("\\", "/")
    for rx, _ in rules["allow-path"]:
        if rx.search(norm):
            return 0
    for rx, label in rules["deny-path"]:
        if rx.search(norm):
            return _deny(
                "ccds-guard: BLOCKED — %s looks like a secrets file (%s).\n"
                "API keys, passwords, and private keys must never enter the "
                "model's context: anything it reads can end up in transcripts "
                "or logs. If a value from this file is needed, the operator "
                "opens it in their own editor; to bootstrap config, copy the "
                "template (cp .env.example .env) yourself. Persistent false "
                "positive? The operator can tune guard-rules.txt in the "
                "ccds-guard plugin." % (norm, label))
    if tool in WRITE_TOOLS:
        reasons = [label for rx, label in rules["ask-write-path"]
                   if rx.search(norm)]
        if reasons:
            return _ask(reasons)
    return 0


def main():
    if os.environ.get("CCDS_GUARD_DISABLE", "").strip() == "1":
        return 0
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, ValueError):
        return 0  # malformed input: never block on our own parse failure
    if not isinstance(payload, dict):
        return 0

    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return 0
    rules = _load_rules()

    if tool == "Bash":
        cmd = tool_input.get("command")
        if isinstance(cmd, str) and cmd.strip():
            return _guard_bash(cmd, rules)
        return 0

    if tool in FILE_TOOLS:
        # Grep is read-shaped: its `path` param pointed at a secrets file
        # would pull matching lines into context just like Read would.
        path = (tool_input.get("file_path")
                or tool_input.get("notebook_path")
                or (tool_input.get("path") if tool == "Grep" else None))
        if isinstance(path, str) and path.strip():
            return _guard_file(tool, path, rules)
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
