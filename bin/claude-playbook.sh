#!/usr/bin/env bash
# claude-playbook — Linux/macOS dispatcher
#
# Resolves paths relative to this script's location, then delegates to the
# Sync-AgentPacks.sh / verify-agents.sh scripts.
#
# Layout assumed:
#   <install-root>/
#     bin/claude-playbook         (this script)
#     scripts/Sync-AgentPacks.sh
#     scripts/verify-agents.sh
#     library/agents/*.md
#     version.txt
#
# Dev-repo layout is also detected (scripts at repo root, library at .claude/agents).

set -euo pipefail

# Resolve this script's real path even when symlinked
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "${BASH_SOURCE[0]}")"
BIN_DIR="$(dirname "$SCRIPT_PATH")"
INSTALL_ROOT="$(cd "$BIN_DIR/.." && pwd)"

# Detect layout
if [[ -f "$INSTALL_ROOT/scripts/Sync-AgentPacks.sh" ]]; then
    SYNC_SCRIPT="$INSTALL_ROOT/scripts/Sync-AgentPacks.sh"
    VERIFY_SCRIPT="$INSTALL_ROOT/scripts/verify-agents.sh"
    LIBRARY_ROOT="$INSTALL_ROOT"
    LAYOUT_KIND="installed"
elif [[ -f "$INSTALL_ROOT/Sync-AgentPacks.sh" ]]; then
    SYNC_SCRIPT="$INSTALL_ROOT/Sync-AgentPacks.sh"
    VERIFY_SCRIPT="$INSTALL_ROOT/verify-agents.sh"
    LIBRARY_ROOT="$INSTALL_ROOT"
    LAYOUT_KIND="dev"
else
    echo "ERROR: Cannot locate Sync-AgentPacks.sh under $INSTALL_ROOT" >&2
    exit 2
fi

installed_version() {
    if [[ -f "$INSTALL_ROOT/version.txt" ]]; then
        tr -d '[:space:]' < "$INSTALL_ROOT/version.txt"
    else
        echo "dev"
    fi
}

show_help() {
    cat <<EOF
claude-playbook -- Claude Code agent pack activator

USAGE
  claude-playbook <command> [arguments]

COMMANDS
  sync <packs>         Activate packs in the current directory (default: apply)
      --dry-run             Preview changes without writing
      --write-adr           Record activation as an ADR in DECISIONS.md
      --no-generalists      Exclude the 7 generalist agents
      --mode <copy|symlink> Sync mode (default: copy)
      --target <path>       Target project path (default: current directory)

  verify               Validate .claude/agents/ in the current directory
      --target <path>       Target path (default: current directory)

  update               Download and install the latest release
      --rollback            Restore the previous installed version

  uninstall            Remove the installation and PATH entries

  version              Print the installed version

  help                 Show this help

EXAMPLES
  claude-playbook sync saas,common
  claude-playbook sync saas,ai,common --write-adr
  claude-playbook sync game --dry-run
  claude-playbook verify
  claude-playbook --target /opt/foo verify

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
NO_GENERALISTS=0
MODE="copy"
TARGET=""
ROLLBACK=0
POSITIONAL=()

if (( $# == 0 )); then
    show_help
    exit 0
fi

COMMAND="$1"; shift

case "$COMMAND" in
    -h|--help|help)    show_help; exit 0 ;;
    --version|version) installed_version; exit 0 ;;
esac

while (( $# > 0 )); do
    case "$1" in
        --dry-run)        DRY_RUN=1; shift ;;
        --write-adr)      WRITE_ADR=1; shift ;;
        --no-generalists) NO_GENERALISTS=1; shift ;;
        --rollback)       ROLLBACK=1; shift ;;
        --mode)
            [[ -n "${2:-}" ]] || { echo "ERROR: --mode requires a value (copy|symlink)" >&2; exit 2; }
            MODE="$2"; shift 2 ;;
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
cmd_sync() {
    if (( ${#POSITIONAL[@]} < 1 )); then
        echo "ERROR: sync requires a pack list. Example: claude-playbook sync saas,common" >&2
        exit 2
    fi
    local packs="${POSITIONAL[0]}"
    local target="${TARGET:-$PWD}"

    local args=(
        --target-project "$target"
        --packs "$packs"
        --library-root "$LIBRARY_ROOT"
        --mode "$MODE"
    )
    (( DRY_RUN ))          && args+=(--dry-run)
    (( WRITE_ADR ))        && args+=(--write-adr)
    (( NO_GENERALISTS ))   && args+=(--no-generalists)

    exec "$SYNC_SCRIPT" "${args[@]}"
}

cmd_verify() {
    local target="${TARGET:-$PWD}"
    local agents_path="$target/.claude/agents"
    if [[ ! -d "$agents_path" ]]; then
        echo "ERROR: No .claude/agents/ found under $target" >&2
        exit 2
    fi
    exec "$VERIFY_SCRIPT" "$agents_path"
}

cmd_update() {
    if (( ROLLBACK )); then
        echo "rollback is implemented by install-playbook.sh."
    else
        echo "update is implemented by install-playbook.sh."
    fi
    cat <<EOF
This command will be wired up in the next session increment.

For now, re-run the bootstrap:
  curl -fsSL https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/install-playbook.sh | bash
EOF
}

cmd_uninstall() {
    echo "uninstall is implemented by install-playbook.sh."
    echo "This command will be wired up in the next session increment."
}

case "$COMMAND" in
    sync)      cmd_sync ;;
    verify)    cmd_verify ;;
    update)    cmd_update ;;
    uninstall) cmd_uninstall ;;
    *)
        echo "ERROR: Unknown command: $COMMAND. Run 'claude-playbook help' for usage." >&2
        exit 2
        ;;
esac
