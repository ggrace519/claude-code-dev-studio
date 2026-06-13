---
name: code-review-checklist
description: Code review reference — the seven review dimensions and comment severity labels. Use proactively when reviewing a diff or self-reviewing changes before handing off to the pr-code-reviewer agent.
---

# Code Review Checklist

Reference for reviewing a changeset — the shared dimensions, severity labels, and
verdict vocabulary that keep reviews consistent whether it's a self-review or the
`pr-code-reviewer` agent's full pass.

## When to reach for this

- Reviewing a diff or PR for someone else
- Self-reviewing changes before handing work off for review
- Calibrating how to label a finding (blocker vs concern vs nit)

## Review dimensions

Evaluate every change across these dimensions:

1. **Correctness** — does the code do what it claims? Are edge cases handled?
2. **Security** — injection risks, auth bypasses, data leaks? (pull `security-checklist` for depth)
3. **Performance** — N+1 queries, unnecessary allocations, blocking I/O?
4. **Maintainability** — readable, well-named, appropriately abstracted?
5. **Test coverage** — are the new code paths tested? Are the tests meaningful?
6. **Documentation** — public interfaces and non-obvious logic documented?
7. **Breaking changes** — does this break backwards compatibility? Is it flagged?

## Comment severity labels

Prefix every review comment:

- `[BLOCKER]` — must be fixed before merge
- `[CONCERN]` — should be addressed; warrants discussion
- `[NIT]` — minor style/preference; non-blocking
- `[QUESTION]` — genuinely unclear; needs author clarification
- `[PRAISE]` — explicitly call out good work

## Verdict

End with one of: `APPROVE`, `APPROVE WITH NITS`, `REQUEST CHANGES`.

## Pitfalls

- Reviewing only the diff lines — the bug is often in the unchanged code the diff
  now interacts with
- Labeling style preferences `[BLOCKER]`, or real correctness bugs `[NIT]`
- A wall of nits with no verdict, leaving the author unsure whether to merge
- Approving on "tests pass" without asking whether the tests test the new behavior

---
*Related: `security-checklist` (security dimension in depth), `playbook-conventions`
(output/ADR format) · pulled by any domain agent for self-review; the
`pr-code-reviewer` agent runs the full-diff review*
