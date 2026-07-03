#!/usr/bin/env bash
# ccds-loops Stop hook — the "give Claude a check it can run" gate, packaged.
#
# Opt-in per project: create .claude/loop-gate.cmd containing ONE command line
# (e.g. "npm test -- --reporter dot" or "python3 -m pytest -q"). While the
# command fails, this hook blocks turn-end (exit 2) and feeds the failure back
# so the model keeps working; when it passes, the turn ends normally. Remove
# the file to disarm. Claude Code's built-in consecutive-block cap
# (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP, default 8) is the runaway backstop.
set -u

cat > /dev/null  # drain the hook's stdin JSON; the gate needs none of it

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
gate="$proj/.claude/loop-gate.cmd"
[[ -f "$gate" ]] || exit 0

cmd="$(head -n 1 "$gate" | tr -d '\r')"
[[ -n "$cmd" ]] || exit 0

out="$(cd "$proj" && bash -c "$cmd" 2>&1)"
status=$?
(( status == 0 )) && exit 0

{
    printf 'loop-gate: check failed (exit %s): %s\n' "$status" "$cmd"
    printf '%s\n' "$out" | tail -n 15
    printf 'The session cannot end while the gate fails (loop-verify: no done claims without fresh evidence). Fix the failure, or ask the user to remove .claude/loop-gate.cmd if the gate itself is wrong.\n'
} >&2
exit 2
