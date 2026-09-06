# >>> ccds >>>
# ⚠ ccds-managed block — do NOT edit between these markers. Everything here is
# regenerated (your edits overwritten) on `ccds sync`/`ccds setup`. Put your own
# instructions ABOVE or BELOW this block; that text is always preserved.
# Update: ccds sync · Remove: ccds uninstall

## Claude Code Dev Studio

Installed at `~/.claude/playbook/`. **19 agents** (14 domain agents + 5 core
generalists) are always loaded — supplied either by the ccds plugins (`ccds-core`
+ the archetype packs) or by copies in `~/.claude/agents/`, never both. Each domain agent
composes its `<pack>-*` **skills** — the just-in-time layer (`~/.claude/playbook/skills/`,
indexed in `catalog.json`). Cross-cutting skills (`playbook-conventions`, `api-design`,
`ux-design`, `security-checklist`, `code-review-checklist`, `inventive-engineer`,
`common-*`, and the `loop-*` agent-loop process skills) come from the same
route (plugins, or copies in `~/.claude/skills/`) and are always available.

To activate a project's domain skills (on `/init`, a new task, "sync agents", or when a
domain agent needs a `<pack>-*` skill not yet in `.claude/skills/`), use the
**`sync-agents` skill** — it reads the catalog, matches packs to the stack, and copies
the relevant skills into `./.claude/skills/`. Run `ccds sync --clean` to remove them.
# <<< ccds <<<
