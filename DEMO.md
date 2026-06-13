# Demo — innovation/skill-content (content-layer improvement)

## The finding

The ADR-0007 migration moved expert agent bodies into skills *near-verbatim*,
leaving the skill library speaking agent language and carrying no concrete
artifacts. Measured on main:

| Symptom | Count (of 90 skills) |
|---|---|
| "Return … to the orchestrator" closings | 88 |
| "You do NOT own → `<agent>`" handoff blocks | 86 |
| Per-skill mandated "Output Format" (duplicating `playbook-conventions`) | 86 |
| Skills containing even one code block | 2 |
| Skills with bundled resource files | 0 |

A skill is reference material loaded into whatever context pulls it — persona
intros, ownership disclaimers, and orchestrator choreography are noise there,
and sometimes contradict the pulling agent's own instructions. And since the
bodies are ~350 words of (good) senior heuristics with nothing concrete, much
of the content is things a frontier model already knows.

## What this branch does

1. **`docs/skill-authoring.md`** — the target skill shape: no persona, no
   scope/handoff blocks, no per-skill output format; principles sharpened with
   numbers; at least one concrete artifact (table / skeleton / checklist);
   big artifacts bundled as `references/*.md` (progressive disclosure);
   a one-line *Related* footer replacing the handoff block.
2. **Two reference conversions:**
   - `skills/saas-billing/` — rewritten + `references/webhook-handler.md`
     (idempotent Stripe-pattern handler skeleton with out-of-order defense,
     plus a failure-mode test checklist). First bundled skill resource in the
     library.
   - `skills/ai-rag/` — rewritten with a "defaults that survive contact"
     table (chunk sizes, top-k, rerank cut, when to move each knob) and a
     pitfalls section.

Frontmatter descriptions are untouched (routing surface unchanged →
`catalog.json` byte-identical). `verify-agents.sh` passes; `Sync-AgentPacks`
copies skill dirs recursively, so `references/` travels with the skill.

## How to try it

```bash
diff <(git show main:skills/ai-rag/SKILL.md) skills/ai-rag/SKILL.md
cat skills/saas-billing/references/webhook-handler.md
./verify-agents.sh skills
```

## What works / what's stubbed

- Working: **all 88 in-scope skills converted** (the 2 exemplars + 86 bulk,
  converted pack by pack after template approval). 16 bundled
  `references/*.md` resources (one per pack + cross-cutting), e.g.
  `saas-multitenancy/references/rls-policies.md`,
  `fintech-ledger/references/double-entry-schema.md`,
  `infra-sre/references/slo-worksheet.md`.
- Exempt by design: `playbook-conventions` (documents the handoff protocol —
  handoff language is its subject matter) and `sync-agents` (procedural
  meta-skill, already instructional).
- Verified after the bulk pass: `verify-agents.sh` PASS (90 skills, 0
  failures); `catalog.json` byte-identical (every frontmatter untouched —
  routing surface unchanged); zero banned-phrase hits outside the exempt
  files; no BOM/CRLF introduced.
- Conversion agents were instructed to add numeric specifics only where
  confident and hedge the rest — but a domain-owner skim of the new tables
  (regulatory deadlines, platform thresholds, config defaults) is the right
  review focus.

## Next increment

1. Add a lint check (`innovation/playbook-lint`) flagging agent-era phrases in
   skills ("orchestrator", "You do NOT own", "## Output Format") to ratchet
   the migration — warn-level until this branch merges.
2. Apply the same de-duplication to the 14 domain agents' closing sections,
   which restate the handoff protocol `playbook-conventions` owns.
3. Regenerate the plugin marketplace tree (`innovation/plugin-marketplace`)
   after this branch merges so plugins ship the converted skills.
