# Claude Code Playbook

A universal, stack-agnostic development workflow for Claude Code CLI. Phase-gated,
aligned with NIST SSDF (SP 800-218) and Agile principles.

**Architecture (ADR-0007):** the playbook ships **19 always-on agents** — 14 domain
agents (one per archetype) + 5 core generalists — plus a library of **skills** that the
agents compose on demand. This replaced the older 105-agent flat roster: subagents can
invoke skills but cannot spawn other subagents, so each domain is one agent that pulls
its `<pack>-*` skills in a single coherent context. See `DECISIONS.md` ADR-0007.

---

## What loads, and from where

| Layer | Location | Loaded | Notes |
|---|---|---|---|
| 19 agents | `~/.claude/agents/` | always (session start) | 14 domain + 5 core; ~850 tokens of descriptions |
| Cross-cutting skills | `~/.claude/skills/` | descriptions always; body JIT | `playbook-conventions`, `api-design`, `ux-design`, `security-checklist`, `code-review-checklist`, `common-*` |
| Domain skills | `~/.claude/playbook/skills/` → `.claude/skills/` | per project (JIT) | `<pack>-*`; copied in by the `sync-agents` skill |
| Index | `~/.claude/playbook/catalog.json` | read during activation | `name, pack, kind, scope, model, description` |

A **domain agent** is a delegated worker you spawn and get a result from. A **skill** is
composable expertise any agent (or the main loop) pulls in place. Authoring rule of
thumb: isolated multi-step work → agent; reference/checklist others must reach → skill.

---

## Initialization Protocol (`/init`)

1. **Confirm project type** — language, framework, runtime, target environment.
2. **Load or create `DECISIONS.md`** — architecture decision log (ADR format below).
3. **Verify the 19 agents are present** in `~/.claude/agents/` — 14 `*-architect` domain
   agents plus the 5 core: `plan-architect`, `pr-code-reviewer`, `secure-auditor`,
   `test-writer-runner`, `deploy-checklist`. If missing, the install is incomplete — see
   README.
4. **Activate domain skills** — invoke the **`sync-agents`** skill: it reads the catalog,
   matches packs to the stack, and copies the relevant `<pack>-*` skills into
   `.claude/skills/`. Record activated packs as an ADR.
5. **Establish working phase** (below).
6. **Context refresh** — when resuming, summarize prior decisions, blockers, next actions.

---

## Phase Framework

Seven sequential phases, each mapped to NIST SSDF practice groups, with entry/exit
criteria. **Phase gates are real** — do not advance until exit criteria are met. `main`
should always be deployable.

1. **Initialize** (PO) — scaffold, CI skeleton, conventions, `DECISIONS.md`.
   *Exit:* repo runnable, CI green on empty suite.
2. **Architecture** (PW.1) — components, data flows, boundaries. The relevant **domain
   agent** owns archetype-shaping decisions; `plan-architect` owns universal structure.
   *Exit:* key decisions recorded, boundaries defined.
3. **Implementation** (PW.2, PW.4) — small reviewable increments. Domain agents pull
   their skills (`saas-billing`, `ai-rag`, …); pull `api-design` / `ux-design` for API
   and UI work. *Exit:* feature complete, lint clean, smoke passes.
4. **Testing** (PW.6, PW.7) — `test-writer-runner` for coverage; `pr-code-reviewer` for
   review (pulls `code-review-checklist`). *Exit:* suite passing, no unjustified skips.
5. **Hardening** (PW.8, PW.9) — `secure-auditor` (pulls `security-checklist`); resolve
   all CRITICAL/HIGH. *Exit:* no unmitigated HIGH+, secrets out of source control.
6. **Documentation** (PO.3) — README, API docs, runbooks, ADRs current. *Exit:* public
   APIs documented, `DECISIONS.md` current.
7. **Deployment** (RV.1) — `deploy-checklist` before promotion. *Exit:* deploy verified,
   rollback confirmed.

---

## Agents and skills

### The 19 agents (always on)

**Domain agents** (one per archetype, each composes its `<pack>-*` skills):
`saas-architect`, `ai-architect`, `infra-architect`, `game-architect`,
`mobile-architect`, `dataplat-architect`, `ecom-architect`, `fintech-architect`,
`devtool-architect`, `desktop-architect`, `ext-architect`, `embed-architect`,
`media-architect`, `orch-architect`.

**Core generalists:** `plan-architect` (universal design), `pr-code-reviewer`,
`secure-auditor`, `test-writer-runner`, `deploy-checklist`.

### Skills

Each domain agent's body lists the skills it pulls. The full, authoritative list of
skills (with triggers) is `catalog.json` — do not duplicate it here. Cross-cutting
skills available everywhere: `playbook-conventions` (output/handoff/ADR format),
`api-design`, `ux-design`, `security-checklist`, `code-review-checklist`, and the
`common-*` set (`common-a11y`, `common-i18n`, `common-privacy`,
`common-notifications`, `common-product-analytics`).

### Composition rules

- Skills **add to** agents; a domain agent pulls several skills in one task.
- A subagent **cannot spawn another agent** — to engage `secure-auditor`,
  `pr-code-reviewer`, etc., it returns to the orchestrator and names them. To reach
  sibling expertise it pulls the skill directly.
- Activated packs are recorded as an ADR in `DECISIONS.md`.

### Prefix registry

`game-`, `saas-`, `mobile-`, `ai-`, `dataplat-`, `ecom-`, `fintech-`, `devtool-`,
`desktop-`, `ext-`, `embed-`, `media-`, `orch-`, `infra-`, and `common-` (cross-archetype
skills only — no `common` domain agent).

---

## Conventions

- **Decisions are logged.** Every significant architectural/security/process decision is
  an ADR in `DECISIONS.md`. The shared `playbook-conventions` skill carries the ADR
  template and the output/handoff format — agents pull it rather than restating it.
- **Skill & agent files are UTF-8 without BOM.** Installer writes must use BOM-less UTF-8
  (PowerShell: `[System.IO.File]::WriteAllText($path, $content,
  [System.Text.UTF8Encoding]::new($false))`). A BOM makes Claude Code silently skip the
  YAML frontmatter. See ADR-0001.
- **Descriptions are the routing surface.** Keep agent/skill descriptions to one crisp
  "use proactively" trigger sentence — no `<example>` blocks, no literal `\n`. Regenerate
  `catalog.json` from the files via `scripts/build-catalog.py` after any change.
- **Layout:** agents are flat `.claude/agents/<name>.md`; skills are
  `skills/<name>/SKILL.md`. Claude Code does not recurse `.claude/agents/` (ADR-0001).

---

## Context Refresh Protocol

For long sessions or on resume: summarize current phase, last 3 decisions, open blockers;
re-confirm active agents/skills; review `DECISIONS.md`; state the next 2–3 concrete actions.
