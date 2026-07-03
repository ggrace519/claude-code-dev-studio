# DEMO — innovation/loop-compliance-evals (stacked on innovation/loop-skills-pack)

Proposal #4 from `INNOVATIONS.md` (2026-07-03): pressure-test the loop skills like
code — a conflicting-incentive scenario per skill, scored for the shape of compliance.

Stacks on `innovation/loop-skills-pack`; merge the pack first.

## What works

- Six scenarios (`evals/loop-compliance/scenarios.json`), one per `loop-*` skill,
  each demanding the iron-law violation under pressure.
- `scripts/eval-loop-compliance.py`: `--dry-run` validation, offline `--score-file`
  scoring, and the live mode (`claude -p --append-system-prompt <skill>` × `--votes`,
  majority decides). stdlib-only.
- **Verified live** (2026-07-03, haiku): the `verify-under-deadline` scenario ran
  end-to-end through `claude -p`; the skill-loaded reply refused to claim the
  incident resolved and demanded evidence → scored PASS. An earlier live run caught a
  real scorer bug — the compliant reply *quoted* "incident is resolved" while
  refusing and the naive fail_if fired — so fail_if patterns are now guarded
  (artifact present AND compliance vocabulary absent), with a regression test.

## How to try it

```bash
python3 scripts/eval-loop-compliance.py --dry-run          # validates scenarios
python3 -m pytest tests/ -q                                # 22 passed (5 new, offline)
# live (spends API tokens — release-time, or after editing a loop-* skill):
python3 scripts/eval-loop-compliance.py --votes 3 --model haiku
python3 scripts/eval-loop-compliance.py --only verify-under-deadline --votes 1
```

## What's stubbed / not included

- Only `verify-under-deadline` has been exercised live (3 calls total during
  development); the other five scenarios are validated offline against canned
  outputs but their live pass-rates are unmeasured — run the full suite once
  before trusting them as gates.
- Deliberately not wired into per-PR CI (API cost); intended cadence is release-time
  and after any `loop-*` wording change.

## Next increment

Measure baseline pass-rates for all six scenarios at `--votes 5`, strengthen any
skill that fails (the whole point), and record the rates in the changelog.
