# Claude Code Dev Studio

A universal, stack-agnostic Claude Code playbook with a library of 105 archetype-aware agents (7 generalists + 14 archetype packs + 1 cross-archetype pack). Aligned with NIST SSDF (SP 800-218) and phase-gated Agile delivery.

## What's here

| File | Purpose |
|---|---|
| `CLAUDE.md` | The playbook — phases, agent triggers, archetype pack registry |
| `.claude/agents/` | 105 agent definitions (canonical library) |
| `Sync-AgentPacks.ps1` | Activate a subset of packs into a target project |
| `install-agents.ps1` | Deprecated SaaS-only wrapper — forwards to the sync script |
| `DECISIONS.md` | Architecture decision records (ADR-0001 … ADR-0005) |
| `CHANGELOG.md` | Session-by-session history |
| `CONTRIBUTING.md` | Contribution terms |
| `LICENSE` | PolyForm Noncommercial 1.0.0 |

## Quick start

Activate the SaaS pack + generalists into a project:

```powershell
.\Sync-AgentPacks.ps1 -TargetProject D:\code\my-saas-app -Packs saas -WriteAdr
```

Activate multiple packs (e.g., an LLM-enabled SaaS product):

```powershell
.\Sync-AgentPacks.ps1 -TargetProject D:\code\my-app -Packs saas,ai,common
```

Preview without writing:

```powershell
.\Sync-AgentPacks.ps1 -TargetProject D:\code\my-app -Packs saas -DryRun
```

Remove a pack by re-running with a narrower list — the manifest tracks what the script owns:

```powershell
.\Sync-AgentPacks.ps1 -TargetProject D:\code\my-app -Packs saas    # drops 'ai'
```

See `Get-Help .\Sync-AgentPacks.ps1 -Full` for full parameter docs.

## Available packs

`game`, `saas`, `mobile`, `ai`, `dataplat`, `ecom`, `fintech`, `devtool`, `desktop`, `ext`, `embed`, `media`, `orch`, `infra`, `common`.

Pack contents and agent triggers are documented in `CLAUDE.md`.

## Requirements

- Claude Code CLI (v2.1.113+ recommended — flat agent discovery)
- PowerShell 5.1 or 7+ on Windows; *nix port tracked in `CHANGELOG.md`

## Conventions

- Agent files are **BOM-less UTF-8**. PS 5.1's `Set-Content -Encoding UTF8` writes a BOM that Claude Code's YAML frontmatter parser silently rejects. The sync script uses `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`.
- Agents live in a **flat** `.claude/agents/` directory (no subfolders — Claude Code does not recurse). See ADR-0001.

## License

**PolyForm Noncommercial 1.0.0** — see [`LICENSE`](./LICENSE).

- **Free for noncommercial use**: personal projects, research, education, public-interest organizations, hobby work, and nonprofits.
- **Commercial use requires a separate license.** Contact ggrace@519lab.com.

Copyright 2026 Onward Investment LLC. All rights reserved.
