# >>> ccds >>>
# Managed by Claude Code Dev Studio. Edit via: ccds sync
# Remove via: ccds uninstall

## Playbook JIT Agent Loading

Claude Code Dev Studio is installed at `~/.claude/playbook/`. It contains 98 specialist
pack agents and a `catalog.json` manifest. The 7 generalist agents are always loaded
from `~/.claude/agents/`. Pack agents are loaded per-project on demand.

### When to run JIT activation

Run the full activation flow (Steps 1–5 below) in any of these cases:
- User runs `/init` in a project
- User describes a new task or project type at session start
- User says "sync agents", "load agents", or runs `/sync-agents`
- You detect that relevant pack agents are absent from `.claude/agents/` for the work at hand

### Step 1 — Read the catalog

Read `~/.claude/playbook/catalog.json`. It is a JSON array; each entry has:
- `name` — agent filename without `.md` (e.g., `saas-billing-expert`)
- `pack` — archetype prefix (`saas`, `ai`, `infra`, `game`, etc.) or `core` for generalists
- `model` — Claude model string
- `description` — what the agent does and its auto-invocation triggers

If the file does not exist, stop and tell the user:
> "Claude Code Dev Studio is not installed. Run the installer first:
> **macOS/Linux:** `curl -fsSL https://raw.githubusercontent.com/519lab/claude-code-dev-studio/main/install-playbook.sh | bash`
> **Windows:** `iwr https://raw.githubusercontent.com/519lab/claude-code-dev-studio/main/Install-Playbook.ps1 | iex`"

### Step 2 — Assess the project

Gather context to determine which packs are relevant:
1. Check if the project has a README, `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`,
   `docker-compose.yml`, or similar files that reveal the stack
2. Read any existing `.claude/agents/` files to see what is already activated
3. Use the user's stated task description if no codebase exists yet

Match against the `pack` field in the catalog. A project may match multiple packs
(e.g., `saas` + `ai` for an LLM-enabled SaaS). The `core` agents are always present —
do not copy or re-evaluate them.

Common pack triggers:
| Signal in project | Packs to consider |
|---|---|
| Stripe / billing / subscriptions | `saas`, `saas-billing-expert` |
| LLM calls, vector DB, RAG, Ollama, vLLM | `ai` |
| Kubernetes, Terraform, Prometheus, SLOs | `infra` |
| React Native, Swift, Kotlin, Expo | `mobile` |
| Unity, Unreal, Godot, game loop | `game` |
| Kafka, dbt, Airflow, data warehouse | `dataplat` |
| Stripe + storefronts, cart, inventory | `ecom` |
| KYC, ledger, compliance, fintech | `fintech` |
| CLI tools, npm packages, Go libraries | `devtool` |
| Electron, Tauri, WPF | `desktop` |
| Chrome extension, manifest.json | `ext` |
| RTOS, firmware, embedded C | `embed` |
| HLS, ffmpeg, DRM, CDN | `media` |
| Agent orchestration, tool design, evals | `orch` |
| i18n, a11y, notifications across any stack | `common` |

### Step 3 — Select specific agents

From the matching packs, select the agents whose `description` field aligns with the
actual work ahead. Prefer targeted selection over pulling an entire pack:

- For a new project in architecture phase: include the pack's `*-architect` agent
- For a focused bug fix: include only the domain expert(s) directly relevant
- Reasonable range: 3–10 pack agents per project; avoid activating all 98

### Step 4 — Copy selected agents

For each selected agent:
- **Source:** `~/.claude/playbook/agents/<name>.md`
- **Destination:** `./.claude/agents/<name>.md`
- Create `./.claude/agents/` if it does not exist
- Skip (do not overwrite) any agent already present in the destination
  unless the source file has changed (compare content)

Use a single bash command to perform the copies:
```bash
mkdir -p ./.claude/agents
cp ~/.claude/playbook/agents/<name>.md ./.claude/agents/<name>.md
# repeat per selected agent
```

### Step 5 — Present activation summary and request restart

Output a summary in this format:

```
## Playbook agents activated

**Packs:** saas, ai

| Agent | Purpose |
|---|---|
| saas-architect | Tenancy, billing topology, SaaS scale decisions |
| saas-auth-sso-expert | Auth flows, SSO/SAML/SCIM, RBAC/ABAC |
| ai-architect | Model selection, serving topology, cost envelope |
| ai-rag-expert | Retrieval pipelines, chunking, embeddings, reranking |
| ai-inference-perf-expert | vLLM/TGI/Ollama tuning, batching, KV cache |

**Already present (skipped):** plan-architect, api-expert (core)

> ⚠️ Claude Code loads agents at session start. Please **restart this session** to
> activate the copied agents. After restart they will be auto-invoked per their triggers.
```

### Removing pack agents from a project

When the user runs `ccds sync --clean` or asks to "remove pack agents":
- Delete all `./.claude/agents/` files whose `name` field in their YAML frontmatter
  matches a non-`core` entry in the catalog
- Do not touch the 7 core generalist agents
- Confirm what was removed
# <<< ccds <<<
