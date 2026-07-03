# DEMO — innovation/loop-lint (stacked on innovation/loop-skills-pack)

Proposal #5 from `INNOVATIONS.md` (2026-07-03): the process-skill lint dimension —
ADR-0010's authoring rules become CI-enforced errors the same day they become rules.

This branch **stacks on `innovation/loop-skills-pack`** (it lints that branch's
skills); merge the pack first, then this.

## What works

- `lint-playbook.py` check 9 (`process-skill`), errors on any `loop-*` skill that:
  - lacks a trigger-style description (`Use when/before/after …`),
  - does not have exactly one `## Iron law` section ("two laws is zero laws"),
  - is missing the `## Rationalizations` table.
- Domain skills (`saas-*`, `common-*`, …) are untouched by the check.
- All six shipped `loop-*` skills pass; 5 new fixture tests prove each failure mode
  fires (missing law, missing table, non-trigger description) and that compliant /
  non-loop skills pass.

## How to try it

```bash
python3 scripts/lint-playbook.py   # PASS on this branch (0 errors)
python3 -m pytest tests/ -q        # 22 passed (17 from the pack branch + 5 new)

# see it catch a violation:
sed -i 's/^## Iron law$/## Iron laws/' skills/loop-verify/SKILL.md
python3 scripts/lint-playbook.py   # ERROR [process-skill] … exactly one '## Iron law'
git checkout -- skills/loop-verify/SKILL.md
```

## What's stubbed / not included

Nothing stubbed. Everything in the loop-skills-pack DEMO also applies here.

## Next increment

Enforcement hooks for `ccds-loops` (INNOVATIONS #2) and release-time compliance
pressure-tests (#4) — the behavioral complement to this structural check.
