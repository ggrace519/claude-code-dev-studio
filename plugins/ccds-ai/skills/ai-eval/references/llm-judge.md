# LLM-as-judge harness skeleton

Python-flavored; the pattern (rubric prompt → order-swapped pairwise scoring →
calibration against human labels → CI gate) is provider-agnostic.

```python
JUDGE_PROMPT = """You are grading two answers to the same question.

<question>{question}</question>
<answer_a>{answer_a}</answer_a>
<answer_b>{answer_b}</answer_b>

Grade ONLY on: {axis}.   # one axis per judge call — composites hide regressions
Rubric: {rubric}

Respond with JSON: {{"winner": "A" | "B" | "tie", "reason": "<one sentence>"}}"""

def judge_pair(question, a, b, axis, rubric, runs=3):
    """Order-swapped, multi-run pairwise judgment."""
    votes = []
    for _ in range(runs):
        # Run BOTH orders every time; a judge that flips with order is voting
        # on position, not quality.
        v1 = call_judge(JUDGE_PROMPT, question=question, answer_a=a, answer_b=b,
                        axis=axis, rubric=rubric)
        v2 = call_judge(JUDGE_PROMPT, question=question, answer_a=b, answer_b=a,
                        axis=axis, rubric=rubric)
        v2 = flip(v2)                      # map B-wins back to "a wins"
        votes += [v1, v2]
    return majority(votes)                 # disagreement across runs → flag for human review


def calibrate(judge, human_labeled):
    """Gate the judge itself before it gates anything else.

    human_labeled: ~100 (question, a, b, human_verdict) tuples.
    """
    agreements = [(judge_pair(*x[:3], axis=AXIS, rubric=RUBRIC) == x.human_verdict)
                  for x in human_labeled]
    kappa = cohen_kappa([x.human_verdict for x in human_labeled],
                        [judge_pair(*x[:3], axis=AXIS, rubric=RUBRIC) for x in human_labeled])
    assert kappa >= 0.6, f"judge not trustworthy (kappa={kappa:.2f}) — fix the rubric, not the gate"
```

## CI gate

```python
def regression_gate(golden_set, candidate_fn, baseline_outputs, threshold=0.05):
    """Block merge if candidate loses to baseline beyond threshold on any axis."""
    for axis in AXES:                      # helpfulness, faithfulness, format, safety
        wins = ties = losses = 0
        for ex in golden_set:
            verdict = judge_pair(ex.question, candidate_fn(ex), baseline_outputs[ex.id],
                                 axis=axis, rubric=RUBRICS[axis])
            wins, ties, losses = tally(verdict, wins, ties, losses)
        win_rate = (wins + 0.5 * ties) / len(golden_set)
        # Threshold committed BEFORE the run, in the repo, not chosen after.
        if win_rate < 0.5 - threshold:
            fail(f"regression on {axis}: win_rate={win_rate:.2f}")
```

## Checklist before trusting the judge

- [ ] Deterministic checks (schema validity, exact match, length caps) run first and separately — the judge never grades what code can grade
- [ ] Calibration kappa ≥ 0.6 against ~100 human labels, re-run whenever the rubric or judge model changes
- [ ] Both presentation orders scored on every pair; order-flipping pairs logged
- [ ] 3+ runs aggregated; run-to-run disagreements sampled for human review
- [ ] Judge model ≠ (or at least audited for self-preference against) the model under test
- [ ] Judge prompt and rubric versioned in the repo next to the golden set
