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

## Process skills (`loop-*`) — additional rules

The `loop-*` pack (ADR-0010) encodes agent work loops, not domain knowledge. Process
skills follow the template above **plus** three requirements borrowed from the most
effective process-skill libraries (superpowers' compliance findings — wording changes
moved compliance 33%→72%):

1. **Trigger-style description.** The description says *when* to invoke, never *what
   the skill contains* — "what" descriptions cause the model to claim the skill and
   improvise without reading it. Lead with the artifact ("Evidence-before-done gate."),
   then "Use when/before …".
2. **One iron law.** An `## Iron law` section with a single bright-line rule in bold.
   Bright lines work because they eliminate case-by-case rationalization; two laws is
   zero laws.
3. **A rationalization table.** A `## Rationalizations` section pre-empting the excuses
   the model will generate under pressure ("just this once", "it's trivial"), each with
   the one-line reality. This is the section that holds when incentives conflict.

The loop itself is the concrete artifact (rule 6 above): numbered steps an agent can
follow mechanically, with thresholds ("after 3 failed fixes", "two review rounds")
rather than adverbs.

## Conversion status

All 88 in-scope skills are converted (the two reference conversions
`saas-billing` and `ai-rag`, plus the 86 remaining domain and cross-cutting
skills, converted pack by pack). Each pack also gained one bundled
`references/*.md` resource (16 total). Out of scope by design:
`playbook-conventions` (it *documents* the handoff protocol, so handoff
language there is subject matter) and `sync-agents` (procedural meta-skill,
already in instructional voice).

New skills must follow the template above from day one.
