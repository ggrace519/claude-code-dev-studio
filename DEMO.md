# Demo — innovation/model-aliases (INNOVATIONS.md Proposal 4)

## What this branch does

Replaces dated model ID pins in all 19 agent frontmatter blocks with Claude Code's
tier aliases, which always resolve to the current best model in each tier:

| Before | After | Files |
|---|---|---|
| `claude-opus-4-7` | `opus` | 16 domain/core agents |
| `claude-sonnet-4-6` | `sonnet` | `pr-code-reviewer`, `test-writer-runner` |
| `claude-haiku-4-6` (not a current public model ID) | `haiku` | `deploy-checklist` |

`catalog.json` regenerated via `scripts/build-catalog.py`.

## How to try it

```bash
./verify-agents.sh                      # structural invariants still pass
grep -h '^model:' .claude/agents/*.md | sort | uniq -c
python3 scripts/build-catalog.py . /tmp/c.json && diff catalog.json /tmp/c.json
```

Install the agents (or copy one into `~/.claude/agents/`) and run `/agents` in
Claude Code — each agent shows its tier alias and resolves to the current model.

## What works / what's stubbed

- Working: complete change; nothing stubbed.
- Historical references to dated IDs in `DECISIONS.md` / `CHANGELOG.md` are
  intentionally untouched (ADRs are never retroactively altered).

## Next increment

Add an allowed-values check (`opus|sonnet|haiku|inherit`) to the playbook linter
(see `innovation/playbook-lint`) so dated pins can't reappear.
