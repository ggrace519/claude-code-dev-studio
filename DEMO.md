# DEMO — innovation/loop-harness-export (stacked on innovation/loop-skills-pack)

Proposal #6 from `INNOVATIONS.md` (2026-07-03): the loop pack is the library's most
harness-agnostic content — export it beyond Claude Code.

Stacks on `innovation/loop-skills-pack`; merge the pack first.

## What works

- `scripts/export-harness.py --target cursor` → `.cursor/rules/<name>.mdc` ×6
  (Agent-Requested rule form: trigger description in frontmatter,
  `alwaysApply: false`).
- `scripts/export-harness.py --target agents-md` → one `AGENTS.md` for Codex CLI and
  the wider AGENTS.md ecosystem, one section per skill with its trigger line.
- Bundled `references/*.md` (the loop-long-horizon state-file kit) are inlined —
  foreign harnesses don't chase Claude-style relative reference links.
- **Live activation verified** (2026-07-03): a scratch project containing only the
  exported AGENTS.md, driven with `codex exec --sandbox read-only "I just committed
  a bug fix and it compiles … may I tell the user it's fixed?"` — Codex answered
  "No. `loop-verify` applies: 'No completion claim without fresh evidence from the
  real system'…", citing the skill by name and quoting the iron law verbatim.

## How to try it

```bash
python3 scripts/export-harness.py --target cursor
python3 scripts/export-harness.py --target agents-md
ls dist/harness-export/cursor/.cursor/rules/          # 6 .mdc rules
python3 -m pytest tests/ -q                           # 20 passed (3 new)

# repeat the live check (spends OpenAI credits):
mkdir /tmp/ct && cp dist/harness-export/agents-md/AGENTS.md /tmp/ct && cd /tmp/ct && git init -q .
codex exec --sandbox read-only "I just committed a fix and it compiles. May I tell the user it's fixed? Cite the rule."
```

## What's stubbed / not included

- Cursor export is structurally valid per the .mdc format but not yet exercised
  inside a live Cursor session (Cursor is installed but rule attachment is
  interactive); the AGENTS.md path is the live-verified one.
- Release workflow doesn't attach export ZIPs yet — wire that up once the pack has
  merged and the export format has a release to ride on.
- Exports only `loop-*` deliberately; widen to `common-*`/domain skills if adoption
  shows up (they carry more Claude-Code-specific assumptions).

## Next increment

Attach per-harness ZIPs to the release workflow, and a `--target claude-plugin`
no-op check that keeps exports byte-stable in CI.
