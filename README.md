# Claude Code Dev Studio

A universal, stack-agnostic Claude Code playbook with a library of 105 archetype-aware agents (7 generalists + 14 archetype packs + 1 cross-archetype pack). Aligned with NIST SSDF (SP 800-218) and phase-gated Agile delivery.

## What's here

| File | Purpose |
|---|---|
| `CLAUDE.md` | The playbook — phases, agent triggers, archetype pack registry |
| `.claude/agents/` | 105 agent definitions (canonical dev-repo library) |
| `catalog.json` | Agent index (name, pack, model, description) — used for JIT selection without loading all 105 files |
| `bin/ccds.{ps1,sh}` | Dispatcher — `sync`, `verify`, `update`, `uninstall`, `version` |
| `Install-Playbook.ps1` | Windows installer (stage/promote, SHA256-verified, PATH-aware, JIT block injection) |
| `install-playbook.sh` | Linux/macOS installer (same behavior, shell-rc PATH block) |
| `Sync-AgentPacks.{ps1,sh}` | Activate a subset of packs into a target project (invoked by `ccds sync`) |
| `Verify-Agents.ps1` / `verify-agents.sh` | Validate `.claude/agents/` against ADR-0001 invariants |
| `build-release.ps1` | Build reproducible release ZIP + sidecar SHA256 |
| `scripts/jit-claude.md` | Canonical source for the JIT protocol block injected into `~/.claude/CLAUDE.md` |
| `.github/workflows/release.yml` | Tag-driven release build + GitHub Release publication |
| `DECISIONS.md` | Architecture decision records (ADR-0001 … ADR-0006) |
| `CHANGELOG.md` | Session-by-session history |
| `CONTRIBUTING.md` | Contribution terms |
| `LICENSE` | PolyForm Noncommercial 1.0.0 |

## How it works

### Installed layout

```
~/.claude/
  agents/          ← 7 generalist agents (always loaded by Claude Code)
  playbook/        ← managed by installer
    bin/           ← ccds dispatcher (ccds.ps1 / ccds.sh / ccds symlink)
    scripts/       ← Sync-AgentPacks, Verify-Agents, jit-claude.md
    agents/        ← 98 pack agents (copied to projects on demand)
    catalog.json   ← agent index for JIT selection
    version.txt
    README.md
  CLAUDE.md        ← your global Claude instructions; installer appends JIT block
```

### JIT agent loading

The installer injects a protocol block into `~/.claude/CLAUDE.md`. At the start of each new Claude Code session the protocol:

1. Reads `~/.claude/playbook/catalog.json` — 105 entries, lightweight metadata only
2. Assesses the project (stack signals in files and conversation)
3. Selects agents from matching packs
4. Copies them to `./.claude/agents/` in the project
5. Summarises what was activated and asks you to restart the session

This keeps the global `~/.claude/agents/` directory to exactly 7 generalists (always present) while giving each project only the specialists it needs.

## Install

The installer downloads a GitHub Release ZIP, verifies its SHA256 against the sidecar, stages to `<prefix>.new`, snapshots the existing install to `<prefix>.previous`, and atomically promotes. It copies the 7 generalist agents to `~/.claude/agents/`, injects the JIT block into `~/.claude/CLAUDE.md`, and updates `PATH` so `ccds` resolves in new shells.

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

Activate the SaaS pack + generalists into a project:

```bash
cd /path/to/my-saas-app
ccds sync saas,common --write-adr
```

Activate multiple packs (e.g., an LLM-enabled SaaS product):

```bash
ccds sync saas,ai,common
```

Preview without writing:

```bash
ccds sync saas --dry-run
```

Remove a pack by re-running with a narrower list — the manifest tracks what the dispatcher owns:

```bash
ccds sync saas    # drops 'ai' if previously activated
```

Validate a project's `.claude/agents/`:

```bash
ccds verify
```

Run `ccds help` for full flag reference (`--mode copy|symlink`, `--no-generalists`, `--target <path>`, `--write-adr`).

## Script invocation (without installing)

The dispatcher wraps `Sync-AgentPacks.{ps1,sh}` and `Verify-Agents.{ps1,sh}`. You can invoke those scripts directly from a clone:

```powershell
.\Sync-AgentPacks.ps1 -TargetProject D:\code\my-app -Packs saas,common -WriteAdr
```

```bash
./Sync-AgentPacks.sh --target-project ~/code/my-app --packs saas,common --write-adr
```

By default both scripts look for the pack library at `~/.claude/playbook/agents/`. Override with `-LibraryRoot` (PS) or `--library-root` / `$CCDS_LIBRARY_ROOT` (bash).

See `Get-Help .\Sync-AgentPacks.ps1 -Full` or `./Sync-AgentPacks.sh --help`.

## Available packs

`game`, `saas`, `mobile`, `ai`, `dataplat`, `ecom`, `fintech`, `devtool`, `desktop`, `ext`, `embed`, `media`, `orch`, `infra`, `common`.

Pack contents, agent counts, and trigger conditions are documented in `CLAUDE.md`.

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

- Agent files are **BOM-less UTF-8**. PS 5.1's `Set-Content -Encoding UTF8` writes a BOM that Claude Code's YAML frontmatter parser silently rejects. The sync script uses `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`. See ADR-0001.
- Agents live in a **flat** `.claude/agents/` directory (no subfolders — Claude Code does not recurse). See ADR-0001.
- Release ZIPs are named `ccds-<tag>.zip` with a matching `ccds-<tag>.zip.sha256` sidecar. Installers verify SHA256 before extracting.
- The `~/.claude/CLAUDE.md` JIT block is delimited by `# >>> ccds >>>` / `# <<< ccds <<<` markers. The installer is idempotent — re-running updates the block in place. See ADR-0006.

## License

**PolyForm Noncommercial 1.0.0** — see [`LICENSE`](./LICENSE).

- **Free for noncommercial use**: personal projects, research, education, public-interest organizations, hobby work, and nonprofits.
- **Commercial use requires a separate license.** Contact contact@519lab.com.

Copyright 2026 Onward Investment LLC. All rights reserved.
