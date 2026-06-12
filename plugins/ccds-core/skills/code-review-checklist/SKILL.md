---
name: code-review-checklist
description: Code review reference — the seven review dimensions and comment severity labels. Use proactively when reviewing a diff or self-reviewing changes before handing off to the pr-code-reviewer agent.
---

# Code Review Checklist

Reference for reviewing a changeset. The `pr-code-reviewer` agent pulls this for its
full review; any agent should pull it to self-review before returning work.

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

For a full PR review across the entire diff, return to the orchestrator to engage the
`pr-code-reviewer` agent.
