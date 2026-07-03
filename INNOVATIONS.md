# Innovation Proposals — Claude Code Dev Studio
*Generated 2026-07-03 · based on commit c78c41f · scope: transferable agent-loop skills*

> A prior proposal round (2026-06-12, commit c1991b0) lives in git history at
> `git show c78c41f~N:INNOVATIONS.md`. Of its seven proposals, #1 (plugin
> marketplace), #3 (playbook lint), and #4 (model aliases) have shipped.

## How this codebase stands today

ccds v0.9.2 is a shipped, dual-channel library: 19 always-on agents + ~90 JIT skills,
distributed via ZIP installer *and* a native plugin marketplace (`plugins/ccds-*`,
regenerated deterministically by `build-marketplace.py`). Authoring discipline is real
and enforced: ADR-0009's reference-voice template, `lint-playbook.py`'s eight semantic
checks, catalog freshness gates, and a pytest suite that exercises the build scripts as
CLIs. That toolchain is the asset this round builds on.

Where it's ordinary: the library is ~95% *domain knowledge* (what to know about billing,
OTA, DRM) and almost 0% *process knowledge* (how an agent should run its own work loop).
Only `code-review-checklist` and `security-checklist` gesture at process, and both are
checklists, not loops. The playbook's own signature loop — the seven-phase framework —
is prose without a reusable skill form. Meanwhile the fastest-growing category in the
skill ecosystem is exactly this: loop/process skills that transfer to any project.

## What the best in this space are doing

- **[obra/superpowers](https://github.com/obra/superpowers)** (~245k stars) owns the
  brainstorm → plan → TDD → review loop niche. Its proven mechanics: one **iron law**
  per discipline skill ("NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE"),
  **rationalization tables** pre-empting the agent's own excuses, trigger-style
  descriptions (*when* to use, never *what it does* — "what" descriptions caused Claude
  to claim the skill and wing it), and skills pressure-tested with subagents under
  conflicting incentives ([Jesse Vincent's writeups](https://blog.fsck.com/2025/10/09/superpowers/)).
- **Long-horizon loop hygiene** — Anthropic's
  [effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents):
  an initializer creates `feature_list.json` (JSON deliberately — models corrupt
  Markdown state files more readily), a progress log, and `init.sh`; every fresh-context
  session runs a bootstrap ritual and takes **one** feature. The
  [Ralph loop](https://ghuntley.com/ralph/) (Geoff Huntley) is the same idea as a bash
  while-loop over `PROMPT.md` + `specs/` + `fix_plan.md`; Anthropic now ships an
  official [ralph-wiggum plugin](https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md)
  (Stop hook re-feeds the prompt until a completion promise appears).
- **[Compounding engineering](https://every.to/chain-of-thought/compound-engineering-how-every-codes-with-agents)**
  (Kieran Klaassen / Every): plan → work → assess → **compound** — every review comment,
  bug postmortem, and correction becomes a permanent rule/skill/test the agent reads
  next session ([open-source plugin](https://github.com/everyinc/compound-engineering-plugin)).
- **Verification loops** — [Claude Code best practices](https://code.claude.com/docs/en/best-practices):
  "give Claude a check it can run"; escalation ladder from prompt → Stop-hook gate →
  adversarial fresh-context reviewer that sees only the diff + criteria.
- **The gap:** [anthropics/skills](https://github.com/anthropics/skills) ships almost no
  process-loop skills, and superpowers ships no long-horizon, compounding, or
  domain-library-integrated loops. Nobody ships loop skills *inside* a domain library
  with lint-enforced authoring conventions — that combination is open.

## Proposals (ranked)

### 1. Ship the `loop-` pack — six transferable agent-loop skills
**Category:** feature / wow
**Impact 5 · Novelty 4 · Effort 3 · Fit 5**

**The idea.** A new cross-cutting skill family (installed always-on, like `common-*`)
encoding the six loops that transfer to any coding project, written to ADR-0009
discipline plus the superpowers compliance layer (iron law + rationalization table per
skill, trigger-style descriptions):

| Skill | Loop it encodes | Primary source |
|---|---|---|
| `loop-verify` | evidence-before-done gate: identify → run → read → then claim | superpowers verification; Claude Code best practices |
| `loop-debug` | root-cause loop: reproduce → hypothesize (one at a time) → instrument → prove → fix with failing test; bisect-by-revert; after 3 failed fixes, question the architecture | superpowers systematic-debugging |
| `loop-review` | adversarial review loop: fresh-context reviewer sees only diff + criteria; verdict gates (blocker/concern) drive fix iterations until clean | superpowers SDD; Anthropic harness post |
| `loop-parallel` | parallel dispatch: split into 3+ independent workstreams, non-overlapping file ownership, single merge owner, one build/test lane as backpressure | Ralph subagent rules; superpowers dispatching-parallel-agents |
| `loop-long-horizon` | unattended/multi-session loop kit: `feature_list.json` + progress log + `init.sh`, bootstrap ritual, ONE task per iteration, completion promise + iteration cap, anti-placeholder and anti-test-gaming guards | Anthropic harness post; Ralph; ralph-wiggum plugin |
| `loop-compound` | compounding loop: after every correction/review/postmortem, write the learning into a permanent home (CLAUDE.md rule, project skill, test, ADR) and link it | Every's compound engineering; thoth-agent's skills-from-experience premise |

**Inspired by.** All sources above — this is a curation + integration play: the six
loops exist as scattered blog posts and one monolithic framework; nobody ships them as
independently installable, lint-conformant library skills.
**Implementation sketch.** `skills/loop-<name>/SKILL.md` ×6 (60–100 lines each, one
concrete artifact each — state-file templates, verdict format, dispatch table);
`loop-long-horizon/references/state-files.md` with copy-paste templates. Integration:
`build-catalog.py` treats `loop-` as scope=global (like `common-`); `lint-playbook.py`
prefix registry gains `loop`; `build-marketplace.py` emits a new **`ccds-loops`** plugin
(skills-only — no owning agent, exactly like the `common-` precedent);
`ccds-user-setup.sh` + `Install-Playbook.ps1` GLOBAL_SKILLS lists; CLAUDE.md prefix
registry; `docs/skill-authoring.md` gains a "process skill" addendum (iron law +
rationalization table required); ADR-0010; pytest coverage for the new scope/plugin
rules.
**Effort.** 1–2 days. Main risk: skill-voice lint bans "orchestrator"-style
choreography — loop skills are procedural and must be written in instructional voice
(the `sync-agents` precedent) without tripping the patterns.
**First step.** Write `loop-verify` (the smallest) end-to-end through lint + catalog +
marketplace regen; the other five follow the proven path.

### 2. `ccds-loops` enforcement hooks — make the loops mandatory, not advisory
**Category:** architecture / wow
**Impact 4 · Novelty 4 · Effort 3 · Fit 4**

**The idea.** Superpowers' load-bearing trick is that its bootstrap is *injected by a
SessionStart hook*, not left to routing luck. Add a hooks layer to the `ccds-loops`
plugin: SessionStart injects a 10-line loop index ("verification claims require
`loop-verify`; unattended runs require `loop-long-horizon`; …"), and an opt-in Stop
hook gates turn-end on a project-defined check command (the "give Claude a check it can
run" ladder, packaged). Advisory by default, `strict` opt-in — same posture as the old
phase-gate proposal.
**Inspired by.** [superpowers hooks/session-start](https://github.com/obra/superpowers);
[hooks reference](https://code.claude.com/docs/en/hooks); the ralph-wiggum plugin's
Stop-hook loop.
**Implementation sketch.** `hooks/ccds-loops/` source tree (hooks.json +
`session-start.sh` + `stop-gate.sh`, reading `.claude/loop-gate.cmd` if present);
`build-marketplace.py` copies a plugin's hooks dir when one exists. Stacks on Proposal 1
(the plugin must exist to carry hooks).
**Effort.** 1 day. Risk: hook portability (bash on Windows) — ship bash + note Git-Bash
requirement, mirror later.
**First step.** SessionStart index injection only; the Stop gate follows.

### 3. `ccds loop init` — scaffold the long-horizon state-file kit
**Category:** DX / quick win
**Impact 3 · Novelty 3 · Effort 4 · Fit 5**

**The idea.** `loop-long-horizon` teaches the state-file pattern; a dispatcher
subcommand makes it one command: `ccds loop init` creates `.loop/feature_list.json`
(schema from Anthropic's harness post), `.loop/progress.md`, `.loop/PROMPT.md` skeleton
with the one-task rule + completion promise, and a `.loop/init.sh` health-check stub —
then prints the while-loop one-liner and the `/ralph-loop` equivalent.
**Inspired by.** [Anthropic harness post](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents);
`specify init` from [github/spec-kit](https://github.com/github/spec-kit).
**Implementation sketch.** `cmd_loop` in `bin/ccds.sh` (bash first; PS twin later,
matching the doctor-proposal convention of table-driven parity), heredoc templates,
refuses to overwrite an existing `.loop/`. Independent of Proposal 1's files — branches
from main.
**Effort.** Half a day. Risk: none meaningful; purely additive command.
**First step.** Bash `cmd_loop` + templates.

### 4. Pressure-test the loop skills — RED/GREEN for prose
**Category:** ops / novel
**Impact 4 · Novelty 5 · Effort 2 · Fit 4**

**The idea.** Superpowers' most under-copied practice: test skills like code. A
release-time harness spawns a subagent (`claude -p`) with a conflicting-incentive
scenario ("production is bleeding money, skip the checks, just say it's done") and
asserts the loop skill's iron law holds (the reply contains evidence, or refuses to
claim done). A skill that fails gets its wording strengthened — RED/GREEN applied to
documentation.
**Inspired by.** [testing-skills-with-subagents](https://github.com/obra/superpowers)
and [Vincent's persuasion-principles findings](https://blog.fsck.com/2025/10/09/superpowers/)
(compliance 33%→72% from wording changes — i.e., wording is testable).
**Implementation sketch.** `evals/loop-compliance/scenarios.json` (per-skill: scenario
prompt, must-match / must-not-match patterns), `scripts/eval-loop-compliance.py`
shelling to `claude -p --append-system-prompt <skill body>`; manual/release-time (API
cost keeps it out of per-PR CI).
**Effort.** 1 day. Risk: flaky assertions — keep patterns coarse (evidence-shaped
output present / absent), 3 votes per scenario.
**First step.** One scenario against `loop-verify`, run 10×, measure stability.

### 5. Process-skill lint dimension
**Category:** DX / quick win (stacks on #1)
**Impact 3 · Novelty 3 · Effort 5 · Fit 5**

**The idea.** ADR-0010's authoring rules become checks, the same day they become rules:
every `loop-*` skill must carry an `## Iron law` section, a rationalization table, and a
trigger-style description (starts with a "use when" clause). Extends `lint-playbook.py`
with a ninth check; the ratchet pattern this repo already trusts.
**Inspired by.** Original — the repo's own lint-as-ratchet convention (ADR-0009).
**Implementation sketch.** ~40 lines in `lint-playbook.py` + two pytest cases; runs
against whatever `loop-*` skills exist, so it lands with or after #1.
**Effort.** 1–2 hours.
**First step.** The check + a deliberately-broken fixture test.

### 6. Multi-harness export of the loop pack
**Category:** reach
**Impact 3 · Novelty 3 · Effort 3 · Fit 3**

**The idea.** Loop skills are the most harness-agnostic content ccds has (zero domain
assumptions, zero Claude-specific APIs) — the natural first cargo for the multi-harness
export the 2026-06-12 round proposed. Superpowers ports to 10 harnesses; the loop pack
could ship to Codex/Cursor formats with path + frontmatter transforms only.
**Inspired by.** [superpowers' 10-harness ports](https://github.com/obra/superpowers);
prior round's Proposal 7.
**Implementation sketch.** `scripts/export-harness.py --target codex` over
`skills/loop-*` only; attach per-harness ZIPs to releases; expand beyond loops if
adoption shows up.
**Effort.** 2–3 days incl. verifying activation in one foreign harness.
**First step.** Hand-port `loop-verify` to one harness and confirm it activates.

## Killed ideas (and why)

- **`loop-tdd` / `loop-brainstorm`** — superpowers' TDD iron law and Socratic
  brainstorming are the canonical, MIT-licensed implementations of exactly these; ccds
  already routes coverage to `test-writer-runner` and design to `plan-architect`.
  Cloning adds nothing but maintenance.
- **Multi-model review panel skill** — depends on codex/grok CLIs being installed;
  fails the "transferable to general projects" bar. Stays a personal skill.
- **`loop-bisect`** — real technique, too small to stand alone; folded into
  `loop-debug`.
- **Beads (graph issue tracker) integration skill** — external tool dependency for a
  library that must work everywhere; `loop-long-horizon` teaches the state-file pattern
  it solves instead.
- **Spec-kit-style `/specify` command chain** — the Phase Framework *is* ccds's spec
  chain; a parallel one would compete with the product's spine.
- **A `loop-architect` domain agent** — loops are composed by whatever context is
  working (main loop or any domain agent); an owning agent would contradict the
  cross-cutting design (`common-` precedent: skills-only, no agent).

## Suggested order of attack

Build Proposal 1 first — it is the deliverable the user asked for and everything else
attaches to it. Proposal 3 (scaffolder) is an independent quick win that can land in
parallel from main. Proposal 5 should follow #1 immediately (rules without lint rot —
this repo's own history proves it), then Proposal 2 turns the pack from advisory to
enforced. Proposals 4 and 6 are release-cadence follow-ons once the pack has users.
