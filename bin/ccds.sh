#!/usr/bin/env bash
# ccds -- Claude Code Dev Studio dispatcher (Linux/macOS)

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "${BASH_SOURCE[0]}")"
BIN_DIR="$(dirname "$SCRIPT_PATH")"
INSTALL_ROOT="$(cd "$BIN_DIR/.." && pwd)"

# Detect layout kind
if [[ -f "$INSTALL_ROOT/scripts/Sync-AgentPacks.sh" ]]; then
    SYNC_SCRIPT="$INSTALL_ROOT/scripts/Sync-AgentPacks.sh"
    VERIFY_SCRIPT="$INSTALL_ROOT/scripts/verify-agents.sh"
    SETUP_SCRIPT="$INSTALL_ROOT/scripts/ccds-user-setup.sh"
    LIBRARY_ROOT="$INSTALL_ROOT"
    # Distinguish system package (/usr/share/ccds) from per-user install (~/.claude/playbook)
    case "$INSTALL_ROOT" in
        /usr/share/ccds*) LAYOUT_KIND="package" ;;
        *)                LAYOUT_KIND="installed" ;;
    esac
elif [[ -f "$INSTALL_ROOT/Sync-AgentPacks.sh" ]]; then
    SYNC_SCRIPT="$INSTALL_ROOT/Sync-AgentPacks.sh"
    VERIFY_SCRIPT="$INSTALL_ROOT/verify-agents.sh"
    SETUP_SCRIPT="$INSTALL_ROOT/scripts/ccds-user-setup.sh"
    LIBRARY_ROOT="$INSTALL_ROOT"
    LAYOUT_KIND="dev"
else
    echo "ERROR: Cannot locate Sync-AgentPacks.sh under $INSTALL_ROOT" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Per-user setup detection
# ---------------------------------------------------------------------------
# Checks whether the per-user setup has been run (generalists present + JIT
# block injected). Returns 0 if setup is complete, 1 if it needs to run.
needs_user_setup() {
    # Check for at least one always-on (core) agent
    [[ -f "$HOME/.claude/agents/plan-architect.md" ]] || return 0
    # Check for ccds block in CLAUDE.md
    [[ -f "$HOME/.claude/CLAUDE.md" ]] && grep -qF '# >>> ccds >>>' "$HOME/.claude/CLAUDE.md" || return 0
    return 1
}

run_user_setup_if_needed() {
    if needs_user_setup; then
        echo "==> First run: performing per-user setup..."
        cmd_setup
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
installed_version() {
    if [[ -f "$INSTALL_ROOT/version.txt" ]]; then
        local v
        v="$(tr -d '[:space:]' < "$INSTALL_ROOT/version.txt")"
        echo "$v"
    else
        echo "dev"
    fi
}

show_help() {
    cat <<EOF
ccds -- Claude Code Dev Studio
USAGE
  ccds <command> [arguments]

COMMANDS
  sync <packs>         Stage domain skills for the packs into ./.claude/skills/
      --clean               Remove all skills staged by a previous sync
      --dry-run             Preview changes without writing
      --write-adr           Record activation as an ADR in DECISIONS.md
      --target <path>       Target project path (default: current directory)

  verify               Validate global agents and project skills
      --target <path>       Target path (default: current directory)

  doctor               Run proactive environment health checks: layout shape,
                       version drift vs the latest release, install
                       completeness (agents, skills, CLAUDE.md block, catalog),
                       BOM/CRLF corruption, PATH and dual-install conflicts.
                       Exit 0 = healthy (WARNs allowed), 1 = failures found.

  lint                 Lint the playbook library's semantic invariants
                       (skill cross-refs, catalog freshness, URL/description
                       conventions). Requires a repo clone (dev layout).

  setup                Install the 19 agents + cross-cutting skills, inject CLAUDE.md block
      --dry-run             Preview without writing

  loop init            Scaffold the long-horizon loop state-file kit into ./.loop/
                       (feature_list.json, progress.md, PROMPT.md, init.sh — see the
                       loop-long-horizon skill)
      --target <path>       Target project path (default: current directory)
      --dry-run             Preview without writing

  update [tag]         Download and install a release (default: latest stable)
      --rollback            Restore the previous installed version
      --include-prerelease  Pick up release candidates when resolving 'latest'

  uninstall            Remove the installation and PATH entries

  version              Print the installed version

  help                 Show this help

EXAMPLES
  ccds sync saas
  ccds sync saas,ai --write-adr
  ccds sync game --dry-run
  ccds sync --clean
  ccds verify
  ccds doctor
  ccds setup
  ccds loop init

LAYOUT
  Install location : $INSTALL_ROOT
  Layout           : $LAYOUT_KIND
  Library          : $LIBRARY_ROOT
  Sync script      : $SYNC_SCRIPT
  Verify script    : $VERIFY_SCRIPT
  Version          : $(installed_version)
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DRY_RUN=0
WRITE_ADR=0
CLEAN=0
TARGET=""
ROLLBACK=0
INCLUDE_PRERELEASE=0
POSITIONAL=()

if (( $# == 0 )); then
    show_help
    exit 0
fi

COMMAND="${1//$'\r'/}"; shift

case "$COMMAND" in
    -h|--help|help)    show_help; exit 0 ;;
    --version|version) installed_version; exit 0 ;;
esac

while (( $# > 0 )); do
    case "$1" in
        --dry-run)            DRY_RUN=1; shift ;;
        --write-adr)          WRITE_ADR=1; shift ;;
        --clean)              CLEAN=1; shift ;;
        --rollback)           ROLLBACK=1; shift ;;
        --include-prerelease) INCLUDE_PRERELEASE=1; shift ;;
        --target)
            [[ -n "${2:-}" ]] || { echo "ERROR: --target requires a path" >&2; exit 2; }
            TARGET="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        --*) echo "ERROR: Unknown flag: $1" >&2; exit 2 ;;
        *)   POSITIONAL+=("$1"); shift ;;
    esac
done

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_setup() {
    [[ -f "$SETUP_SCRIPT" ]] || {
        echo "ERROR: ccds-user-setup.sh not found at $SETUP_SCRIPT" >&2
        exit 2
    }
    local dry=""
    (( DRY_RUN )) && dry="--dry-run"
    bash "$SETUP_SCRIPT" "$INSTALL_ROOT" $dry
}

cmd_sync() {
    run_user_setup_if_needed
    local target="${TARGET:-$PWD}"
    local args=(--target-project "$target" --library-root "$LIBRARY_ROOT")

    if (( CLEAN )); then
        args+=(--clean)
    else
        if (( ${#POSITIONAL[@]} < 1 )); then
            echo "ERROR: sync requires a pack list (or --clean). Example: ccds sync saas" >&2
            exit 2
        fi
        args+=(--packs "${POSITIONAL[0]}")
    fi
    (( DRY_RUN ))   && args+=(--dry-run)
    (( WRITE_ADR )) && args+=(--write-adr)

    exec "$SYNC_SCRIPT" "${args[@]}"
}

cmd_verify() {
    run_user_setup_if_needed
    local target="${TARGET:-$PWD}"
    local agents_path="$target/.claude/agents"
    if [[ ! -d "$agents_path" ]]; then
        echo "ERROR: No .claude/agents/ found under $target" >&2
        exit 2
    fi
    exec "$VERIFY_SCRIPT" "$agents_path"
}

# ---------------------------------------------------------------------------
# ccds doctor -- proactive environment health checks
# ---------------------------------------------------------------------------
# Every class of environment bug this project has shipped (BOM-broken
# frontmatter, CRLF scripts, silent no-op installs, stale versions, dual
# install roots) gets a proactive check here instead of a reactive fix.
#
# Contract:
#   - each check prints exactly one line:  OK|WARN|FAIL  <name>: <detail>
#     plus an indented 'remedy:' line on WARN/FAIL
#   - exit 0 if no FAIL (WARNs allowed), 1 if any FAIL, 2 on config error
#
# CCDS_DOCTOR_RELEASE_URL is a TEST-ONLY override for the GitHub
# latest-release endpoint, so tests can force the offline path
# deterministically. Do not set it in normal use.

DOC_OK=0; DOC_WARN=0; DOC_FAIL=0

doc_line() {  # doc_line STATUS NAME DETAIL [REMEDY]
    local status="$1" name="$2" detail="$3" remedy="${4:-}"
    printf '%s  %s: %s\n' "$status" "$name" "$detail"
    case "$status" in
        OK)   DOC_OK=$((DOC_OK + 1)) ;;
        WARN) DOC_WARN=$((DOC_WARN + 1)) ;;
        FAIL) DOC_FAIL=$((DOC_FAIL + 1)) ;;
        *)    echo "ERROR: doc_line: unknown status '$status'" >&2; exit 2 ;;
    esac
    if [[ "$status" != "OK" && -n "$remedy" ]]; then
        printf '      remedy: %s\n' "$remedy"
    fi
}

doc_check_layout() {
    if [[ "$LAYOUT_KIND" == "dev" ]]; then
        doc_line WARN layout \
            "dev (repo clone at $INSTALL_ROOT); 'ccds setup' expects the packaged shape (<root>/agents, <root>/skills) -- this repo keeps agents in .claude/agents" \
            "stage a release first (bash build-release.sh) or install via install-playbook.sh, then run 'ccds setup' from that tree"
    else
        doc_line OK layout "$LAYOUT_KIND ($INSTALL_ROOT)"
    fi
}

doc_check_version() {
    local installed url body latest
    installed="$(installed_version)"
    url="${CCDS_DOCTOR_RELEASE_URL:-https://api.github.com/repos/ggrace519/claude-code-dev-studio/releases/latest}"

    if ! command -v curl >/dev/null 2>&1; then
        doc_line WARN version \
            "installed $installed; could not check latest release (curl not found)" \
            "install curl to enable the update check"
        return
    fi
    if ! body="$(curl -fsSL --max-time 5 -H 'User-Agent: ccds-doctor' "$url" 2>/dev/null)"; then
        doc_line WARN version \
            "installed $installed; could not check latest release (offline, timeout, or rate-limited)" \
            "retry with network access, or check https://github.com/ggrace519/claude-code-dev-studio/releases"
        return
    fi
    latest="$(printf '%s' "$body" \
        | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')"
    if [[ -z "$latest" ]]; then
        doc_line WARN version \
            "installed $installed; could not parse latest release tag from $url" \
            "check https://github.com/ggrace519/claude-code-dev-studio/releases"
        return
    fi

    local vi="${installed#v}" vl="${latest#v}"
    if [[ "$installed" == "dev" ]]; then
        doc_line OK version "dev (repo clone; latest release is $latest)"
    elif [[ "$vi" == "$vl" ]]; then
        doc_line OK version "$installed (up to date with latest release $latest)"
    elif [[ "$(printf '%s\n%s\n' "$vi" "$vl" | sort -V | head -n1)" == "$vi" ]]; then
        doc_line WARN version \
            "installed $installed is older than latest release $latest" \
            "run 'ccds update'"
    else
        doc_line OK version "$installed (ahead of latest release $latest)"
    fi
}

doc_check_agents() {
    local dir="$HOME/.claude/agents"
    if [[ -f "$dir/plan-architect.md" ]]; then
        local n
        n="$(find "$dir" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
        doc_line OK agents-installed "core sentinel plan-architect.md present ($n agent file(s) in $dir)"
    else
        doc_line FAIL agents-installed \
            "plan-architect.md missing from $dir -- the always-on agents are not installed" \
            "run 'ccds setup'"
    fi
}

doc_check_skills() {
    # Read the authoritative GLOBAL_SKILLS list from the setup script at
    # runtime -- never a second hardcoded copy that can drift.
    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        doc_line WARN skills-installed \
            "cannot determine expected skill list ($SETUP_SCRIPT not found)" \
            "reinstall via 'ccds update' or the installer"
        return
    fi
    local -a expected=()
    mapfile -t expected < <(sed -n '/^GLOBAL_SKILLS=(/,/^)/p' "$SETUP_SCRIPT" \
        | sed -e '1d' -e '$d' -e 's/#.*$//' -e 's/[[:space:]]//g' | grep -v '^$' || true)
    if (( ${#expected[@]} == 0 )); then
        doc_line WARN skills-installed \
            "could not extract GLOBAL_SKILLS from $SETUP_SCRIPT" \
            "reinstall via 'ccds update' or the installer"
        return
    fi
    local name
    local -a missing=()
    for name in "${expected[@]}"; do
        [[ -f "$HOME/.claude/skills/$name/SKILL.md" ]] || missing+=("$name")
    done
    if (( ${#missing[@]} == 0 )); then
        doc_line OK skills-installed "all ${#expected[@]} cross-cutting skills present in $HOME/.claude/skills"
    else
        doc_line FAIL skills-installed \
            "${#missing[@]}/${#expected[@]} cross-cutting skills missing from $HOME/.claude/skills: ${missing[*]}" \
            "run 'ccds setup'"
    fi
}

doc_check_bom() {
    local f
    local -a hits=()
    for f in "$HOME/.claude/agents"/*.md "$HOME/.claude/skills"/*/SKILL.md; do
        [[ -f "$f" ]] || continue
        if [[ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" == "efbbbf" ]]; then
            hits+=("$f")
        fi
    done
    if (( ${#hits[@]} == 0 )); then
        doc_line OK bom-scan "no UTF-8 BOM in installed agents or skills"
    else
        doc_line FAIL bom-scan \
            "${#hits[@]} installed file(s) start with a UTF-8 BOM, which makes Claude Code silently skip the frontmatter (ADR-0001): ${hits[*]}" \
            "run 'ccds setup' to restore clean copies; re-save any hand-edited file as UTF-8 without BOM"
    fi
}

doc_check_crlf() {
    local -a hits=()
    mapfile -t hits < <(find "$INSTALL_ROOT" -name '*.sh' -type f -not -path '*/.git/*' \
        -exec grep -lI $'\r' {} + 2>/dev/null || true)
    if (( ${#hits[@]} == 0 )); then
        doc_line OK crlf-scan "no CR bytes in *.sh under $INSTALL_ROOT"
    else
        doc_line WARN crlf-scan \
            "${#hits[@]} shell script(s) under $INSTALL_ROOT contain CR (CRLF) bytes: ${hits[*]}" \
            "normalize to LF (e.g. sed -i 's/\\r\$//' <file>) or reinstall via 'ccds update'"
    fi
}

doc_check_claude_block() {
    local md="$HOME/.claude/CLAUDE.md"
    if [[ ! -f "$md" ]]; then
        doc_line FAIL claude-md-block "$md not found -- the ccds pointer block is not installed" "run 'ccds setup'"
        return
    fi
    local nb ne
    nb="$(grep -cF '# >>> ccds >>>' "$md" || true)"
    ne="$(grep -cF '# <<< ccds <<<' "$md" || true)"
    if [[ "$nb" == "1" && "$ne" == "1" ]]; then
        doc_line OK claude-md-block "exactly one ccds marker block in $md"
    else
        doc_line FAIL claude-md-block \
            "expected exactly one ccds block in $md; found $nb begin / $ne end marker(s)" \
            "run 'ccds setup' (it strips duplicate/broken blocks and reinjects a single fresh one)"
    fi
}

doc_check_catalog() {
    local cat="$LIBRARY_ROOT/catalog.json"
    if [[ ! -f "$cat" ]]; then
        doc_line FAIL catalog "catalog.json not found at $cat" \
            "reinstall via 'ccds update' (or regenerate with scripts/build-catalog.py in a repo clone)"
        return
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        doc_line WARN catalog \
            "$cat present; python3 not found so JSON validity was not checked" \
            "install python3 to enable the parse check"
        return
    fi
    if python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$cat" >/dev/null 2>&1; then
        doc_line OK catalog "$cat parses as valid JSON"
    else
        doc_line FAIL catalog "$cat is not valid JSON" \
            "regenerate with scripts/build-catalog.py or reinstall via 'ccds update'"
    fi
}

doc_check_path_duals() {
    local resolved dual=0
    resolved="$(command -v ccds 2>/dev/null || true)"
    [[ -d /usr/share/ccds && -d "$HOME/.claude/playbook" ]] && dual=1
    if (( dual )); then
        doc_line WARN path-and-duals \
            "both /usr/share/ccds (system package) and $HOME/.claude/playbook (per-user) are installed; this shell runs: ${resolved:-<none -- ccds not on PATH>}" \
            "keep one install: 'sudo apt remove ccds' for the system package, or 'ccds uninstall' from the per-user copy"
    elif [[ -z "$resolved" ]]; then
        doc_line WARN path-and-duals \
            "'ccds' is not resolvable on PATH (this run used $SCRIPT_PATH)" \
            "add $BIN_DIR to PATH (the installer normally does this) or re-run the installer"
    else
        doc_line OK path-and-duals "ccds resolves to $resolved"
    fi
}

cmd_doctor() {
    # Registry: check-name -> check function. Adding a check = one function
    # plus one row here.
    local -a checks=(
        "layout:doc_check_layout"
        "version:doc_check_version"
        "agents-installed:doc_check_agents"
        "skills-installed:doc_check_skills"
        "bom-scan:doc_check_bom"
        "crlf-scan:doc_check_crlf"
        "claude-md-block:doc_check_claude_block"
        "catalog:doc_check_catalog"
        "path-and-duals:doc_check_path_duals"
    )

    echo "ccds doctor -- environment checks (version $(installed_version), $LAYOUT_KIND layout)"
    echo
    local entry
    for entry in "${checks[@]}"; do
        "${entry#*:}"
    done
    echo
    echo '=== ccds doctor summary ==='
    printf 'OK    : %d\nWARN  : %d\nFAIL  : %d\n' "$DOC_OK" "$DOC_WARN" "$DOC_FAIL"
    if (( DOC_FAIL > 0 )); then
        echo 'RESULT: FAIL'
        exit 1
    fi
    echo 'RESULT: PASS'
    exit 0
}

cmd_lint() {
    local lint_script="$INSTALL_ROOT/scripts/lint-playbook.py"
    if [[ ! -f "$lint_script" ]]; then
        echo "ERROR: lint-playbook.py not found at $lint_script" >&2
        echo "       'ccds lint' validates the library source; run it from a repo clone." >&2
        exit 2
    fi
    command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required for lint" >&2; exit 2; }
    exec python3 "$lint_script" "$INSTALL_ROOT"
}

# Scaffold the long-horizon loop state-file kit (loop-long-horizon skill).
cmd_loop() {
    local sub="${POSITIONAL[0]:-}"
    if [[ "$sub" != "init" ]]; then
        echo "ERROR: unknown loop subcommand '${sub:-<none>}'. Usage: ccds loop init [--target <path>] [--dry-run]" >&2
        exit 2
    fi
    local target="${TARGET:-$PWD}"
    local loop_dir="$target/.loop"

    if [[ -e "$loop_dir" ]]; then
        echo "ERROR: $loop_dir already exists -- refusing to overwrite an existing kit." >&2
        echo "       Remove or rename it first if you really want to re-init." >&2
        exit 2
    fi
    if (( DRY_RUN )); then
        echo "DRY RUN -- would create $loop_dir/ with feature_list.json, progress.md, PROMPT.md, init.sh"
        return
    fi

    mkdir -p "$loop_dir"

    cat > "$loop_dir/feature_list.json" <<'EOF'
{
  "features": [
    {
      "id": "example-feature",
      "description": "Replace me: one observable behavior, phrased so its absence is detectable",
      "verify": "replace me: the command that proves this feature works",
      "priority": 1,
      "passes": false
    }
  ]
}
EOF

    cat > "$loop_dir/progress.md" <<'EOF'
# Loop progress log

Append-only. One entry per iteration, newest last. The "why" line is the one that
stops the next iteration from re-walking this one's dead ends.

<!-- entry template:
## <date> · iteration <n> · <feature-id>
- Done: <what, with the verify evidence>
- Why it took a detour: <the non-obvious part>
- Next: <feature-id or note>
-->
EOF

    cat > "$loop_dir/PROMPT.md" <<'EOF'
Work on the project in this directory. THE ONE UNBREAKABLE RULE: exactly ONE
feature this run. Finishing early does not earn a second one.

1. Read .loop/progress.md and .loop/feature_list.json. Run .loop/init.sh;
   if it fails, fixing it is this iteration's ONLY task.
2. Pick the ONE highest-priority feature with "passes": false. That id is
   the only feature you may touch this run. Search the codebase first — do
   not re-implement something that exists.
3. Implement it COMPLETELY. No placeholders, no stubs, no simplified
   versions. A stub that compiles is a failure, not progress.
4. Run the feature's verify command and read the output. Only then set
   "passes": true.
5. Append an entry (what / why / next) to .loop/progress.md. Commit with a
   message naming the feature id.
6. STOP. If other features remain "passes": false, do NOT start one — not
   even a small one; the loop runs again with fresh context. End your reply
   with exactly: ITERATION DONE
7. Only if EVERY feature now has "passes": true, output exactly:
   ALL FEATURES COMPLETE
EOF

    cat > "$loop_dir/init.sh" <<'EOF'
#!/usr/bin/env bash
# Health check: must prove the project still BUILDS and minimally RUNS.
# Replace the placeholders with this project's real commands.
set -euo pipefail
echo "TODO: replace with this project's build command" >&2
echo "TODO: replace with this project's smoke check (the app actually serves/runs)" >&2
exit 1
EOF
    chmod +x "$loop_dir/init.sh" 2>/dev/null || true  # exec bits unreliable on NTFS mounts

    cat <<EOF
==> Loop kit created in $loop_dir

Next steps:
  1. Fill .loop/feature_list.json with every unit of work (all "passes": false).
  2. Make .loop/init.sh actually build + smoke-check this project.
  3. Run the loop, capped -- never unbounded:

     for i in \$(seq 1 40); do
       cat .loop/PROMPT.md | claude -p --dangerously-skip-permissions && \\
         grep -q '"passes": false' .loop/feature_list.json || break
     done

     or with the ralph-wiggum plugin:
     /ralph-loop "\$(cat .loop/PROMPT.md)" --max-iterations 40 --completion-promise "ALL FEATURES COMPLETE"

  Unattended runs belong in a sandbox (container/VM/worktree). See the
  loop-long-horizon skill for the full discipline.
EOF
}

INSTALLER_URL_SH='https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/install-playbook.sh'

fetch_installer() {
    local out="$1"
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required for update/uninstall" >&2; exit 2; }
    echo "==> Fetching installer from main"
    if ! curl -fsSL -H "User-Agent: ccds-dispatcher" -o "$out" "$INSTALLER_URL_SH"; then
        echo "ERROR: Failed to download installer from $INSTALLER_URL_SH" >&2
        exit 2
    fi
    chmod +x "$out"
}

cmd_update() {
    if [[ "$LAYOUT_KIND" == "package" ]]; then
        echo "This installation is managed by your system package manager."
        echo "To update: sudo apt upgrade ccds  (Debian/Ubuntu)"
        echo "           sudo dnf upgrade ccds   (RHEL/Fedora)"
        exit 0
    fi

    local tmp
    tmp="$(mktemp -t install-playbook.XXXXXXXX.sh)"
    trap 'rm -f "$tmp"' EXIT

    fetch_installer "$tmp"

    local -a args=(--prefix "$INSTALL_ROOT")
    if (( ROLLBACK )); then
        args+=(--rollback)
    else
        local requested="${POSITIONAL[0]:-latest}"
        args+=(--version "$requested" --force)
        (( INCLUDE_PRERELEASE )) && args+=(--include-prerelease)
    fi

    bash "$tmp" "${args[@]}"
    exit "$?"
}

cmd_uninstall() {
    if [[ "$LAYOUT_KIND" == "package" ]]; then
        echo "This installation is managed by your system package manager."
        echo "To remove: sudo apt remove ccds   (Debian/Ubuntu)"
        echo "           sudo dnf remove ccds    (RHEL/Fedora)"
        exit 0
    fi

    local tmp
    tmp="$(mktemp -t install-playbook.XXXXXXXX.sh)"
    trap 'rm -f "$tmp"' EXIT

    fetch_installer "$tmp"
    bash "$tmp" --prefix "$INSTALL_ROOT" --uninstall
    exit "$?"
}

# ---------------------------------------------------------------------------
# Dispatch
# Strip any trailing \r so the dispatcher works even if the script has
# Windows line endings (CRLF) baked in from the build host.
# ---------------------------------------------------------------------------
COMMAND="${COMMAND//$'\r'/}"

if   [[ "$COMMAND" == "setup"     ]]; then cmd_setup
elif [[ "$COMMAND" == "sync"      ]]; then cmd_sync
elif [[ "$COMMAND" == "verify"    ]]; then cmd_verify
elif [[ "$COMMAND" == "doctor"    ]]; then cmd_doctor
elif [[ "$COMMAND" == "lint"      ]]; then cmd_lint
elif [[ "$COMMAND" == "loop"      ]]; then cmd_loop
elif [[ "$COMMAND" == "update"    ]]; then cmd_update
elif [[ "$COMMAND" == "uninstall" ]]; then cmd_uninstall
else
    echo "ERROR: Unknown command: $COMMAND. Run 'ccds help' for usage." >&2
    exit 2
fi
