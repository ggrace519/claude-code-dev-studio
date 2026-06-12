# Demo — innovation/playbook-lint (INNOVATIONS.md Proposal 3)

## What this branch does

Adds `scripts/lint-playbook.py` — a semantic linter that verifies the playbook's
*claims*, not just its file shapes (which `verify-agents` already covers):

| Check | What it guards | Severity |
|---|---|---|
| `skill-refs` | every `<pack>-*` skill an agent body references exists in `skills/` | error |
| `reverse-refs` | every project-scoped skill appears in its domain agent's manifest | error |
| `catalog-fresh` | `catalog.json` matches a fresh `build-catalog.py` regeneration | error |
| `url-consistency` | all repo URLs use the canonical GitHub owner | error |
| `description-style` | one-line descriptions, no `<example>`, no literal `\n`, ≤400 chars | error |
| `model-values` | agent `model:` is a tier alias, not a dated ID | warning |
| `token-budget` | always-on agent descriptions stay within the advertised budget | warning |

Wired in three places: a `lint-playbook` CI job in `ci.yml`, and a `ccds lint`
command in both dispatchers (`bin/ccds.sh`, `bin/ccds.ps1`).

It caught a live bug on first run: `skills/sync-agents/SKILL.md` pointed install
instructions at `519lab/claude-code-dev-studio` instead of
`ggrace519/claude-code-dev-studio` — fixed in this branch. It also warns on all
19 dated model pins (fixed separately on `innovation/model-aliases`).

## How to try it

```bash
python3 scripts/lint-playbook.py          # or: ccds lint (from the repo clone)
echo 'See `saas-nonexistent` skill' >> .claude/agents/saas-architect.md
python3 scripts/lint-playbook.py          # fails with [skill-refs]
git checkout .claude/agents/saas-architect.md
```

## What works / what's stubbed

- Working: all seven checks, CI job, both dispatcher commands. Nothing stubbed.
- `ccds lint` requires a repo clone (dev layout); on an installed layout it
  exits 2 with a clear message — the linter validates library *source*.
- Token estimate is chars/4; the warn threshold (1300) reflects that crudeness.

## Next increment

Once `innovation/model-aliases` merges, promote `model-values` from warning to
error so dated IDs can never return. Then reuse this script's catalog parsing
for the routing-eval harness (INNOVATIONS.md Proposal 2).
