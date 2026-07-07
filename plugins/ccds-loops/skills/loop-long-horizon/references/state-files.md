# Long-Horizon State-File Templates

Copy-paste starting points for the `loop-long-horizon` kit. Keep them in a `.loop/`
directory at the project root (or the repo root itself for a Ralph-style run — either
way, commit them: git history is part of the loop's memory).

## feature_list.json

Every unit of work, exhaustively, before the first iteration. JSON deliberately —
models corrupt structured JSON far less readily than Markdown plans. Only two fields
are load-bearing: a stable `id` and `passes`.

```json
{
  "features": [
    {
      "id": "auth-login",
      "description": "Users can log in with email + password; wrong password shows an error without revealing which field was wrong",
      "verify": "npm test -- auth && curl -sf localhost:3000/login",
      "priority": 1,
      "passes": false
    },
    {
      "id": "auth-reset",
      "description": "Password reset flow end-to-end: request, email link (mailhog in dev), new password accepted",
      "verify": "npm test -- reset",
      "priority": 2,
      "passes": false
    }
  ]
}
```

Rules: flip `"passes": true` only with fresh evidence from the `verify` command; never
delete entries (mark obsolete ones `"passes": true` with a note in progress.md); new
discoveries get appended, not squeezed into existing entries.

## progress.md

Append-only. One entry per iteration, newest last so the file reads chronologically:

```markdown
## 2026-07-03 · iteration 14 · auth-login
- Done: login endpoint + session cookie; 9/9 auth tests pass (`npm test -- auth`)
- Why it took a detour: bcrypt cost 12 blew the test timeout — pinned to 4 in test env
- Next: auth-reset; note mailhog must be up (`docker compose up -d mailhog`)
```

The **why** line is the valuable one — it is what stops the next iteration from
re-walking this iteration's dead ends.

## init.sh

One command that proves the project still *runs* — build alone is not enough:

```bash
#!/usr/bin/env bash
set -euo pipefail
npm run build
npm test -- --reporter dot
# smoke: the app actually serves
npm start & APP=$!; sleep 2
curl -sf http://localhost:3000/health
kill "$APP"
echo "init: OK"
```

## PROMPT.md (unattended runs)

The per-iteration instructions. Rebuild it whenever the loop drifts — drift is a
prompt bug, not a code bug.

```markdown
Work on the project in this directory. THE ONE UNBREAKABLE RULE: exactly ONE
feature this run. Finishing early does not earn a second one.

1. Read .loop/progress.md and .loop/feature_list.json (and .claude/handoff.md
   if it exists — the PreCompact snapshot of the open cycle, recent evidence
   verdicts, and git state). Run .loop/init.sh; if it fails, fixing it is this
   iteration's ONLY task.
2. Pick the ONE highest-priority feature with "passes": false. That id is
   the only feature you may touch this run. Search the codebase first — do
   not re-implement something that exists.
3. Implement it COMPLETELY. No placeholders, no stubs, no simplified
   versions. A stub that compiles is a failure, not progress.
4. Run the feature's verify command and read the output. Only then set
   "passes": true.
5. Append an entry (what / why / next) to .loop/progress.md. Commit with a
   message naming the feature id.
6. STOP. If other features remain "passes": false, do NOT start one — not
   even a small one; the loop runs again with fresh context. End your reply
   with exactly: ITERATION DONE
7. Only if EVERY feature now has "passes": true, output exactly:
   ALL FEATURES COMPLETE
```

Live datapoint (2026-07-03, haiku): with the softer "Do not start a second
feature" buried at step 6, the model completed two features in one run. The
bright-line header plus an explicit STOP step with its own end-of-reply
sentinel is the fix — the same lesson as the iron-law rule: wording is what
holds under pressure.

## Running the loop

Plain shell (cap the iterations — never unbounded):

```bash
for i in $(seq 1 40); do
  cat .loop/PROMPT.md | claude -p --dangerously-skip-permissions && \
    grep -q '"passes": false' .loop/feature_list.json || break
done
```

Or Claude Code's official ralph-wiggum plugin, which drives the same shape with a
Stop hook:

```
/ralph-loop "$(cat .loop/PROMPT.md)" --max-iterations 40 --completion-promise "ALL FEATURES COMPLETE"
```

`--dangerously-skip-permissions` means what it says: unattended runs belong in a
sandbox (container, throwaway VM, or at minimum a dedicated worktree with nothing
secret in reach), never on a machine whose files you can't afford to lose.
