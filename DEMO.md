# DEMO — innovation/loop-hooks (stacked on innovation/loop-skills-pack)

Proposal #2 from `INNOVATIONS.md` (2026-07-03): make the loop skills mandatory
instead of advisory — hooks in the `ccds-loops` plugin.

Stacks on `innovation/loop-skills-pack`; merge the pack first.

## What works

- **SessionStart hook** (`startup|clear|compact`): injects a compact loop index into
  context — which loop is non-optional in which situation, plus how to arm the stop
  gate. Injected bootstrap, not routing luck (the superpowers load-bearing trick).
- **Stop gate** (opt-in per project): put one command in `.claude/loop-gate.cmd`
  (e.g. `npm test -- --reporter dot`) and the session cannot end while it fails —
  exit-2 block with the failure tail fed back to the model. No gate file = no-op.
  Only the first line of the file is executed. Claude Code's built-in
  consecutive-block cap (default 8, `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`) is the
  runaway backstop.
- **`plugin-extras/` mechanism** in `build-marketplace.py`: hand-authored plugin
  components survive the `plugins/` regeneration (copied verbatim per plugin).
- Hook JSON format verified against current docs (hooks.json at plugin root,
  `${CLAUDE_PLUGIN_ROOT}` command paths, plain-stdout context injection, exit-2
  Stop blocking).

## How to try it

```bash
python3 -m pytest tests/ -q     # 23 passed (6 new hook/behavior cases)
python3 scripts/lint-playbook.py

# behavioral, by hand:
bash plugins/ccds-loops/hooks/session-start.sh
mkdir -p /tmp/p/.claude && echo false > /tmp/p/.claude/loop-gate.cmd
echo '{}' | CLAUDE_PROJECT_DIR=/tmp/p bash plugins/ccds-loops/hooks/stop-gate.sh; echo $?   # 2 (blocks)
echo true > /tmp/p/.claude/loop-gate.cmd
echo '{}' | CLAUDE_PROJECT_DIR=/tmp/p bash plugins/ccds-loops/hooks/stop-gate.sh; echo $?   # 0

# live: /plugin install ccds-loops@ccds, restart, and the loop index appears in context
```

All script paths above were exercised on this branch (block/pass/no-gate/first-line-only).

## What's stubbed / not included

- Hooks are bash: Windows users need Git Bash on PATH (documented posture; PS twins
  are a follow-up if demand shows).
- Not verified end-to-end inside a live plugin-installed session (requires
  install + restart); the hook scripts and shipped hooks.json are verified directly,
  and the JSON contract was confirmed against current docs.

## Next increment

A `/loop-gate <command>` slash command in the plugin to arm/disarm the gate without
hand-editing `.claude/loop-gate.cmd`.
