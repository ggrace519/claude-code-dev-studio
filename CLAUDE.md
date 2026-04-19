# Claude Code Playbook

A universal, stack-agnostic development workflow for Claude Code CLI. This playbook establishes a consistent, phase-gated methodology aligned with NIST SSDF (SP 800-218) and Agile principles.

---

## Initialization Protocol (`/init`)

When starting a new session or project, run the following checklist:

1. **Confirm project type** — language, framework, runtime, target environment
2. **Load or create `DECISIONS.md`** — architecture decision log (see convention below)
3. **Verify agents are installed** — check `.claude/agents/` for all required agents:
   - `api-expert`
   - `deploy-checklist`
   - `plan-architect`
   - `pr-code-reviewer`
   - `secure-auditor`
   - `test-writer-runner`
   - `ux-design-critic`

   If any agent is missing, notify the user:
   > ⚠️ Agent `<name>` not found in `.claude/agents/`. Install from the playbook bundle before proceeding.

4. **Confirm archetype** — identify the project's primary archetype (see Archetype Packs below). Verify the matching pack agents are present in `.claude/agents/` and record the choice as an ADR in `DECISIONS.md` if not already logged. A project may activate more than one pack (e.g., SaaS + AI for an LLM-enabled SaaS product).
5. **Establish working phase** — confirm which phase the project is currently in (see Phase Framework below)
6. **Context refresh** — if resuming a long session, summarize prior decisions, blockers, and next actions before continuing

---

## Phase Framework

Development proceeds through seven sequential phases. Each phase maps to NIST SSDF practice groups and has defined entry/exit criteria and agent triggers.

---

### Phase 1 — Initialize
**SSDF:** PO (Prepare the Organization)

**Goal:** Establish project structure, tooling, and conventions.

**Activities:**
- Scaffold project layout and configuration files
- Set up version control, CI skeleton, and linting
- Define coding standards and commit conventions
- Create `DECISIONS.md`

**Exit criteria:** Repo is runnable, CI passes on an empty test suite, `DECISIONS.md` exists.

---

### Phase 2 — Architecture
**SSDF:** PW.1 (Design Software)

**Goal:** Define system design before implementation begins.

**Activities:**
- Map components, data flows, and integration boundaries
- Document all significant design decisions in `DECISIONS.md`
- Identify security and compliance requirements upfront

**Auto-invoke:** `plan-architect` — triggered when beginning system design or when major architectural decisions are being made.

**Exit criteria:** Key architectural decisions recorded, component boundaries defined.

---

### Phase 3 — Implementation
**SSDF:** PW.2, PW.4 (Implement, Review)

**Goal:** Build features incrementally with continuous review.

**Activities:**
- Implement in small, reviewable increments
- Commit frequently against defined tasks
- Apply agent triggers as work progresses

**Agent triggers:**
- **`api-expert`** — auto-invoked when writing API endpoints, HTTP clients, authentication flows, or data contracts
- **`ux-design-critic`** — auto-invoked when implementing UI components, forms, layouts, or user-facing interactions

**Exit criteria:** Feature complete, no outstanding lint errors, passes local smoke test.

---

### Phase 4 — Testing
**SSDF:** PW.6, PW.7 (Test, Remediate)

**Goal:** Achieve meaningful coverage; validate behavior, not just lines.

**Activities:**
- Write unit, integration, and edge-case tests
- Run full test suite; remediate failures before proceeding
- Review test coverage gaps

**Agent triggers:**
- **`test-writer-runner`** — auto-invoked after implementation is complete or after a PR review resolves issues
- **`pr-code-reviewer`** — auto-invoked when a PR is opened or ready for review

**Exit criteria:** Test suite passing, coverage meets project threshold, no skipped tests without justification.

---

### Phase 5 — Hardening
**SSDF:** PW.8, PW.9 (Analyze, Archive)

**Goal:** Reduce attack surface and eliminate known vulnerabilities.

**Activities:**
- Run static analysis and dependency audit
- Review secrets management and input validation
- Address all HIGH/CRITICAL findings before proceeding

**Agent triggers:**
- **`secure-auditor`** — auto-invoked at the start of this phase and whenever security-sensitive code is written (auth, crypto, file I/O, external data handling)

**Exit criteria:** No unmitigated HIGH/CRITICAL findings, secrets confirmed out of source control.

---

### Phase 6 — Documentation
**SSDF:** PO.3 (Implement Supporting Toolchains)

**Goal:** Produce accurate, maintainable documentation.

**Activities:**
- Write or update README, API docs, runbooks, and ADRs
- Ensure `DECISIONS.md` is current
- Document environment setup and deployment prerequisites

**Exit criteria:** README accurate, all public APIs documented, `DECISIONS.md` up to date.

---

### Phase 7 — Deployment
**SSDF:** RV.1 (Identify and Confirm Vulnerabilities in Releases)

**Goal:** Ship safely with a verified deployment checklist.

**Activities:**
- Confirm environment configs and secrets are correct
- Verify rollback plan exists
- Execute deployment and validate post-deploy health checks

**Agent triggers:**
- **`deploy-checklist`** — auto-invoked before any production deployment or environment promotion

**Exit criteria:** Deployment successful, health checks passing, rollback plan confirmed.

---

## Context Refresh Protocol

For sessions exceeding ~50 exchanges or when resuming after a break:

1. Summarize: current phase, last 3 decisions made, any open blockers
2. Re-confirm the active agent triggers relevant to current work
3. Review `DECISIONS.md` for any decisions that affect upcoming work
4. State the next 2–3 concrete actions before proceeding

---

## Archetype Packs

Archetype packs are archetype-specific specialist agents that **compose with** — never replace — the seven generalist agents. Each pack contains one archetype-architect and 3–5 domain specialists. Activation is declared per-project via an ADR in `DECISIONS.md` at `/init`.

### Layout

Project agents use a flat file layout with archetype prefixes:

- Generalists: `.claude/agents/<name>.md` (e.g., `plan-architect.md`)
- Archetype pack: `.claude/agents/<prefix>-<role>.md` (e.g., `saas-architect.md`, `saas-billing-expert.md`)
- Cross-archetype shared specialists: `.claude/agents/common-<role>.md`

Subfolder layouts were evaluated and rejected — Claude Code v2.1.113 does not recurse `.claude/agents/`. See ADR-0001.

### Installer conventions

Installer scripts (`install-agents.ps1` and future pack installers) must write agent files as **UTF-8 without BOM**. PowerShell 5.1's `Set-Content -Encoding UTF8` writes a BOM (`EF BB BF`) that Claude Code's YAML frontmatter parser silently rejects — agents appear on disk but never in `/agents`. Use `[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))` (works on PS 5.1+).

### Prefix registry

| Archetype | Prefix |
|---|---|
| Gaming | `game-` |
| SaaS / productivity | `saas-` |
| Mobile (iOS / Android) | `mobile-` |
| AI / LLM apps | `ai-` |
| Data platform / analytics | `dataplat-` |
| E-commerce | `ecom-` |
| Fintech / regulated | `fintech-` |
| DevTools / CLIs / libraries | `devtool-` |
| Desktop apps | `desktop-` |
| Browser extensions | `ext-` |
| Embedded / IoT / firmware | `embed-` |
| Media / streaming | `media-` |
| Agent / orchestration systems | `orch-` |
| Dev platform / infra | `infra-` |
| Shared cross-archetype | `common-` |

### Composition rules

- Packs **add to** generalists; they never replace them
- Each pack specialist declares explicit handoffs ("You do NOT own → `<other-agent>`") so scopes do not overlap
- A project may activate more than one pack
- Activated packs are declared via an ADR in `DECISIONS.md`

### Available packs

| Archetype | Pack agents | Status |
|---|---|---|
| Gaming | `game-architect`, `game-engine-expert`, `game-netcode-expert`, `game-perf-profiler`, `game-balance-designer`, `game-feel-critic`, `game-liveops-expert`, `game-platform-cert-expert`, `game-audio-expert` | Available |
| SaaS / productivity | `saas-architect`, `saas-data-model-expert`, `saas-multitenancy-expert`, `saas-billing-expert`, `saas-auth-sso-expert`, `saas-collab-sync-expert` | Available |
| Mobile | `mobile-architect`, `mobile-platform-expert`, `mobile-offline-sync-expert`, `mobile-release-expert`, `mobile-perf-expert`, `mobile-iap-expert`, `mobile-crash-expert` | Available |
| AI / LLM apps | `ai-architect`, `ai-prompt-engineer`, `ai-rag-expert`, `ai-eval-expert`, `ai-inference-perf-expert`, `ai-safety-expert`, `ai-finetune-expert` | Available |
| Data platform / analytics | `dataplat-architect`, `dataplat-etl-expert`, `dataplat-sql-expert`, `dataplat-quality-expert`, `dataplat-viz-expert`, `dataplat-privacy-expert`, `dataplat-feature-store-expert`, `dataplat-streaming-expert` | Available |
| E-commerce | `ecom-architect`, `ecom-payments-expert`, `ecom-inventory-expert`, `ecom-search-merch-expert`, `ecom-storefront-perf-expert`, `ecom-tax-expert`, `ecom-promotions-expert` | Available |
| Fintech / regulated | `fintech-architect`, `fintech-ledger-expert`, `fintech-compliance-expert`, `fintech-audit-trail-expert`, `fintech-risk-expert` | Available |
| DevTools / CLIs / libraries | `devtool-architect`, `devtool-cli-ux-expert`, `devtool-library-api-expert`, `devtool-packaging-expert`, `devtool-docgen-expert`, `devtool-telemetry-expert` | Available |
| Desktop apps | `desktop-architect`, `desktop-ipc-expert`, `desktop-autoupdate-expert`, `desktop-code-signing-expert`, `desktop-installer-expert`, `desktop-shell-integration-expert` | Available |
| Browser extensions | `ext-architect`, `ext-permissions-expert`, `ext-security-expert`, `ext-ux-expert`, `ext-native-messaging-expert` | Available |
| Embedded / IoT / firmware | `embed-architect`, `embed-driver-expert`, `embed-rtos-expert`, `embed-ota-expert`, `embed-power-expert`, `embed-connectivity-expert`, `embed-manufacturing-expert` | Available |
| Media / streaming | `media-architect`, `media-transcode-expert`, `media-drm-cdn-expert`, `media-cms-workflow-expert`, `media-player-expert`, `media-ad-insertion-expert`, `media-live-expert` | Available |
| Agent / orchestration systems | `orch-architect`, `orch-tool-design-expert`, `orch-prompt-engineer`, `orch-eval-expert`, `orch-sandbox-safety-expert` | Available |
| Dev platform / infra | `infra-architect`, `infra-sre-expert`, `infra-observability-expert`, `infra-k8s-expert`, `infra-finops-expert`, `infra-dr-backup-expert`, `infra-networking-expert`, `infra-iam-expert` | Available |
| Shared cross-archetype (`common-`) | `common-i18n-expert`, `common-a11y-expert`, `common-notifications-expert`, `common-privacy-expert`, `common-product-analytics-expert` | Available |

All 14 archetype packs are scaffolded plus the cross-archetype `common-` pack — 105 total agent files (7 generalists + 98 pack agents).

---

## Agent Auto-Invocation Summary

### Generalists

| Agent | Trigger |
|---|---|
| `plan-architect` | System design, major architectural decisions |
| `api-expert` | API endpoints, HTTP clients, auth flows, data contracts |
| `ux-design-critic` | UI components, forms, layouts, user-facing interactions |
| `test-writer-runner` | Post-implementation, post-PR-review |
| `pr-code-reviewer` | PR opened or ready for review |
| `secure-auditor` | Hardening phase start; auth, crypto, file I/O, external data |
| `deploy-checklist` | Pre-production deployment or environment promotion |

### SaaS pack

| Agent | Trigger |
|---|---|
| `saas-architect` | Phase 2 on SaaS projects; tenancy, billing, scale, or compliance topology decisions |
| `saas-data-model-expert` | Schema creation/change, migration writing, slow-query debugging, index design |
| `saas-multitenancy-expert` | Tenant isolation code (RLS, query guards), cross-tenant boundary code, per-tenant quotas |
| `saas-billing-expert` | Payment-provider integration, webhook handling, entitlement checks, usage metering |
| `saas-auth-sso-expert` | Auth flows, SSO / SAML / SCIM integration, session management, RBAC / ABAC policy code |
| `saas-collab-sync-expert` | Realtime features, sync protocols, CRDT / OT integration, conflict resolution |

### Gaming pack

| Agent | Trigger |
|---|---|
| `game-architect` | Phase 2 on game projects; engine choice, netcode topology, platform targets |
| `game-engine-expert` | Engine-specific code (Unity / Unreal / Godot / custom); rendering, ECS, asset pipeline |
| `game-netcode-expert` | Multiplayer sync, rollback, prediction, anti-cheat, matchmaking |
| `game-perf-profiler` | Frame-time regressions, memory / GC spikes, GPU bottlenecks |
| `game-balance-designer` | Economy tuning, difficulty curves, progression systems |
| `game-feel-critic` | Input responsiveness, animation blending, camera, juice |
| `game-liveops-expert` | Telemetry, A/B testing, content cadence, IAP integration for live-service games |
| `game-platform-cert-expert` | Console TRC / XR / Lotcheck submissions, ratings, store listing compliance |
| `game-audio-expert` | Wwise / FMOD integration, mix bus, spatial audio, voice budget |

### Mobile pack

| Agent | Trigger |
|---|---|
| `mobile-architect` | Phase 2 on mobile projects; native vs cross-platform, architecture (MVVM/TCA), offline posture |
| `mobile-platform-expert` | iOS / Android platform APIs, lifecycle, permissions, push, deep links |
| `mobile-offline-sync-expert` | Offline-first data, queued mutations, conflict resolution |
| `mobile-release-expert` | App Store / Play Store submission, review response, phased rollout, signing |
| `mobile-perf-expert` | Startup time, jank, battery, memory, APK / IPA size |
| `mobile-iap-expert` | StoreKit 2 / Play Billing v6, receipts, subscription lifecycle, restore / refund |
| `mobile-crash-expert` | Crashlytics / Sentry / Bugsnag, symbolication, crash-free-session SLO |

### AI / LLM pack

| Agent | Trigger |
|---|---|
| `ai-architect` | Phase 2 on AI/LLM projects; model selection, serving topology, cost envelope |
| `ai-prompt-engineer` | System prompts, few-shot selection, output contracts, structured output |
| `ai-rag-expert` | Retrieval pipelines, chunking, embeddings, reranking, hybrid search |
| `ai-eval-expert` | Eval set design, metrics, judges, regression harnesses |
| `ai-inference-perf-expert` | vLLM / TGI / Ollama tuning, batching, KV cache, GPU utilization |
| `ai-safety-expert` | Guardrails, jailbreak testing, PII handling, policy enforcement |
| `ai-finetune-expert` | SFT / LoRA / DPO, dataset curation, training-eval loop, deployment of custom models |

### Data platform pack

| Agent | Trigger |
|---|---|
| `dataplat-architect` | Phase 2 on data platform projects; warehouse / lakehouse topology, storage format, governance |
| `dataplat-etl-expert` | Ingestion pipelines, CDC, dbt / Airflow / Dagster, backfill design |
| `dataplat-sql-expert` | Query optimization, dialect translation, CTEs, window functions |
| `dataplat-quality-expert` | Data contracts, expectation testing, lineage, freshness SLAs |
| `dataplat-viz-expert` | Semantic / metrics layer, dashboards, self-serve patterns |
| `dataplat-privacy-expert` | Warehouse PII classification, masking, DSAR fulfillment at the data layer |
| `dataplat-feature-store-expert` | Feast / Tecton, online / offline parity, feature backfill and serving |
| `dataplat-streaming-expert` | Kafka / Kinesis / Pub-Sub, schema evolution, exactly-once, stream processing |

### E-commerce pack

| Agent | Trigger |
|---|---|
| `ecom-architect` | Phase 2 on e-commerce projects; storefront / checkout / OMS topology, peak-event posture |
| `ecom-payments-expert` | Gateway integration, 3DS / SCA, auth / capture / refund, chargebacks |
| `ecom-inventory-expert` | Inventory model, reservation TTLs, multi-location allocation, oversell prevention |
| `ecom-search-merch-expert` | Product search / relevance, faceting, ranking, merchandising rules |
| `ecom-storefront-perf-expert` | Core Web Vitals, rendering strategy, edge caching, image optimization |
| `ecom-tax-expert` | Sales tax / VAT / GST, Avalara / TaxJar / Stripe Tax, nexus tracking, marketplace-facilitator |
| `ecom-promotions-expert` | Coupons, discounts, gift cards, loyalty, promo stacking rules |

### Fintech pack

| Agent | Trigger |
|---|---|
| `fintech-architect` | Phase 2 on fintech / regulated projects; ledger topology, custody, licensing, jurisdictions |
| `fintech-ledger-expert` | Ledger postings, double-entry, balances, multi-currency, reversals |
| `fintech-compliance-expert` | KYC / KYB, sanctions screening, AML monitoring, SAR / CTR workflows |
| `fintech-audit-trail-expert` | Immutable event logs, tamper evidence, retention, audit export |
| `fintech-risk-expert` | Credit / fraud models, decision thresholds, shadow rollouts, model monitoring |

### DevTool pack

| Agent | Trigger |
|---|---|
| `devtool-architect` | Phase 2 on devtool / CLI / library projects; API surface, versioning, distribution, plugins |
| `devtool-cli-ux-expert` | CLI flag design, output formats, error messages, shell integration |
| `devtool-library-api-expert` | Public library signatures, error types, async surface, cancellation |
| `devtool-packaging-expert` | Build pipelines, signing, SBOM, release automation, provenance |
| `devtool-docgen-expert` | API reference generation, doctests, versioned docs, changelog automation |
| `devtool-telemetry-expert` | Opt-in usage telemetry, crash reports, update pings, enterprise-safe disable paths |

### Desktop pack

| Agent | Trigger |
|---|---|
| `desktop-architect` | Phase 2 on desktop projects; runtime choice, process model, OS integration, cross-platform posture |
| `desktop-ipc-expert` | Inter-process message design, typed channels, security boundaries |
| `desktop-autoupdate-expert` | Update channels, delta / full downloads, signature verification, staged rollout |
| `desktop-code-signing-expert` | Authenticode, Apple notarization, GPG signing, key rotation |
| `desktop-installer-expert` | MSI / EXE / PKG / DMG / DEB / RPM installers, silent install, enterprise deployment |
| `desktop-shell-integration-expert` | File associations, protocol handlers, context menus, Spotlight / Quick Look, jump lists |

### Browser extension pack

| Agent | Trigger |
|---|---|
| `ext-architect` | Phase 2 on extension projects; manifest version, permissions strategy, cross-browser posture |
| `ext-permissions-expert` | Permission model, host patterns, optional permissions, store-review justifications |
| `ext-security-expert` | Content-script isolation, CSP, message validation, secret handling |
| `ext-ux-expert` | Popup, options page, onboarding, in-page overlay UX |
| `ext-native-messaging-expert` | Native Messaging host — stdio framing, manifest deployment, allowlist, authorization |

### Embedded / IoT pack

| Agent | Trigger |
|---|---|
| `embed-architect` | Phase 2 on embedded projects; SoC choice, boot chain, A/B partitioning, fleet OTA topology |
| `embed-driver-expert` | Bus protocols (I2C/SPI/UART/CAN), DMA, ISR design, HAL / driver code |
| `embed-rtos-expert` | Task design, scheduling, synchronization, stack sizing, real-time constraints |
| `embed-ota-expert` | Firmware OTA, delta updates, signature verification, A/B swap, fleet rollout |
| `embed-power-expert` | Sleep modes, duty cycling, peripheral gating, battery-life budgeting |
| `embed-connectivity-expert` | Wi-Fi / BLE / Thread-Matter / cellular / LoRaWAN, provisioning, reconnect, MQTT / CoAP |
| `embed-manufacturing-expert` | Factory test, serialization, key injection, yield, traceability, RMA |

### Media / streaming pack

| Agent | Trigger |
|---|---|
| `media-architect` | Phase 2 on media projects; pipeline topology, codec ladder, DRM, CDN strategy |
| `media-transcode-expert` | ffmpeg pipelines, bitrate ladders, CMAF / HLS / DASH packaging, VMAF targets |
| `media-drm-cdn-expert` | Widevine / FairPlay / PlayReady, tokenized URLs, multi-CDN, QoE analysis |
| `media-cms-workflow-expert` | Asset ingest, metadata, rights windows, editorial workflow, scheduling |
| `media-player-expert` | Client playback — ABR tuning, startup time, rebuffer, Shaka / dash.js / ExoPlayer / AVPlayer |
| `media-ad-insertion-expert` | SSAI / CSAI, VAST / VMAP, SCTE-35, ad-break pacing, viewability |
| `media-live-expert` | Live pipeline — SRT / RTMP ingest, LL-HLS / LL-DASH, multi-CDN failover, tentpole runbook |

### Orchestration / agent-systems pack

| Agent | Trigger |
|---|---|
| `orch-architect` | Phase 2 on agent / orchestration projects; topology, tool surface, control loops, sandbox boundaries |
| `orch-tool-design-expert` | Individual tool specs, schemas, descriptions, error coaching |
| `orch-prompt-engineer` | System prompts, few-shot, output contracts, guardrail prompting |
| `orch-eval-expert` | Eval set curation, judges, CI regression harnesses, prod-trace evals |
| `orch-sandbox-safety-expert` | Execution sandbox, resource limits, tool authority, injection defense |

### Infra / dev-platform pack

| Agent | Trigger |
|---|---|
| `infra-architect` | Phase 2 on platform / infra projects; landing zone, environments, IaC strategy, secrets topology |
| `infra-sre-expert` | SLOs, error budgets, incident response, postmortems, on-call |
| `infra-observability-expert` | Metrics / logs / traces instrumentation, cardinality control, dashboards |
| `infra-k8s-expert` | Cluster design, RBAC, workloads, autoscaling, GitOps delivery |
| `infra-finops-expert` | Cost allocation, unit economics, right-sizing, commitment strategy |
| `infra-dr-backup-expert` | Backup coverage, RPO / RTO, cross-region failover, restore drills |
| `infra-networking-expert` | VPC / subnets, peering / TGW, DNS, ingress / egress, service mesh, segmentation |
| `infra-iam-expert` | Cloud IAM, SCPs / Org Policies, workload identity, KMS, break-glass, access reviews |

### Common pack (cross-archetype)

The `common-` pack contains specialists that apply to almost any project regardless of archetype. Activate alongside one or more archetype packs.

| Agent | Trigger |
|---|---|
| `common-i18n-expert` | Adding locales, RTL, ICU MessageFormat, translation workflow, CLDR-aware formatting |
| `common-a11y-expert` | WCAG audits, ARIA design, keyboard / screen-reader UX, ACR / VPAT generation |
| `common-notifications-expert` | Push / email / SMS / in-app, preferences UI, deliverability, quiet hours, rate caps |
| `common-privacy-expert` | Consent management (TCF / GPP), DSAR fulfillment, vendor / SDK governance, PIAs |
| `common-product-analytics-expert` | Event taxonomy, instrumentation, identity resolution, funnels / cohorts, experiment wiring |

---

## Principles

- **Phase gates are real.** Do not proceed to the next phase until exit criteria are met.
- **Decisions are logged.** Every significant architectural, security, or process decision goes in `DECISIONS.md`.
- **Agents are specialists.** Invoke them at the right moment; do not bypass.
- **Incremental delivery.** Prefer small, shippable increments over large batches.
- **Continuous deployability.** `main` should always be deployable.
