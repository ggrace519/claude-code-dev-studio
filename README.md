# Claude Code Dev Studio

A universal, stack-agnostic Claude Code playbook with a library of 105 archetype-aware agents (7 generalists + 14 archetype packs + 1 cross-archetype pack). Aligned with NIST SSDF (SP 800-218) and phase-gated Agile delivery.

## What's here

| File | Purpose |
|---|---|
| `CLAUDE.md` | The playbook — phases, agent triggers, archetype pack registry |
| `.claude/agents/` | 105 agent definitions (canonical library) |
| `bin/claude-playbook.{ps1,sh}` | Dispatcher — `sync`, `verify`, `update`, `uninstall`, `version` |
| `Install-Playbook.ps1` | Windows installer (stage/promote, SHA256-verified, PATH-aware) |
| `install-playbook.sh` | Linux/macOS installer (same behavior, shell-rc PATH block) |
| `Sync-AgentPacks.{ps1,sh}` | Activate a subset of packs into a target project (invoked by `claude-playbook sync`) |
| `Verify-Agents.ps1` / `verify-agents.sh` | Validate `.claude/agents/` against ADR-0001 invariants |
| `scripts/build-release.ps1` | Build reproducible release ZIP + sidecar SHA256 |
| `.github/workflows/release.yml` | Tag-driven release build + GitHub Release publication |
| `DECISIONS.md` | Architecture decision records (ADR-0001 … ADR-0005) |
| `CHANGELOG.md` | Session-by-session history |
| `CONTRIBUTING.md` | Contribution terms |
| `LICENSE` | PolyForm Noncommercial 1.0.0 |

## Install

The installer downloads a GitHub Release ZIP, verifies its SHA256 against the sidecar, stages to `<prefix>.new`, snapshots the existing install to `<prefix>.previous`, and atomically promotes. It updates `PATH` so `claude-playbook` resolves in new shells.

**Windows (PowerShell 5.1 or 7+):**

```powershell
iwr -UseBasicParsing https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/Install-Playbook.ps1 | iex
```

Default prefix: `%LOCALAPPDATA%\ClaudePlaybook`. Override with `-Prefix`, pin a version with `-Version v0.4.0`, include prereleases with `-IncludePrerelease`, skip PATH with `-NoPath`.

**Linux / macOS (bash):**

```bash
curl -fsSL https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/install-playbook.sh | bash
```

Default prefix: `$HOME/.local/share/claude-playbook`. Override with `--prefix`, pin a version with `--version v0.4.0`, include prereleases with `--include-prerelease`, skip PATH with `--no-path`.

Both installers take `--dry-run` / `-DryRun`, `--local-zip <path>` / `-LocalZip <path>` (install from a local ZIP), and `-Token` / `--token` (GitHub token for rate-limited environments).

## Update / rollback / uninstall

Once installed, the dispatcher delegates these to a fresh copy of the installer fetched from `main`, so bug fixes to the installer propagate automatically. All operations target the running install's prefix.

```bash
claude-playbook update              # update to latest stable release
claude-playbook update v0.4.1       # pin a specific tag
claude-playbook update --include-prerelease   # resolve 'latest' to latest prerelease
claude-playbook update --rollback   # restore the previous install from <prefix>.previous
claude-playbook uninstall           # remove the install directory and PATH entry
claude-playbook version             # print installed version
```

## Quick start

Activate the SaaS pack + generalists into a project:

```bash
cd /path/to/my-saas-app
claude-playbook sync saas,common --write-adr
```

Activate multiple packs (e.g., an LLM-enabled SaaS product):

```bash
claude-playbook sync saas,ai,common
```

Preview without writing:

```bash
claude-playbook sync saas --dry-run
```

Remove a pack by re-running with a narrower list — the manifest tracks what the dispatcher owns:

```bash
claude-playbook sync saas    # drops 'ai' if previously activated
```

Validate a project's `.claude/agents/`:

```bash
claude-playbook verify
```

Run `claude-playbook help` for full flag reference (`--mode copy|symlink`, `--no-generalists`, `--target <path>`, `--write-adr`).

## Script invocation (without installing)

The dispatcher wraps `Sync-AgentPacks.{ps1,sh}` and `Verify-Agents.{ps1,sh}`. You can still invoke those scripts directly from a clone:

```powershell
.\Sync-AgentPacks.ps1 -TargetProject D:\code\my-app -Packs saas,common -WriteAdr
```

```bash
./Sync-AgentPacks.sh --target-project ~/code/my-app --packs saas,common --write-adr
```

See `Get-Help .\Sync-AgentPacks.ps1 -Full` or `./Sync-AgentPacks.sh --help`.

## Available packs

`game`, `saas`, `mobile`, `ai`, `dataplat`, `ecom`, `fintech`, `devtool`, `desktop`, `ext`, `embed`, `media`, `orch`, `infra`, `common`.

Pack contents and agent triggers are documented in `CLAUDE.md`.

## Requirements

- Claude Code CLI (v2.1.113+ recommended — flat agent discovery)
- PowerShell 5.1 or 7+ on Windows
- bash 4+, `curl`, `unzip`, `sha256sum`/`shasum` on Linux/macOS

## Conventions

- Agent files are **BOM-less UTF-8**. PS 5.1's `Set-Content -Encoding UTF8` writes a BOM that Claude Code's YAML frontmatter parser silently rejects. The sync script uses `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`.
- Agents live in a **flat** `.claude/agents/` directory (no subfolders — Claude Code does not recurse). See ADR-0001.
- Release ZIPs are non-deterministic across build machines — the sidecar-shipped SHA256 (`claude-playbook-<tag>.zip.sha256`) is the source of truth. Installers verify before extracting.

## License

**PolyForm Noncommercial 1.0.0** — see [`LICENSE`](./LICENSE).

- **Free for noncommercial use**: personal projects, research, education, public-interest organizations, hobby work, and nonprofits.
- **Commercial use requires a separate license.** Contact ggrace@519lab.com.

Copyright 2026 Onward Investment LLC. All rights reserved.
