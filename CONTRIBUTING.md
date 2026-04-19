# Contributing

Thanks for considering a contribution to Claude Code Dev Studio.

## Licensing of contributions

This project is published under **PolyForm Noncommercial 1.0.0** (see [`LICENSE`](./LICENSE)), with copyright held by **Onward Investment LLC**. To keep licensing coherent and to preserve the option of offering a commercial license separately, all contributions are accepted on the following terms:

By submitting a pull request, patch, issue with code, or other contribution ("Contribution"), you agree that:

1. **You have the right to contribute the material.** The Contribution is your original work, or you have explicit authority to submit it under these terms.
2. **Inbound license grant.** You grant Onward Investment LLC a perpetual, worldwide, non-exclusive, royalty-free, irrevocable license to reproduce, modify, distribute, sublicense, and relicense your Contribution, including under licenses different from PolyForm Noncommercial 1.0.0 (e.g., a paid commercial license).
3. **No warranty.** Your Contribution is provided "as is" without warranty of any kind.
4. **DCO-style affirmation.** You have read and certify to the [Developer Certificate of Origin 1.1](https://developercertificate.org/) for each Contribution.

This lightweight model avoids a full CLA workflow while still giving the project maintainer (Onward Investment LLC) the flexibility to offer commercial licenses to companies without re-negotiating with every past contributor.

## Scope of accepted contributions

| Welcome | Not accepted without prior discussion |
|---|---|
| New pack agents that fill documented gaps | New archetype packs (open an issue first — scope needs alignment) |
| Fixes to existing agent prompts, triggers, or handoffs | Renames or reorganization of existing prefixes |
| Cross-platform port of `Sync-AgentPacks.ps1` (e.g., `Sync-AgentPacks.sh`) | Breaking changes to the manifest format |
| README / docs improvements, typo fixes | Changes to licensing, copyright, or attribution notices |
| Bug reports with reproducers | |

If your change might be invasive, open an issue first — alignment is faster than a rejected PR.

## Conventions

### File encoding
**BOM-less UTF-8** for every file. PowerShell 5.1's `Set-Content -Encoding UTF8` writes a BOM that Claude Code's YAML frontmatter parser silently rejects (agent appears on disk, never in `/agents`). Use:

```powershell
[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
```

See ADR-0001 in `DECISIONS.md` for the background.

### Agent file layout
Flat — no subdirectories under `.claude/agents/`. Claude Code v2.1.113 does not recurse that folder.

### Naming
- Generalists: `.claude/agents/<role>.md` (e.g., `plan-architect.md`)
- Archetype packs: `.claude/agents/<prefix>-<role>.md` (e.g., `saas-billing-expert.md`)
- Cross-archetype shared: `.claude/agents/common-<role>.md`
- Valid prefixes: `game, saas, mobile, ai, dataplat, ecom, fintech, devtool, desktop, ext, embed, media, orch, infra, common`.

### Handoffs
Every pack specialist declares explicit boundaries ("You do NOT own → `<other-agent>`") so scopes don't overlap. Follow this convention in new agents.

### Commits
Short, imperative subject line; explanatory body when scope is non-obvious. Reference ADR numbers when relevant.

### Record significant decisions
Non-trivial architectural or process changes go into `DECISIONS.md` as a new ADR (see existing ADR-0001 through ADR-0005 for the format).

## Security and responsible disclosure

Do **not** open public issues for security problems. Email ggrace@519lab.com with the details and a reproducer. Expect an acknowledgement within a week.

## Code of conduct

Be direct, technical, and respectful. Disagree on the merits; don't attack people. Maintainers reserve the right to lock or close discussions that drift into bad faith.

## Questions

Open a discussion or reach out at ggrace@519lab.com.
