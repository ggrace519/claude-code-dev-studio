# DEMO — innovation/loop-skills-pack

Proposal #1 from `INNOVATIONS.md` (2026-07-03): the `loop-` pack — six transferable
agent-loop process skills, integrated end-to-end into the library toolchain.

## What works

- **Six new skills** in `skills/loop-*`: `loop-verify`, `loop-debug`, `loop-review`,
  `loop-parallel`, `loop-long-horizon` (+ bundled `references/state-files.md`
  templates), `loop-compound`. Each follows ADR-0009 voice plus the new process-skill
  rules (trigger-style description, one iron law, rationalization table — documented in
  `docs/skill-authoring.md`).
- **Catalog**: `loop-` prefix is scope=global (regenerated `catalog.json`: 115 entries).
- **Marketplace**: new skills-only `ccds-loops` plugin (16 plugins total), category
  `workflow`, installable standalone.
- **Installers**: both `ccds-user-setup.sh` and `Install-Playbook.ps1` ship the pack
  always-on to `~/.claude/skills/`.
- **Lint + docs**: prefix registry (`CLAUDE.md`, `lint-playbook.py`), ADR-0010,
  changelog, README, `sync-agents` and the managed CLAUDE.md block all updated.

## How to try it

```bash
# structural + semantic verification (all pass on this branch)
python3 scripts/lint-playbook.py        # 0 errors, 0 warnings
python3 -m pytest tests/ -q             # 17 passed (2 new: loop scope, loops plugin)
bash verify-agents.sh                   # PASS

# install the pack locally via the marketplace
#   /plugin marketplace add /mnt/d/coding-projects/claude-code-dev-studio
#   /plugin install ccds-loops@ccds
# then in any project, e.g.: "wire up an overnight run" → loop-long-horizon triggers
```

## What's stubbed / not included

- Nothing is stubbed; the pack is complete.
- Follow-on proposals not on this branch: enforcement hooks for `ccds-loops`
  (INNOVATIONS #2), `ccds loop init` scaffolder (#3 — separate branch
  `innovation/loop-init-scaffolder`), compliance pressure-tests (#4), process-skill
  lint dimension (#5).

## Next increment

Add `## Iron law` / rationalization-table lint checks (INNOVATIONS #5) so the
process-skill rules can't drift, then the `ccds-loops` SessionStart hook (#2).
