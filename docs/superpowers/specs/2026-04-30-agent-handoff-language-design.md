# Agent Handoff Language Design

**Date:** 2026-04-30  
**Status:** Approved — pending implementation plan  
**Scope:** All agents in `.claude/agents/` (~100 files)

---

## Problem

The agent system has two handoff gaps:

1. **Five generalist agents have no scope delegation language at all** — `pr-code-reviewer`, `test-writer-runner`, `deploy-checklist`, `api-expert`, `ux-design-critic` contain no "You do NOT own" sections and no recommended-next-steps output fields. The orchestrator has no in-agent signal for when to move to the next phase or escalate to a specialist.

2. **Most pack specialists have scope delegation bodies but no "Recommended next steps" output field** — they tell the orchestrator what they don't own, but their output format never says what to invoke after their work is done. An initial sample of ~33 agents found this field missing in ~27 of them; the full population across all packs is 75+ specialists.

The combined effect: handoffs rely entirely on the orchestrator inferring next steps from context rather than receiving explicit signals from the agents themselves. This works when the orchestrator has full context, but degrades as sessions grow and context compresses.

---

## Design

### Three additions per agent

Every agent receives up to three additions, tailored to its specific scope and voice. Not all three apply to every agent — existing agents that already have scope delegation don't get a duplicate section.

---

#### 1. Scope delegation block — "You do NOT own"

**Applies to:** The 5 generalist agents (missing this entirely).

A `## Scope Boundaries` section with two subsections:

- **You own** — brief statement of the agent's primary domain (1–4 bullet points)
- **You do NOT own** — explicit `→ agent-name` entries for:
  - *Phase-chain handoffs*: the next generalist in the workflow sequence
  - *Domain escalations*: pack specialists to invoke when domain-specific territory is crossed mid-task

Format:
```markdown
## Scope Boundaries

You own: [concise domain statement]

You do NOT own:
- [Domain area] → `agent-name`
- [Domain area] → `agent-name`
```

The phase chain order is:
`plan-architect` → implement → `pr-code-reviewer` → `test-writer-runner` → `secure-auditor` → `deploy-checklist`

`api-expert` and `ux-design-critic` are lateral specialists invoked during Phase 3 (Implementation), not sequential phase-gate agents. Their handoffs point back to `pr-code-reviewer` as the gate before proceeding.

---

#### 2. "Recommended next steps" output field

**Applies to:** All agents currently missing this field (~30+ agents, including all 5 generalists and most pack specialists).

A two-part field appended to the existing output format section:

- **Static line** — always present; names what the orchestrator should invoke after this agent's work is done (phase-flow continuation)
- **Conditional lines** — only surface when findings fall outside this agent's scope; name the specific agent to invoke

Format:
```markdown
- **Recommended next steps** — [static: what comes next in the phase flow]. If [condition], invoke `agent-name`. If [condition], invoke `agent-name`.
```

The static line uses consistent phrasing:
- Generalists: *"After [this agent's] findings are resolved, proceed with `next-agent`."*
- Pack specialists: *"Return findings to the orchestrator. If implementation is complete and no sibling specialist handoff is needed, `pr-code-reviewer` reviews before the work proceeds to the next phase."* (Where a pack specialist's output feeds directly into another specialist — e.g. `saas-data-model-expert` → `saas-multitenancy-expert` — the static line names that sibling instead.)

---

#### 3. Cross-pack advisory hint

**Applies to:** Agents whose work can benefit from a perspective outside their pack or the activated packs — added as a conditional line in the "Recommended next steps" field.

Uses soft, unnamed language — no specific agent filename — so it degrades gracefully when the relevant pack isn't installed:

```
If this work touches [domain], consider whether a [type of specialist] agent would add value — the orchestrator can assess whether to activate one.
```

Examples:
- A `saas-data-model-expert` working on a schema with heavy analytics usage might hint: *"If this schema is primarily serving analytical queries, consider whether a data platform specialist would add value."*
- An `infra-k8s-expert` working on a latency-sensitive workload might hint: *"If this involves real-time ML inference, consider whether an AI inference performance specialist would add value."*

The orchestrator — not the agent — decides whether to search the playbook and restart the session to add the relevant agent.

---

### CLAUDE.md update

**File:** `~/.claude/CLAUDE.md` — global init protocol, Step 1 (Codebase Analysis).

**Addition:** After the existing `ccds --help` instruction, add:

> After selecting packs and before running the sync command, state the pack selection and reasoning explicitly to the user so they can redirect if needed. Note that copying new agents to `.claude/agents/` requires a session restart before they are active.

This makes the restart requirement visible at the moment it matters, and gives the user a checkpoint before the sync runs.

---

## Execution Plan

### Tier 1 — Generalists (5 files, highest effort)

Written first because their delegation vocabulary establishes the reference points pack agents name.

| Agent | Missing | Key handoffs to add |
|---|---|---|
| `pr-code-reviewer` | Scope section + output field | Phase-next: `test-writer-runner`; escalate: `secure-auditor` (security findings), pack auth/billing specialists |
| `test-writer-runner` | Scope section + output field | Phase-next: `secure-auditor`; escalate: domain specialists for coverage gaps |
| `deploy-checklist` | Scope section + output field | End of chain; escalate: `secure-auditor` (unresolved findings), `saas-data-model-expert` (migration issues) |
| `api-expert` | Scope section + output field | Phase-next: `pr-code-reviewer`; escalate: `secure-auditor` (auth/secrets), `ux-design-critic` (API UX) |
| `ux-design-critic` | Scope section + output field | Phase-next: `pr-code-reviewer`; escalate: `common-a11y-expert`, `common-i18n-expert` |

### Tier 2 — Architect agents (up to 15 files, medium effort)

Each architect already has a "You do NOT own" section. They need:
- "Recommended next steps" output field (static: name their pack's lead specialist; conditional: escalate to relevant generalist)
- Cross-pack advisory hint where the architecture decision touches adjacent domains

Architects: `plan-architect`, `saas-architect`, `ai-architect`, `infra-architect`, `devtool-architect`, `game-architect`, `mobile-architect`, `ecom-architect`, `fintech-architect`, `dataplat-architect`, `desktop-architect`, `ext-architect`, `embed-architect`, `media-architect`, `orch-architect`

Note: `plan-architect` is a generalist but is included here because it reportedly already has scope delegation — verify during implementation and skip the scope section if already present; add only the output field if missing.

### Tier 3 — Pack specialists (75+ files, lower effort per file)

Already have scope delegation. They need:
- "Recommended next steps" output field added to the output format section
- Cross-pack advisory hint where applicable

Packs: `saas-*`, `ai-*`, `infra-*`, `devtool-*`, `game-*`, `mobile-*`, `ecom-*`, `fintech-*`, `dataplat-*`, `desktop-*`, `ext-*`, `embed-*`, `media-*`, `orch-*`, `common-*`

---

## Quality bar

Each agent's additions must:
- Match the existing voice and terminology of that agent's body text
- Not duplicate language already present in the agent
- Name specific agent filenames (`agent-name`) for in-scope handoffs
- Use unnamed, type-descriptive language for cross-pack advisory hints
- Be concise — the output field addition should be 1–4 lines total

---

## Files changed

- `~/.claude/CLAUDE.md` — restart note added to Step 1
- `.claude/agents/*.md` — all ~100 agent files receive additions per the tier plan above
- This spec is committed to `docs/superpowers/specs/2026-04-30-agent-handoff-language-design.md`
