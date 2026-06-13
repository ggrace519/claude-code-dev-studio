---
name: sync-agents
description: Activate Claude Code Dev Studio domain skills for the current project. Use proactively when running /init, when the user describes a new task or project type, when the user says "sync agents" / "load skills", or when the relevant domain skills are absent from .claude/skills/ for the work at hand.
---

# Sync Agents — Domain Skill Activation

Claude Code Dev Studio is installed at `~/.claude/playbook/`. The **19 agents**
(14 domain agents + 5 core generalists) live permanently in `~/.claude/agents/` and are
always loaded — there is nothing to activate for them. The **domain skills** are the
just-in-time layer: each domain agent composes its `<pack>-*` skills via the Skill tool,
and those skills load only when present in the project. This flow copies the relevant
ones into `./.claude/skills/`.

Cross-cutting skills (`playbook-conventions`, `api-design`, `ux-design`,
`security-checklist`, `code-review-checklist`, and the `common-*` set) are installed once
in `~/.claude/skills/` and are always available — do not copy them per project.

## When to run

- User runs `/init` in a project
- User describes a new task or project type at session start
- User says "sync agents", "load skills", or runs `/sync-agents`
- A domain agent needs a `<pack>-*` skill that is not present in `.claude/skills/`

## Step 1 — Read the catalog

Read `~/.claude/playbook/catalog.json`. It indexes every agent and skill with `name`,
`pack`, `kind` (`agent` | `skill`), `scope` (`global` | `project`), `model`, and
`description`. If the file does not exist, stop and tell the user to install:
> **macOS/Linux:** `curl -fsSL https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/install-playbook.sh | bash`
> **Windows:** `iwr https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/Install-Playbook.ps1 | iex`

## Step 2 — Assess the project

Determine the relevant packs from the stack: read README, `package.json`,
`pyproject.toml`, `go.mod`, `Cargo.toml`, `docker-compose.yml`, manifests, etc., plus the
user's stated task. A project may match multiple packs (e.g. `saas` + `ai`).

| Signal in project | Pack |
|---|---|
| Stripe / billing / subscriptions / multi-tenant web app | `saas` |
| LLM calls, vector DB, RAG, Ollama, vLLM | `ai` |
| Kubernetes, Terraform, Prometheus, SLOs | `infra` |
| React Native, Swift, Kotlin, Expo | `mobile` |
| Unity, Unreal, Godot, game loop | `game` |
| Kafka, dbt, Airflow, data warehouse | `dataplat` |
| Storefronts, cart, inventory, checkout | `ecom` |
| KYC, ledger, compliance, money movement | `fintech` |
| CLI tools, npm packages, libraries | `devtool` |
| Electron, Tauri, WPF, native desktop | `desktop` |
| Chrome/Firefox extension, manifest.json | `ext` |
| RTOS, firmware, embedded C | `embed` |
| HLS, ffmpeg, DRM, CDN, streaming | `media` |
| Agent orchestration, tool design, evals | `orch` |

## Step 3 — Select the domain skills

For each matching pack, select the `scope: project` skills whose `description` aligns
with the work ahead (`kind: skill`, `pack: <pack>`). Prefer targeted selection — a
focused task needs 2–5 skills, not the whole pack. The domain agent for the pack is
already loaded; you are only staging the skills it will compose.

## Step 4 — Copy selected skills

```bash
mkdir -p ./.claude/skills
cp -r ~/.claude/playbook/skills/<name> ./.claude/skills/<name>
# repeat per selected skill; skip any already present unless the source changed
```

## Step 5 — Summary and refresh

Present what was staged:

```
## Domain skills activated

**Packs:** saas, ai

| Skill | Purpose |
|---|---|
| saas-billing | Stripe/webhooks/entitlements/metering |
| saas-auth-sso | Login, SSO/SAML/SCIM, RBAC/ABAC |
| ai-rag | Retrieval, chunking, embeddings, reranking |

Always-available: playbook-conventions, api-design, ux-design, common-* (global)

> Newly copied skills are discovered at session start. Restart or refresh the session
> so the domain agents can compose them.
```

## Removing project skills

When the user runs `ccds sync --clean` or asks to remove project skills: delete
`./.claude/skills/` entries that match `scope: project` catalog skills. Never touch the
19 global agents or the global cross-cutting skills.
