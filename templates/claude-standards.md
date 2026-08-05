# >>> ccds-standards >>>
# ⚠ ccds-managed block — do NOT edit between these markers. Regenerated on
# `ccds sync`; your edits here are overwritten. Put project-specific
# instructions ABOVE or BELOW this block; that text is always preserved.
# Remove: ccds sync --clean (or delete this block).

## Quality & security standards (ccds Gate 2)

These rules exist because AI-generated code is contributor code, not your own
— review it like a stranger wrote it, because statistically one did.

- **Small changes.** One feature = one branch = one PR, under ~400 changed
  lines. Review quality collapses past that; split big work.
- **Every PR explains its diff.** If the description can't say what changed
  and why in plain language, the change isn't understood well enough to merge.
- **Highest-scrutiny zones** — read these lines yourself before merging:
  authorization checks (models write login and forget permissions), error
  paths, anything concurrent, cryptography, and any SQL or shell command
  built from strings. Database queries and shell commands must use
  parameterization, never string concatenation.
- **Secrets never enter code or chat.** Keys and passwords live in `.env`
  (which is git-ignored and deny-listed for the model) or a secrets manager
  — never in source files, commit messages, or pasted into the session.
- **Pin dependencies.** Commit lockfiles (package-lock.json, uv.lock,
  Cargo.lock, go.sum) and install from them. Before approving a new package
  the model suggested, check it exists on the registry with real downloads —
  models sometimes invent package names, and attackers register them.
- **Tests by a different context.** Don't let the same session that wrote
  the code also write its only tests — ask for a fresh review/test pass
  (the pr-code-reviewer and test-writer-runner agents exist for this).
- **Protect your main branch.** On GitHub: Settings → Branches → Add branch
  protection rule → check "Require a pull request before merging". This
  makes every change reviewable and reversible — do it once, today.
- **Pre-commit and CI are your safety net** (`.pre-commit-config.yaml`,
  `.github/workflows/ccds-quality.yml`, staged by ccds). If a check blocks
  you, fix the cause — deleting the check is how bugs ship.
# <<< ccds-standards <<<
