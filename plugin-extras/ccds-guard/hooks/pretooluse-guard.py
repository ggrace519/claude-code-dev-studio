#!/usr/bin/env python3
"""
ccds-guard PreToolUse hook — zero-config security guard (pipeline Gate 1).

One script, two matchers (see hooks.json):
  Bash                               -> dangerous-command deny, rm-outside-
                                        project deny (path logic, not regex),
                                        secret-path ask, config-tamper ask,
                                        package-install ask (slopsquatting)
  Read|Write|Edit|NotebookEdit|Grep  -> secret-path deny, config-tamper ask

Rules are DATA (guard-rules.txt beside this script, five categories); editing
the table tunes the guard without touching code. Two checks live in CODE, not
the table, because they need path resolution a regex cannot express (both
lessons from the round-2 multi-model review, ADR-0012 addendum):
  - recursive force-delete outside the project (rm -rf <target> where the
    resolved target is not under the project dir),
  - path normalization (`tests/fixtures/../../.env` must not slip through the
    fixtures exemption).

Decision paths, per the hooks reference (exit 2 + stderr blocks and stdout is
ignored; JSON needs exit 0):
  deny  -> exit 2, plain-language teaching message on stderr (fed to model).
  ask   -> exit 0, stdout JSON hookSpecificOutput.permissionDecision "ask";
           the reason is shown to the user in the permission prompt.
  allow -> exit 0, silent.

Charter (ADR-0012): protective only. Deny is reserved for actions with no
legitimate in-session form; anything a user might genuinely want asks instead.
Honest threat model: stops model mistakes and casual prompt injection, not a
determined adversary — shell quoting/interpolation remains the documented,
test-pinned limitation. Fail-open (with a stderr note when the rule table is
empty): a guard that hard-fails when its data breaks gets removed, not fixed.
Kill switch for operators: CCDS_GUARD_DISABLE=1. Hooks fire for subagent tool
calls too (verified live 2026-08-04), so domain agents cannot bypass this.
"""

import json
import os
import posixpath
import re
import sys

RULES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "guard-rules.txt")

FILE_TOOLS = ("Read", "Write", "Edit", "NotebookEdit", "Grep")
WRITE_TOOLS = ("Write", "Edit", "NotebookEdit")
CATEGORIES = ("allow-path", "deny-path", "ask-write-path",
              "deny-command", "ask-command")

# Wrappers to skip when locating the real command word of a shell segment.
WRAPPERS = ("sudo", "env", "command", "nice", "ionice", "time", "nohup")

# Fallback prefixes treated as system territory when no project dir is
# resolvable. /tmp is deliberately absent: session scratch dirs live there.
SYSTEM_ROOTS = ("etc", "usr", "var", "opt", "home", "Users", "root",
                "srv", "boot", "dev", "bin", "sbin", "lib", "lib64", "mnt")


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


def _norm(path):
    """Slash-normalize and collapse ./.. so traversal can't dodge the rules."""
    return posixpath.normpath(path.replace("\\", "/"))


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


def _project_dir(payload):
    return (os.environ.get("CLAUDE_PROJECT_DIR")
            or payload.get("cwd")
            or os.environ.get("PWD")
            or os.getcwd())


def _tokens(cmd):
    """Shell-ish tokens: split on whitespace and metacharacters, strip quotes
    and glob tails, collapse ./.. — best-effort, quoting stays out of scope."""
    out = []
    for raw in re.split(r"[\s=<>|&;(){}]+", cmd):
        tok = raw.strip("\"'`").rstrip("*?")
        if not tok:
            continue
        out.append(_norm(tok) if "/" in tok else tok)
    return out


def _rm_outside_project(cmd, payload):
    """Return (bad_target, resolved) for a recursive force-delete whose target
    resolves outside the project dir (or IS the project root/home/system).
    Path logic, not regex: quoted paths, /Users, /mnt, ../sibling all resolve."""
    proj = _norm(_project_dir(payload))
    cwd = _norm(payload.get("cwd") or proj)
    home = _norm(os.path.expanduser("~"))
    for seg in re.split(r"[;|&\n]+", cmd):
        toks = [t.strip("\"'`") for t in seg.split()]
        i = 0
        while i < len(toks) and toks[i] in WRAPPERS:
            i += 1
        if i >= len(toks) or toks[i] != "rm":
            continue  # `git rm` etc. never reaches here: token != "rm"
        args = toks[i + 1:]
        flags = [a for a in args if a.startswith("-")]
        recursive = any(re.match(r"-[a-z]*r", f, re.IGNORECASE)
                        or f == "--recursive" for f in flags)
        force = any(re.match(r"-[a-z]*f", f, re.IGNORECASE)
                    or f == "--force" for f in flags)
        if not (recursive and force):
            continue
        for target in (a for a in args if a and not a.startswith("-")):
            t = target.rstrip("*?") or "."
            if t.startswith("~"):
                t = home + t[1:]
            elif t.startswith("$HOME"):
                t = home + t[len("$HOME"):]
            if "$" in t:
                continue  # unresolvable variable: quoting limitation applies
            resolved = _norm(t if posixpath.isabs(t)
                             else posixpath.join(cwd, t))
            if resolved.startswith("/tmp/") or resolved == "/tmp":
                continue  # scratch space: agents clean up after themselves
            inside = (resolved + "/").startswith(proj.rstrip("/") + "/")
            is_proj_root = resolved == proj.rstrip("/")
            if inside and not is_proj_root:
                continue
            if not posixpath.isabs(resolved):
                continue
            first = resolved.split("/")[1] if "/" in resolved else ""
            if (is_proj_root or resolved in ("/", home)
                    or not inside and (proj != "." and proj)
                    or first in SYSTEM_ROOTS):
                return target, resolved
    return None


def _guard_bash(cmd, payload, rules):
    for rx, label in rules["deny-command"]:
        if rx.search(cmd):
            return _deny(
                "ccds-guard: BLOCKED — this command is on the security deny "
                "list.\nWhy: %s.\nCommand: %s\nUse a safer form, or if this "
                "is genuinely intended, the operator can run it themselves. "
                "Persistent false positive? The operator can tune "
                "guard-rules.txt in the ccds-guard plugin." % (label, cmd.strip()))

    hit = _rm_outside_project(cmd, payload)
    if hit:
        target, resolved = hit
        return _deny(
            "ccds-guard: BLOCKED — recursive force-delete outside the "
            "project.\nTarget: %s (resolves to %s; project is %s)\nDeleting "
            "outside the project from the agent loop is irreversible blast "
            "radius. If you truly intend this, the operator runs it "
            "themselves. Inside-project and /tmp deletes are not blocked."
            % (target, resolved, _norm(_project_dir(payload))))

    reasons = [label for rx, label in rules["ask-command"] if rx.search(cmd)]

    # Secret-bearing or gate-bearing paths referenced in a shell command:
    # ask, don't deny — `cp .env.example .env` and `source .env` have
    # legitimate uses, but the user should knowingly approve them. Tokens are
    # normalized (quotes, glob tails, ./..) and allow-path exemptions apply,
    # so `cat .env.example` and fixtures stay silent.
    secret_hit = tamper_hit = False
    for tok in _tokens(cmd):
        if any(rx.search(tok) for rx, _ in rules["allow-path"]):
            continue
        if not secret_hit and any(rx.search(tok)
                                  for rx, _ in rules["deny-path"]):
            secret_hit = True
        if not tamper_hit and any(rx.search(tok)
                                  for rx, _ in rules["ask-write-path"]):
            tamper_hit = True
    if secret_hit:
        reasons.append(
            "this command touches a file that may hold secrets; approve only "
            "if you expect that - secrets a model reads can end up in logs "
            "or transcripts")
    if tamper_hit:
        reasons.append(
            "this command touches session-safety configuration (settings, "
            "hooks, or guard rules) - confirm you asked for this change")
    if reasons:
        return _ask(reasons)
    return 0


def _guard_file(tool, tool_input, rules):
    path = (tool_input.get("file_path")
            or tool_input.get("notebook_path")
            or (tool_input.get("path") if tool == "Grep" else None))
    candidates = []
    if isinstance(path, str) and path.strip():
        candidates.append(_norm(path))
    if tool == "Grep":
        # A directory passed without a trailing slash must still match dir
        # rules, and the glob param selects files just like path does.
        if candidates:
            candidates.append(candidates[0] + "/")
        glob = tool_input.get("glob")
        if isinstance(glob, str) and glob.strip():
            bare = glob.replace("*", "").replace("?", "").replace("[", "") \
                       .replace("]", "")
            if bare.strip("/"):
                candidates.append(_norm(bare))
    if not candidates:
        return 0

    for cand in candidates:
        if any(rx.search(cand) for rx, _ in rules["allow-path"]):
            continue
        for rx, label in rules["deny-path"]:
            if rx.search(cand):
                return _deny(
                    "ccds-guard: BLOCKED — %s looks like a secrets file/"
                    "location (%s).\nAPI keys, passwords, and private keys "
                    "must never enter the model's context: anything it reads "
                    "can end up in transcripts or logs. If a value from it is "
                    "needed, the operator opens it in their own editor; to "
                    "bootstrap config, copy the template (cp .env.example "
                    ".env) yourself. Persistent false positive? The operator "
                    "can tune guard-rules.txt in the ccds-guard plugin."
                    % (cand, label))
    if tool in WRITE_TOOLS:
        reasons = []
        for cand in candidates:
            reasons += [label for rx, label in rules["ask-write-path"]
                        if rx.search(cand)]
        if reasons:
            return _ask(sorted(set(reasons)))
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
    if not any(rules.values()) and tool in ("Bash",) + FILE_TOOLS:
        # Fail-open, but never silently: an empty table means the guard is
        # inert, and the operator should know (stderr on exit 0 = non-blocking).
        sys.stderr.write("ccds-guard: guard-rules.txt is missing or empty — "
                         "the guard is currently inert. Reinstall the "
                         "ccds-guard plugin or restore the rules file.\n")

    if tool == "Bash":
        cmd = tool_input.get("command")
        if isinstance(cmd, str) and cmd.strip():
            return _guard_bash(cmd, payload, rules)
        return 0

    if tool in FILE_TOOLS:
        return _guard_file(tool, tool_input, rules)

    return 0


if __name__ == "__main__":
    sys.exit(main())
