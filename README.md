# Claude Code Dev Studio

A universal, stack-agnostic Claude Code playbook: **19 always-on agents** (14 domain agents + 5 core generalists) plus a library of **~90 skills** the agents compose on demand. Aligned with NIST SSDF (SP 800-218) and phase-gated Agile delivery. See `DECISIONS.md` ADR-0007 for the architecture.

## What's here

| File | Purpose |
|---|---|
| `CLAUDE.md` | The playbook — phases, the agent/skill model, prefix registry |
| `.claude/agents/` | The 19 always-on agent definitions (14 domain + 5 core) |
| `skills/` | The skill library (`<name>/SKILL.md`) — domain + cross-cutting |
| `catalog.json` | Index of agents and skills (`name, pack, kind, scope, model, description`) for JIT selection |
| `bin/ccds.{ps1,sh}` | Dispatcher — `sync`, `verify`, `update`, `uninstall`, `version` |
| `Install-Playbook.ps1` | Windows installer (stage/promote, SHA256-verified, PATH-aware, CLAUDE.md block) |
| `install-playbook.sh` | Linux/macOS installer (same behavior, shell-rc PATH block) |
| `Sync-AgentPacks.{ps1,sh}` | Stage a pack's domain skills into a project (invoked by `ccds sync`) |
| `Verify-Agents.ps1` / `verify-agents.sh` | Validate agents and skills against ADR-0001 invariants |
| `build-release.ps1` | Build reproducible release ZIP + sidecar SHA256 |
| `scripts/jit-claude.md` | Canonical source for the ccds pointer block injected into `~/.claude/CLAUDE.md` |
| `.github/workflows/release.yml` | Tag-driven release build + GitHub Release publication |
| `DECISIONS.md` | Architecture decision records (ADR-0001 … ADR-0009) |
| `CHANGELOG.md` | Session-by-session history |
| `CONTRIBUTING.md` | Contribution terms |
| `LICENSE` | PolyForm Noncommercial 1.0.0 |

## How it works

### Installed layout

```
~/.claude/
  agents/          ← 19 always-on agents (14 domain + 5 core; always loaded)
  skills/          ← cross-cutting skills (always available)
  playbook/        ← managed by installer
    bin/           ← ccds dispatcher (ccds.ps1 / ccds.sh / ccds symlink)
    scripts/       ← Sync-AgentPacks, Verify-Agents, jit-claude.md
    agents/        ← source copy of the 19 agents
    skills/        ← full skill library (domain skills copied to projects on demand)
    catalog.json   ← agent + skill index for JIT selection
    version.txt
    README.md
  CLAUDE.md        ← your global Claude instructions; installer injects the ccds pointer block
```

### Always-on agents, JIT skills (ADR-0007)

The 19 agents are cheap enough (~850 tokens of trimmed descriptions) to load every session, so there is no agent-activation step. Each **domain agent** composes its `<pack>-*` **skills** via the Skill tool — and because subagents can invoke skills but cannot spawn other subagents, one domain agent handles a multi-specialty task in a single coherent context.

Skills are the just-in-time layer. The `sync-agents` skill (or `ccds sync`):

1. Reads `~/.claude/playbook/catalog.json` — agents + skills, lightweight metadata only
2. Assesses the project (stack signals in files and conversation)
3. Selects the matching packs' domain skills
4. Copies them to `./.claude/skills/` in the project
5. Summarises what was staged; new skills are discovered on the next session refresh

Cross-cutting skills (`playbook-conventions`, `api-design`, `ux-design`, `security-checklist`, `code-review-checklist`, `common-*`) install once to `~/.claude/skills/` and are always available.

## Install as native Claude Code plugins (recommended)

The repo doubles as a **Claude Code plugin marketplace**: one plugin per pack
(`ccds-saas`, `ccds-ai`, …) plus `ccds-core` (the 5 core agents + cross-cutting
skills). Claude Code handles versioning, updates, and enable/disable — no
installer, no PATH, no restart dance.

```
/plugin marketplace add ggrace519/claude-code-dev-studio
/plugin install ccds-core@ccds
/plugin install ccds-saas@ccds        # one per archetype you work in
```

Update later with `/plugin marketplace update ccds`. The marketplace tree
(`.claude-plugin/marketplace.json` + `plugins/`) is generated from the library
source by `scripts/build-marketplace.py` and gated for freshness in CI.

The ZIP installer below remains fully supported — it additionally provides the
`ccds` CLI, the global `~/.claude/playbook/` library, and per-project skill
staging via `ccds sync`.

## Install

The installer downloads a GitHub Release ZIP, verifies its SHA256 against the sidecar, stages to `<prefix>.new`, snapshots the existing install to `<prefix>.previous`, and atomically promotes. It copies the 19 agents to `~/.claude/agents/`, the cross-cutting skills to `~/.claude/skills/`, injects the ccds block into `~/.claude/CLAUDE.md`, and updates `PATH` so `ccds` resolves in new shells.

**Windows (PowerShell 5.1 or 7+):**

```powershell
iwr -UseBasicParsing https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/Install-Playbook.ps1 | iex
```

Default prefix: `%USERPROFILE%\.claude\playbook`. Override with `-Prefix`, pin a version with `-Version v0.5.0`, include prereleases with `-IncludePrerelease`, skip PATH with `-NoPath`.

**Linux / macOS (bash):**

```bash
curl -fsSL https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/install-playbook.sh | bash
```

Default prefix: `$HOME/.claude/playbook`. Override with `--prefix`, pin a version with `--version v0.5.0`, include prereleases with `--include-prerelease`, skip PATH with `--no-path`.

Both installers accept `--dry-run` / `-DryRun`, `--local-zip <path>` / `-LocalZip <path>` (install from a locally built ZIP), and `--token` / `-Token` (GitHub token for rate-limited or private-repo environments).

**Linux native packages (`.deb` / `.rpm`):**

Each release also ships a `.deb` (Debian/Ubuntu) and `.rpm` (RHEL/Fedora) attached to the GitHub Release.

```bash
sudo apt install ./ccds_<version>_all.deb     # Debian/Ubuntu
sudo dnf install ./ccds-<version>-1.noarch.rpm # RHEL/Fedora
```

The package installs the shared library to `/usr/share/ccds` and the `ccds` launcher to `/usr/bin/ccds`. Because the agents/skills/`CLAUDE.md` block are **per-user** (they live under `~/.claude/`), per-user setup runs for the installing user automatically when the package can identify them (`sudo`, polkit/GUI installers, or a login terminal).

If you install from a bare root shell or a headless/CI/Docker context, the package cannot tell which user to set up — run setup yourself once per user:

```bash
ccds setup          # copies the 19 agents + cross-cutting skills, injects the CLAUDE.md block
```

Setup also runs automatically the first time that user runs `ccds sync <packs>` or `ccds verify`. Updates and removal go through the system package manager (`apt`/`dnf`); `ccds update` and `ccds uninstall` are no-ops for package installs and print the right command.

## Update / rollback / uninstall

Once installed, the dispatcher delegates these to a fresh copy of the installer fetched from `main`, so bug fixes to the installer propagate automatically.

```bash
ccds update                          # update to latest stable release
ccds update v0.5.1                   # pin a specific tag
ccds update --include-prerelease     # resolve 'latest' to latest prerelease
ccds update --rollback               # restore previous install from <prefix>.previous
ccds uninstall                       # remove install directory and PATH entry
ccds version                         # print installed version
```

## Quick start

Stage the SaaS domain skills into a project (the `saas-architect` agent is already loaded):

```bash
cd /path/to/my-saas-app
ccds sync saas --write-adr
```

Stage multiple packs (e.g., an LLM-enabled SaaS product):

```bash
ccds sync saas,ai
```

Preview without writing:

```bash
ccds sync saas --dry-run
```

Re-run with a narrower list to drop skills, or clear all staged skills — the manifest tracks what the dispatcher owns:

```bash
ccds sync saas    # drops 'ai' skills if previously staged
ccds sync --clean # removes all staged skills
```

Validate the agents and a project's skills:

```bash
ccds verify
```

Run `ccds help` for the full flag reference (`--clean`, `--target <path>`, `--write-adr`).

## Script invocation (without installing)

The dispatcher wraps `Sync-AgentPacks.{ps1,sh}` and `Verify-Agents.{ps1,sh}`. You can invoke those scripts directly from a clone:

```powershell
.\Sync-AgentPacks.ps1 -TargetProject D:\code\my-app -Packs saas -WriteAdr
```

```bash
./Sync-AgentPacks.sh --target-project ~/code/my-app --packs saas --write-adr
```

By default both scripts look for the skill library at `~/.claude/playbook/skills/`. Override with `-LibraryRoot` (PS) or `--library-root` / `$CCDS_LIBRARY_ROOT` (bash).

See `Get-Help .\Sync-AgentPacks.ps1 -Full` or `./Sync-AgentPacks.sh --help`.

## Available packs

`game`, `saas`, `mobile`, `ai`, `dataplat`, `ecom`, `fintech`, `devtool`, `desktop`, `ext`, `embed`, `media`, `orch`, `infra` (each is one domain agent + its skills), plus `common` (cross-cutting skills only — no domain agent).

Pack skills and trigger conditions are the source-of-truth in `catalog.json`; the model is documented in `CLAUDE.md`.

## Extras

### Shell completion for the `claude` CLI

Optional, opt-in tab-completion for the Claude Code CLI itself — independent of the playbook. See [`claude_auto_completion/README.md`](./claude_auto_completion/README.md) for per-OS install instructions.

```bash
# Linux / macOS / WSL (per-user)
./claude_auto_completion/Linux/claude-autocomplete.sh
```

```powershell
# Windows (PowerShell 5.1 / 7+)
. .\claude_auto_completion\Windows\install-claude-completion.ps1
```

## Requirements

- Claude Code CLI (v2.1.113+ recommended — flat agent discovery)
- PowerShell 5.1 or 7+ on Windows
- bash 4+, `curl`, `unzip`, `sha256sum` / `shasum` on Linux/macOS

## Conventions

- Agent and skill files are **BOM-less UTF-8**. PS 5.1's `Set-Content -Encoding UTF8` writes a BOM that Claude Code's YAML frontmatter parser silently rejects. Writes use `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`. See ADR-0001.
- Agents live in a **flat** `.claude/agents/` directory; skills are `skills/<name>/SKILL.md` (one dir per skill). Claude Code does not recurse `.claude/agents/`. See ADR-0001 / ADR-0007.
- Release ZIPs are named `ccds-<tag>.zip` with a matching `ccds-<tag>.zip.sha256` sidecar. Installers verify SHA256 before extracting.
- The `~/.claude/CLAUDE.md` ccds block is delimited by `# >>> ccds >>>` / `# <<< ccds <<<` markers. The installer is idempotent — re-running updates the block in place. See ADR-0006 / ADR-0007.

## License

**PolyForm Noncommercial 1.0.0** — see [`LICENSE`](./LICENSE).

- **Free for noncommercial use**: personal projects, research, education, public-interest organizations, hobby work, and nonprofits.
- **Commercial use requires a separate license.** Contact contact@519lab.com.

Copyright 2026 Onward Investment LLC. All rights reserved.
