# Architecture Decision Log

This file records significant architectural, security, and process decisions made during development.
Each entry should be created at the time the decision is made and never retroactively altered.
Superseded decisions should be marked as such, not deleted.

---

## Decision Template

```
## ADR-XXXX: <Title>

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Superseded | Deprecated
**Phase:** Initialize | Architecture | Implementation | Testing | Hardening | Documentation | Deployment
**Deciders:** <names or roles>

### Context
What situation or problem forced this decision?

### Decision
What was decided?

### Rationale
Why this option over alternatives?

### Consequences
What are the trade-offs, risks, or follow-on work?

### Supersedes
ADR-XXXX (if applicable)
```

---

## Decisions

## ADR-0001: Archetype Pack System

**Date:** 2026-04-19
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg

### Context
The base playbook ships seven generalist agents (`plan-architect`, `api-expert`, `ux-design-critic`, `test-writer-runner`, `pr-code-reviewer`, `secure-auditor`, `deploy-checklist`) that apply to any project. Across different app categories — gaming, SaaS, mobile, AI/LLM, fintech, etc. — the generalists cover universal concerns but miss archetype-specific architectural decisions that shape the entire system (e.g., tenancy model, netcode topology, inference-serving topology).

### Decision
Introduce **archetype packs** — archetype-specific agent bundles that compose with the seven generalists. Each pack contains one archetype-architect (opus-4-7) and 3–5 domain specialists (sonnet-4-6). Fourteen archetype categories are registered. Activation is declared per-project via ADR in `DECISIONS.md` at `/init`. A project may activate multiple packs.

Layout: flat files in `.claude/agents/` with a prefix per archetype (e.g., `saas-architect.md`, `saas-billing-expert.md`). Cross-archetype shared specialists use the `common-` prefix.

### Rationale
- **Composition over replacement** — the seven generalists remain universally valuable; specialists add depth without duplicating coverage.
- **Explicit handoffs** — every specialist declares "You do NOT own → `<other-agent>`", making the scope boundary machine-verifiable and preventing overlap with generalists or siblings.
- **Flat + prefix** — the only layout currently discoverable by Claude Code; matches existing generalist conventions.
- **Multi-pack support** — a project with mixed characteristics (e.g., SaaS + AI) activates multiple packs without agent conflicts.

Alternatives considered and rejected:
- **Replace generalists per-archetype** — would duplicate generalist coverage, fragment the playbook, and break cross-archetype reuse.
- **Subfolder layout `.claude/agents/<archetype>/`** — empirically not discovered by Claude Code v2.1.113 (verified via probe agent `.claude/agents/saas/subfolder-probe.md`, which did not appear in `/agents` list).
- **Single mega-agent per archetype** — violates the "specialists are specialists" principle established in the base playbook.

### Consequences
- Full rollout: 14 packs × ~5 agents ≈ 70 additional agent files (vs. 7 generalists today).
- Prefix discipline required at creation; the prefix registry is maintained in `CLAUDE.md`.
- `/init` protocol gains an archetype-selection step.
- Each activated pack is recorded as its own ADR in `DECISIONS.md`.
- First implementation shipped: **SaaS pack** (6 agents: `saas-architect`, `saas-data-model-expert`, `saas-multitenancy-expert`, `saas-billing-expert`, `saas-auth-sso-expert`, `saas-collab-sync-expert`). Other 13 archetypes are registered but not yet scaffolded.

### Supersedes
None.

---

## ADR-0002: Full 13-Pack Rollout and Direct-Write Deployment

**Date:** 2026-04-19
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg

### Context
ADR-0001 established the archetype pack system and shipped the SaaS pack as the template. The prefix registry reserved 13 additional archetypes (game-, mobile-, ai-, dataplat-, ecom-, fintech-, devtool-, desktop-, ext-, embed-, media-, orch-, infra-) but left them unscaffolded. Two open questions:

1. **Build all 13 now, or wait for demand?** Risk of drift if agents are authored inconsistently over time.
2. **Per-pack PowerShell installers, or direct-write via bash?** Per-pack installers match the SaaS pattern but scale poorly (14 installers) and require the user to run each.

### Decision
Build all 13 remaining packs in a single pass and write them directly to `.claude/agents/` via bash (which has real filesystem access to the mounted path, unlike the protected Cowork Write tool). Seventy additional specialist agents total, conforming to the pattern established by the SaaS pack:

- One `<prefix>-architect` per pack (model: `claude-opus-4-7`)
- 3–5 domain specialists per pack (model: `claude-sonnet-4-6`)
- Every specialist declares "You do NOT own → `<other-agent>`" handoffs
- Same YAML frontmatter convention (escaped `\\n` in description), same scope/approach/output-format sections

**Pack inventory (this ADR):**
| Pack | Agents | Architect color | Notes |
|---|---|---|---|
| game- | 6 | `#ea580c` | engine, netcode, perf, balance, feel |
| mobile- | 5 | `#2563eb` | platform, offline-sync, release, perf |
| ai- | 6 | `#6366f1` | prompt, RAG, eval, inference-perf, safety |
| dataplat- | 5 | `#0f766e` | ETL, SQL, quality, viz |
| ecom- | 5 | `#db2777` | payments, inventory, search-merch, storefront-perf |
| fintech- | 5 | `#365314` | ledger, compliance, audit-trail, risk |
| devtool- | 5 | `#475569` | CLI-UX, library-API, packaging, docgen |
| desktop- | 4 | `#92400e` | IPC, autoupdate, code-signing |
| ext- | 4 | `#4338ca` | permissions, security, UX |
| embed- | 5 | `#78350f` | driver, RTOS, OTA, power |
| media- | 4 | `#0369a1` | transcode, DRM/CDN, CMS-workflow |
| orch- | 5 | `#be123c` | tool-design, prompt-engineer, eval, sandbox-safety |
| infra- | 5 | `#334155` | SRE, observability, k8s, finops |

### Rationale
- **Consistency** — writing all 13 in one pass guarantees template drift doesn't accumulate.
- **Direct bash writes** — bypass the Cowork Write tool's `.claude/` write-protection via the mount, avoiding 14 installer round-trips. Agents become discoverable immediately; no "run installer" user step per pack.
- **BOM-less writes via bash heredoc** — bash's redirection writes UTF-8 without BOM by default, side-stepping the PowerShell trap from ADR-0001's rollout.
- **Leave `install-agents.ps1` as-is** — it remains useful for reinstalling / distributing the SaaS pack; future installer consolidation (parameterized `-Pack` argument) is a follow-up, not a blocker.
- **Model tiering preserved** — architects on opus-4-7 where deep cross-cutting trade-offs live; specialists on sonnet-4-6 for focused domain execution.

Alternatives considered and rejected:
- **Lazy build (on-demand per project)** — maximizes drift risk; fragments the playbook into ad-hoc, unowned writeups.
- **Fourteen per-pack PowerShell installers** — would work but doesn't scale; failure-mode surface grows linearly.
- **One mega-installer with `-Pack <name>`** — viable refactor later; not worth the delay on initial rollout.

### Consequences
- `.claude/agents/` grows from 13 files to 77 (7 generalists + 6 SaaS + 70 new specialists).
- Disk footprint ~180 KB; `/init` listing in Claude Code may paginate — monitor user experience.
- Installer surface is uneven: SaaS has `install-agents.ps1`, other 13 packs are bash-installed this session. Follow-up ADR (if pursued) will consolidate to a single parameterized installer.
- `CLAUDE.md` updated with full Available Packs table (all 14 rows) and trigger matrices for every pack.
- No removal or modification of existing generalist or SaaS pack agents.

### Supersedes
None. Extends ADR-0001.

---

## ADR-0003: Gap-Closure Rollout — 23 Per-Pack Additions and `common-` Cross-Archetype Pack

**Date:** 2026-04-19
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg

### Context
ADR-0001 and ADR-0002 established and scaffolded 14 archetype packs (77 agent files total — 7 generalists + 6 SaaS + 70 other-pack specialists). Post-rollout gap analysis against real production workloads surfaced two classes of missing specialists:

1. **Per-pack production gaps** — every pack covered architecture and core specialties but missed specialists required by most shipped products in that category. Examples: gaming lacked live-ops and platform-certification; mobile lacked in-app-purchase and crash management; media lacked a player specialist and live-streaming runbook ownership.
2. **Cross-archetype cross-cutting concerns** — i18n, accessibility, notifications, application-layer privacy, and product analytics apply to nearly every product regardless of archetype. The `common-` prefix was reserved in ADR-0001 but left empty.

Shipping the system as 77 agents would leave consistent, repeatable production gaps across archetypes. Greg's directive: "We are building a full, repeatable system here. No Shortcuts!" — commit to closing the gaps now rather than lazily over time.

### Decision
Add **28 specialist agent files** across the existing packs and the `common-` pack, bringing the total roster from 77 to **105 agents** (7 generalists + 98 pack agents across 15 packs).

**Per-pack additions (23):**

| Pack | Added agents | Gap addressed |
|---|---|---|
| game- | `game-liveops-expert`, `game-platform-cert-expert`, `game-audio-expert` | Live-service telemetry / A-B / cadence; console TRC / XR / Lotcheck; Wwise / FMOD audio |
| mobile- | `mobile-iap-expert`, `mobile-crash-expert` | StoreKit 2 / Play Billing v6; Crashlytics / Sentry, crash-free SLO |
| ai- | `ai-finetune-expert` | SFT / LoRA / DPO, dataset curation, custom-model deployment |
| dataplat- | `dataplat-privacy-expert`, `dataplat-feature-store-expert`, `dataplat-streaming-expert` | Warehouse PII / DSAR; Feast / Tecton; Kafka / Kinesis streaming |
| ecom- | `ecom-tax-expert`, `ecom-promotions-expert` | Sales tax / VAT / nexus; coupons / gift cards / loyalty / stacking |
| devtool- | `devtool-telemetry-expert` | Opt-in telemetry, enterprise-safe disable |
| desktop- | `desktop-installer-expert`, `desktop-shell-integration-expert` | MSI / PKG / DEB installers, silent enterprise deploy; file associations / protocol handlers / Spotlight |
| ext- | `ext-native-messaging-expert` | Browser ↔ native-host bridge, manifest deployment, authorization |
| embed- | `embed-connectivity-expert`, `embed-manufacturing-expert` | Wi-Fi / BLE / Matter / cellular connectivity; factory test / yield / RMA |
| media- | `media-player-expert`, `media-ad-insertion-expert`, `media-live-expert` | Client playback QoE; SSAI / SCTE-35 / VAST; live pipeline and tentpole runbooks |
| infra- | `infra-dr-backup-expert`, `infra-networking-expert`, `infra-iam-expert` | DR / RPO / RTO / restore drills; VPC / DNS / mesh / segmentation; cloud IAM / workload identity / KMS |

**Cross-archetype `common-` pack (5):**

| Agent | Scope |
|---|---|
| `common-i18n-expert` | Externalization, ICU MessageFormat, RTL, translation workflow, pseudo-localization |
| `common-a11y-expert` | WCAG 2.2 AA+, ARIA, keyboard / screen-reader UX, ACR / VPAT |
| `common-notifications-expert` | Push / email / SMS / in-app, preferences, deliverability, rate / quiet-hours |
| `common-privacy-expert` | Consent (TCF / GPP), DSAR, vendor / SDK governance, PIAs (app-layer — distinct from `dataplat-privacy-expert`) |
| `common-product-analytics-expert` | Event taxonomy, instrumentation, identity resolution, experiment wiring |

**Packs unchanged this rollout:** SaaS (6 — already saturated), Fintech (5), Orchestration (5).

### Rationale
- **Consistent production readiness across archetypes.** Before this rollout, a team picking the gaming pack got solid engine / netcode / perf coverage but would silently miss live-ops and platform cert — both universal in shipped games. Gap-closure eliminates these asymmetries.
- **Two distinct privacy scopes is correct.** `dataplat-privacy-expert` (warehouse-layer classification, masking, DSAR at the data layer) and `common-privacy-expert` (application-layer consent, CMP integration, DSAR orchestration). These are different roles done by different people in real companies; explicit handoffs between them are documented in each agent.
- **`common-` pack is opt-in, not default.** Projects explicitly activate via ADR. This preserves the "packs compose, not replace" invariant from ADR-0001.
- **Direct-bash-write deployment reused.** Same path as ADR-0002 — all 28 files written via bash heredoc to the mounted `.claude/agents/` path, UTF-8 without BOM, no PowerShell BOM trap.
- **Model tiering preserved.** All 28 new agents on `claude-sonnet-4-6` (no new architects; the architect for each pack already exists). Matches the pattern from ADR-0002.

Alternatives considered and rejected:
- **Ship as-is (77 agents) and add specialists on demand.** Greg's explicit directive against this. Also matches the drift argument from ADR-0002 — lazy adds produce inconsistent scope boundaries and template shape.
- **Only high-severity gaps (≈10 agents).** Partial closure leaves uneven readiness across archetypes. The marginal cost of the remaining 18 agents is low compared to the composability benefit.
- **Put `common-` agents into each archetype pack.** Would duplicate work and produce N copies of e.g. i18n that drift over time. Cross-cutting is the correct scope for `common-`.

### Consequences
- `.claude/agents/` grows from 77 → 105 files. Disk footprint ~245 KB.
- `CLAUDE.md` Available Packs table extended with gap-fillers per pack; each pack's trigger matrix extended; new Common-pack trigger section added.
- Pack counts now: game 9, saas 6, mobile 7, ai 7, dataplat 8, ecom 7, fintech 5, devtool 6, desktop 6, ext 5, embed 7, media 7, orch 5, infra 8, common 5 (= 98) + 7 generalists = 105.
- Cross-archetype handoff hygiene: every gap-filler declares explicit "You do NOT own → `<other-agent>`" boundaries, including across the `dataplat-privacy` / `common-privacy` split and the `devtool-telemetry` / `common-product-analytics` / `infra-observability` split.
- Installer coverage remains uneven: `install-agents.ps1` still only covers SaaS. Follow-up deferred (parameterized `-Pack` installer). Not a blocker — bash direct-write is the operational path for new packs.
- No changes to generalists; no changes to SaaS / fintech / orch packs.

### Supersedes
None. Extends ADR-0001 and ADR-0002.

---

## ADR-0004: `Sync-AgentPacks.ps1` as Canonical Activation Mechanism

**Date:** 2026-04-19
**Status:** Accepted
**Phase:** Initialize
**Deciders:** Greg

### Context
Post-ADR-0003 the library at `C:\coding-projects\claude-code-dev-studio\.claude\agents\` holds all 105 agents. Loading every agent into every project is suboptimal:

- Claude Code's `/agents` command reported `‼ Large cumulative agent descriptions will impact performance (~17.1k tokens > 15.0k)` — the descriptions alone exceed the soft budget.
- Most projects need one or two archetype packs, not all fifteen.
- The original `install-agents.ps1` only knew how to deploy the SaaS pack (inline-embedded content, PS 5.1 BOM-less pattern). Other 14 packs had no activation script — direct-bash writes were the operational path, fine for the library author but not portable for downstream consumers.
- ADR-0002 and ADR-0003 both explicitly deferred the "parameterized `-Pack` installer" follow-up. This ADR closes it.

### Decision
Adopt `Sync-AgentPacks.ps1` (written this session) as the **canonical per-project activation mechanism**:

- **Library-as-registry / project-as-consumer.** The dev-studio library is the single source of truth for all 105 agents. Individual projects sync a subset into their own `.claude/agents/`.
- **Pack selection by prefix.** `-Packs saas,common` activates `saas-*.md` + `common-*.md` files. Valid prefixes: `game, saas, mobile, ai, dataplat, ecom, fintech, devtool, desktop, ext, embed, media, orch, infra, common`.
- **Generalists included by default.** The 7 generalists (files not matching any known prefix) are copied unless `-NoGeneralists` is passed.
- **Manifest-tracked idempotence.** Each project's `.claude/agents/.pack-manifest.json` records what the script installed. Re-running with a smaller pack list removes only files the script previously owned; manual additions are left untouched.
- **Two distribution modes.** `-Mode Copy` (default, portable, no admin) or `-Mode Symlink` (requires Developer Mode or admin on Windows; auto-tracks library updates).
- **Optional ADR emission.** `-WriteAdr` appends an activation ADR to the target project's `DECISIONS.md` — closes the `/init` "record activation" step.
- **BOM-less UTF-8 throughout.** Manifest and ADR writes use `[System.IO.File]::WriteAllText(path, content, [System.Text.UTF8Encoding]::new($false))` per ADR-0001.

**Deprecation of `install-agents.ps1`.** The original SaaS installer is rewritten as a thin wrapper that forwards to `Sync-AgentPacks.ps1 -Packs saas`, preserving its `$ProjectRoot` / `$DryRun` parameter shape. It emits a deprecation warning and is scheduled for removal in a future revision.

### Rationale
- **Scales to all 15 packs** — one script instead of 14 per-pack installers (the alternative rejected in ADR-0002 as "14 linear failure-mode surfaces").
- **Solves the /agents perf warning** — projects only load the packs they need, keeping cumulative descriptions under the 15k token budget.
- **Idempotent activation and deactivation** — the manifest lets the same script *remove* packs on re-run with a narrower `-Packs` list. No manual cleanup required when an archetype assessment changes.
- **Safe re-run semantics** — files not in the manifest are never touched, so manually-authored project-local agents coexist with library-synced ones.
- **Dry-run-first workflow** — `-DryRun` shows the add/remove/keep plan before touching the filesystem; aligns with the "reversible changes first" preference.
- **Removes the PS 5.1 BOM-trap from the distribution surface.** The legacy installer wrote each agent inline; errors in that pattern (forgetting the `[System.Text.UTF8Encoding]::new($false)` form) would silently break YAML frontmatter. The new mechanism always copies from the library, which is already known-good BOM-less.

Alternatives considered and rejected:
- **Keep per-pack installers (14 `install-<pack>.ps1` scripts).** Rejected in ADR-0002; gap-closure only made the scaling worse (15 packs now).
- **Activate by symlinking the whole library into every project.** Doesn't address the perf warning; couples project layout to library internals.
- **Submodule the library per-project.** Heavier ceremony than most consumers need; fine as an advanced option but not the default.

### Consequences
- **New canonical flow:**
  ```powershell
  # Activate SaaS + common for a SaaS project:
  .\Sync-AgentPacks.ps1 -TargetProject D:\code\acme-saas -Packs saas,common -WriteAdr

  # Switch a project from SaaS to AI:
  .\Sync-AgentPacks.ps1 -TargetProject D:\code\acme-ai -Packs ai,common

  # Preview before applying:
  .\Sync-AgentPacks.ps1 -TargetProject D:\code\game -Packs game,common -DryRun
  ```
- **Per-project footprint drops dramatically.** A SaaS-only project carries 7 generalists + 6 SaaS + (optional) 5 common = 13–18 agents, not 105. Cumulative description tokens fit within the /agents budget.
- `install-agents.ps1` is now a 3-line wrapper + a deprecation warning. Existing consumers invoking `.\install-agents.ps1` continue to work; they're nudged toward the new script via `Write-Warning`.
- **Library self-targeting guard (implemented in Session 7).** The script resolves both `$TargetProject` and `$LibraryRoot` via `Resolve-Path -LiteralPath`, normalizes trailing separators, and refuses to run when they match case-insensitively. Override via `-AllowLibraryTarget` (emits `Write-Warning`; not recommended). This closes the original risk that running against the library root would create a manifest inside the library itself and later *remove* library files on a re-run with a narrower `-Packs` list.
- **Closes the ADR-0002 / ADR-0003 "parameterized -Pack installer" follow-up.** Subsequent changelog entries no longer need to defer it.
- **Opens:** Symlink-mode auto-elevation UX (currently requires user to pre-enable Developer Mode); porting a minimal `Sync-AgentPacks.sh` for *nix hosts.

### Supersedes
- **Deprecates** the direct-install pattern in `install-agents.ps1` (kept as a forwarding wrapper; scheduled for removal).
- **Closes** the "parameterized `-Pack` installer" follow-up noted in ADR-0002 (Consequences) and ADR-0003 (Consequences).
- Extends ADR-0001, ADR-0002, ADR-0003.

---

## ADR-0005: License Choice — PolyForm Noncommercial 1.0.0

**Date:** 2026-04-19
**Status:** Accepted
**Phase:** Initialize
**Deciders:** Greg (Onward Investment LLC)

### Context
The repository is being published to GitHub (`ggrace519/claude-code-dev-studio`). A license is required to (a) let noncommercial users legally use the playbook and agent library, and (b) preserve the right to charge companies that want to use the work in commercial products or services. Without a license, visitors have no legal permission to use, copy, or modify the repository at all.

Constraints:
- **Noncommercial free / commercial paid** is the explicit goal. Permissive OSI licenses (MIT, Apache-2.0) and weak-copyleft (LGPL) all permit commercial use without payment and were ruled out.
- **Single license for the whole repo.** Mixed content (PowerShell code, markdown playbook, 105 agent prompts) — splitting into code-vs-docs licenses adds friction without useful protection.
- **Solo maintainer.** A dual-license operation (e.g., AGPL + commercial) was rejected as premature overhead.
- **Copyright held by Onward Investment LLC**, not the maintainer personally, so that a future commercial license offering can be executed by the entity rather than the individual.

### Decision
License the repository under **PolyForm Noncommercial 1.0.0** (<https://polyformproject.org/licenses/noncommercial/1.0.0>). Copyright held by **Onward Investment LLC**.

Artifacts added this session:
- `LICENSE` — verbatim PolyForm Noncommercial 1.0.0 text with `Required Notice: Copyright 2026 Onward Investment LLC. All rights reserved.` and a commercial-inquiry contact line pointing to `contact@519lab.com`.
- `README.md` — project overview, quick start, license summary, commercial contact.
- `CONTRIBUTING.md` — declares that all contributions grant Onward Investment LLC a perpetual, worldwide, relicense-capable license. DCO-style affirmation in lieu of a full CLA. Preserves the ability to offer a separate commercial license without re-negotiating with past contributors.
- `.gitignore` — excludes per-consumer `.pack-manifest.json`, OS cruft, editor state.

### Rationale
- **PolyForm Noncommercial draws the bright line the project wants.** "Any noncommercial purpose is a permitted purpose"; commercial use is prohibited without a separate license. Individuals, students, hobbyists, nonprofits, schools, and government institutions are explicitly permitted.
- **Drafted by specialized counsel** (Heather Meeker + Kyle Mitchell). Standardized, legally reviewed, reusable — avoids the ambiguity of hand-written non-commercial clauses or "Commons Clause + MIT" hybrids.
- **No sunset.** Unlike BSL, there is no automatic conversion to open source; that suits a maintainer-owned playbook that may always want to charge commercial users.
- **Short and readable.** One-page structure with named clauses; easier to reason about than BSL's change-date mechanics or ELv2's managed-service carve-out.
- **Inbound=outbound-plus for contributions.** The CONTRIBUTING.md terms intentionally go beyond "inbound equals outbound" by granting Onward Investment LLC relicensing rights. Without this, every past contributor would need to be re-contacted before offering a commercial license — the MongoDB-era lesson that blocked many dual-license transitions elsewhere.
- **Copyright held by the entity, not the individual.** Onward Investment LLC holds the rights, enabling clean commercial license issuance, invoicing, and enforcement from the correct legal actor.

Alternatives considered and rejected:
- **MIT / Apache-2.0.** Permit commercial use outright; contradict the stated goal.
- **AGPL-3.0 alone.** Allows commercial use subject to copyleft; in practice many companies ship AGPL software privately without sharing modifications. Does not achieve "companies pay."
- **AGPL-3.0 + commercial dual license.** Effective but requires sales / contracts / invoicing operations; premature for a solo-maintained playbook.
- **BSL 1.1.** Strong fit for company-backed OSS with a roadmap to open-source; change-date mechanics are overhead for this project.
- **Elastic License v2.** Permits most commercial use except hosted/managed-service resale; this project isn't a service at risk of being rehosted, so the carve-out doesn't fit.
- **Commons Clause + MIT/Apache.** Legally ambiguous patchwork; superseded by purpose-built source-available licenses.
- **Custom hand-written license.** Unacceptable legal risk; hostile to adoption.

### Consequences
- **Repository is source-available, not open source.** This is intentional. Discovery via GitHub's license filter will list it as "Other" or "PolyForm Noncommercial," not as an OSI-approved license. Some OSS directories will exclude it; that's the tradeoff.
- **Commercial use requires a separate license from Onward Investment LLC.** The inquiry channel is `contact@519lab.com` (stated in `LICENSE`, `README.md`, and `CONTRIBUTING.md`).
- **Contributors grant Onward Investment LLC relicensing rights.** Contribution volume may be lower than for OSI-licensed projects; this is acceptable and expected.
- **Relicense path remains open.** Onward Investment LLC (sole rights holder, plus contributor inbound grants) can later relicense the repository under a more permissive license (MIT, Apache-2.0) or a different source-available license (BSL, ELv2) without clearing past contributors.
- **Enforcement falls on the copyright holder.** A license without enforcement is just a polite request. Active enforcement is optional but the right to enforce is preserved.
- **Noncommercial definition follows the PolyForm text.** Edge cases (consultants, nonprofits charging fees, dual-use research) are governed by that definition; disputes should reference the license text rather than improvised criteria.

### Supersedes
None. Complements ADR-0001 through ADR-0004. Establishes the licensing baseline for all artifacts in this repository going forward.

---

## ADR-0006: JIT Agent Loading Architecture

**Date:** 2026-04-24
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg Grace

### Context

Loading all 105 agent files at Claude Code session start imposes a confirmed overhead of ~17,000 tokens on every session regardless of the project type. For a project that uses only 2–3 packs, this burns context budget on 90+ irrelevant agent definitions. The goal is to make the correct agents available at runtime without paying the full 17k token cost on unrelated projects.

Two constraints drive the design:
1. **Claude Code loads agents statically at session start** — there is no mid-session agent injection mechanism. Any "loading" must occur before the next session begins.
2. **The global `~/.claude/agents/` directory** is the only location Claude Code reads agents from at startup. Per-project `.claude/agents/` directories are also read when Claude Code is opened in that directory.

### Decision

1. **7 generalist agents live permanently in `~/.claude/agents/`** — they are always loaded (~1,500 tokens, acceptable), trigger on all projects, and contain no pack-specific logic.

2. **98 pack agents are stored in `~/.claude/playbook/agents/`** (inside the installer-managed prefix) — they are never loaded automatically and add zero token overhead until explicitly activated.

3. **`~/.claude/playbook/catalog.json`** is a machine-readable index of all 105 agents (name, pack, model, description). Claude reads this during project initialization to select relevant agents without loading the agent files themselves.

4. **JIT selection and copy** — when a user starts a new project or runs `/sync-agents`, Claude:
   - Reads `catalog.json` and matches agents to the project context
   - Copies selected pack agent `.md` files from `~/.claude/playbook/agents/` to `./.claude/agents/`
   - Presents an activation summary and requests a session restart
   - After restart, only the selected agents are loaded into context

5. **`~/.claude/CLAUDE.md` injection** — the JIT protocol is injected as a marker-bounded block (`# >>> claude-playbook >>>` / `# <<< claude-playbook <<<`) into the user's global CLAUDE.md by the installer. The block is idempotent (safe to re-run on update) and non-destructive (content outside the markers is never touched). Uninstall removes the block cleanly.

6. **`scripts/jit-claude.md`** is the canonical source of the injected block. It is bundled in the release ZIP and read by the installer at install/update time, ensuring the protocol text stays in sync with the agent library version.

### Rationale

**Why not load all 105 agents globally?**
Empirically confirmed 17,000-token overhead. On a project that only needs `infra` agents, loading `game-`, `media-`, `embed-`, and 10 other packs wastes budget and pollutes auto-invocation matching.

**Why not a dynamic mid-session load?**
Claude Code's agent system is static-at-startup. There is no API to register an agent mid-session. The pre-session copy-then-restart approach is the only viable path given this constraint.

**Why `~/.claude/playbook/` instead of a separate prefix like `%LOCALAPPDATA%\ClaudePlaybook`?**
Claude Code's native config directory is `~/.claude/`. Keeping the agent library inside it (`~/.claude/playbook/`) reduces the installation surface: no separate tool-specific directory, no separate PATH-management concern for the library itself. The CLI dispatcher (`~/.claude/playbook/bin/`) still goes on PATH, but the library data lives adjacent to where Claude Code expects config.

**Why a marker block in CLAUDE.md rather than a separate include?**
Claude Code does not support include directives in CLAUDE.md. A marker block in the single global CLAUDE.md is the only way to inject persistent global instructions. The marker pattern (`# >>> ... >>>` / `# <<< ... <<<`) mirrors the established convention used by the shell-rc PATH management in the same installer.

**Why `catalog.json` rather than reading all 105 agent files?**
Reading 105 `.md` files during project init would itself consume tokens and incur file I/O. The catalog provides structured metadata (name, pack, model, description) at negligible cost. Descriptions are pre-cleaned: `<example>` blocks and `\\n` escapes are stripped so the catalog is a flat, scannable JSON array.

### Consequences

- **Token cost at startup:** 7 generalists only (~1,500 tokens); pack agents contribute zero until activated per-project.
- **Per-project restart required on first activation:** users must restart Claude Code after the first `claude-playbook sync` or `/init` run in a new project. This is a one-time friction per project.
- **Pack agents are project-scoped:** `./.claude/agents/` accumulates pack agent files per project. `claude-playbook sync --clean` removes them; the 7 generalists in `~/.claude/agents/` are never touched by clean.
- **Installer must manage two destinations:** generalists → `~/.claude/agents/`, pack agents stay in `~/.claude/playbook/agents/`. Build-release must bundle all 105 agents flat in `agents/` and the installer separates them post-extraction.
- **CLAUDE.md must exist or be creatable:** installer creates `~/.claude/CLAUDE.md` if absent. Uninstall removes the marker block but leaves the file intact.

### Supersedes
Partial supersession of ADR-0004 (`Sync-AgentPacks.ps1` as canonical activation mechanism): `Sync-AgentPacks.ps1`/`.sh` remain for explicit pack-to-project copying, but the JIT flow (Claude-driven via `catalog.json` + CLAUDE.md instructions) is now the primary activation path. `sync` commands become the explicit fallback.

---

## ADR-0007: Domain-Agent + Skills Architecture

**Date:** 2026-06-03
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg Grace

### Context

ADR-0001 through ADR-0006 grew the system to **105 agents** (7 generalists + 98 pack
specialists), with ADR-0006 introducing JIT activation to avoid the ~17,000-token cost
of loading all of them. JIT reduced the token bill, but three structural problems remained
once the goal was stated as **"Claude can access and use the playbook efficiently,"** not
just "minimize tokens":

1. **Subagents cannot reach other subagents.** Claude Code forbids subagent nesting
   (subagents cannot spawn subagents) but **permits subagents to invoke skills via the
   Skill tool**. Every `*-expert` was an agent, so a running specialist (e.g.
   `saas-billing-expert`) could not consult a sibling (`saas-auth-sso-expert`) directly —
   it had to return to the orchestrator and ask. Cross-specialty work bounced through the
   main loop on every handoff.

2. **The routing surface was 98 near-identical expert descriptions.** Auto-invocation
   routing degrades when the choices overlap finely ("billing vs entitlement vs
   multitenancy") instead of being distinct ("is this a SaaS task?"). Descriptions also
   carried literal `\n` escapes and 2–3 `<example>` blocks each — noise that buried the
   routing signal (the `catalog.json` descriptions were pre-cleaned per ADR-0006, but the
   agent **files** were not).

3. **JIT activation required a session restart** for the selected agents to load, after
   the orchestrator had already spent effort selecting them.

The enabling facts (verified against Claude Code docs, v2.1.153+): agent **descriptions**
load at session start for routing; agent **bodies** load only inside the spawned subagent;
**skills** load only `name`+`description` at start (project-scoped skills load only in that
project) with the body fetched JIT on invocation; subagents inherit all tools (including
`Skill`) when `tools:` is omitted, and can invoke project/user/plugin skills during a run.

### Decision

Collapse the per-pack architect+experts bundle into **one domain agent per pack, backed by
skills it composes on demand.**

1. **19 agents, always installed in `~/.claude/agents/`** (no per-project agent
   activation):
   - **14 domain agents** — one per archetype pack (`saas`, `ai`, `infra`, `game`,
     `mobile`, `dataplat`, `ecom`, `fintech`, `devtool`, `desktop`, `ext`, `embed`,
     `media`, `orch`). Each body = the former `*-architect` persona + a **skill manifest**
     listing the domain skills it pulls and when.
   - **5 core agents** — `plan-architect`, `pr-code-reviewer`, `secure-auditor`,
     `test-writer-runner`, `deploy-checklist` (genuine delegated workers that run isolated
     and return a result).

2. **Skills (visible, project-scoped, JIT-activated into `.claude/skills/`):**
   - **~84 domain skills** — every former `*-expert` becomes a `SKILL.md` grouped under
     its domain (`saas-billing`, `saas-auth-sso`, …). The expert body moves over near
     verbatim.
   - **5 cross-cutting skills** — the former `common-*` agents (a11y, i18n, privacy,
     notifications, analytics), reachable by **any** domain agent mid-task.
   - **2 former core → skills** — `api-design` (from `api-expert`) and `ux-design` (from
     `ux-design-critic`), so a domain agent can reach API/UX guidance in place.
   - **2 checklist skills** — `security-checklist` and `code-review-checklist`, the
     **reference half** of `secure-auditor` / `pr-code-reviewer`. The agents keep the
     **action half** (isolated audit/review returning findings) and themselves pull the
     checklist skill; a domain agent can pull the checklist directly without a round-trip.
   - **`playbook-conventions`** — the output-format skeleton, handoff protocol, and ADR
     format formerly hand-copied into all 98 bodies, now a single source of truth.
   - **`sync-agents`** — the JIT activation protocol, lifted out of the global `CLAUDE.md`
     marker block (which shrinks to a ~5-line pointer).

3. **Skills are "visible," not hidden.** Project-scoped skill descriptions load only in a
   project where that domain is activated; both the main loop and the domain agent may
   invoke them. `disable-model-invocation` is **not** used — direct main-loop access to a
   skill is itself efficient access, and the per-project description cost is small and
   relevant.

4. **Activation inverts.** The always-on layer becomes the cheap 19 trimmed agents
   (~850 tokens total — *less* than the 7 verbose generalists cost today). The JIT layer
   becomes the **skills**: `sync-agents` copies the relevant domain's skills from the
   playbook library into `.claude/skills/`. `catalog.json` indexes agents and skills
   separately.

### Rationale

- **Skills compose downward; agents do not.** This is the decisive fact. Making each
  domain a single agent that pulls skills lets one spawned worker handle a billing+auth
  task in one coherent context, instead of bouncing between isolated expert subagents via
  the orchestrator.
- **Routing surface drops 98 → ~21.** The orchestrator chooses among distinct domains plus
  the core workers — higher routing accuracy, lower noise.
- **The "mega-agent" objection from ADR-0001 is answered, not ignored.** ADR-0001 rejected
  "single mega-agent per archetype" because it would erase specialist depth. Here the depth
  is **preserved as skills** — the expert bodies survive intact and load JIT; only their
  packaging changes from "sibling agent the worker can't reach" to "skill the worker
  pulls."
- **Always-on agents are now cheaper than the status quo.** 19 trimmed descriptions
  (~850 tokens) undercut today's 7 verbose generalists (~1,500 tokens), so the per-project
  agent-activation/restart dance disappears for the agent layer entirely.
- **One source of truth for conventions.** `playbook-conventions` replaces 98 drifting
  copies of the output/handoff/ADR boilerplate.

Alternatives considered and rejected:
- **Keep 98 expert agents, only trim descriptions.** Fixes routing noise but not the
  no-nesting composability problem; experts still can't reach each other.
- **Convert experts to *global* skills.** Would load all ~95 skill descriptions in every
  session everywhere — strictly worse than project-scoped JIT.
- **Hide domain skills behind `disable-model-invocation`.** Rejected — removes the option
  of cheap direct main-loop access for no meaningful saving.
- **Fold the architect into the domain agent but keep experts as agents.** Half-measure;
  retains the routing bloat and the handoff round-trips.

### Consequences

- **Migration surface is large and one-shot:** 98 agent files → 14 domain agents +
  ~95 skills; `catalog.json` + `build-catalog.*` reworked to index two artifact types;
  `jit-claude.md` slimmed; `install-playbook.*`, `Sync-AgentPacks.*`, `verify-agents.*` /
  `Verify-Agents.ps1`, `build-release.*`, and `bin/ccds.*` updated to manage an
  agents-always-on + skills-library layout; both `CLAUDE.md` files rewritten.
- **Restart friction reduced, not eliminated:** agents never need activation; newly
  copied skills still need a session refresh to be discovered (same as any skill install).
- **Skill scoping mechanics:** domain skills live in `~/.claude/playbook/skills/` and are
  JIT-copied to `.claude/skills/`; `sync --clean` removes project skills, never the 19
  global agents.
- **`common-` becomes skills-only** — it is no longer an agent pack; existing references in
  docs/CLAUDE.md are updated.
- **Backward compatibility:** projects with old per-project `.claude/agents/*-expert.md`
  files keep working until re-synced; `sync --clean` plus a fresh `sync` migrates them.
- **Versioning:** ships as a minor/major release with a CHANGELOG entry; the installer
  remains idempotent and BOM-less per ADR-0001.

### Supersedes
- **ADR-0006 (JIT Agent Loading Architecture)** — superseded in substance: the JIT unit
  becomes skills, not agents; the 19 agents are always-on. The catalog and `sync` flow
  carry forward in restructured form.
- **Partial supersession of ADR-0001 and ADR-0003** — the flat per-pack `*-expert` *agent*
  layout and the `common-` *agent* pack are replaced by the domain-agent + skills layout;
  the prefix registry and "compose, don't replace" invariant are retained.

---

## ADR-0008: Native Claude Code Plugin Marketplace as a Distribution Channel

**Date:** 2026-06-12
**Status:** Accepted
**Phase:** Deployment
**Deciders:** Greg Grace

### Context

Distribution was entirely hand-rolled: ~1,400 lines of dual bash/PowerShell installer
(`Install-Playbook.*`, `install-playbook.sh`) plus a `ccds` dispatcher doing SHA256
verification, stage/promote, PATH management, and `~/.claude/CLAUDE.md` block injection.
Since the v0.8.0 cut, Claude Code's **plugin marketplace** system reached stable: a
`.claude-plugin/marketplace.json` catalog of versioned plugins, each shipping
skills/agents/hooks, with native install, enable/disable, pinning, and
`/plugin marketplace update`. The playbook's pack architecture (one domain agent + its
`<pack>-*` skills) maps 1:1 onto the plugin unit, so the native system can do for free
most of what the installer does by hand.

### Decision

Ship the repo **also** as a native plugin marketplace, generated from the library source:

1. `scripts/build-marketplace.py` (sibling of `build-catalog.py`) emits a checked-in
   `.claude-plugin/marketplace.json` + `plugins/` tree: `ccds-core` (the 5 core agents +
   cross-cutting skills) plus one `ccds-<pack>` plugin per archetype (its domain agent +
   `<pack>-*` skills). 15 plugins, 19 agents, 89 skills.
2. Generation is **deterministic and git-state-independent**. Plugins are emitted
   **without a `version` field** by default — a git-hosted marketplace lets the commit
   SHA drive updates — so the committed tree is byte-stable across release tags and the
   `marketplace-freshness` CI job (regenerate + `git diff --exit-code`) never races a
   version bump. `--version` pins an explicit semver when a snapshot is wanted.
3. Plugin `source` entries use explicit `./plugins/<name>` relative paths rather than
   `metadata.pluginRoot` + bare names — identical meaning, but accepted by older Claude
   Code versions (the bare-name form failed on a locally installed build).
4. `sync-agents` is **excluded** from plugins: it drives the ZIP-install JIT skill-staging
   flow, which plugin enablement replaces.
5. The ZIP / `.deb` / `.rpm` installer path and the `ccds` CLI are **retained unchanged**.
   The marketplace is an additional, parallel channel — not a replacement.

### Rationale

- **The native system already solves distribution.** Versioning, updates, per-plugin
  enable/disable, and pinning come from Claude Code, not from maintained shell code.
- **1:1 architectural fit.** The pack = plugin mapping required no re-architecture; the
  generator is a thin projection of the existing tree.
- **Verified, not assumed.** The full cycle (`marketplace add` → `install ccds-saas` →
  component inventory → `uninstall`) was exercised against the real `claude` CLI before
  merge; CI gates tree freshness on every push.
- **Unversioned-by-default removes a footgun.** Baking a git-derived version into a
  committed-and-freshness-checked file creates a tag-push race; omitting it is also the
  documented recommendation for git-hosted marketplaces.

Alternatives considered and rejected:
- **Replace the installer with the marketplace.** Rejected — the `ccds` CLI, global
  `~/.claude/playbook/` library, and per-project skill staging have no plugin equivalent
  yet; keeping both serves CLI users and plugin users.
- **Pin a semver into every plugin from `git describe`.** Rejected — the tag-push freshness
  race (CI regenerates at the new tag and diffs against the old committed version).
- **Hand-maintain `marketplace.json`.** Rejected — drifts from the source tree; the
  generator + freshness gate is the same discipline as `catalog.json`.

### Consequences

- New checked-in `.claude-plugin/` + `plugins/` trees (~500 KB; agent/skill content is
  duplicated from source, regenerated by the generator and gated by CI).
- `README.md` documents the plugin path as the recommended install alongside the ZIP.
- The release ZIP / packages do **not** bundle `plugins/` — the marketplace is consumed
  directly from git via `/plugin marketplace add`.
- Future hooks-based features (e.g. phase gates) slot in as a 16th plugin.

### Supersedes
None. Complements the installer (ADR-0004 / ADR-0006 / ADR-0007), which remains the
canonical CLI path.

---

## ADR-0009: Skill Authoring Convention — Reference Voice, Concrete Artifacts, Enforced by Lint

**Date:** 2026-06-12
**Status:** Accepted
**Phase:** Documentation
**Deciders:** Greg Grace

### Context

ADR-0007 moved the former `*-expert` **agent bodies** into **skills** "near verbatim."
That preserved the expertise but left the skill library speaking in agent voice. Measured
on the v0.8.0 tree: 88/90 skill bodies closed with "return to the orchestrator," 86
carried "You do NOT own → `<agent>`" ownership blocks, 86 had per-skill "Output Format"
sections duplicating `playbook-conventions`, only 2 contained any code block, and 0 shipped
a bundled resource file. A skill is reference material loaded into whatever context pulls
it (the main loop or a domain agent) — agent-era choreography there is noise and can
contradict the pulling agent's own instructions. Nothing enforced any of this, and small
drift had already appeared (a wrong-owner install URL; a non-existent model-ID pin).

### Decision

1. **Adopt a skill-voice authoring convention** (`docs/skill-authoring.md`): no persona, no
   scope/ownership blocks, no per-skill Output Format, no orchestrator choreography;
   principles sharpened with concrete defaults; at least one concrete artifact (decision
   table, checklist, or skeleton); large artifacts in `references/*.md` linked one level
   deep (progressive disclosure); a one-line *Related* footer. Aligned with Anthropic's
   published skill-authoring best practices.
2. **Convert all 88 in-scope skills** to the convention, adding 16 bundled `references/`
   resources. Frontmatter `description` fields are untouched — the routing surface and
   `catalog.json` are unchanged. `playbook-conventions` and `sync-agents` are exempt
   (the former documents the handoff protocol; the latter is a procedural meta-skill).
3. **Enforce it.** `scripts/lint-playbook.py` checks the library's own claims —
   skill cross-references (both directions), catalog freshness, canonical repo URL,
   description style, dated-model pins, token budget, and agent-voice leakage in skill
   bodies. A fixture-based `tests/` suite covers the generators and every lint check. Both
   run in CI; `ccds lint` exposes the linter. The `skill-voice` and `model-values` checks
   are **errors** once the corresponding fixes have landed, so the cleanup cannot regress.
4. **Align core agents with subagent best practices** (same release): tier-alias models;
   `skills:` preload on the two checklist-pulling agents; `disallowedTools` on the three
   read-only verdict agents.

### Rationale

- **Voice correctness.** The pulling agent already owns routing and handoffs; the skill
  should be expertise, not a second actor giving conflicting orders.
- **Concrete earns its tokens.** A skill of generic senior heuristics mostly restates what
  a frontier model knows; decision tables, thresholds, and skeletons are the part that
  changes an outcome.
- **Lint makes the convention durable.** Without enforcement the next near-verbatim paste
  re-introduces agent voice; the error-level checks turn the one-time cleanup into a
  ratchet.

Alternatives considered and rejected:
- **Convert opportunistically when a skill is touched.** Rejected — leaves the library
  half-and-half indefinitely and gives the lint nothing it can enforce at error level.
- **Mechanical strip of banned phrases.** Rejected — it removes the noise but not the gap;
  the value is the added concrete layer, which is per-skill content work.

### Consequences

- 88 skill bodies rewritten; 16 new `references/*.md`; `docs/skill-authoring.md` is the
  standard for new skills.
- `catalog.json` byte-identical (descriptions untouched); routing unaffected.
- CI gains `lint-playbook` and `python-tests` jobs; `ccds lint` added to both dispatchers.
- The plugin marketplace (ADR-0008) ships the converted skills and bundled resources.

### Supersedes
None. Refines the skill layer established by ADR-0007.

## ADR-0010: `loop-` Pack — Cross-Cutting Agent-Loop Process Skills

**Date:** 2026-07-03
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg Grace

### Context

The library is ~95% domain knowledge (`saas-*`, `embed-*`, …) and near-0% process
knowledge — how an agent should run its own work loop. The fastest-growing category in
the skill ecosystem is exactly that: obra/superpowers (~245k stars) owns the
brainstorm→plan→TDD loop niche; Anthropic's long-running-harness guidance and the Ralph
loop define unattended-run hygiene; Every's "compounding engineering" defines the
learning loop. None of it ships as independently installable, lint-conformant library
skills, and ccds's own conventions (ADR-0009 voice, catalog, marketplace, dual
installers) are a ready distribution channel. Scoped by the user request: transferable,
reusable agent-loop skills for general coding projects.

### Decision

1. **Add a `loop-` cross-cutting pack** of six process skills — `loop-verify`,
   `loop-debug`, `loop-review`, `loop-parallel`, `loop-long-horizon` (with a bundled
   `references/state-files.md` kit), `loop-compound`. Skills-only, no owning agent —
   the `common-` precedent: loops are composed by whatever context is working.
2. **Scope=global.** Installed once to `~/.claude/skills/` (both installers'
   GLOBAL_SKILLS lists; `build-catalog.py` treats the `loop-` prefix like `common-`),
   because process skills apply to every project regardless of stack.
3. **Ship as a dedicated `ccds-loops` marketplace plugin** (category `workflow`), not
   inside `ccds-core` — the pack is the library's most harness-agnostic content and
   should be installable on its own.
4. **Process-skill authoring rules** appended to `docs/skill-authoring.md`: trigger-style
   descriptions (when, never what), exactly one bold iron law per skill, and a
   rationalization table — the mechanics superpowers measured as moving compliance
   33%→72%.

### Rationale

- **Curation over invention where the field converged** — each loop cites its sources
  (superpowers, Anthropic harness post, Ralph, compound engineering); the value is the
  integration into ccds's enforced conventions, not novelty for its own sake.
- **No `loop-architect`.** An owning agent would contradict the cross-cutting design and
  the composition rule that skills load into whatever context is already working.
- **TDD and brainstorming deliberately excluded** — superpowers' implementations are
  canonical and MIT; ccds routes those needs to `test-writer-runner` / `plan-architect`.

### Consequences

- Prefix registry gains `loop-`; `lint-playbook.py` validates `loop-*` references.
- Six more always-available skill descriptions in every session (~150 tokens).
- Follow-ons proposed in INNOVATIONS.md (2026-07-03): enforcement hooks for the
  `ccds-loops` plugin, a `ccds loop init` scaffolder, compliance pressure-tests.

### Supersedes
None. Extends the cross-cutting layer established by ADR-0003/ADR-0007.

---

## ADR-0011: Loop Enforcement Layer — File-Enforced Control Primitives

**Date:** 2026-07-06
**Status:** Accepted
**Phase:** Hardening
**Deciders:** Greg Grace

### Context

ADR-0010 shipped the `loop-` process skills as prose contracts (iron laws +
rationalization tables) and named, as explicit follow-on work, "enforcement
hooks for the `ccds-loops` plugin." Prose sets intent; it does not survive
session death, a model reroute, or a mid-task incentive to cut a corner. The
`ccds-loops` plugin already carried exactly one real gate (`stop-gate.sh`, an
opt-in *command* gate) and a SessionStart context injector — everything else the
loops assert (verify before done, reversible-first, files-not-context, learn on
repeat) lived only in the model's head.

The governing question for this ADR was applied to every candidate change:
**"Which file enforces this tomorrow?"** Anything answerable only with "the
prompt" or "the model will remember" was rejected as wishful thinking.
Enforcement had to live in a hook, a schema, an eval, or a data file.

### Decision

Add an enforcement layer to the `ccds-loops` plugin (hooks) plus one repo
script, converting the load-bearing loop contracts into file invariants. Six
primitives were specified; five were built, one deferred:

1. **Delivery gate** — `stop-evidence-gate.py` (Stop hook). A tracked cycle may
   not end without `.claude/evidence/<cycle_id>.json` carrying a `PASS`/`FAIL`
   verdict; missing/invalid → `exit 2` with the required shape fed back.
   Opt-in and cycle-scoped (armed by `CCDS_LOOP_CYCLE` env or a
   `.claude/loop-cycle` marker) so ad-hoc sessions are untouched. `FAIL`
   satisfies the gate — honest failure is compliance; the blocked anti-pattern
   is a silent done-claim. Runs beside the existing command gate.
2. **Pre-tool risk guard** — `pretooluse-risk-guard.py` (PreToolUse, matcher
   `Bash`). Blocks (`exit 2`) an irreversible/blast-radius deny-list (`rm -rf /`,
   `rm -rf *`, `mkfs`, `dd of=/dev/…`, forkbomb, `zpool destroy`,
   `DROP DATABASE`/`DROP TABLE`/`TRUNCATE`); non-blocking WARN (`exit 1`) for
   fleet-wide SSH fan-out. Deny-list is a separate data file
   (`risk-deny-list.txt`); fails open if unreadable.
3. **Pre-compact handoff writer** — `precompact-handoff.py` (PreCompact). Snapshots
   open cycle id, last-N evidence verdicts, `git status --short`, and last-5
   commits to `.claude/handoff.md`; `loop-long-horizon`'s bootstrap ritual reads
   it back. Always `exit 0`.
4. **Evidence sink, dual-tier** — fast tier is the `.claude/evidence/*.json`
   files the delivery gate reads; durable tier is `posttooluse-evidence-log.py`
   (PostToolUse, matcher `Write|Edit`) which validates + **secret-scans** each
   evidence write (`exit 2` on a planted secret) and mirrors it to Postgres via
   `psql` — optional, env-only DSN, no-op without `CCDS_EVIDENCE_DSN`/`psql`,
   idempotent DDL in `agent-evidence.sql`.
5. **Failures → evals** — `scripts/evidence-to-evals.py`. Scans recurring `FAIL`
   verdicts by task (Postgres or local) and emits stubs in the *existing*
   `scenarios.json` schema to a separate review file, deduped against promoted
   ids. No new eval schema.
6. **Budget governor** — **DEFERRED, not built.** A reliable token counter is not
   available to hooks, and there is no always-on per-tool-call hook to cheaply
   piggyback a call counter without adding one solely for this. Recorded here
   rather than half-built, per the "don't gold-plate / don't half-build" rule.

All new hook/enforcement files are BOM-less UTF-8 and comply with ADR-0001;
hooks are python3 (matching the repo's existing `loop-skill-edited.py`
PostToolUse hook, and because JSON-on-stdin parsing in bash is fragile). The
plugin's original `stop-gate.sh`/`session-start.sh` are unchanged.

### Rationale

- **Model-agnostic by construction.** Every gate decides from a file (evidence
  JSON, deny-list, handoff) rather than from the model's prose, so a silent
  model reroute cannot break the `PASS`/`FAIL` contract or the risk guard. This
  was a hard constraint, and files are precisely how it is met.
- **Opt-in where blunt enforcement would harm.** The delivery gate arms only on
  a declared cycle; the risk guard fails open; the durable tier no-ops without a
  DSN. Enforcement that fired on every ad-hoc session would train users to rip
  the plugin out.
- **Reuse over invention.** The failures→evals bridge emits into the existing
  compliance schema; the durable tier reuses the task-provided DDL verbatim; the
  evidence schema is the one the delivery gate already documents in its own
  error message.
- **python3 over dual .sh/.ps1 for the new hooks.** One interpreter, cross-
  platform, and real JSON parsing — versus bash-only string wrangling or a
  doubled .ps1 surface. The plugin's pre-existing bash hooks stay as they are.

### Consequences

- The `ccds-loops` plugin now wires five hook events (was two):
  PreToolUse, PostToolUse, PreCompact, SessionStart, Stop. `plugins/` is
  regenerated from `plugin-extras/` (marketplace-fresh lint enforces the copy).
- `tests/test_playbook_scripts.py` gains ~43 cases across the five primitives;
  the pre-existing `test_loops_plugin_ships_hooks` was updated from the old
  two-event surface to the new five.
- **Empirical finding (2026-07-06): the handoff read is wired via the
  SessionStart hook, NOT the compliance-measured skill body.** The first attempt
  added a bootstrap bullet to `loop-long-horizon/SKILL.md`. Live measurement
  (`eval-loop-compliance.py`, haiku) bisected it against `main`: the pristine
  body scored 9/9 votes on `long-horizon-second-task`; the edited body scored
  ~11/15 (≈73%) — a measurable regression of the one-task iron law, exactly what
  the compliance eval exists to catch. Resolution honoring the "which file
  enforces this" principle: revert the SKILL.md body to pristine and wire the
  `.claude/handoff.md` read into `session-start.sh` (the hook that fires on
  session boot / "continue") plus the bundled `references/state-files.md`
  bootstrap step. The eval injects only SKILL.md bodies, so neither the hook nor
  the reference touches the measured wording. Net effect: **no loop-* SKILL.md
  body differs from `main`, so the committed 2026-07-03 compliance baseline
  remains valid and current** (pristine body re-verified at 9/9); no re-record
  was warranted, and the handoff read is enforced by a hook rather than by prose
  that costs compliance.
- Three loop stages remain **impossible to file-enforce** and are named so no one
  pretends otherwise: **intent** (what to build is a human judgment), **decide**
  (choosing the next action from a digest is the model's reasoning), and
  **tools-early / dispatch selection** (which tool to reach for first). Files can
  gate the *outputs* of these stages (evidence, risk, handoff) but not the
  judgment itself.
- Budget governor deferral remains open follow-on work.

### Supersedes
None. Implements the enforcement-hooks follow-on named in ADR-0010's
Consequences; composes with the command gate and context injector already there.

---

## ADR-0012: `ccds-guard` — Zero-Config Security Guard Plugin (Pipeline Gate 1)

**Date:** 2026-08-04
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg Grace

### Context

CCDS's users are vibe coders: they will not configure linters, read security
docs, or review diffs unprompted. A five-gate quality/security pipeline was
agreed (in-session hooks → session config → pre-commit → CI → review process)
so that any CCDS-powered project inherits protection with zero configuration.
The 2026-08-04 hook audit found Gate 1 almost entirely unbuilt: the only
shipped hooks are the `ccds-loops` process-enforcement layer (ADR-0011), whose
risk guard covers a fragment of "dangerous commands" under a deliberately
catastrophic-only charter. No secret-path guard, no install gate, no tamper
watch exists, and hooks ship through exactly one outlet (the plugin
marketplace) — the classic installer wires none.

Facts verified before this decision (2026-08-04, Claude Code docs + live test):
- PreToolUse/PostToolUse hooks fire for subagent tool calls too; the payload
  carries `agent_id`/`agent_type`. Confirmed live: a logging PreToolUse hook
  recorded a Task-subagent's Bash call. Domain agents cannot bypass the guard.
- A PreToolUse hook may return `hookSpecificOutput.permissionDecision`
  `allow|deny|ask` via stdout JSON (exit 0); `permissionDecisionReason` is
  shown to the user. Exit 2 + stderr is the block path (stdout ignored).
- A `ConfigChange` hook event exists (matchers `user_settings`,
  `project_settings`, `local_settings`, `skills`); exit 2 can block.
- `claude plugin install <name>@<marketplace> --scope user` is scriptable.

### Decision

Ship Gate 1 as a **new, separate plugin `ccds-guard`** — not folded into
`ccds-core` or `ccds-loops` — with a **protective-only charter**:

1. **Secret-path guard.** File tools (Read/Write/Edit/NotebookEdit, plus
   Grep's `path` param — Grep is read-shaped) touching secret-bearing paths
   (`.env*`, key material, `id_*` SSH keys, `.ssh/`, credential stores
   (anchored, not bare substring — `credentials_manager.py` must stay
   editable), `secrets/`, `.netrc`, `.git-credentials`, `*.tfstate`) are
   **denied** (exit 2). The same paths appearing in a Bash command **ask**
   instead of deny — `source .env`-style commands are sometimes legitimate,
   and a prompt keeps false positives from teaching users to uninstall the
   guard. Explicit allow-list exempts `.env.example`-style templates.
2. **Dangerous-command guard (Bash).** Deny: force-push (`--force-with-lease`
   exempted), curl/wget piped to a shell, `chmod 777`, TLS-verification
   disables (curl `-k`, `--no-check-certificate`, git/npm/env-var forms), and
   recursive force-deletes outside the project. Complements — does not replace
   or modify — the catastrophic-only `ccds-loops` risk guard.
3. **Install ask-gate (slopsquatting).** Installing a *named* package
   (npm/pnpm/yarn add, pip/uv install <name>, cargo add, go get, gem install,
   composer require) returns `permissionDecision: "ask"` with a reason telling
   the user to verify the package exists on the registry first. Bare lockfile
   restores (`npm install`, `pip install -r`) pass untouched.
4. **Config tamper watch.** A `ConfigChange` hook (user/project/local settings
   matchers) surfaces a non-blocking warning when session config changes
   mid-session; additionally, Write/Edit to `.claude/settings*.json`,
   `.claude/hooks/`, `.claude/plugins/` (the guard's own installed rules
   included — no silent self-tamper), or `.pre-commit-config.yaml` returns an
   **ask** — users legitimately ask Claude to edit permissions, so a hard
   deny is wrong, but silent self-modification (including via prompt
   injection) is not allowed.

   *Post-review hardening, round 1 (same-day multi-model review, pre-merge):*
   the review panel found four HIGH regex defects — unanchored `credentials`
   substring (false-positived on everyday source files), quoted-path bypass
   of the rm deny, combined-short-flag bypass of `curl -k`, and leading-flag
   bypass of the npm/pnpm/yarn install ask — plus the Grep hole and
   self-tamper gap above. All fixed with the panel's failing cases encoded
   as regression tests; shell-quoting invisibility remains the documented,
   test-pinned limitation of the threat model.

   *Post-review hardening, round 2 (full codex + grok + Claude panel; 24/24
   unique claims verified, 0 hallucinated):* the panel's structural verdict
   was accepted — pure-regex rules kept failing on target-model and
   flag-order problems — so two checks moved from the data file into script
   logic: **rm-outside-project** now resolves each delete target (quotes,
   `~`/`$HOME`, relative paths) against the project dir, covering macOS
   `/Users`, WSL `/mnt`, `/` itself and `../siblings` while un-blocking
   in-project and `/tmp` deletes; and **path normalization** (normpath)
   runs before all rule matching, closing the `tests/fixtures/../../.env`
   traversal of the fixtures exemption. Bash tokens now get the full rule
   treatment (allow-path exemptions and the ask-write-path tamper watch —
   `echo {} > .claude/settings.json` asks). Rule fixes: credentials re-anchor
   regression (dirs + `credentials.yml.enc` restored), named `*.env` files,
   `+refspec`/`-uf`/`git -C` force-push variants (`--force-if-includes`
   exempted), multi-hop pipe-to-shell + process substitution (which also
   fixed the latent `| grep bash` false positive), curl k-cluster narrowed
   to boolean flags (`-Hk` un-blocked), one shared flag-skipping shape for
   all install gates (pre-command flags ask; pip/uv `-r` restores with
   flags un-blocked; bun + yarn-global added; `go get -u ./...` and
   redirection tokens un-blocked), `.pub` keys exempt, ConfigChange gains
   the `skills` matcher, installers refresh a stale marketplace before
   installing, and fail-open now warns on stderr instead of going silently
   inert. Every verified panel case is a row in the data-driven
   `test_round2_panel_matrix`. Named residual limitations: shell
   quoting/interpolation (pinned), and `python3`-on-PATH as a hook runtime
   requirement — native Windows without it leaves the guard inert (warn
   path); a dual launcher was rejected because `||` fallback would re-run
   the hook after legitimate exit-2 denials.

   *Post-review hardening, round 3 (focused codex + grok pass on the new
   path logic only):* wrapper-aware rm detection (assignments, wrapper args,
   `/bin/rm`, `\\rm`, `timeout`/`xargs`; text in `echo`/commit messages
   never matches), realpath containment so an in-project symlink cannot
   smuggle a delete outside (verified with a real symlink), the
   `proj="/"` rstrip-root containment collapse fixed, project-root
   protection now precedes the `/tmp` scratch exemption (CI projects under
   `/tmp`), relative-cwd resolution falls back to the project dir,
   drive-absolute (`C:/…`) paths recognized, Grep glob `{a,b}`/`[xy]`
   expansion joined with the search path (fixture context restored,
   fragments never glue into fake basenames), exclude-style options
   (`--exclude=.env`) and text-only commands (`echo`/`printf`/`export`)
   exempt from the secret ask — the tamper ask always still fires. All
   cases live in `test_round3_panel_matrix` + a real-symlink test. Newly
   named residuals: `find -exec` / `xargs`-fed deletes (targets invisible
   to the hook) and `~otheruser` expansion (resolves fail-closed).

Mechanics, reusing the ADR-0011 substrate: one python3 hook script
(`pretooluse-guard.py`) + one categorized data file (`guard-rules.txt`,
`deny-path` / `allow-path` / `ask-write-path` / `deny-command` / `ask-command`)
in `plugin-extras/ccds-guard/hooks/`, copied into the generated plugin by
`build-marketplace.py`. Every block/ask message teaches: what was stopped, why
it matters in plain language, and what to do instead. Kill switch:
`CCDS_GUARD_DISABLE=1`.

**Fail-open, backed by a harder layer.** The hook fails open (unreadable rules
file → allow) per ADR-0011's rationale: a guard that bricks the shell when its
data file breaks trains users to remove it. The non-negotiables (secret-path
denies) will ALSO ship as Gate-2 `permissions.deny` rules in the settings
template staged by sync (work item 3), which the harness enforces with no
runtime dependency — the hook is the teaching layer, the deny rule the hard
layer. Until Gate 2 ships, the hook is the only layer; that gap is accepted
and time-boxed, not hidden.

**Distribution: plugins are the only hook-shipping mechanism.** The classic
installer does not learn to write hooks into user settings; instead it
registers the repo as a marketplace and runs
`claude plugin install ccds-guard@ccds` (and `ccds-loops@ccds`) by default,
with a `--skip-plugins` flag to opt out. One mechanism, every outlet converges
on it (honors the every-outlet rule without doubling the hook surface).

**Out of scope, deliberately:** a stack-detected formatter hook. Edit-time
formatting only works when the formatter is installed, which for this audience
it usually is not; a hook that silently no-ops most of the time is a broken
promise. Formatting enforcement belongs to Gate 3 (pre-commit, which manages
its own tool environments) — work item 3's scope. The guard's v1 charter is
purely protective: zero dependencies, always fires.

### Rationale

- **Separate plugin because the escape hatch matters more than charter
  purity.** Security guards on unknown stacks will false-positive eventually;
  the user's remedy must be "disable the guard," not "uninstall the thing
  carrying all my agents and skills." Folding into ccds-core welds them.
- **Ask over deny wherever legitimate use exists** (bash env-file access,
  config edits, package installs). Deny is reserved for actions with no
  legitimate in-session form (reading key material, curl|bash, chmod 777).
  Every ask is also the teaching moment the audience needs.
- **Honest threat model.** Regex guards stop model mistakes and casual
  injection, not a determined adversary (`python read_env.py` beats any Bash
  regex). The security boundary remains Claude Code's permission modes +
  environment isolation; the guard is the smart layer on top. Documentation
  must not claim otherwise, and must never instruct users to run with
  permissions bypassed outside an isolated container.
- **Data-file rules, code-free tuning** proved out in ADR-0011: project-side
  false positives get fixed by editing a text file, not by forking a plugin.

### Consequences

- New plugin surface: `plugin-extras/ccds-guard/hooks/*`;
  `build-marketplace.py` gains the entry and accepts hooks-only plugins in its
  self-check (previously required agents/ or skills/).
- Installer changes in both dispatchers (bash + PowerShell, same PR) for the
  marketplace-registration + default-install step; cli-parity lint applies.
- `tests/test_playbook_scripts.py` gains behavioral coverage for all four
  guard concerns, including the `.env.example` allowance and fail-open.
- Gate-2 settings template (work item 3) must mirror the secret-path denies —
  tracked as the pipeline's next work item, referenced here so the fail-open
  posture is never the sole layer long-term.
- The `ConfigChange` wiring is new API surface; live verification on the
  installed Claude Code version is part of this work item's definition of
  done (an older CLI that ignores unknown events must degrade silently, not
  fail to load the plugin).

### Supersedes
None. Composes with ADR-0011 (ccds-loops enforcement layer); implements Gate 1
of the five-gate pipeline; ADR-0001 (BOM-less UTF-8) applies to all new files.

---

## ADR-0013: Gate Staging — `ccds sync` Stages Gates 2/3/4 with Never-Destroy Semantics

**Date:** 2026-08-04
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg Grace

### Context

ADR-0012 shipped Gate 1 (the ccds-guard hook plugin) deliberately fail-open,
time-boxed against a Gate-2 hard layer: harness-enforced `permissions.deny`
rules with no runtime dependency. The pipeline handoff further requires Gate 3
(pre-commit) and Gate 4 (CI) staged per detected stack, all zero-config for an
audience that configures nothing. Exploration confirmed sync had no per-file
overwrite protection (managed dirs are rm-rf+cp), no templates directory, an
allow-listed release layout, and a `sync-agents` skill whose manual-copy step
bypassed the manifest entirely.

### Decision

1. **Gates stage by default in `ccds sync`; `--no-gates` opts out.** The sync
   twins call one shared engine, `scripts/stage-gates.py` (python3 — JSON
   merging in shell is how user files get corrupted). No python3 → gates skip
   with a warning; skills staging is unaffected.
2. **Templates live in a new top-level `templates/`**, keyed by
   `templates/stack-matrix.json` (signals → toolchain files; data, not
   logic). Stacks v1: base (always: gitleaks + hygiene), python (ruff,
   pip-audit), node (prettier, npm audit), go (gofmt, govulncheck), rust
   (cargo fmt/audit). Detection is deterministic file-presence in the
   engine; multi-stack projects get the union. Shipped by both release
   builders; not cataloged and not under `skills/` (marketplace/catalog
   lints stay untouched).
3. **Per-artifact never-destroy semantics:**
   - `.claude/settings.json`: merge-with-backup — timestamped
     `.ccds-backup-*`, then ADD missing deny entries only; key order and all
     other content preserved; unparseable JSON is never touched. The deny
     set (`templates/settings-deny.json`) mirrors ccds-guard's deny-paths —
     changing one without the other fails a pairing test. **This closes
     ADR-0012's fail-open time-box.**
   - `CLAUDE.md`: managed block between `# >>> ccds-standards >>>` /
     `# <<< ccds-standards <<<` (distinct markers from the user-scope block;
     doctor's exactly-one check unaffected), strip-and-append with backup —
     the ccds-user-setup semantics, project-scoped. Content: plain-language
     process standards (small PRs, explainable diffs, AI code as untrusted
     contributor code, parameterization, pinned deps, branch protection).
   - `.pre-commit-config.yaml` / `.github/workflows/ccds-quality.yml`:
     created only when absent (loop-init refusal precedent); ccds-created
     files are hash-tracked in the manifest and `--clean` removes them only
     while unmodified — user edits always win.
4. **Manifest schema v3**: `managedGateFiles` ([{path, sha256}]) and
   `gateEdits` join the existing keys. The bash twin's manifest writer
   prefers python3 (preserving the engine's keys; skills travel as argv —
   a heredoc owns stdin); the printf fallback is skills-only, consistent
   because gates need python3 anyway. The fallback manifest parser is scoped
   to the managedSkills line, and `--clean` on a schema-3 manifest without
   python3 refuses rather than misparsing gate paths as skill names.
5. **`sync-agents` skill prefers `ccds sync`** — fixing the pre-existing
   hole where hand-copied skills escaped the manifest — with manual copy
   retained only for plugin-only installs (documented as untracked).

### Consequences

- `--clean` strips the standards block and removes unmodified ccds-created
  files, but deliberately leaves deny rules in settings.json (protective,
  harmless; removing them would silently re-open Gate 2). Documented in the
  clean output itself.
- Gate staging requires the installed library (`ccds` CLI outlet); plugin-only
  installs get Gate 1 only. Named limitation, revisit if plugins grow a
  scaffolding mechanism.
- Doctor checks for staged gates are follow-up work (doctor twins are
  unlinted; kept out to bound this change).
- Both release builders and the install sentinel list now ship `templates/`
  + `stage-gates.py`; cli-parity covers the command surface, and the new
  `--no-gates` flag exists in both dispatchers and both sync twins.

### Post-review hardening (same-day full panel: codex + grok + Claude)

The three-reviewer panel (all claims verified before acceptance) drove one
wording correction and a batch of fixes, all regression-tested:

- **Honest scope of Gate 2** (wording): `permissions.deny` `Read(...)` rules
  govern the model's FILE TOOLS only — a Bash `cat .env` is not stopped by
  them (that remains the guard hook's ask), and the OS-level layer is Claude
  Code's sandboxing, not settings. "Hard layer" claims were narrowed
  accordingly here, in the changelog, README, and template comments.
- **Never-destroy blockers fixed**: unbalanced ccds-standards markers now
  leave CLAUDE.md untouched (previously everything below a begin-without-end
  was silently dropped); PS `-Clean` refuses on a schema-3 manifest without
  the python engine (parity with bash — it previously deleted the manifest
  and orphaned gate files); the bash printf manifest fallback refuses to
  rewrite a schema-3 manifest (it previously truncated the gate keys on any
  python3-less re-sync); `--clean` validates manifest paths (relative,
  `..`-free, realpath-contained) so a tampered manifest cannot delete files
  outside the project; a pre-existing empty CLAUDE.md survives clean.
- **Gate-2/Gate-1 mirror corrected**: the deny set now honors the guard's
  allow-list — `.env.example`-style templates and `*.pub` keys are not
  denied (live `.env` variants enumerated; `id_*` rules match exact key
  basenames); credentials/secrets shapes extended to match the guard.
- **Templates**: rust CI got its missing toolchain step; dependency audits
  are explicitly *advisory* (`continue-on-error`, named as such) — gitleaks
  is the enforcing job; pip-audit targets the project, not pipx's venv.
- **Fidelity**: CRLF files round-trip (CLAUDE.md and settings), backups are
  byte-identical copies with collision-proof names, template refresh takes a
  backup, duplicate-key settings JSON is refused (a rewrite would collapse
  it), `gateEdits` unions with history instead of being wiped by idempotent
  re-runs, malformed manifest values are validated before any mutation, and
  the bash fallback skill parser handles multi-line manifests.
- **Interaction noted**: `ccds sync` writes `.claude/settings.json` via a
  subprocess, which the guard's Bash-text tamper watch cannot see — accepted
  because sync is a deliberate user-invoked action and the change is
  additive-only; recorded here so it is a decision, not an oversight.

### Supersedes
None. Implements pipeline Gates 2–4 staging; composes with ADR-0012 (Gate 1)
and closes its fail-open follow-on; extends ADR-0004/0007's sync mechanism.

---

## ADR-0014: Fresh-Context Review as Default — AI-Review Principles in the Skill Layer

**Date:** 2026-08-05
**Status:** Accepted
**Phase:** Documentation
**Deciders:** Greg Grace

### Context

The quality-pipeline handoff's final work item (Gate 5, the review process):
the review skills and agents must encode how AI-generated code is reviewed,
not just generic review practice. Two principles carried over verbatim in
intent: model output is untrusted contributor code, and the same context
writing both code and tests encodes the same misunderstandings twice.

### Decision

Encode the principles in the always-on layer, avoiding the compliance-measured
`loop-*` bodies (the ADR-0011 lesson — a body edit regressed the measured
baseline; the eval injects only SKILL.md bodies):

1. **`code-review-checklist`** gains "Reviewing AI-generated code" (untrusted
   contributor framing, the scrutiny zones, same-context tests prove nothing,
   explainable-diff and ~400-line size gates) and "The fresh-context rule" —
   generator never grades its own work; fresh-context dispatch to
   `pr-code-reviewer`/`test-writer-runner` is the default flow, with
   `loop-review` carrying the dispatch mechanics unchanged.
2. **`security-checklist`** gains the named recurring AI mistake patterns
   (string-built SQL/commands vs mandatory parameterization, shell=True,
   yaml.load without SafeLoader, verify=False, 0.0.0.0 binds, ECB/MD5/
   non-CSPRNG crypto, authz-not-just-authn, slopsquatting dependency
   verification) — deliberately shaped to double as per-stack semgrep/hook
   rules later.
3. **`pr-code-reviewer`** gets an explicit fresh-context charter (reviews
   without the author's history; line-by-line on the scrutiny zones);
   **`test-writer-runner`** gets principle 8: derive expected behavior from
   requirements, never from the implementation; disclose and re-dispatch if
   it shares the generator's context.

Descriptions (the routing surface) are untouched — no catalog or routing-eval
churn; the marketplace tree is regenerated as usual.

### Rationale

- **Checklists over agent bodies for the shared content**: skills are the
  reference layer any agent pulls; agents carry only their charter (the
  fresh-context framing) and point at the checklist rather than restating it
  (the secure-auditor precedent — restating creates two hand-synced copies).
- **Named patterns over general advice**: "models write insecure code" is not
  reviewable; `shell=True` and string-built SQL are — and double as future
  automated rules.
- **Loop bodies untouched** because the compliance baseline measures them;
  the always-on layer reaches every review anyway.

### Consequences

Completes the five-gate pipeline handoff (items 1–5). Gate 5 is prose-encoded
rather than hook-enforced by nature — review judgment cannot be a file
invariant (ADR-0011's named limit); the enforcement-shaped share of Gate 5
(PR size, templates, branch protection) already ships via the Gate-2 standards
block. Follow-on candidate: per-stack semgrep rules generated from the
security-checklist patterns into the Gate-3 pre-commit templates.

### Supersedes
None. Completes the ADR-0012/0013 pipeline series at the content layer.

## ADR-0015: Unattended Ask-Gate Adjudication — ccds-guard Never Stalls a Loop

**Date:** 2026-08-07
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg Grace

### Context

ccds-guard's ask tier (named package installs, secret-shaped paths in Bash
text, config-tamper writes — ADR-0012) surfaces a permission prompt. Docs
verified 2026-08-07 (code.claude.com/docs hooks + permissions): the PreToolUse
payload carries `permission_mode`, and a hook `permissionDecision: "ask"`
**still prompts even in `bypassPermissions` mode** — hook asks override the
operator's "don't prompt me". In unattended /loop sessions there is nobody to
answer, so every ask-gate hit stalls the session indefinitely. Greg's loop
sessions were hanging on exactly this.

Options considered: blanket ask→deny when unattended (loses legitimate
installs until an operator returns), ask→allow-with-warning (drops the
slopsquatting and tamper protection precisely when nobody is watching), and
LLM adjudication (Greg's direction: "auto-approval where another agent is
asked whether the command should proceed").

### Decision

When the session is **unattended** — `permission_mode` ∈ {`acceptEdits`,
`auto`, `dontAsk`, `bypassPermissions`} (Greg: all auto-accept modes), or
`CCDS_GUARD_UNATTENDED=1` for default-mode sessions running on allowlists —
ask-tier hits are decided by a **fresh-context LLM adjudicator** instead of a
prompt:

1. **Invocation.** `CCDS_GUARD_ADJUDICATOR_CMD` (data-not-logic, same
   philosophy as the rule table; also the test seam), default
   `claude -p --model haiku --safe-mode --strict-mcp-config --tools ""`.
   **All three isolation flags are load-bearing**, each kept because a live
   probe measured what its absence leaks (2026-08-07):
   - `--tools ""` disables only the *built-in* set. Asked to enumerate its
     tools, a `--tools ""` child still held every MCP tool the user and
     project config grant — Gmail, Google Drive, Supabase `execute_sql`,
     Cloudflare API `execute`, n8n `execute_workflow`. A judge reading
     attacker-influencable text with live MCP write tools is a strictly
     larger hole than the ask-gate it replaces.
   - `--strict-mcp-config` (no `--mcp-config`) is what reduces the child to
     zero MCP servers — user config *and* a repo's own `.mcp.json`.
   - `--safe-mode` disables CLAUDE.md, skills, plugins, custom agents, and
     **hooks**. Without it the child *ran the operator's configured hooks*:
     a `SessionStart` hook fired inside the "isolated" adjudicator on every
     adjudication (reproduced with this playbook's own `ccds-loops` hooks
     installed — a very plausible pairing). It also read any `CLAUDE.md`
     above its cwd, which the judged model can write for itself. Auth and
     model selection survive `--safe-mode`, unlike `--bare`, which forces
     `ANTHROPIC_API_KEY` and never reads OAuth or the keychain — verified
     live, which is why `--bare` cannot be the default.

   Prompt on stdin (the variadic `--tools` flag swallows a positional
   prompt); subprocess timeout `CCDS_GUARD_ADJUDICATOR_TIMEOUT` (default 45s,
   clamped ≤85s) inside a 90s hooks.json budget. Child env sets
   `CCDS_GUARD_DISABLE=1`, drops `CCDS_GUARD_UNATTENDED` (no recursion into
   the guard) and drops `CLAUDE_PROJECT_DIR`/`PWD`/`OLDPWD`. **Private empty
   cwd** (`mkdtemp`, removed after): run from the project dir, a live test
   showed the adjudicator reading repo context (branch name) and *inventing
   a justifying intent* for a settings write; and the shared temp root is
   not neutral either — `/tmp` is world-writable, the guard permits writes
   there, and CLAUDE.md discovery walks cwd upward, so the judged model could
   plant `/tmp/CLAUDE.md` to instruct its own judge. Fresh context means
   judging the flagged input on its face.
   Operator trust boundary (documented, not enforced): anyone who can set
   `CCDS_GUARD_ADJUDICATOR_CMD` can already set `CCDS_GUARD_DISABLE=1`, so
   the command is not validated — but the docstring, README and this ADR all
   state that a replacement must keep all three flags.
2. **Contract.** Command-as-data framing, guard reason labels attached,
   exactly one output line: `ALLOW: <reason>` or `DENY: <reason>`. The data
   block is delimited by **per-call random nonce markers**
   (`secrets.token_hex(8)`), not a Markdown fence: the flagged text is written
   by the very model under judgment, so it can reproduce any fixed delimiter —
   a ``` in the payload closed the old fence and let it speak as peer
   instructions (review finding, this ADR's own review round). Instructions
   are repeated *after* the payload so trailing text is not the last word.
   Judgment bias: when uncertain, DENY (a deny is retried by a human later;
   a wrong allow is not).
3. **Verdict handling — default-deny.** The verdict grammar is the **whole**
   of stdout: exactly one line matching `(ALLOW|DENY):\s*<non-empty reason>`.
   A prefix match is not enough — the first cut accepted any line *starting*
   with those letters, so `Allow me to explain: … I do NOT approve it` and
   `ALLOWANCE:DENY` both parsed as ALLOW and let the call through (reproduced
   in review). Explicit ALLOW → the guard steps aside silently (exit 0,
   stderr note logs verdict + reason for the transcript). Never an `"allow"`
   JSON: the guard must not grant permissions Claude Code's own flow would
   have prompted for; it only withdraws its own ask. DENY, garbage output,
   extra lines, non-zero exit, timeout, missing CLI, and any unexpected
   exception all → exit-2 deny whose message carries the verdict and the
   standing guidance — the model routes around it and the loop keeps moving.
   The exception catch matters: an escaping error exits 1, and Claude Code
   treats a hook error as *non-blocking*, so the call would have proceeded on
   the one path whose entire design is fail-closed. For the same reason the
   adjudicator timeout is clamped to `[1, 85]` seconds and rejects `inf`/`NaN`
   — an unbounded value raised `OverflowError` straight out of
   `subprocess.run`.
4. **Scope — two tiers never reach the judge.** Deny-tier rules, and
   **`ask-write-path` hits *from the file tools* (Write/Edit/NotebookEdit),
   where the tool itself proves a write: writes to session-safety
   configuration
   (`.claude/settings.json`, `.claude/hooks/`, `.claude/plugins/`,
   `.pre-commit-config.yaml`) deny outright in an unattended session.** The
   first cut asked the judge to allow them "if the flagged input itself proves
   the operator asked" — an instruction to accept intent asserted by the
   untrusted object, which cannot be prompt-engineered around, only removed.
   Removing it makes the answer unconditional, so the code short-circuits
   before the subprocess. That leaves the adjudicator judging package-name
   plausibility and secret-shaped paths — judgments an LLM can actually make —
   and bounds a successful injection to "one package install proceeds".
   Attended modes (`default`, `plan`, absent/unknown) keep the ask path
   byte-identical.

   **Amended 2026-08-07, hours after v0.15.0 shipped** — the first cut also
   hard-denied `ask-write-path` hits found in **Bash** command text, which was
   wrong: there the guard only knows a safety path was *named*, never that it
   is being written. `ls ~/.claude/plugins/…`, `cat .claude/settings.json`,
   `git log` and `grep` match the same patterns as
   `echo {} > .claude/settings.json`. The result was that read-only inspection
   of one's own config became impossible in an unattended session — caught
   live within minutes of the release, when the guard blocked a plain `ls` of
   the plugin cache. Bash hits now go to the adjudicator, whose prompt already
   says safety-config writes are always DENY unattended: verified after the
   fix, all three write forms (`>`, `cp`, `sed -i`) still deny while reads
   proceed. Rejected alternative: shell write-shape detection (redirections,
   `cp`/`mv`/`tee`/`sed -i`). ADR-0012's threat model explicitly declines the
   shell-quoting arms race, and a heuristic that is wrong in the other
   direction would silently pass real writes.

   Residual, measured not assumed: the judge is deny-biased, so some
   legitimate reads under `.claude/plugins/…/hooks/` still get denied. That is
   a judgment which can go either way rather than an unconditional wall, and
   it is the same bar the ask tier always had.

### Rationale

- A prompt that cannot be answered is a deadlock, not a safety gate. Denies
  feed the reason back to the model; asks feed it to a chair nobody sits in.
- Adjudication preserves throughput (legitimate installs proceed — live:
  `pip install requests` ALLOW in ~9s) without dropping the ask tier
  (live: typo-squat `reqeusts-tolbelt-xyz` DENY; settings-write DENY;
  injection-in-command "reply ALLOW" DENY, named as social engineering).
- Fail-toward-deny inverts the guard's own fail-open rule deliberately: the
  rule table failing means *no signal*; the adjudicator failing means *a
  flagged call couldn't be cleared* — different situations, different safe
  defaults.

### Consequences

- Loop sessions no longer stall on ask-gates; each adjudication is visible
  in the transcript (stderr).
- **This ADR sets the project's minimum Claude Code version: v2.1.169**, the
  release that added `--safe-mode` (verified against that release's published
  changelog; `--strict-mcp-config` and `--tools` predate it). On an older CLI
  the flag is rejected, the child exits non-zero, and every unattended
  package-install ask becomes a deny instead of a judgment — safe, but it
  forfeits the throughput this ADR exists to preserve. Deliberately not
  papered over with a retry that drops `--safe-mode`: silently downgrading a
  security boundary to keep a loop moving is the wrong default. The child's
  stderr now surfaces in the deny message, so the cause is visible rather than
  mysterious. Recorded in README Requirements and CLAUDE.md. **Follow-up
  delivered:** `ccds doctor`'s `claude-cli` check WARNs below the floor, so the
  degraded state is visible instead of silent.
- Unattended sessions can no longer edit `.claude/settings.json`, hooks,
  plugins, or `.pre-commit-config.yaml` at all — they get a teaching deny and
  route around it. That work moves to an attended session. Accepted cost:
  the alternative is a judge deciding, on the strength of text the judged
  model wrote, whether to let that model rewrite its own safety config.
- Named residual limitation (joins ADR-0012's shell-quoting entry): the
  adjudicator is itself an LLM reading attacker-influencable text. Nonce
  delimiters, the strict one-line contract, deny bias, the untouched deny
  tier, and now the unadjudicable config-write tier hold the worst case at
  "a human rubber-stamped the prompt" — which was already the ask tier's bar
  — and bound it to a package install. Plugin-provided tools were a named
  residual until `--safe-mode` closed them; the child still inherits the rest
  of the parent environment (no execution surface left to use it, so this is
  defense-in-depth debt, not a live hole).
- Test surface: `TestGuardUnattended` inherits the full `TestGuardHooks`
  attended matrix (proof the change is additive) plus stub-CLI coverage of
  every verdict/failure path, the recursion-guard env, and regression tests
  for each defect this ADR's review round found: the verdict grammar
  (7 adversarial outputs), the unbounded-timeout fail-open, the project-
  context scrub and private cwd, per-call nonce delimiters, config-write
  hard deny, and the three isolation flags pinned in both copies of the
  shipped default command.
- Attended `acceptEdits`/`auto` users trade a prompt for an automatic
  judgment; verdicts are logged, and `default` mode restores prompts.

### Supersedes
None. Amends the ADR-0012 charter's ask-tier behavior for unattended
sessions.

---

## ADR-0016: Enforcement Plugins Install From Per-User Setup, Not the Installers

**Date:** 2026-08-07
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg Grace

### Context

ADR-0012 decided that plugins are the only hook-shipping mechanism and that
every outlet converges on it: "the classic installer … registers the repo as a
marketplace and runs `claude plugin install ccds-guard@ccds` (and
`ccds-loops@ccds`) by default, with a `--skip-plugins` flag to opt out."

Only the two *script* installers ever implemented it. Traced outlet by outlet
against the shipped v0.15.0 tree:

| Outlet | Plugins wired? |
|---|---|
| `install-playbook.sh` / `Install-Playbook.ps1` | yes |
| `ccds update` (re-invokes the installer) | yes |
| `/plugin marketplace add` (documented "recommended" path) | yes — plugins *are* the artifact |
| **`.deb` / `.rpm`** → `packaging/postinst` → `ccds-user-setup.sh` | **no** |
| **`ccds setup`** (bash and PowerShell) | **no** |
| **`ccds sync` first-run lazy setup** (bash) | **no** |
| **Manual ZIP extraction** | **no** — and the ZIP contains no `plugins/` at all |

A `.deb` user therefore got the 19 agents and the cross-cutting skills and
**no `ccds-guard` and no `ccds-loops`** — the entire Gate 1 security layer and
the process-enforcement layer, absent, with nothing in the output saying so.
The product looked complete and was not.

Root cause is placement, not logic: the step lived in the outermost layer
(the installers) instead of the innermost one every outlet shares.

### Decision

1. **Per-user setup owns the plugin step.** `scripts/ccds-user-setup.sh` gains
   Step 4 (`install_plugins`) and its own `Plugins :` status line; the bash
   installer deletes its copy and forwards `--skip-plugins`. Every outlet that
   runs per-user setup — deb/rpm postinst, `ccds setup`, `ccds sync`'s lazy
   first-run setup, and the installer itself — now converges on one
   implementation. Flags parse in any order and an **unknown flag is an error**
   (the old positional `[[ "$2" == --dry-run ]]` silently ignored a typo and
   made real changes).
2. **Source and CLI are seams.** `CCDS_MARKETPLACE_SOURCE` (default
   `ggrace519/claude-code-dev-studio`) and `CCDS_CLAUDE_CMD` (default `claude`)
   follow the data-not-logic pattern of the guard's rule table. They exist so
   tests can never reach a real marketplace or a real CLI — see Consequences.
3. **`bin/ccds.ps1` gains the twin**, plus `Test-NeedsUserSetup` /
   `Invoke-UserSetupIfNeeded` so PowerShell `ccds sync` performs first-run
   setup like its bash counterpart. Without that, fixing `ccds setup` would
   have left a *new* asymmetry: a Windows user who only ever runs `ccds sync`
   would still get nothing.
4. **`Install-Playbook.ps1` keeps its own copy.** It is a curl-piped
   standalone script that cannot depend on an installed `ccds-user-setup.sh`
   or `bin/ccds.ps1`. Named duplication, not an oversight.

### Rationale

- The fix belongs at the narrowest waist every outlet passes through. Adding
  the step to each outlet instead would have re-created the same bug the next
  time an outlet is added.
- Best-effort, never fatal: a missing `claude` CLI warns, **names what is
  missing** ("no security guard and no loop enforcement"), prints the exact
  commands, and setup still succeeds. A security layer that fails an install
  gets uninstalled; one that explains itself gets fixed.
- GitHub stays the marketplace source (Greg's call), matching what the
  installers and the README already do. Bundling `plugins/` into the packages
  would make offline installs work and lock plugin versions to the package —
  rejected for now as a second mechanism to maintain.

### Consequences

- deb/rpm and `ccds setup` users gain both hook layers. This is new
  user-visible behavior on those outlets, hence a minor release, not a patch.
- **Test hazard, fixed first in its own commit:** `TestDebPostinst._run`
  appends the real `PATH` (postinst needs `getent`/`chmod`/`su`), so once
  setup shelled out to `claude`, a plain `pytest` run would have hit the
  developer's real CLI and mutated their actual marketplace registration —
  `marketplace add`, then `update` on the already-exists path. The harness now
  stubs `claude`, records argv for assertions, and pins `CCDS_CLAUDE_CMD` by
  absolute path.
- Still not covered, and stated rather than hidden: **manual ZIP extraction**
  with no installer run wires nothing, because the ZIP ships no `plugins/`
  tree and no `.claude-plugin/marketplace.json`. The README documents the
  installer and the marketplace as the supported paths.
- `install-playbook.sh` and `Install-Playbook.ps1` had **no test coverage at
  all** (confirmed while tracing this). Deleting the bash installer's block
  was verified by hand — `bash -n`, `--help`, and a real `--dry-run` run —
  not by the suite. **Since closed for the bash installer:** `TestInstallPlaybook`
  covers install, `--skip-plugins` forwarding, dry-run, `--no-path`, snapshot,
  rollback, uninstall, a wrong-shaped archive, and a checksum mismatch, run
  hermetically via `--local-zip` + sandboxed `HOME` + a stubbed `claude`.
  `Install-Playbook.ps1` remains uncovered — it is a standalone PowerShell
  script and needs a `pwsh` runner the CI Linux job does not have.
- **Follow-up delivered:** `ccds doctor`'s `plugins-installed` check FAILs when
  either plugin is missing *or installed-but-disabled* — the backstop that
  would have caught this entire class of bug. A disabled guard protects
  nothing, so it is treated exactly like a missing one.

### Supersedes
None. Completes ADR-0012's distribution decision, which was only
half-implemented.

---

## ADR-0017: Per-Outlet Payloads Are a Linted Contract, and bash Gets Its Completion

**Date:** 2026-08-07
**Status:** Accepted
**Phase:** Architecture
**Deciders:** Greg Grace

### Context

`build-release.sh` (deb/rpm) and `build-release.ps1` (ZIP) stage the release
payload from **independent, hand-maintained lists with no cross-check**. They
had drifted six files apart:

```
in ZIP, not in deb:
  scripts/Sync-AgentPacks.ps1      scripts/ccds-completion.ps1
  scripts/Verify-Agents.ps1        scripts/claude-completion.ps1
  scripts/ccds-completion.bash     scripts/claude-completion.bash
```

Two defects fell out of it:

1. The packages staged `bin/ccds.ps1` **without** `scripts/Sync-AgentPacks.ps1`.
   `bin/ccds.ps1:63-79` resolves its layout by locating that file and otherwise
   exits with "Cannot locate Sync-AgentPacks.ps1" — the packages shipped a
   dispatcher that could never run.
2. The packages shipped **no bash completion**. Worse, tracing that showed the
   bash side never had completion *at all*: `Install-Playbook.ps1:466-516` has
   loaded both completions into the PowerShell profile since it shipped, while
   `install-playbook.sh` and `packaging/postinst` had no completion handling.
   Windows users had completion; bash users never did, on any outlet.

Latent alongside: `build-release.sh`'s `REQUIRED_SOURCES` preflight omitted
`scripts/stage-gates.py` and `templates`, both of which the stage block copies.

### Decision

1. **Linux packages ship Linux tools.** `bin/ccds.ps1` is dropped from the
   deb/rpm rather than completed by adding the PowerShell helpers. Windows
   users take the ZIP or the PowerShell installer.
2. **The payload contract is `ZIP == deb ∪ WINDOWS_ONLY`,** enforced by a new
   `release-parity` check in `scripts/lint-playbook.py` (check 12), modeled on
   the existing `cli-parity` check. It parses the destination paths out of both
   builders and fails in all three drift directions, with `WINDOWS_ONLY_PAYLOAD`
   as the single declared exception list. Adding a cross-platform file to one
   builder now fails; adding a Windows-only file must be declared.
3. **Completion is activated per outlet, in the way each outlet should.**
   - Script installer: a marked `# >>> ccds-completion >>>` block appended to
     the same shell rc files the PATH block targets, sourcing both completion
     scripts from the install prefix. Removed by `--uninstall`.
   - deb/rpm: `ccds-completion.bash` is staged to
     `usr/share/bash-completion/completions/ccds`, the distro-native path that
     loads for every user with **no rc-file edits**. A package may not edit a
     user's dotfiles; an explicitly-invoked installer script may.
4. **`claude-completion.bash` completes a third-party binary,** so the packages
   ship it under `/usr/share/ccds/scripts/` for a user to source deliberately
   rather than installing it system-wide. The script installer, being an
   explicit per-user action, wires both.
5. **`--no-path` governs all shell-rc mutation,** not just PATH. Completion
   writes to the same files, and that flag is how an operator says "leave my
   startup files alone" — widening it beats adding a second near-identical
   flag. Documented in help, README and the changelog.

The PATH and completion blocks now share one `write_rc_block` /
`remove_rc_block` implementation, so idempotency is fixed in one place. A
refresh strips and re-appends rather than editing in place, which keeps a
multi-line body simple; the block therefore moves to the end of the rc file.

### Rationale

- Two hand-maintained lists with no cross-check is the same class of defect as
  the two dispatchers before `cli-parity`, and the same remedy applies. The
  lint states the intended relationship instead of hoping reviewers diff two
  files in different languages.
- Shipping `ccds-completion.bash` without activating it would have made the
  payloads consistent and left the feature just as broken — the drift fix and
  the activation are one change, not two.

### Consequences

- deb/rpm users lose a `bin/ccds.ps1` that never worked, and gain working
  `ccds` tab-completion with no action required.
- Script-installer users gain completion on install; `--no-path` opts out of
  both rc blocks; `--uninstall` removes both.
- Test surface: `TestReleaseParity` (7 cases, synthesized builders — the real
  scripts are never mutated) plus two `TestInstallPlaybook` cases. The
  completion test **sources the rc file in a real shell and asserts
  `complete -p ccds` resolves**, rather than asserting the text was written —
  which is what caught that the test ZIP fixture lacked the completion files,
  a gap a text assertion would have passed straight through.
- Every check above was mutation-verified: three drift directions for the lint,
  three broken behaviors for the completion, each caught by the intended test.

### Supersedes
None. Extends ADR-0012's every-outlet principle from hooks to the release
payload itself.

---

## ADR-0018: The Suite Runs on Both Platforms

**Date:** 2026-08-07
**Status:** Accepted
**Phase:** Testing
**Deciders:** Greg Grace

### Context

ccds ships a bash half and a PowerShell half, and CI only ever ran the test
suite on Linux. `Install-Playbook.ps1` — the primary install path for every
Windows user — had no behavioral coverage at all; PSScriptAnalyzer linted it
at Error severity and nothing exercised it.

The first plan for this proposed a Windows job running **one hand-picked test
class**. Greg rejected it: *"the tool works on both windows and linux, then it
should be tested on both … testing certain files out of context is not smart."*
A job that runs one class proves nothing about the product; it makes a green
check appear. He also corrected a false premise — these sessions run in WSL on
a Windows machine, so Windows is directly reachable (`powershell.exe` is
Windows PowerShell 5.1, `python.exe` is Windows Python 3.14) and none of this
needed to be guessed at through CI.

### Decision

1. **One suite, both runners.** A `windows-latest` job runs
   `python -m unittest discover -s tests -v`, exactly as the Linux job does.
   Each platform runs what applies and skips what does not — the existing
   `sys.platform != "win32"` guards already express that, and
   `TestInstallPlaybookPs1` carries the mirror guard. Result today: 268 tests
   collected on both, 59 skipped on Windows, 7 on Linux.
   `core.autocrlf false` before checkout, because the generators emit LF and
   several tests compare their output against checked-in files.
2. **`Install-Playbook.ps1` stays Windows-targeted** and is tested on Windows.
   It exists precisely because `install-playbook.sh` covers Linux/macOS;
   reworking `$env:USERPROFILE`, User-scope registry PATH and `;` separators
   into cross-platform equivalents would duplicate that for no gain.
3. **Seams, because the script had none.** It inlines its per-user work rather
   than delegating, so it was the one component with its externals hardcoded:
   `CCDS_MARKETPLACE_SOURCE`, `CCDS_CLAUDE_CMD`, and `CCDS_PS_PROFILE`. The
   last one is load-bearing for safety, not just testing —
   `$PROFILE.CurrentUserAllHosts` is **not** derived from `$env:USERPROFILE`
   (it resolves from the Documents known folder, often OneDrive-redirected), so
   sandboxing `USERPROFILE` alone would still have written the completion block
   into the operator's real profile on every test run. Every test also passes
   `-NoPath`: the PATH write goes to the real User-scope registry.

### Three product bugs this found immediately

All were invisible while the suite was Linux-only, and all are Windows-only
failures in shipped code. The third surfaced only in CI, on a runner whose
checkout differs from this machine's — which is the argument for the job
existing rather than trusting one developer's box:

- **`ccds-guard` could never adjudicate on Windows.** `shlex.split` defaults to
  POSIX mode, where backslash is an escape character, so any
  `CCDS_GUARD_ADJUDICATOR_CMD` containing an absolute path was destroyed
  (`C:\Python314\python.exe` → `C:Python314python.exe`), the adjudicator failed
  to start, and every unattended ask-gate hit denied. The documented way to
  override the judge was broken on Windows; only the default command worked,
  and only because it contains no backslashes. Fixed with a Windows-aware split
  that also strips the quote pair non-POSIX mode leaves behind — otherwise
  `--tools ""` would arrive as a literal `""` instead of an empty string.
- **`posttooluse-evidence-log.py` invoked a bare `psql`.** On Windows
  `CreateProcess` resolves only `.exe`, so a psql shipped as `.cmd`/`.bat` was
  found by `which()` and then failed to start. Now it invokes the resolved
  path, and honors a `CCDS_EVIDENCE_PSQL` override — a real need (versioned
  installs, Program Files) as well as the test seam.
- **`ccds sync` rewrote `CLAUDE.md` on every run for Windows users.**
  `stage_claude_block` LF-normalized the existing file but not the template it
  compared against, so a CRLF `templates/claude-standards.md` never matched:
  each run "updated" the block and dropped another timestamped backup — the
  backup churn its own test exists to prevent. Windows checkouts produce
  exactly that template, because `.gitattributes` marks `*.md` as `text` and
  Git converts those to `core.eol` (native = CRLF on Windows) **regardless of
  `core.autocrlf`** — which is also why the Windows CI job sets `core.eol lf`
  and not just `core.autocrlf false`. Reproduced on Linux by CRLF-ing the
  template, fixed by normalizing the template side; the file is still written
  in whatever convention it already had.

### Consequences

- Windows regressions surface in CI instead of in users' installs.
- `TestInstallPlaybookPs1` (7 cases) covers install, the seams, `-SkipPlugins`,
  `-DryRun`, snapshot + `-Rollback`, `-Uninstall`, and a wrong-shaped archive.
  Both installer suites now share one `build_test_release_zip()` fixture — the
  two installers install the same artifact, so they must exercise the same
  payload.
- Mutation-verified, as with every suite since v0.17.0: removing the archive
  sentinels, ignoring the `CCDS_PS_PROFILE` seam, and ignoring `-SkipPlugins`
  each failed exactly the intended test. The profile mutation was deliberately
  written to point *inside the sandbox* rather than at the real `$PROFILE`, so
  a mutation could not damage the operator's environment.
- **A reported bug that was not one:** `Set-ClaudePlaybookBlock`'s `$backup` was
  flagged as possibly-unassigned. It is only read inside `if ($backup)`, and
  the script sets no `StrictMode`, so an unassigned value is `$null` and the
  branch is skipped. Left alone rather than "fixed" to tidy a checklist.

### Supersedes
None.
