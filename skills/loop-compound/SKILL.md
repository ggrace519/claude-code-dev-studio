---
name: loop-compound
description: Compounding loop. Use after any user correction, review finding, bug postmortem, or second occurrence of a mistake — write the learning into a permanent home (rule, skill, test, ADR, hook) so the next session doesn't repeat it.
---

# Compounding Loop

Each unit of work should make the next one easier. Corrections, review findings, and
postmortems are the highest-value tokens in a session — and they evaporate when the
context ends unless they land in a file the next session actually reads.

## When to reach for this

- The user corrects an approach, preference, or assumption
- A review or audit produces a finding worth more than its one fix
- A bug's root cause is proven (`loop-debug` step 7 hands off here)
- The same mistake or question shows up a second time

## Iron law

**Every correction lands in a file the next session reads.** A lesson that lives only
in the conversation is a lesson scheduled for re-learning.

## The loop

1. **Trigger.** A correction, finding, postmortem, or repeat occurrence.
2. **Extract the general rule** — the *why* behind the incident, stated so it applies
   to the next case, not just this one. "Use UTC in the events table" is an incident;
   "all persisted timestamps are UTC; convert at the display edge" is a rule.
3. **Route it to its permanent home:**

   | Learning | Permanent home |
   |---|---|
   | How-to-work preference or convention | `CLAUDE.md` rule (project or user level) |
   | Repo-specific gotcha or non-obvious wiring | Project `CLAUDE.md` or a project skill |
   | A class of regression | A test that fails if it recurs |
   | An architecture/process decision with alternatives | ADR in `DECISIONS.md` |
   | A repeatable multi-step procedure | A skill (project `.claude/skills/`) |
   | A tool-use mistake a script could catch | A hook or lint check — deterministic beats prose |

4. **Write it as rule + why + how-to-apply** — the why is what lets a future session
   apply it to a case the original author never saw.
5. **Link it** to related rules/ADRs so the knowledge accretes instead of fragmenting.
6. **Verify the load path**: is the file actually read by a fresh session? A rule in a
   file nothing loads is step 1 all over again.

## The escalation ratchet

- **First occurrence** — fix it.
- **Second occurrence** — fix it *and* write the rule (step 3).
- **Third occurrence** — the prose rule failed; promote it to something deterministic:
  a test, a lint check, or a hook.

## Rationalizations

| Excuse | Reality |
|---|---|
| "I'll remember this" | The next session starts with no memory of this one |
| "Too small to write down" | Small × every-future-session is not small |
| "I'll batch the learnings at the end" | Context ends are rarely chosen; harvest at the trigger |
| "The fix itself documents the lesson" | A fix shows *what* changed; the rule carries *why* — the transferable part |

## Pitfalls

- Recording the incident instead of the rule (step 2 is the actual work)
- Writing rules into files no session loads — verify the load path every time
- Duplicating an existing rule instead of sharpening it — search before writing
- Hoarding everything: a rule that doesn't change future behavior is noise; prune
  rules that turn out wrong as aggressively as you add them

---
*Related: `loop-debug` (root causes feed this loop), `loop-review` (findings feed this
loop), `playbook-conventions` (ADR template) · the escalation ratchet's deterministic
end-state is a hook or lint check*
