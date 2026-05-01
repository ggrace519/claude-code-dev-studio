#!/usr/bin/env bash
# install-claude-completion.sh
# Installs the claude CLI bash completion script.
#
# Usage:
#   ./install-claude-completion.sh           # per-user install
#   sudo ./install-claude-completion.sh -s   # system-wide install

set -euo pipefail

SRC="$(dirname "$(readlink -f "$0")")/claude-completion.bash"
SCOPE="user"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--system) SCOPE="system" ;;
        -h|--help)
            sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: claude-completion.bash not found next to installer ($SRC)" >&2
    exit 1
fi

if [[ "$SCOPE" == "system" ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: system install requires root. Re-run with sudo." >&2
        exit 1
    fi
    DEST_DIR="/etc/bash_completion.d"
    DEST="$DEST_DIR/claude"
else
    DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
    DEST="$DEST_DIR/claude"
fi

mkdir -p "$DEST_DIR"
install -m 0644 "$SRC" "$DEST"

echo "Installed: $DEST"

# Verify bash-completion is available
if ! command -v _init_completion >/dev/null 2>&1; then
    if [[ -r /usr/share/bash-completion/bash_completion ]]; then
        echo "Note: bash-completion is installed but not loaded in this shell."
    else
        echo "WARNING: bash-completion package not found." >&2
        echo "  Debian/Ubuntu: sudo apt install bash-completion" >&2
    fi
fi

# Ensure completion is loaded in user's bashrc
if [[ "$SCOPE" == "user" ]] && [[ -f "$HOME/.bashrc" ]]; then
    if ! grep -q "bash-completion/bash_completion\|/etc/bash_completion" "$HOME/.bashrc" 2>/dev/null; then
        echo
        echo "Add the following to ~/.bashrc if completion does not load on next shell:"
        echo '  [[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion'
    fi
fi

echo
echo "Activate now with:  source \"$DEST\""
echo "Or open a new shell."
