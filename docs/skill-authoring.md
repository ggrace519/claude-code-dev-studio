# Skill Authoring Guide

The ADR-0007 migration moved the former `*-expert` agent bodies into skills
**near-verbatim**. That preserved the expertise but left 86+ skills speaking in
agent voice — persona intros, "You do NOT own → `<agent>`" handoff blocks, and
"Return to the orchestrator" closings. A skill is not an actor: it is reference
material loaded into whatever context pulls it (the main loop or a domain
agent). Agent-era language inside a skill is at best noise and at worst
contradicts the instructions of the agent that pulled it.

This guide defines the target shape. `saas-billing` and `ai-rag` are the
reference conversions.

## The rules

1. **No persona.** Delete "You are a senior engineer…". The skill's authority
   comes from its content, not a claimed identity.
2. **No scope/handoff blocks.** "You own / You do NOT own → `agent`" belongs in
   *agent* bodies (they decide routing). Replace with a one-line **Related**
   footer naming sibling skills and the owning domain agent.
3. **No per-skill Output Format.** `playbook-conventions` owns output and ADR
   structure. A skill may note *deliverables specific to its domain* in one
   line, nothing more.
4. **No orchestrator choreography.** Delete "Return implementation to the
   orchestrator; `pr-code-reviewer` reviews…". The agent composing the skill
   already knows the handoff protocol.
5. **Keep the principles, sharpen them with numbers.** The "Approach" bullets
   are the best part of the migrated bodies — keep them, but every principle
   that can carry a concrete default, threshold, or version should
   ("rerank top-50 → top-5", not "rerank more chunks").
6. **Add the concrete layer.** Every skill should contain at least one of:
   a decision table, a code skeleton, a checklist, or a worked example.
   If the model already knew everything in the skill, the skill isn't paying
   for its tokens.
7. **Bundle big artifacts as resources.** Keep `SKILL.md` scannable (~60–100
   lines); put full skeletons and long references in `references/*.md` next to
   it and link them. Claude reads them on demand — progressive disclosure.
8. **Descriptions are untouched routing surface.** Frontmatter `description`
   changes go through the routing rules in `CLAUDE.md`, not this guide.

## Target template

```markdown
---
name: <skill-name>
description: <unchanged routing sentence>
---

# <Title>

<1–2 sentence framing: what class of problem this covers and the stakes.>

## When to reach for this
<2–4 bullets: concrete situations, not restated description.>

## Principles
<The sharpened Approach bullets — with numbers/versions where possible.>

## <Concrete section(s)>
<Decision table / skeleton / checklist / worked example. Link references/.>

## Pitfalls
<The mistakes specific to this domain that reviews actually catch.>

---
*Related: `<sibling-skill>`, `<sibling-skill>` · domain agent: `<pack>-architect` ·
output/ADR format: `playbook-conventions`*
```

## Conversion status

| Skill | Status |
|---|---|
| `saas-billing` | converted (reference) |
| `ai-rag` | converted (reference) |
| remaining 88 | pending — convert opportunistically when a skill is touched |
