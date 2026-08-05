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
the table tunes the guard without touching code. Checks that need path
resolution a regex cannot express live in CODE (lessons from three multi-model
review rounds, ADR-0012 addendum):
  - recursive force-delete outside the project: targets are resolved (quotes,
    ~/$HOME, relative paths, drive-absolute forms) against the project dir,
    with a realpath pass so an in-project symlink cannot smuggle the delete
    outside;
  - path normalization (`tests/fixtures/../../.env` must not slip through the
    fixtures exemption);
  - Grep glob expansion ({a,b} alternation and [xy] classes) joined with the
    search path, so globs selecting secret-shaped names are seen in context.

Decision paths, per the hooks reference (exit 2 + stderr blocks and stdout is
ignored; JSON needs exit 0):
  deny  -> exit 2, plain-language teaching message on stderr (fed to model).
  ask   -> exit 0, stdout JSON hookSpecificOutput.permissionDecision "ask";
           the reason is shown to the user in the permission prompt.
  allow -> exit 0, silent.

Charter (ADR-0012): protective only. Deny is reserved for actions with no
legitimate in-session form; anything a user might genuinely want asks instead.
Honest threat model: stops model mistakes and casual prompt injection, not a
determined adversary — shell quoting/interpolation, `$VAR` indirection, and
find/xargs-mediated deletes remain documented residual limitations. Fail-open
(with a stderr note when the rule table is empty): a guard that hard-fails
when its data breaks gets removed, not fixed. Kill switch:
CCDS_GUARD_DISABLE=1. Hooks fire for subagent tool calls too (verified live
2026-08-04), so domain agents cannot bypass this.
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

# Wrapper commands: when one of these leads a segment, `rm` may appear later
# in the argv (wrappers take their own flags/args: `sudo -u root rm ...`).
WRAPPERS = ("sudo", "env", "command", "nice", "ionice", "time", "nohup",
            "timeout", "xargs", "stdbuf", "doas")

# Segment command words whose arguments are text, not file access — exempt
# from the secret-token ask (echo .env >> .gitignore must stay silent), but
# NOT from the tamper ask (echo {} > .claude/settings.json must still ask).
TEXT_COMMANDS = ("echo", "printf", "export", "unset")

# Option prefixes whose =value names files to EXCLUDE, not open.
EXCLUDE_OPT_RE = re.compile(
    r"--(?:exclude|exclude-dir|exclude-from|ignore|ignore-pattern|filter)"
    r"(?:=\S+)?", re.IGNORECASE)

# Fallback prefixes treated as system territory when containment cannot
# decide. /tmp is deliberately absent: session scratch dirs live there.
SYSTEM_ROOTS = ("etc", "usr", "var", "opt", "home", "Users", "root",
                "srv", "boot", "dev", "bin", "sbin", "lib", "lib64", "mnt")

MAX_GLOB_EXPANSIONS = 16


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


def _isabs(path):
    """Absolute in the posix sense, or drive-absolute (C:/...)."""
    return posixpath.isabs(path) or bool(re.match(r"^[A-Za-z]:(/|$)", path))


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


def _segments(cmd):
    return re.split(r"[;|&\n]+", cmd)


def _seg_tokens(seg):
    return [t.strip("\"'`") for t in seg.split()]


def _match_any(rx_list, text):
    return any(rx.search(text) for rx, _ in rx_list)


def _tokens_for_scan(seg):
    """Path-ish tokens of one segment for rule matching: metachar-split,
    quote/glob-stripped, ./.. collapsed. Exclude-style options are blanked
    first — `--exclude=.env` names a file to skip, not to open."""
    cleaned = EXCLUDE_OPT_RE.sub(" ", seg)
    out = []
    for raw in re.split(r"[\s=<>|&;(){}]+", cleaned):
        tok = raw.strip("\"'`").rstrip("*?")
        if not tok:
            continue
        out.append(_norm(tok) if ("/" in tok or "\\" in tok) else tok)
    return out


def _find_rm(toks):
    """Index of the rm command word in a segment's tokens, or None.
    argv[0] may be rm, a path to rm (/bin/rm), or backslash-escaped (\\rm);
    when a known wrapper leads the segment, rm may appear anywhere later
    (wrappers take their own flags/args: sudo -u root rm ...). Leading
    VAR=val assignments are skipped. `git rm` never matches: git is not a
    wrapper, so only argv[0] is considered and it is not rm."""
    i = 0
    while i < len(toks) and "=" in toks[i]:
        i += 1
    if i >= len(toks):
        return None

    def is_rm(tok):
        return posixpath.basename(_norm(tok.lstrip("\\"))) == "rm"

    if is_rm(toks[i]):
        return i
    if toks[i] in WRAPPERS or posixpath.basename(_norm(toks[i])) in WRAPPERS:
        for j in range(i + 1, len(toks)):
            if is_rm(toks[j]):
                return j
    return None


def _rm_outside_project(cmd, payload):
    """Return (target, resolved) for a recursive force-delete whose target
    resolves outside the project dir (or IS the project root / home / system
    territory). Path logic, not regex; realpath guards symlink smuggling."""
    proj = _norm(_project_dir(payload))
    proj = proj.rstrip("/") or "/"
    cwd = _norm(payload.get("cwd") or proj)
    if not _isabs(cwd):
        cwd = proj if _isabs(proj) else cwd
    home = _norm(os.path.expanduser("~"))
    real_proj = _norm(os.path.realpath(proj)) if _isabs(proj) else proj

    def contained(path, root):
        return root != "/" and _isabs(root) and \
            (path + "/").startswith(root.rstrip("/") + "/")

    for seg in _segments(cmd):
        toks = _seg_tokens(seg)
        idx = _find_rm(toks)
        if idx is None:
            continue
        args = toks[idx + 1:]
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
                continue  # unresolvable variable: documented limitation
            resolved = _norm(t if _isabs(t) else posixpath.join(cwd, t))
            if not _isabs(resolved):
                continue  # cannot judge; give up on this target only

            is_proj_root = resolved == proj or resolved == real_proj
            if is_proj_root or resolved in ("/", home):
                return target, resolved  # wiping the project/home/root itself

            inside = contained(resolved, proj)
            if inside:
                # Lexically inside — but an intermediate symlink may point
                # elsewhere; realpath both sides before trusting it.
                real = _norm(os.path.realpath(resolved))
                if real == real_proj:
                    return target, real
                if contained(real, real_proj) or real.startswith("/tmp/"):
                    continue
                return target, real
            if resolved.startswith("/tmp/") or resolved == "/tmp":
                continue  # scratch space: agents clean up after themselves
            first = resolved.split("/")[1] if resolved.startswith("/") else ""
            drive_abs = bool(re.match(r"^[A-Za-z]:(/|$)", resolved))
            if (proj != "/" and _isabs(proj)) or first in SYSTEM_ROOTS \
                    or drive_abs:
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
    # normalized and allow-path exemptions apply; text-only commands (echo,
    # printf, export) skip the secret scan but never the tamper scan.
    secret_hit = tamper_hit = False
    for seg in _segments(cmd):
        toks = _seg_tokens(seg)
        i = 0
        while i < len(toks) and "=" in toks[i]:
            i += 1
        cmd_word = posixpath.basename(_norm(toks[i])) if i < len(toks) else ""
        text_only = cmd_word in TEXT_COMMANDS
        for tok in _tokens_for_scan(seg):
            if _match_any(rules["allow-path"], tok):
                continue
            if not secret_hit and not text_only \
                    and _match_any(rules["deny-path"], tok):
                secret_hit = True
            if not tamper_hit and _match_any(rules["ask-write-path"], tok):
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


def _expand_glob(glob):
    """Expand {a,b} alternation and [xy] classes into concrete variants,
    bounded; wildcards become path separators so fragments never glue into
    fake basenames (a*b*c.env stays suffix-matchable, never 'abc.env')."""
    variants = [glob]
    changed = True
    while changed and len(variants) <= MAX_GLOB_EXPANSIONS:
        changed = False
        nxt = []
        for v in variants:
            m = re.search(r"\{([^{}]*)\}", v)
            if m:
                for alt in m.group(1).split(","):
                    nxt.append(v[:m.start()] + alt + v[m.end():])
                changed = True
                continue
            m = re.search(r"\[([^\[\]]{1,6})\]", v)
            if m:
                for ch in m.group(1).lstrip("!^") or "?":
                    nxt.append(v[:m.start()] + ch + v[m.end():])
                changed = True
                continue
            nxt.append(v)
        variants = nxt[:MAX_GLOB_EXPANSIONS + 1]
    return [re.sub(r"[*?]+", "/", v) for v in variants[:MAX_GLOB_EXPANSIONS]]


def _guard_file(tool, tool_input, rules):
    path = (tool_input.get("file_path")
            or tool_input.get("notebook_path")
            or (tool_input.get("path") if tool == "Grep" else None))
    base = _norm(path) if isinstance(path, str) and path.strip() else None

    candidates = []
    if base:
        candidates.append(base)
    if tool == "Grep":
        # A directory passed without a trailing slash must still match dir
        # rules, and the glob param selects files just like path does — in
        # the CONTEXT of the search path, so fixture exemptions apply.
        if base:
            candidates.append(base + "/")
        glob = tool_input.get("glob")
        if isinstance(glob, str) and glob.strip():
            for variant in _expand_glob(glob):
                if not variant.strip("/"):
                    continue
                joined = posixpath.join(base, variant.lstrip("/")) if base \
                    else variant
                candidates.append(_norm(joined))
    if not candidates:
        return 0

    for cand in candidates:
        if _match_any(rules["allow-path"], cand):
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
