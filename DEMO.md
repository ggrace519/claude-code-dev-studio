# Demo — innovation/plugin-marketplace (INNOVATIONS.md Proposal 1)

## What this branch does

Turns the repo into a **native Claude Code plugin marketplace**, mapping the
pack architecture 1:1 onto plugins:

- `scripts/build-marketplace.py` — generates `.claude-plugin/marketplace.json`
  and `plugins/ccds-<name>/` (15 plugins: `ccds-core` + 14 packs; 19 agents +
  89 skills) from `.claude/agents/` and `skills/`. Deterministic output;
  version resolved from git tags (`--version` to override).
- Checked-in generated tree, with a `marketplace-freshness` CI job that
  regenerates and fails on drift (same pattern the catalog should follow).
- README documents the plugin path alongside the still-supported ZIP installer.

`sync-agents` is deliberately excluded from plugins — plugin enablement
replaces the JIT staging flow it drives.

## How to try it (verified end-to-end with the real CLI)

```
claude plugin marketplace add /path/to/this/clone   # or: ggrace519/claude-code-dev-studio once merged
claude plugin install ccds-saas@ccds
claude plugin details ccds-saas@ccds
```

Verified output: 1 agent (`saas-architect`) + 5 skills, ~637 always-on tokens.
Clean up with `claude plugin uninstall ccds-saas@ccds` and
`claude plugin marketplace remove ccds`.

Regenerate after editing any agent/skill:

```bash
python3 scripts/build-marketplace.py
```

## What works / what's stubbed

- Working: generation, determinism (re-run produces byte-identical output),
  real `marketplace add` → `install` → `details` → `uninstall` cycle.
- Compatibility note: plugin sources use explicit `./plugins/<name>` paths
  instead of `metadata.pluginRoot` + bare names — the latter failed on the
  locally installed Claude Code version.
- Trade-off: `plugins/` duplicates agent/skill content (~500 KB). Accepted for
  the vertical slice; CI guards staleness. Alternative (publish generated tree
  to a release branch) is noted below.

## Next increment

1. Hook `build-marketplace.py` into `build-release.sh` so releases bump plugin
   versions automatically.
2. Decide checked-in vs release-branch publication for `plugins/`.
3. Add the `ccds-phases` hooks plugin (INNOVATIONS.md Proposal 5) as a 16th
   plugin — the marketplace makes hooks distribution trivial.
