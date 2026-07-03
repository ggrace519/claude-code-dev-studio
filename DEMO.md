# DEMO — innovation/loop-init-scaffolder

Proposal #3 from `INNOVATIONS.md` (2026-07-03, on branch
`innovation/loop-skills-pack`): `ccds loop init` — one command that scaffolds the
long-horizon loop state-file kit the `loop-long-horizon` skill teaches.

## What works

- `ccds loop init [--target <path>] [--dry-run]` creates `./.loop/` with
  `feature_list.json` (sample entry, `"passes": false`), `progress.md` (append-only
  log with entry template), `PROMPT.md` (one-task rule + `ALL FEATURES COMPLETE`
  completion promise), and an `init.sh` health-check stub (deliberately `exit 1`
  until the user fills in real build/smoke commands).
- Prints the capped while-loop one-liner and the `/ralph-loop` equivalent, with the
  sandbox warning.
- Refuses to overwrite an existing `.loop/` (exit 2); `--dry-run` writes nothing;
  unknown subcommands error cleanly. Shell completion knows `loop` / `init`.

## How to try it

```bash
bash bin/ccds.sh loop init --target /tmp/some-project && ls /tmp/some-project/.loop
python3 -m pytest tests/ -q     # 19 passed (4 new TestLoopInit cases)
bash -n bin/ccds.sh             # syntax-clean (ShellCheck runs in CI)
```

All of the above verified on this branch (create / refuse / dry-run / bad-subcommand
each exercised against a scratch directory).

## What's stubbed / not included

- PowerShell twin (`ccds.ps1`) — follows the repo's bash-first convention for new
  subcommands; noted for a follow-up.
- Independent of the `innovation/loop-skills-pack` branch: the command works without
  the skill pack (it references the skill by name in output text only). Both
  branches add a `## Unreleased` changelog entry — trivial merge overlap.

## Next increment

PowerShell `cmd_loop` twin, and `ccds loop status` (summarize `feature_list.json`
pass counts + last progress entry).
