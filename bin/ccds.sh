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
elif [[ "$COMMAND" == "lint"      ]]; then cmd_lint
elif [[ "$COMMAND" == "loop"      ]]; then cmd_loop
elif [[ "$COMMAND" == "update"    ]]; then cmd_update
elif [[ "$COMMAND" == "uninstall" ]]; then cmd_uninstall
else
    echo "ERROR: Unknown command: $COMMAND. Run 'ccds help' for usage." >&2
    exit 2
fi
