# Agent Handoff Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add scope delegation blocks, "Recommended next steps" output fields, and cross-pack advisory hints to all ~100 agents in `.claude/agents/`, and update `~/.claude/CLAUDE.md` with a session-restart note.

**Architecture:** Three surgical additions per agent — (1) a `## Scope Boundaries` section for the 8 generalists missing it, (2) a `- **Recommended next steps**` bullet appended to every Output Format section missing it, and (3) advisory cross-pack hints embedded inline in the next-steps sentence. All edits preserve each agent's existing voice and content. Generalists are edited first because their agent names are referenced by pack specialists.

**Tech Stack:** Markdown files only. Edit tool for modifications. Grep for verification.

---

## Conventions used throughout

**Scope section insertion** — add before `## Responsibilities` using:
- old_string: `## Responsibilities`
- new_string: `## Scope Boundaries\n\n[content]\n\n## Responsibilities`

**Output field append** — add after the last existing Output Format bullet using:
- old_string: `[last bullet text]`
- new_string: `[last bullet text]\n- **Recommended next steps** — [content]`

**Output field replacement** — for agents that already have a generic next-steps line, replace it with the specific version.

---

## Task 1: ~/.claude/CLAUDE.md — session restart note

**Files:**
- Modify: `C:\Users\grace\.claude\CLAUDE.md`

- [ ] **Step 1: Verify the restart note is missing**

  ```bash
  grep -n "session restart" "C:/Users/grace/.claude/CLAUDE.md"
  ```
  Expected: no matches.

- [ ] **Step 2: Add restart note after the ccds --help line**

  old_string:
  ```
  - Run the following command - "ccds --help", choose the probable agents that may be needed for the codebase, then run the sync command.
  ```

  new_string:
  ```
  - Run the following command - "ccds --help", choose the probable agents that may be needed for the codebase, then run the sync command.
  - After selecting packs, state the selection and reasoning to the user before running the sync command so they can redirect if needed. Note that copying agents to `.claude/agents/` requires a session restart before they become active — state this explicitly to the user.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -n "session restart" "C:/Users/grace/.claude/CLAUDE.md"
  ```
  Expected: one match on the new line.

- [ ] **Step 4: Commit**

  ```bash
  git add "C:/Users/grace/.claude/CLAUDE.md"
  git commit -m "feat(claude-md): add agent session restart note to init protocol"
  ```

---

## Task 2: plan-architect.md

**Files:**
- Modify: `.claude/agents/plan-architect.md`

- [ ] **Step 1: Verify scope section and specific next-steps are missing**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/plan-architect.md
  ```
  Expected: no matches (or only the generic "recommended next step" bullet).

- [ ] **Step 2: Add Scope Boundaries section**

  old_string: `## Responsibilities`
  new_string:
  ```
  ## Scope Boundaries

  You own: universal component and service boundary design, data flow mapping, integration pattern selection, architectural trade-off analysis, and recording decisions in `DECISIONS.md`.

  You do NOT own:
  - SaaS-specific tenancy, billing topology, and scale decisions → `saas-architect`
  - AI/LLM model selection and serving topology → `ai-architect`
  - Security vulnerability identification and hardening → `secure-auditor`
  - API contract and endpoint design → `api-expert`
  - UI/UX design critique → `ux-design-critic`
  - Pull request and code review → `pr-code-reviewer`
  - Test writing and execution → `test-writer-runner`
  - Production deployment validation → `deploy-checklist`
  - Domain-specific architecture (gaming, mobile, infra, etc.) → the relevant `*-architect` agent

  ## Responsibilities
  ```

- [ ] **Step 3: Replace generic next-step bullet with specific version**

  old_string: `- End with a **recommended next step**`
  new_string:
  ```
  - **Recommended next steps** — name which generalist or specialist to invoke next. After architecture approval, `pr-code-reviewer` follows the first implementation increment. For SaaS-specific decisions invoke `saas-architect`; for AI/LLM decisions invoke `ai-architect`; for security concerns invoke `secure-auditor`. If the system spans a specialized domain, name the relevant domain architect explicitly. If the design crosses multiple specialized domains, consider whether a domain-specific architect would add value before implementation begins.
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/plan-architect.md
  ```
  Expected: two matches.

- [ ] **Step 5: Commit**

  ```bash
  git add .claude/agents/plan-architect.md
  git commit -m "feat(agents): add scope boundaries and next-steps to plan-architect"
  ```

---

## Task 3: pr-code-reviewer.md

**Files:**
- Modify: `.claude/agents/pr-code-reviewer.md`

- [ ] **Step 1: Verify missing**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/pr-code-reviewer.md
  ```
  Expected: no matches.

- [ ] **Step 2: Add Scope Boundaries section**

  old_string: `## Responsibilities`
  new_string:
  ```
  ## Scope Boundaries

  You own: reviewing diffs for correctness, logic errors, edge cases, security surface, performance, maintainability, test coverage, documentation, and breaking changes.

  You do NOT own:
  - Writing implementation tests → `test-writer-runner`
  - Deep security audit (auth bypass, crypto, injection vectors, secrets) → `secure-auditor`
  - API contract and endpoint design → `api-expert`
  - UI component and UX pattern critique → `ux-design-critic`
  - Architecture planning and ADR authoring → `plan-architect`
  - Domain-specific code correctness (billing invariants, ledger postings, etc.) → the relevant pack specialist

  ## Responsibilities
  ```

- [ ] **Step 3: Append next-steps to Output Format**

  old_string: `5. **Verdict** — one of: \`APPROVE\`, \`APPROVE WITH NITS\`, \`REQUEST CHANGES\``
  new_string:
  ```
  5. **Verdict** — one of: `APPROVE`, `APPROVE WITH NITS`, `REQUEST CHANGES`
  - **Recommended next steps** — When all BLOCKER and CONCERN items are resolved, invoke `test-writer-runner` to verify coverage before the work proceeds to hardening. If security findings surface (auth, crypto, injection), invoke `secure-auditor`. If API design issues are found, invoke `api-expert`. If UX/interaction issues are found, invoke `ux-design-critic`. If the diff touches a specialized billing, auth, or ledger domain, consider whether invoking the relevant pack specialist for a domain review would add value.
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/pr-code-reviewer.md
  ```
  Expected: two matches.

- [ ] **Step 5: Commit**

  ```bash
  git add .claude/agents/pr-code-reviewer.md
  git commit -m "feat(agents): add scope boundaries and next-steps to pr-code-reviewer"
  ```

---

## Task 4: test-writer-runner.md

**Files:**
- Modify: `.claude/agents/test-writer-runner.md`

- [ ] **Step 1: Verify missing**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/test-writer-runner.md
  ```
  Expected: no matches.

- [ ] **Step 2: Add Scope Boundaries section**

  old_string: `## Responsibilities`
  new_string:
  ```
  ## Scope Boundaries

  You own: writing and running tests — unit, integration, API, smoke, and edge-case coverage — after implementation is complete or PR review issues are resolved.

  You do NOT own:
  - Security vulnerability analysis → `secure-auditor`
  - API contract design and review → `api-expert`
  - Architecture decisions → `plan-architect`
  - Production deployment validation → `deploy-checklist`
  - Domain-specific test strategy (ML evals, game telemetry, financial invariant testing) → the relevant pack specialist

  ## Responsibilities
  ```

- [ ] **Step 3: Append next-steps to Output Format**

  old_string: `- After writing, summarize: tests added, coverage delta (if measurable), any untestable code flagged`
  new_string:
  ```
  - After writing, summarize: tests added, coverage delta (if measurable), any untestable code flagged
  - **Recommended next steps** — When the test suite passes and coverage meets the project threshold, invoke `secure-auditor` to begin the hardening phase. If coverage gaps exist in domain-specific code (auth, billing, ledger, etc.), invoke the relevant pack specialist to verify the test strategy covers domain invariants. If testing an AI/ML feature, consider whether an eval specialist would add value designing the evaluation harness.
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/test-writer-runner.md
  ```
  Expected: two matches.

- [ ] **Step 5: Commit**

  ```bash
  git add .claude/agents/test-writer-runner.md
  git commit -m "feat(agents): add scope boundaries and next-steps to test-writer-runner"
  ```

---

## Task 5: api-expert.md

**Files:**
- Modify: `.claude/agents/api-expert.md`

- [ ] **Step 1: Verify missing**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/api-expert.md
  ```
  Expected: no matches.

- [ ] **Step 2: Add Scope Boundaries section**

  old_string: `## Responsibilities`
  new_string:
  ```
  ## Scope Boundaries

  You own: HTTP/REST/GraphQL API design and implementation, authentication flows, data contracts, API clients, webhooks, and request/response schemas.

  You do NOT own:
  - Security review of auth bypass, crypto, or injection vectors → `secure-auditor`
  - UI/UX for API consumers and developer ergonomics → `ux-design-critic`
  - Full diff code review → `pr-code-reviewer`
  - SSO/SAML/SCIM and SaaS identity topology → `saas-auth-sso-expert`
  - Payment provider API integration → `ecom-payments-expert` or `saas-billing-expert`
  - Domain-specific protocol design (MQTT, HLS manifests, FIX) → the relevant pack specialist

  ## Responsibilities
  ```

- [ ] **Step 3: Append next-steps to Output Format**

  old_string: `- For review tasks: list issues by severity (CRITICAL, HIGH, MEDIUM, LOW) with specific line references and fix recommendations`
  new_string:
  ```
  - For review tasks: list issues by severity (CRITICAL, HIGH, MEDIUM, LOW) with specific line references and fix recommendations
  - **Recommended next steps** — Return design or review findings to the orchestrator; invoke `pr-code-reviewer` to review implementation before it proceeds. If auth or crypto vulnerabilities surface, invoke `secure-auditor`. If API UX or ergonomics need attention, invoke `ux-design-critic`. If SSO or SAML is involved, invoke `saas-auth-sso-expert`. If the API serves a specialized protocol domain (payment rails, media manifests, embedded device comms), consider whether a domain specialist would add value reviewing the contract.
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/api-expert.md
  ```
  Expected: two matches.

- [ ] **Step 5: Commit**

  ```bash
  git add .claude/agents/api-expert.md
  git commit -m "feat(agents): add scope boundaries and next-steps to api-expert"
  ```

---

## Task 6: ux-design-critic.md

**Files:**
- Modify: `.claude/agents/ux-design-critic.md`

- [ ] **Step 1: Verify missing**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/ux-design-critic.md
  ```
  Expected: no matches.

- [ ] **Step 2: Add Scope Boundaries section**

  old_string: `## Responsibilities`
  new_string:
  ```
  ## Scope Boundaries

  You own: UX evaluation of UI components, forms, layouts, navigation flows, and user-facing interactions — pattern correctness, friction reduction, and accessibility surface identification.

  You do NOT own:
  - Accessibility audit to WCAG criterion level → `common-a11y-expert`
  - Internationalization, RTL, and locale-aware formatting → `common-i18n-expert`
  - Full diff code review → `pr-code-reviewer`
  - API contract design → `api-expert`
  - Browser extension popup/options-page UX → `ext-ux-expert`
  - Game feel, input responsiveness, and haptic feedback → `game-feel-critic`
  - Notification design and preferences UI → `common-notifications-expert`

  ## Responsibilities
  ```

- [ ] **Step 3: Append next-steps to Output Format**

  old_string: `- End with **2–3 concrete improvement suggestions** the developer can act on immediately`
  new_string:
  ```
  - End with **2–3 concrete improvement suggestions** the developer can act on immediately
  - **Recommended next steps** — Return UX findings to the orchestrator; invoke `pr-code-reviewer` to review implementation before proceeding. If accessibility issues surface, invoke `common-a11y-expert`. If localization or RTL concerns arise, invoke `common-i18n-expert`. If the interface is a CLI/devtool, invoke `devtool-cli-ux-expert`. If it is a browser extension popup, invoke `ext-ux-expert`. If it is a game UI, invoke `game-feel-critic`. If notification or preference UI is involved, consider whether a notification design specialist would add value.
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/ux-design-critic.md
  ```
  Expected: two matches.

- [ ] **Step 5: Commit**

  ```bash
  git add .claude/agents/ux-design-critic.md
  git commit -m "feat(agents): add scope boundaries and next-steps to ux-design-critic"
  ```

---

## Task 7: deploy-checklist.md

**Files:**
- Modify: `.claude/agents/deploy-checklist.md`

- [ ] **Step 1: Verify missing**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/deploy-checklist.md
  ```
  Expected: no matches.

- [ ] **Step 2: Add Scope Boundaries section**

  old_string: `## Responsibilities`
  new_string:
  ```
  ## Scope Boundaries

  You own: pre-deployment readiness validation — code quality gates, configuration and secrets verification, database migration safety, infrastructure health checks, rollback planning, and GO/NO-GO decisions.

  You do NOT own:
  - Resolving unmitigated security findings → `secure-auditor`
  - Database schema and migration design → `saas-data-model-expert`, `dataplat-etl-expert`, or the relevant data specialist
  - Infrastructure topology decisions → `infra-architect`
  - Post-deploy monitoring and SLO incident response → `infra-sre-expert`
  - Domain-specific deployment concerns (OTA firmware, mobile store submission, etc.) → the relevant pack specialist

  ## Responsibilities
  ```

- [ ] **Step 3: Append next-steps to Output Format**

  old_string: `5. **Post-deploy validation steps** — what to verify in the first 15 minutes after deploy`
  new_string:
  ```
  5. **Post-deploy validation steps** — what to verify in the first 15 minutes after deploy
  - **Recommended next steps** — A GO verdict clears the way for deployment. A NO-GO halts until all blockers are resolved. If CRITICAL or HIGH security findings are unresolved, invoke `secure-auditor` before re-running this checklist. If database migration issues surface, invoke the relevant data specialist (`saas-data-model-expert`, `dataplat-etl-expert`, etc.). If SLO or monitoring gaps are found, invoke `infra-sre-expert`. If infrastructure configuration is incorrect, invoke `infra-architect`. If deploying into a regulated environment (financial, healthcare, government), consider whether a compliance specialist would add value reviewing the deployment evidence.
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/deploy-checklist.md
  ```
  Expected: two matches.

- [ ] **Step 5: Commit**

  ```bash
  git add .claude/agents/deploy-checklist.md
  git commit -m "feat(agents): add scope boundaries and next-steps to deploy-checklist"
  ```

---

## Task 8: secure-auditor.md

**Files:**
- Modify: `.claude/agents/secure-auditor.md`

- [ ] **Step 1: Verify scope section is missing and next-steps is generic**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/secure-auditor.md
  ```
  Expected: one match for the existing generic "Recommended next steps" line (no scope section match).

- [ ] **Step 2: Add Scope Boundaries section**

  old_string: `## Responsibilities`
  new_string:
  ```
  ## Scope Boundaries

  You own: static analysis for vulnerabilities, authentication and authorization review, cryptographic audit, injection vector identification, secrets hygiene, dependency risk, and input validation at trust boundaries.

  You do NOT own:
  - SaaS-specific RBAC/ABAC implementation and SSO/SAML flows → `saas-auth-sso-expert`
  - AI/LLM content safety and prompt injection defense → `ai-safety-expert`
  - Agent sandbox security and tool authority → `orch-sandbox-safety-expert`
  - Billing/PCI scope architecture → `saas-billing-expert` (escalate scope expansion here)
  - General code review across the full diff → `pr-code-reviewer`
  - Embedded firmware security and secure boot → `embed-architect`

  ## Responsibilities
  ```

- [ ] **Step 3: Replace generic next-steps with specific version**

  old_string: `4. **Recommended next steps** — ordered by risk reduction impact`
  new_string:
  ```
  4. **Recommended next steps** — ordered by risk reduction impact. When all CRITICAL and HIGH findings are resolved, invoke `deploy-checklist` for pre-production validation. If SaaS auth or RBAC code requires deeper domain review, invoke `saas-auth-sso-expert`. If AI/LLM prompt injection is in scope, invoke `ai-safety-expert`. If agent sandbox security is in scope, invoke `orch-sandbox-safety-expert`. If the codebase handles regulated financial data, consider whether a fintech compliance specialist would add value reviewing data-handling practices.
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -n "Scope Boundaries\|Recommended next steps" .claude/agents/secure-auditor.md
  ```
  Expected: two matches.

- [ ] **Step 5: Commit**

  ```bash
  git add .claude/agents/secure-auditor.md
  git commit -m "feat(agents): add scope boundaries and specific next-steps to secure-auditor"
  ```

---

## Task 9: saas pack — 6 agents

**Files:**
- Modify: `.claude/agents/saas-architect.md`, `saas-auth-sso-expert.md`, `saas-billing-expert.md`, `saas-data-model-expert.md`, `saas-multitenancy-expert.md`, `saas-collab-sync-expert.md`

- [ ] **Step 1: Verify output fields are missing or generic**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/saas-*.md
  ```
  Expected: one match in `saas-architect.md` (the existing generic one); no matches in the others.

- [ ] **Step 2: saas-architect.md — replace generic next-steps with specific version**

  old_string: `- **Recommended next steps** — concrete next actions and which specialists to engage`
  new_string:
  ```
  - **Recommended next steps** — Name which specialists to engage based on decisions made: schema work → `saas-data-model-expert`; auth topology → `saas-auth-sso-expert`; billing implementation → `saas-billing-expert`; tenant isolation enforcement → `saas-multitenancy-expert`; realtime sync → `saas-collab-sync-expert`. Route all implementation through `pr-code-reviewer` after code is written. If security concerns surface, invoke `secure-auditor`. For universal component boundaries, collaborate with `plan-architect`.
  ```

- [ ] **Step 3: saas-auth-sso-expert.md — append next-steps**

  old_string: `- **Draft ADR** — for any non-trivial auth topology choice`
  new_string:
  ```
  - **Draft ADR** — for any non-trivial auth topology choice
  - **Recommended next steps** — Return auth implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. Ensure `secure-auditor` has reviewed any cryptographic primitive or token-handling changes. If multi-tenant SSO affects channel isolation, coordinate with `saas-multitenancy-expert`. If entitlement checks are affected by the auth change, coordinate with `saas-billing-expert`.
  ```

- [ ] **Step 4: saas-billing-expert.md — append next-steps**

  old_string: `- **Draft ADR** — when a non-obvious billing decision is made`
  new_string:
  ```
  - **Draft ADR** — when a non-obvious billing decision is made
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If PCI scope expands, invoke `secure-auditor` immediately. Confirm `secure-auditor` has reviewed any code touching payment tokens or raw webhook bodies before merging.
  ```

- [ ] **Step 5: saas-data-model-expert.md — append next-steps**

  old_string: `- **Draft ADR** — when a non-obvious data modeling decision is made`
  new_string:
  ```
  - **Draft ADR** — when a non-obvious data modeling decision is made
  - **Recommended next steps** — Return schema or migration to the orchestrator; `pr-code-reviewer` reviews before applying. For large-table migrations, coordinate timing with `deploy-checklist`. If RLS policies are affected by schema changes, invoke `saas-multitenancy-expert`. If billing data schema is changing, coordinate with `saas-billing-expert`. If the schema will serve heavy analytical workloads, consider whether a data platform specialist would add value reviewing the access patterns.
  ```

- [ ] **Step 6: saas-multitenancy-expert.md — append next-steps**

  old_string: `- **Draft ADR** — when a non-trivial isolation pattern is chosen`
  new_string:
  ```
  - **Draft ADR** — when a non-trivial isolation pattern is chosen
  - **Recommended next steps** — Return isolation code to the orchestrator; `pr-code-reviewer` reviews before proceeding. Escalate any cryptographic or privilege-escalation concerns to `secure-auditor`. If the schema is also changing, coordinate with `saas-data-model-expert`.
  ```

- [ ] **Step 7: saas-collab-sync-expert.md — append next-steps**

  old_string: `- **Draft ADR** — when a non-trivial sync decision is made`
  new_string:
  ```
  - **Draft ADR** — when a non-trivial sync decision is made
  - **Recommended next steps** — Return sync implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If tenant isolation of realtime channels needs verification, invoke `saas-multitenancy-expert`. If the sync protocol must operate over mobile devices with intermittent connectivity, consider whether a mobile offline sync specialist would add value reviewing the reconnection and replay design.
  ```

- [ ] **Step 8: Verify all additions**

  ```bash
  grep -c "Recommended next steps" .claude/agents/saas-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 9: Commit**

  ```bash
  git add .claude/agents/saas-*.md
  git commit -m "feat(agents): add handoff language to saas pack"
  ```

---

## Task 10: ai pack — 7 agents

**Files:**
- Modify: `.claude/agents/ai-architect.md`, `ai-prompt-engineer.md`, `ai-rag-expert.md`, `ai-eval-expert.md`, `ai-inference-perf-expert.md`, `ai-safety-expert.md`, `ai-finetune-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/ai-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: ai-architect.md — append next-steps**

  old_string: `- **Draft ADR**`

  Note: ai-architect has two bullets ending with `- **Draft ADR**`. Use this more specific old_string to ensure uniqueness — confirm by reading the file first. The Output Format section's Draft ADR is the final bullet.

  new_string (append after the Output Format's Draft ADR bullet):
  ```
  - **Draft ADR**
  - **Recommended next steps** — Engage specialists per domain: prompts → `ai-prompt-engineer`; retrieval → `ai-rag-expert`; evals → `ai-eval-expert`; inference tuning → `ai-inference-perf-expert`; safety/injection → `ai-safety-expert`; fine-tuning → `ai-finetune-expert`. Route all implementation through `pr-code-reviewer`. If the AI system handles regulated data (financial, health), consider whether a compliance or privacy specialist would add value reviewing the data policy.
  ```

  **Implementation note:** Read the file first to confirm the exact context of the last Output Format bullet before applying the edit.

- [ ] **Step 3: ai-prompt-engineer.md — append next-steps**

  old_string: `- **Failure modes** — where the prompt is known to drift`
  new_string:
  ```
  - **Failure modes** — where the prompt is known to drift
  - **Recommended next steps** — Return the prompt and eval result to the orchestrator. If output quality meets the eval bar, `pr-code-reviewer` reviews the integration code before proceeding. If the prompt is failing on adversarial inputs, invoke `ai-safety-expert`. If retrieval context is malformed or insufficient, invoke `ai-rag-expert`. If the prompt handles regulated-domain content (medical, legal, financial), consider whether a domain safety specialist would add value reviewing the refusal policy.
  ```

- [ ] **Step 4: ai-rag-expert.md — append next-steps**

  old_string: `- **Eval** — recall@k / MRR / context-precision before and after`
  new_string:
  ```
  - **Eval** — recall@k / MRR / context-precision before and after
  - **Recommended next steps** — Return the retrieval pipeline to the orchestrator; `pr-code-reviewer` reviews the integration code before proceeding. If eval metrics are below target, invoke `ai-eval-expert`. If the prompt consuming retrieved context is performing poorly, invoke `ai-prompt-engineer`. If the knowledge base contains PII or regulated data, consider whether a privacy specialist would add value reviewing the retention and access policy.
  ```

- [ ] **Step 5: ai-eval-expert.md — append next-steps**

  old_string: `- **Baseline** — current metric values across axes`
  new_string:
  ```
  - **Baseline** — current metric values across axes
  - **Recommended next steps** — Return the eval harness and baseline metrics to the orchestrator; `pr-code-reviewer` reviews CI wiring before merging. If a perf regression gate is needed alongside quality, invoke `ai-inference-perf-expert`. If a human-rater protocol is required, surface the protocol for product review before implementing.
  ```

- [ ] **Step 6: ai-inference-perf-expert.md — append next-steps**

  old_string: `- **Regression guard** — monitored metric and threshold`
  new_string:
  ```
  - **Regression guard** — monitored metric and threshold
  - **Recommended next steps** — Return the perf change and quality-check result to the orchestrator; `pr-code-reviewer` reviews before deploying. If quality degraded under the perf change, invoke `ai-eval-expert`. If the serving topology needs restructuring, invoke `ai-architect`. If the inference workload is cost-sensitive at scale, consider whether a cloud FinOps specialist would add value reviewing the compute commitment strategy.
  ```

- [ ] **Step 7: ai-safety-expert.md — append next-steps**

  old_string: `- **Monitoring** — refusal rate, leak-detection metrics`
  new_string:
  ```
  - **Monitoring** — refusal rate, leak-detection metrics
  - **Recommended next steps** — Return safety controls and red-team results to the orchestrator; `secure-auditor` reviews any application-security concerns before proceeding. If sandbox execution is involved, invoke `orch-sandbox-safety-expert`. If the policy touches PII collection or retention, invoke `common-privacy-expert`.
  ```

- [ ] **Step 8: ai-finetune-expert.md — append next-steps**

  old_string: `- **Eval plan** — pre/post comparison, regression gates`
  new_string:
  ```
  - **Eval plan** — pre/post comparison, regression gates
  - **Recommended next steps** — Return the training config and eval plan to the orchestrator; `ai-eval-expert` verifies quality gates before the model is deployed. If the dataset contains PII or regulated content, invoke `ai-safety-expert` and `common-privacy-expert` before training begins. If inference serving of the fine-tuned model is needed, invoke `ai-inference-perf-expert`.
  ```

- [ ] **Step 9: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/ai-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 10: Commit**

  ```bash
  git add .claude/agents/ai-*.md
  git commit -m "feat(agents): add handoff language to ai pack"
  ```

---

## Task 11: infra pack — 8 agents

**Files:**
- Modify: `.claude/agents/infra-architect.md`, `infra-sre-expert.md`, `infra-observability-expert.md`, `infra-k8s-expert.md`, `infra-finops-expert.md`, `infra-dr-backup-expert.md`, `infra-networking-expert.md`, `infra-iam-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/infra-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **infra-architect.md**
  old_string: `- **Decisions** — ADR-ready bullets`
  new_string:
  ```
  - **Decisions** — ADR-ready bullets
  - **Recommended next steps** — Engage specialists per domain: Kubernetes → `infra-k8s-expert`; observability → `infra-observability-expert`; SLOs → `infra-sre-expert`; IAM → `infra-iam-expert`; cost → `infra-finops-expert`; DR/backup → `infra-dr-backup-expert`; networking → `infra-networking-expert`. Route all implementation through `pr-code-reviewer`. If deploying an AI serving workload, consider whether an AI inference performance specialist would add value sizing GPU topology and cost.
  ```

  **infra-sre-expert.md**
  old_string: `- **Postmortem template** — timeline, contributors, action items`
  new_string:
  ```
  - **Postmortem template** — timeline, contributors, action items
  - **Recommended next steps** — Return SLO specs and runbooks to the orchestrator; `pr-code-reviewer` reviews any code changes before merging. If alert routing involves Kubernetes specifics, coordinate with `infra-k8s-expert`. If cost trade-offs influence reliability targets, coordinate with `infra-finops-expert`. If the system under SLO is an AI model pipeline, consider whether an AI architect would add value reviewing model-specific reliability patterns.
  ```

  **infra-observability-expert.md**
  old_string: `- **Dashboard set** — golden signals + service + on-call views`
  new_string:
  ```
  - **Dashboard set** — golden signals + service + on-call views
  - **Recommended next steps** — Return instrumentation plan and dashboards to the orchestrator; `pr-code-reviewer` reviews instrumentation code before merging. If cardinality cost is high, coordinate with `infra-finops-expert`. If Kubernetes-specific metrics are needed, coordinate with `infra-k8s-expert`. If the system includes AI model serving, consider whether an AI eval specialist would add value designing model-specific monitoring.
  ```

  **infra-k8s-expert.md**
  old_string: `- **GitOps topology** — apps, sync waves, environments`
  new_string:
  ```
  - **GitOps topology** — apps, sync waves, environments
  - **Recommended next steps** — Return manifests and GitOps config to the orchestrator; `pr-code-reviewer` reviews before merging. If network policy changes are involved, coordinate with `infra-networking-expert`. If SLO targets are affected, invoke `infra-sre-expert`. If workloads include GPU or ML inference pods, consider whether an AI inference performance specialist would add value sizing the node pools.
  ```

  **infra-finops-expert.md**
  old_string: `- **Alerting** — anomaly + budget thresholds with routing`
  new_string:
  ```
  - **Alerting** — anomaly + budget thresholds with routing
  - **Recommended next steps** — Return cost analysis to the orchestrator; `pr-code-reviewer` reviews any code changes before merging. If reliability vs cost trade-offs need resolution, collaborate with `infra-sre-expert`. If K8s workload sizing is the lever, collaborate with `infra-k8s-expert`. If cost is driven primarily by AI inference, consider whether an AI inference performance specialist would add value identifying optimization opportunities.
  ```

  **infra-dr-backup-expert.md**
  old_string: `- **Coverage dashboard** — services enrolled vs total, last-successful-backup age, last-restore-drill age`
  new_string:
  ```
  - **Coverage dashboard** — services enrolled vs total, last-successful-backup age, last-restore-drill age
  - **Recommended next steps** — Return the DR topology and runbook to the orchestrator; `pr-code-reviewer` reviews any automation code before merging. If SLO targets are affected by RPO/RTO decisions, coordinate with `infra-sre-expert`. If financial record backup has regulatory retention requirements, invoke `fintech-audit-trail-expert` (if fintech pack is active).
  ```

  **infra-networking-expert.md**
  old_string: `- **Debug playbook** — packet-loss / latency / DNS / MTU / conntrack diagnostic flow with commands`
  new_string:
  ```
  - **Debug playbook** — packet-loss / latency / DNS / MTU / conntrack diagnostic flow with commands
  - **Recommended next steps** — Return the network topology and policy config to the orchestrator; `pr-code-reviewer` reviews any IaC changes before merging. If Kubernetes network policy is involved, coordinate with `infra-k8s-expert`. If IAM boundary changes accompany the network change, coordinate with `infra-iam-expert`. If the network serves embedded or IoT devices at the edge, consider whether an embedded connectivity specialist would add value reviewing the device-to-cloud path.
  ```

  **infra-iam-expert.md**
  old_string: `- **Drift-detection rules** — daily checks, finding taxonomy, SLA per severity, remediation path`
  new_string:
  ```
  - **Drift-detection rules** — daily checks, finding taxonomy, SLA per severity, remediation path
  - **Recommended next steps** — Return IAM policies and access-review plan to the orchestrator; `pr-code-reviewer` reviews policy code before merging. If application-layer RBAC is affected, coordinate with `saas-auth-sso-expert`. If pod-level Kubernetes RBAC is involved, coordinate with `infra-k8s-expert`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/infra-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/infra-*.md
  git commit -m "feat(agents): add handoff language to infra pack"
  ```

---

## Task 12: devtool pack — 6 agents

**Files:**
- Modify: `.claude/agents/devtool-architect.md`, `devtool-cli-ux-expert.md`, `devtool-library-api-expert.md`, `devtool-packaging-expert.md`, `devtool-docgen-expert.md`, `devtool-telemetry-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/devtool-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **devtool-architect.md**
  old_string: `- **Compat matrix** — supported runtimes / platforms / previous major`
  new_string:
  ```
  - **Compat matrix** — supported runtimes / platforms / previous major
  - **Recommended next steps** — Engage specialists per domain: CLI ergonomics → `devtool-cli-ux-expert`; library API surface → `devtool-library-api-expert`; build and distribution → `devtool-packaging-expert`; documentation → `devtool-docgen-expert`; usage telemetry → `devtool-telemetry-expert`. Route all implementation through `pr-code-reviewer`. If the tool serves regulated industries, consider whether a compliance specialist would add value reviewing data handling and telemetry design.
  ```

  **devtool-cli-ux-expert.md**
  old_string: `- **Completion** — bash/zsh/fish, dynamic completion triggers`
  new_string:
  ```
  - **Completion** — bash/zsh/fish, dynamic completion triggers
  - **Recommended next steps** — Return CLI spec to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If the change also affects the public API surface, coordinate with `devtool-library-api-expert`. If shell completion or packaging is affected, coordinate with `devtool-packaging-expert`.
  ```

  **devtool-library-api-expert.md**
  old_string: `- **Compat notes** — what this changes for existing consumers`
  new_string:
  ```
  - **Compat notes** — what this changes for existing consumers
  - **Recommended next steps** — Return the API spec to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If the change is a breaking surface change, invoke `devtool-architect` to evaluate versioning impact. If documentation needs updating, invoke `devtool-docgen-expert`.
  ```

  **devtool-packaging-expert.md**
  old_string: `- **Provenance / SBOM** — generation, publication, verification`
  new_string:
  ```
  - **Provenance / SBOM** — generation, publication, verification
  - **Recommended next steps** — Return the build and release pipeline to the orchestrator; `pr-code-reviewer` reviews CI config before merging. If supply-chain or signing concerns surface, invoke `secure-auditor`.
  ```

  **devtool-docgen-expert.md**
  old_string: `- **Changelog policy** — format, automation, curation rules`
  new_string:
  ```
  - **Changelog policy** — format, automation, curation rules
  - **Recommended next steps** — Return the docs architecture to the orchestrator; `pr-code-reviewer` reviews doc-generation code before merging. If the API surface being documented has changed, coordinate with `devtool-library-api-expert` to verify accuracy.
  ```

  **devtool-telemetry-expert.md**
  old_string: `- **Transport config** — endpoint, TLS pinning policy (if any), timeout, retry, batching, dead-letter`
  new_string:
  ```
  - **Transport config** — endpoint, TLS pinning policy (if any), timeout, retry, batching, dead-letter
  - **Recommended next steps** — Return the telemetry design to the orchestrator; `pr-code-reviewer` reviews implementation before merging. If PII risks are identified in the event schema, invoke `common-privacy-expert`. If in-product analytics (not just CLI telemetry) are also needed, consider whether a product analytics specialist would add value designing the event taxonomy.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/devtool-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/devtool-*.md
  git commit -m "feat(agents): add handoff language to devtool pack"
  ```

---

## Task 13: game pack — 9 agents

**Files:**
- Modify: `.claude/agents/game-architect.md`, `game-engine-expert.md`, `game-netcode-expert.md`, `game-perf-profiler.md`, `game-balance-designer.md`, `game-feel-critic.md`, `game-liveops-expert.md`, `game-platform-cert-expert.md`, `game-audio-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/game-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **game-architect.md**
  old_string: `- **Draft ADR** — for \`DECISIONS.md\``
  new_string:
  ```
  - **Draft ADR** — for `DECISIONS.md`
  - **Recommended next steps** — Engage specialists per domain: engine implementation → `game-engine-expert`; multiplayer → `game-netcode-expert`; frame budget → `game-perf-profiler`; audio → `game-audio-expert`; economy/progression → `game-balance-designer`; game feel → `game-feel-critic`; live-ops → `game-liveops-expert`; platform cert → `game-platform-cert-expert`. Route all implementation through `pr-code-reviewer`. If the game UI has complex accessibility requirements, consider whether an accessibility specialist would add value reviewing input and display design.
  ```

  **game-engine-expert.md**
  old_string: `- **Fallback / alternative** — if the built-in option was rejected, why`
  new_string:
  ```
  - **Fallback / alternative** — if the built-in option was rejected, why
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If the change affects frame budget, invoke `game-perf-profiler`. If audio integration is involved, invoke `game-audio-expert`. If the implementation exposes player-facing interactions, consider whether a game feel specialist would add value reviewing the responsiveness.
  ```

  **game-netcode-expert.md**
  old_string: `- **Draft ADR** — for non-obvious topology choices`
  new_string:
  ```
  - **Draft ADR** — for non-obvious topology choices
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If matchmaking affects economy balancing, coordinate with `game-balance-designer`. If the game runs on mobile, consider whether a mobile architecture specialist would add value reviewing background execution constraints on the network thread.
  ```

  **game-perf-profiler.md**
  old_string: `- **Regression guard** — a test or metric that catches a return`
  new_string:
  ```
  - **Regression guard** — a test or metric that catches a return
  - **Recommended next steps** — Return the fix to the orchestrator; `pr-code-reviewer` reviews before proceeding. If the fix requires an engine-level refactor, invoke `game-engine-expert`. If profiling reveals audio CPU cost as the primary bottleneck, invoke `game-audio-expert`.
  ```

  **game-balance-designer.md**
  old_string: `- **Telemetry plan** — the metric that confirms or refutes the tuning post-launch`
  new_string:
  ```
  - **Telemetry plan** — the metric that confirms or refutes the tuning post-launch
  - **Recommended next steps** — Return tuning values to the orchestrator; `game-liveops-expert` validates with live telemetry after ship. If economy involves IAP, coordinate with `mobile-iap-expert` (mobile) or `ecom-payments-expert` (web storefront). If a data pipeline is needed to capture the telemetry, consider whether a data platform streaming specialist would add value reviewing the event ingestion design.
  ```

  **game-feel-critic.md**
  old_string: `- **Playtest note** — what to watch for in the next session`
  new_string:
  ```
  - **Playtest note** — what to watch for in the next session
  - **Recommended next steps** — Return findings to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If accessibility coverage is insufficient, invoke `common-a11y-expert`.
  ```

  **game-liveops-expert.md**
  old_string: `- **Rollback plan** — kill switch, comms, refund posture`
  new_string:
  ```
  - **Rollback plan** — kill switch, comms, refund posture
  - **Recommended next steps** — Return the live-ops plan to the orchestrator; `pr-code-reviewer` reviews code changes before merging. If A/B test statistical rigor is needed, consider whether a data platform quality specialist would add value reviewing the experiment design. If the telemetry pipeline feeds a warehouse, consider whether a data platform streaming specialist would add value reviewing the ingestion topology.
  ```

  **game-platform-cert-expert.md**
  old_string: `- **Risk log** — known fragile requirements and mitigation`
  new_string:
  ```
  - **Risk log** — known fragile requirements and mitigation
  - **Recommended next steps** — Return the cert checklist to the orchestrator. Coordinate with `mobile-release-expert` for mobile platform (App Store / Play Store) submissions. If cert failures require engine changes, invoke `game-engine-expert`.
  ```

  **game-audio-expert.md**
  old_string: `- **Perf budget** — CPU %, memory MB, voice limits`
  new_string:
  ```
  - **Perf budget** — CPU %, memory MB, voice limits
  - **Recommended next steps** — Return audio architecture to the orchestrator; `pr-code-reviewer` reviews integration code before proceeding. If platform cert has audio-specific requirements, coordinate with `game-platform-cert-expert`. If audio CPU cost is contributing to frame budget overruns, involve `game-perf-profiler`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/game-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/game-*.md
  git commit -m "feat(agents): add handoff language to game pack"
  ```

---

## Task 14: mobile pack — 7 agents

**Files:**
- Modify: `.claude/agents/mobile-architect.md`, `mobile-platform-expert.md`, `mobile-offline-sync-expert.md`, `mobile-release-expert.md`, `mobile-perf-expert.md`, `mobile-iap-expert.md`, `mobile-crash-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/mobile-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **mobile-architect.md**
  old_string: `- **Draft ADR**`

  Note: read the file first to confirm this is the Output Format section's final bullet, not the Approach section.

  new_string:
  ```
  - **Draft ADR**
  - **Recommended next steps** — Engage specialists per domain: platform APIs → `mobile-platform-expert`; offline sync → `mobile-offline-sync-expert`; perf → `mobile-perf-expert`; IAP → `mobile-iap-expert`; crashes → `mobile-crash-expert`; store submission → `mobile-release-expert`. Route all implementation through `pr-code-reviewer`. If the app handles payments beyond IAP (web-based subscriptions, wallet features), consider whether a SaaS billing or fintech specialist would add value reviewing the money-movement design.
  ```

  **mobile-platform-expert.md**
  old_string: `- **Both-platform parity** — explicit diff of iOS vs Android behavior if applicable`
  new_string:
  ```
  - **Both-platform parity** — explicit diff of iOS vs Android behavior if applicable
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If new permissions are being requested, coordinate with `mobile-release-expert` to update privacy declarations. If the integration involves notifications, consider whether a notification design specialist would add value reviewing the permission request timing and UX.
  ```

  **mobile-offline-sync-expert.md**
  old_string: `- **Adversarial tests** — device-offline-mid-edit, duplicate-retry, schema-rollback`
  new_string:
  ```
  - **Adversarial tests** — device-offline-mid-edit, duplicate-retry, schema-rollback
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If the server-side sync protocol also needs changes, invoke `saas-collab-sync-expert` (if active) or `api-expert`.
  ```

  **mobile-release-expert.md**
  old_string: `- **Review prep** — demo account, notes, known-issue list`
  new_string:
  ```
  - **Review prep** — demo account, notes, known-issue list
  - **Recommended next steps** — After submission, monitor for review feedback. If the review is rejected for permissions, coordinate with `mobile-platform-expert`. If rejected for billing or IAP, coordinate with `mobile-iap-expert`. If rejected for privacy declarations, invoke `common-privacy-expert`.
  ```

  **mobile-perf-expert.md**
  old_string: `- **Regression guard** — CI check or dashboard entry`
  new_string:
  ```
  - **Regression guard** — CI check or dashboard entry
  - **Recommended next steps** — Return the fix to the orchestrator; `pr-code-reviewer` reviews before proceeding. If the regression guard subsequently triggers a crash spike, invoke `mobile-crash-expert`.
  ```

  **mobile-iap-expert.md**
  old_string: `- **Reconciliation job** — schedule, comparison, alerting`
  new_string:
  ```
  - **Reconciliation job** — schedule, comparison, alerting
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If subscription state needs to reconcile with a SaaS billing system, coordinate with `saas-billing-expert`.
  ```

  **mobile-crash-expert.md**
  old_string: `- **Symbolication checklist** — per-platform pipeline`
  new_string:
  ```
  - **Symbolication checklist** — per-platform pipeline
  - **Recommended next steps** — Return SDK setup and triage workflow to the orchestrator; `pr-code-reviewer` reviews pipeline changes before merging. If the crash is caused by a platform API misuse, invoke `mobile-platform-expert`. If crashes correlate with IAP or subscription state transitions, invoke `mobile-iap-expert`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/mobile-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/mobile-*.md
  git commit -m "feat(agents): add handoff language to mobile pack"
  ```

---

## Task 15: ecom pack — 7 agents

**Files:**
- Modify: `.claude/agents/ecom-architect.md`, `ecom-payments-expert.md`, `ecom-inventory-expert.md`, `ecom-search-merch-expert.md`, `ecom-storefront-perf-expert.md`, `ecom-tax-expert.md`, `ecom-promotions-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/ecom-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **ecom-architect.md**
  old_string: `- **Decisions** — ADR-ready bullets`
  new_string:
  ```
  - **Decisions** — ADR-ready bullets
  - **Recommended next steps** — Engage specialists per domain: payments → `ecom-payments-expert`; inventory → `ecom-inventory-expert`; search/merchandising → `ecom-search-merch-expert`; storefront perf → `ecom-storefront-perf-expert`; tax → `ecom-tax-expert`; promotions → `ecom-promotions-expert`. Route all implementation through `pr-code-reviewer`. If the platform serves regulated financial products, consider whether a fintech compliance specialist would add value reviewing the compliance posture.
  ```

  **ecom-payments-expert.md**
  old_string: `- **Reconciliation plan** — daily/weekly comparison jobs`
  new_string:
  ```
  - **Reconciliation plan** — daily/weekly comparison jobs
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If PCI scope expands, invoke `secure-auditor` immediately. If checkout UX needs review, invoke `ux-design-critic`. If subscription billing extends into a SaaS model, consider whether a SaaS billing specialist would add value reviewing the recurring-payment design.
  ```

  **ecom-inventory-expert.md**
  old_string: `- **Integration map** — OMS / WMS / ERP sync directions and cadences`
  new_string:
  ```
  - **Integration map** — OMS / WMS / ERP sync directions and cadences
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If allocation changes affect how stock status surfaces in search, coordinate with `ecom-search-merch-expert`.
  ```

  **ecom-search-merch-expert.md**
  old_string: `- **Eval plan** — metric, baseline, holdout`
  new_string:
  ```
  - **Eval plan** — metric, baseline, holdout
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If ML ranking is involved, consider whether an AI specialist would add value reviewing the model pipeline. If the search system feeds a personalization experiment, consider whether a product analytics specialist would add value designing the experiment wiring.
  ```

  **ecom-storefront-perf-expert.md**
  old_string: `- **Monitoring** — RUM + synthetic setup, alert thresholds`
  new_string:
  ```
  - **Monitoring** — RUM + synthetic setup, alert thresholds
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If the storefront uses AI for personalization, consider whether an AI inference performance specialist would add value reviewing the latency impact on Core Web Vitals.
  ```

  **ecom-tax-expert.md**
  old_string: `- **Reconciliation report** — monthly three-way tie-out with drift explanations and corrective entries`
  new_string:
  ```
  - **Reconciliation report** — monthly three-way tie-out with drift explanations and corrective entries
  - **Recommended next steps** — Return integration spec to the orchestrator; `pr-code-reviewer` reviews before proceeding. If a new jurisdiction triggers new compliance obligations beyond sales tax, invoke `fintech-compliance-expert`.
  ```

  **ecom-promotions-expert.md**
  old_string: `- **Testing strategy** — property-based cart-generation tests, regression suite for historical order replay, peak-load validation`
  new_string:
  ```
  - **Testing strategy** — property-based cart-generation tests, regression suite for historical order replay, peak-load validation
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If gift-card or loyalty liability involves ledger entries, invoke `fintech-ledger-expert` (if fintech pack is active) or `saas-billing-expert`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/ecom-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/ecom-*.md
  git commit -m "feat(agents): add handoff language to ecom pack"
  ```

---

## Task 16: fintech pack — 5 agents

**Files:**
- Modify: `.claude/agents/fintech-architect.md`, `fintech-ledger-expert.md`, `fintech-compliance-expert.md`, `fintech-audit-trail-expert.md`, `fintech-risk-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/fintech-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **fintech-architect.md**
  old_string: `- **Decisions** — ADR-ready bullets`
  new_string:
  ```
  - **Decisions** — ADR-ready bullets
  - **Recommended next steps** — Engage specialists per domain: ledger → `fintech-ledger-expert`; KYC/AML → `fintech-compliance-expert`; audit trail → `fintech-audit-trail-expert`; risk modeling → `fintech-risk-expert`. Route all implementation through `pr-code-reviewer`. If the platform also serves e-commerce checkout, consider whether an e-commerce architect would add value reviewing the checkout-to-rail boundary.
  ```

  **fintech-ledger-expert.md**
  old_string: `- **API contract** — idempotency, validation, error behavior`
  new_string:
  ```
  - **API contract** — idempotency, validation, error behavior
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If posting logic affects KYC/AML triggers, coordinate with `fintech-compliance-expert`. If a new posting type requires an immutable audit record, invoke `fintech-audit-trail-expert`.
  ```

  **fintech-compliance-expert.md**
  old_string: `- **Regulator mapping** — which rule addresses which requirement`
  new_string:
  ```
  - **Regulator mapping** — which rule addresses which requirement
  - **Recommended next steps** — Return rule spec and workflow to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If vendor integration changes data boundaries, invoke `secure-auditor` for a data-boundary review. If compliance rules involve international tax obligations, consider whether a tax specialist would add value reviewing jurisdiction-specific requirements.
  ```

  **fintech-audit-trail-expert.md**
  old_string: `- **Export spec** — query, integrity proof, delivery format`
  new_string:
  ```
  - **Export spec** — query, integrity proof, delivery format
  - **Recommended next steps** — Return implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If storage topology changes, coordinate with `fintech-architect`.
  ```

  **fintech-risk-expert.md**
  old_string: `- **Monitoring** — drift metrics, alerts, response plan`
  new_string:
  ```
  - **Monitoring** — drift metrics, alerts, response plan
  - **Recommended next steps** — Return model spec and rollout plan to the orchestrator; `pr-code-reviewer` reviews code before proceeding. If the model requires new training data containing PII, invoke `fintech-compliance-expert` before data collection begins. If ML infrastructure for the risk model is needed, consider whether an AI architect or fine-tune specialist would add value reviewing the model pipeline.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/fintech-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/fintech-*.md
  git commit -m "feat(agents): add handoff language to fintech pack"
  ```

---

## Task 17: dataplat pack — 8 agents

**Files:**
- Modify: `.claude/agents/dataplat-architect.md`, `dataplat-etl-expert.md`, `dataplat-sql-expert.md`, `dataplat-quality-expert.md`, `dataplat-viz-expert.md`, `dataplat-privacy-expert.md`, `dataplat-feature-store-expert.md`, `dataplat-streaming-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/dataplat-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **dataplat-architect.md**
  old_string: `- **Risks / follow-ups** — what could force a re-architecture`
  new_string:
  ```
  - **Risks / follow-ups** — what could force a re-architecture
  - **Recommended next steps** — Engage specialists per domain: pipelines → `dataplat-etl-expert`; query optimization → `dataplat-sql-expert`; quality contracts → `dataplat-quality-expert`; dashboards/metrics → `dataplat-viz-expert`; PII/masking → `dataplat-privacy-expert`; feature store → `dataplat-feature-store-expert`; streaming → `dataplat-streaming-expert`. Route all implementation through `pr-code-reviewer`. If the platform serves AI/ML model training, consider whether an AI architecture specialist would add value reviewing the data-to-model boundary.
  ```

  **dataplat-etl-expert.md**
  old_string: `- **Tests** — dbt tests / expectations required before merge`
  new_string:
  ```
  - **Tests** — dbt tests / expectations required before merge
  - **Recommended next steps** — Return pipeline design to the orchestrator; `pr-code-reviewer` reviews code before merging. If quality contracts need updating to reflect the new pipeline, invoke `dataplat-quality-expert`. If the pipeline feeds an AI/ML feature store, consider whether a feature store specialist would add value reviewing point-in-time correctness.
  ```

  **dataplat-sql-expert.md**
  old_string: `- **Index / cluster recommendations** — if platform supports them`
  new_string:
  ```
  - **Index / cluster recommendations** — if platform supports them
  - **Recommended next steps** — Return the rewritten query to the orchestrator; `pr-code-reviewer` reviews before merging. If a dialect translation was performed, verify semantic equivalence with the original before closing.
  ```

  **dataplat-quality-expert.md**
  old_string: `- **Incident runbook** — who, what, rollback, comms`
  new_string:
  ```
  - **Incident runbook** — who, what, rollback, comms
  - **Recommended next steps** — Return the contract spec and test suite to the orchestrator; `pr-code-reviewer` reviews test code before merging. If lineage gaps surface upstream, invoke `dataplat-etl-expert`.
  ```

  **dataplat-viz-expert.md**
  old_string: `- **Governance notes** — certification tier, review cadence`
  new_string:
  ```
  - **Governance notes** — certification tier, review cadence
  - **Recommended next steps** — Return the metric spec and dashboard design to the orchestrator; `pr-code-reviewer` reviews semantic layer code before merging. If metric definitions change, surface the change for product review before merging to prevent dashboard drift.
  ```

  **dataplat-privacy-expert.md**
  old_string: `- **Retention rules** — class → TTL → enforcement job`
  new_string:
  ```
  - **Retention rules** — class → TTL → enforcement job
  - **Recommended next steps** — Return masking policy and deletion plan to the orchestrator; `pr-code-reviewer` reviews code before merging. If app-layer consent handling is also involved, coordinate with `common-privacy-expert`.
  ```

  **dataplat-feature-store-expert.md**
  old_string: `- **Parity test** — sampling, comparison, alert`
  new_string:
  ```
  - **Parity test** — sampling, comparison, alert
  - **Recommended next steps** — Return feature registry and serving spec to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If training-serving skew is found, invoke `ai-finetune-expert` or `ai-architect` to investigate the model pipeline root cause.
  ```

  **dataplat-streaming-expert.md**
  old_string: `- **Delivery semantics** — exactly-once / at-least-once choice + enforcement`
  new_string:
  ```
  - **Delivery semantics** — exactly-once / at-least-once choice + enforcement
  - **Recommended next steps** — Return topology and job spec to the orchestrator; `pr-code-reviewer` reviews job code before merging. If schema evolution breaks downstream consumers, invoke `dataplat-quality-expert`. If the stream feeds an embedded device fleet, consider whether an embedded connectivity specialist would add value reviewing the device-to-cloud protocol design.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/dataplat-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/dataplat-*.md
  git commit -m "feat(agents): add handoff language to dataplat pack"
  ```

---

## Task 18: desktop pack — 6 agents

**Files:**
- Modify: `.claude/agents/desktop-architect.md`, `desktop-ipc-expert.md`, `desktop-autoupdate-expert.md`, `desktop-code-signing-expert.md`, `desktop-installer-expert.md`, `desktop-shell-integration-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/desktop-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **desktop-architect.md**
  old_string: `- **Decisions** — ADR-ready bullets`
  new_string:
  ```
  - **Decisions** — ADR-ready bullets
  - **Recommended next steps** — Engage specialists per domain: IPC → `desktop-ipc-expert`; autoupdate → `desktop-autoupdate-expert`; signing/notarization → `desktop-code-signing-expert`; installer → `desktop-installer-expert`; shell integration → `desktop-shell-integration-expert`. Route all implementation through `pr-code-reviewer`. If the app communicates with a companion browser extension, consider whether an extension architecture specialist would add value reviewing the IPC boundary.
  ```

  **desktop-ipc-expert.md**
  old_string: `- **Bench notes** — measured latency / throughput where relevant`
  new_string:
  ```
  - **Bench notes** — measured latency / throughput where relevant
  - **Recommended next steps** — Return channel catalog and implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If the security boundary of a channel changes, invoke `secure-auditor`. If IPC communicates with a browser extension content script, consider whether an extension security specialist would add value reviewing the message-validation boundary.
  ```

  **desktop-autoupdate-expert.md**
  old_string: `- **Rollback plan** — trigger, mechanism, comms`
  new_string:
  ```
  - **Rollback plan** — trigger, mechanism, comms
  - **Recommended next steps** — Return update flow and channel config to the orchestrator; `pr-code-reviewer` reviews before proceeding. If signing or certificate changes accompany the update mechanism, invoke `desktop-code-signing-expert`.
  ```

  **desktop-code-signing-expert.md**
  old_string: `- **Rotation runbook** — when, who, steps, rollback`
  new_string:
  ```
  - **Rotation runbook** — when, who, steps, rollback
  - **Recommended next steps** — Return signing matrix and CI wiring to the orchestrator; `pr-code-reviewer` reviews CI config before merging. If supply-chain risk surfaces during the audit, invoke `secure-auditor`.
  ```

  **desktop-installer-expert.md**
  old_string: `- **Enterprise doc** — SCCM / Intune / JAMF deployment snippets, transform files, MDM profile samples`
  new_string:
  ```
  - **Enterprise doc** — SCCM / Intune / JAMF deployment snippets, transform files, MDM profile samples
  - **Recommended next steps** — Return installer spec to the orchestrator; `pr-code-reviewer` reviews scripts before merging. If shell integration registrations are being added (file types, protocol handlers), invoke `desktop-shell-integration-expert`.
  ```

  **desktop-shell-integration-expert.md**
  old_string: `- **OS-tool verification commands** — exact CLI invocations that confirm registration worked`
  new_string:
  ```
  - **OS-tool verification commands** — exact CLI invocations that confirm registration worked
  - **Recommended next steps** — Return registration matrix and verification commands to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If registration triggers OS security prompts or entitlement changes, invoke `secure-auditor`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/desktop-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/desktop-*.md
  git commit -m "feat(agents): add handoff language to desktop pack"
  ```

---

## Task 19: ext pack — 5 agents

**Files:**
- Modify: `.claude/agents/ext-architect.md`, `ext-permissions-expert.md`, `ext-security-expert.md`, `ext-ux-expert.md`, `ext-native-messaging-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/ext-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **ext-architect.md**
  old_string: `- **Store plan** — per-store submission notes and expected reviews`
  new_string:
  ```
  - **Store plan** — per-store submission notes and expected reviews
  - **Recommended next steps** — Engage specialists per domain: permission strategy → `ext-permissions-expert`; threat model and CSP → `ext-security-expert`; popup/onboarding UX → `ext-ux-expert`; native host bridge → `ext-native-messaging-expert`. Route all implementation through `pr-code-reviewer`. If the extension integrates with a companion desktop app, consider whether a desktop architecture specialist would add value reviewing the IPC boundary.
  ```

  **ext-permissions-expert.md**
  old_string: `- **Reviewer notes** — per permission, one paragraph`
  new_string:
  ```
  - **Reviewer notes** — per permission, one paragraph
  - **Recommended next steps** — Return permission list and request flow to the orchestrator; `pr-code-reviewer` reviews before proceeding. If new host permissions broaden the extension's reach, invoke `ext-security-expert` to review the expanded scope.
  ```

  **ext-security-expert.md**
  old_string: `- **CSP policy** — directives and rationale`
  new_string:
  ```
  - **CSP policy** — directives and rationale
  - **Recommended next steps** — Return threat model and validation contracts to the orchestrator; `pr-code-reviewer` reviews before proceeding. If dependency auditing reveals supply-chain risk, invoke `secure-auditor`.
  ```

  **ext-ux-expert.md**
  old_string: `- **In-page UI rules** — isolation, theming, dismissal`
  new_string:
  ```
  - **In-page UI rules** — isolation, theming, dismissal
  - **Recommended next steps** — Return UX spec to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If in-page UI has accessibility issues, invoke `common-a11y-expert`.
  ```

  **ext-native-messaging-expert.md**
  old_string: `- **Test matrix** — malformed-length, oversized-payload, unknown-command, spoofed-origin, version-skew cases`
  new_string:
  ```
  - **Test matrix** — malformed-length, oversized-payload, unknown-command, spoofed-origin, version-skew cases
  - **Recommended next steps** — Return message schema and host manifest to the orchestrator; `pr-code-reviewer` reviews before proceeding. If the native host requires installer packaging or code signing, invoke `desktop-installer-expert` and `desktop-code-signing-expert`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/ext-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/ext-*.md
  git commit -m "feat(agents): add handoff language to ext pack"
  ```

---

## Task 20: embed pack — 7 agents

**Files:**
- Modify: `.claude/agents/embed-architect.md`, `embed-driver-expert.md`, `embed-rtos-expert.md`, `embed-ota-expert.md`, `embed-power-expert.md`, `embed-connectivity-expert.md`, `embed-manufacturing-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/embed-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **embed-architect.md**
  old_string: `- **Fleet update topology** — trigger, staging, rollback, telemetry`
  new_string:
  ```
  - **Fleet update topology** — trigger, staging, rollback, telemetry
  - **Recommended next steps** — Engage specialists per domain: drivers → `embed-driver-expert`; RTOS task design → `embed-rtos-expert`; OTA mechanics → `embed-ota-expert`; power budget → `embed-power-expert`; connectivity → `embed-connectivity-expert`; factory/manufacturing → `embed-manufacturing-expert`. Route all implementation through `pr-code-reviewer`. If the device streams telemetry to a cloud backend, consider whether a data platform streaming specialist would add value reviewing the ingestion topology.
  ```

  **embed-driver-expert.md**
  old_string: `- **Error handling** — timeouts, retries, escalation`
  new_string:
  ```
  - **Error handling** — timeouts, retries, escalation
  - **Recommended next steps** — Return driver implementation to the orchestrator; `pr-code-reviewer` reviews before proceeding. If DMA or interrupt priority changes affect RTOS task scheduling, invoke `embed-rtos-expert`.
  ```

  **embed-rtos-expert.md**
  old_string: `- **Schedulability notes** — WCET, utilization, headroom`
  new_string:
  ```
  - **Schedulability notes** — WCET, utilization, headroom
  - **Recommended next steps** — Return task table and sync primitives to the orchestrator; `pr-code-reviewer` reviews before proceeding. If task timing changes affect the power budget, coordinate with `embed-power-expert`.
  ```

  **embed-ota-expert.md**
  old_string: `- **Rollout plan** — stages, gates, comms`
  new_string:
  ```
  - **Rollout plan** — stages, gates, comms
  - **Recommended next steps** — Return update protocol and rollback mechanism to the orchestrator; `pr-code-reviewer` reviews before proceeding. If OTA transport uses a radio peripheral, coordinate with `embed-connectivity-expert`. If the fleet OTA feeds a cloud telemetry pipeline, consider whether a data platform streaming specialist would add value reviewing the ingestion design.
  ```

  **embed-power-expert.md**
  old_string: `- **Regression test plan** — measurement harness + thresholds`
  new_string:
  ```
  - **Regression test plan** — measurement harness + thresholds
  - **Recommended next steps** — Return sleep state table and battery-life estimate to the orchestrator; `pr-code-reviewer` reviews before proceeding. If sleep modes affect connectivity duty cycle, coordinate with `embed-connectivity-expert`.
  ```

  **embed-connectivity-expert.md**
  old_string: `- **Certification roadmap** — required certs, lab choices, estimated timeline and cost, sample-unit requirements`
  new_string:
  ```
  - **Certification roadmap** — required certs, lab choices, estimated timeline and cost, sample-unit requirements
  - **Recommended next steps** — Return radio selection and connection state machine to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If cloud-side ingestion needs scaling, coordinate with `infra-architect` or `dataplat-streaming-expert`.
  ```

  **embed-manufacturing-expert.md**
  old_string: `- **CM handoff packet** — test specs, fixture BOM, acceptance criteria, ECN protocol`
  new_string:
  ```
  - **CM handoff packet** — test specs, fixture BOM, acceptance criteria, ECN protocol
  - **Recommended next steps** — Return DFT spec and test flow to the orchestrator; `pr-code-reviewer` reviews any automation code before merging. If key injection involves cryptographic design decisions, invoke `secure-auditor`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/embed-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/embed-*.md
  git commit -m "feat(agents): add handoff language to embed pack"
  ```

---

## Task 21: media pack — 7 agents

**Files:**
- Modify: `.claude/agents/media-architect.md`, `media-transcode-expert.md`, `media-drm-cdn-expert.md`, `media-cms-workflow-expert.md`, `media-player-expert.md`, `media-ad-insertion-expert.md`, `media-live-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/media-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **media-architect.md**
  old_string: `- **CDN plan** — topology, cost model, failover`
  new_string:
  ```
  - **CDN plan** — topology, cost model, failover
  - **Recommended next steps** — Engage specialists per domain: transcode pipeline → `media-transcode-expert`; DRM/CDN delivery → `media-drm-cdn-expert`; CMS/editorial → `media-cms-workflow-expert`; client playback → `media-player-expert`; ad insertion → `media-ad-insertion-expert`; live streaming → `media-live-expert`. Route all implementation through `pr-code-reviewer`. If the platform serves regulated content (children's programming, financial education), consider whether a compliance specialist would add value reviewing licensing and consent posture.
  ```

  **media-transcode-expert.md**
  old_string: `- **QC checklist** — automated checks per asset`
  new_string:
  ```
  - **QC checklist** — automated checks per asset
  - **Recommended next steps** — Return encode profile and ladder to the orchestrator; `pr-code-reviewer` reviews pipeline code before merging. If DRM packaging is involved in the same workflow, coordinate with `media-drm-cdn-expert`. If the encode workload is ML-driven (content-aware per-title encoding), consider whether an AI inference performance specialist would add value reviewing the compute cost.
  ```

  **media-drm-cdn-expert.md**
  old_string: `- **QoE dashboard** — metrics, targets, alerts`
  new_string:
  ```
  - **QoE dashboard** — metrics, targets, alerts
  - **Recommended next steps** — Return DRM flow and CDN plan to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If playback quality issues surface after the change, invoke `media-player-expert`.
  ```

  **media-cms-workflow-expert.md**
  old_string: `- **Workflow UX** — editor views, bulk ops, permissions`
  new_string:
  ```
  - **Workflow UX** — editor views, bulk ops, permissions
  - **Recommended next steps** — Return asset state machine and metadata schema to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If editorial workflow touches rights windows with regulatory implications, invoke `fintech-compliance-expert` (if fintech pack is active). If the CMS serves live content scheduling, consider whether a live streaming specialist would add value reviewing the scheduling and failover design.
  ```

  **media-player-expert.md**
  old_string: `- **Regression harness** — reference devices, golden-path scenarios, pass/fail thresholds`
  new_string:
  ```
  - **Regression harness** — reference devices, golden-path scenarios, pass/fail thresholds
  - **Recommended next steps** — Return player config and QoE schema to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If accessibility requirements surface (captions, audio description), invoke `common-a11y-expert`.
  ```

  **media-ad-insertion-expert.md**
  old_string: `- **Instrumentation** — ad-fill rate, ad-start rate, completion rate, revenue per viewer hour, per-device QoE`
  new_string:
  ```
  - **Instrumentation** — ad-fill rate, ad-start rate, completion rate, revenue per viewer hour, per-device QoE
  - **Recommended next steps** — Return ad pipeline architecture to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If consent handling involves TCF/GPP signal propagation, invoke `common-privacy-expert`.
  ```

  **media-live-expert.md**
  old_string: `- **DVR / clip-out spec** — window size, origin storage policy, clip-out pipeline`
  new_string:
  ```
  - **DVR / clip-out spec** — window size, origin storage policy, clip-out pipeline
  - **Recommended next steps** — Return pipeline architecture and failover runbook to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If cloud capacity needs scaling for a tentpole event, coordinate with `infra-architect` and `infra-sre-expert`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/media-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/media-*.md
  git commit -m "feat(agents): add handoff language to media pack"
  ```

---

## Task 22: orch pack — 5 agents

**Files:**
- Modify: `.claude/agents/orch-architect.md`, `orch-tool-design-expert.md`, `orch-prompt-engineer.md`, `orch-eval-expert.md`, `orch-sandbox-safety-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/orch-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **orch-architect.md**
  old_string: `- **Decisions** — ADR-ready bullets`
  new_string:
  ```
  - **Decisions** — ADR-ready bullets
  - **Recommended next steps** — Engage specialists per domain: tool specs → `orch-tool-design-expert`; system prompts → `orch-prompt-engineer`; eval harness → `orch-eval-expert`; sandbox and safety → `orch-sandbox-safety-expert`. Route all implementation through `pr-code-reviewer`. If the agent handles regulated data or makes decisions with compliance implications, consider whether a fintech or privacy specialist would add value reviewing the authority model.
  ```

  **orch-tool-design-expert.md**
  old_string: `- **Overlap notes** — sibling tools and when to pick which`
  new_string:
  ```
  - **Overlap notes** — sibling tools and when to pick which
  - **Recommended next steps** — Return tool spec to the orchestrator; `pr-code-reviewer` reviews before proceeding. If tool execution is sandboxed, coordinate with `orch-sandbox-safety-expert` to verify the authority model.
  ```

  **orch-prompt-engineer.md**
  old_string: `- **Regression cases** — test prompts + expected behavior`
  new_string:
  ```
  - **Regression cases** — test prompts + expected behavior
  - **Recommended next steps** — Return the system prompt and few-shot set to the orchestrator; `pr-code-reviewer` reviews integration code before proceeding. If eval regression surfaces after the prompt change, invoke `orch-eval-expert`. If adversarial injection attempts succeed, invoke `orch-sandbox-safety-expert` or `ai-safety-expert`.
  ```

  **orch-eval-expert.md**
  old_string: `- **CI wiring** — when it runs, what it blocks`
  new_string:
  ```
  - **CI wiring** — when it runs, what it blocks
  - **Recommended next steps** — Return eval set and CI wiring to the orchestrator; `pr-code-reviewer` reviews before merging. If a human-rater protocol is required, surface the protocol for product review before implementing.
  ```

  **orch-sandbox-safety-expert.md**
  old_string: `- **Incident response** — what gets revoked when things go wrong`
  new_string:
  ```
  - **Incident response** — what gets revoked when things go wrong
  - **Recommended next steps** — Return sandbox spec and authority model to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If application-security concerns surface (beyond agent sandboxing), invoke `secure-auditor`.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/orch-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/orch-*.md
  git commit -m "feat(agents): add handoff language to orch pack"
  ```

---

## Task 23: common pack — 5 agents

**Files:**
- Modify: `.claude/agents/common-i18n-expert.md`, `common-a11y-expert.md`, `common-notifications-expert.md`, `common-privacy-expert.md`, `common-product-analytics-expert.md`

- [ ] **Step 1: Verify fields are missing**

  ```bash
  grep -rn "Recommended next steps" .claude/agents/common-*.md
  ```
  Expected: no matches.

- [ ] **Step 2: Apply edits per file**

  **common-i18n-expert.md**
  old_string: `- **Launch-locale checklist** — font coverage, legal content review, QA plan, soft-launch plan`
  new_string:
  ```
  - **Launch-locale checklist** — font coverage, legal content review, QA plan, soft-launch plan
  - **Recommended next steps** — Return i18n architecture to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If RTL layout issues surface that affect keyboard navigation or focus order, invoke `common-a11y-expert`. If translations involve regulated content (legal, medical, financial), consider whether a domain compliance specialist would add value reviewing the jurisdiction-specific copy.
  ```

  **common-a11y-expert.md**
  old_string: `- **Remediation roadmap** — ordered by impact × effort, with milestones`
  new_string:
  ```
  - **Remediation roadmap** — ordered by impact × effort, with milestones
  - **Recommended next steps** — Return the audit report and remediation roadmap to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If platform-specific accessibility APIs need changes, invoke `mobile-platform-expert`.
  ```

  **common-notifications-expert.md**
  old_string: `- **Compliance matrix** — jurisdiction × channel × consent requirement × retention`
  new_string:
  ```
  - **Compliance matrix** — jurisdiction × channel × consent requirement × retention
  - **Recommended next steps** — Return channel matrix and sending pipeline to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If consent and opt-out mechanics are involved, coordinate with `common-privacy-expert`. If mobile push notification platform integration is needed, coordinate with `mobile-platform-expert`.
  ```

  **common-privacy-expert.md**
  old_string: `- **Sensitive data handling** — children, health, biometric, special-category handling rules`
  new_string:
  ```
  - **Sensitive data handling** — children, health, biometric, special-category handling rules
  - **Recommended next steps** — Return consent architecture and DSAR workflow to the orchestrator; `pr-code-reviewer` reviews implementation before proceeding. If data-warehouse-layer PII masking is also needed, invoke `dataplat-privacy-expert`. If KYC/AML obligations are involved, invoke `fintech-compliance-expert`.
  ```

  **common-product-analytics-expert.md**
  old_string: `- **Self-serve docs** — naming index, saved queries, dashboard templates, anti-patterns`
  new_string:
  ```
  - **Self-serve docs** — naming index, saved queries, dashboard templates, anti-patterns
  - **Recommended next steps** — Return event taxonomy and instrumentation guide to the orchestrator; `pr-code-reviewer` reviews instrumentation code before merging. If consent or privacy governance for the analytics stream is needed, invoke `common-privacy-expert`. If analytics will feed ML model features, consider whether a data platform specialist would add value reviewing the feature pipeline design.
  ```

- [ ] **Step 3: Verify**

  ```bash
  grep -c "Recommended next steps" .claude/agents/common-*.md
  ```
  Expected: each file shows count = 1.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/agents/common-*.md
  git commit -m "feat(agents): add handoff language to common pack"
  ```

---

## Final verification

- [ ] **Confirm all agents have the field**

  ```bash
  grep -rL "Recommended next steps" .claude/agents/*.md
  ```
  Expected: empty output (no files missing the field).

- [ ] **Confirm CLAUDE.md was updated**

  ```bash
  grep -n "session restart" "C:/Users/grace/.claude/CLAUDE.md"
  ```
  Expected: one match.
