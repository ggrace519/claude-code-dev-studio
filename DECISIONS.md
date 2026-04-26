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
