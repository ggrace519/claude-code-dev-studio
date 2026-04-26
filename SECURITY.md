# Security Policy

## Reporting a vulnerability

Do **not** open a public issue for security-related reports.

Email: **security@519lab.com**

Include:

- A description of the vulnerability and its impact
- A reproducer (minimal steps or proof-of-concept)
- Affected version, commit SHA, or tag
- Any suggested remediation

You should receive an acknowledgement within **7 days**. A remediation plan — fix, workaround, or won't-fix with rationale — within **30 days**.

## Supported versions

This repository is a playbook and agent library, not a long-running service. Security fixes are applied to `main` and to tagged releases going forward. There is no long-term-support branch.

## Scope

### In scope

- PowerShell activation scripts (`Sync-AgentPacks.ps1`, `install-agents.ps1`)
- The future `Sync-AgentPacks.sh` *nix port
- Agent prompt files under `.claude/agents/`
- Documentation content in `CLAUDE.md`, `DECISIONS.md`, `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`

### Out of scope

- Claude Code CLI itself — report to Anthropic directly
- Third-party tools or services mentioned in agent prompts
- User-authored agents added to a consumer project's own `.claude/agents/` after `Sync-AgentPacks` has run
- Issues in downstream forks that have diverged from `main`

## Disclosure

Please allow a coordinated disclosure window of at least **30 days** unless a vulnerability is actively being exploited in the wild. Public credit granted on request.

## Not a bug bounty

There is currently no monetary bug bounty program. Responsible disclosure is still welcomed and will be credited in release notes.
