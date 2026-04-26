#!/usr/bin/env bash
# ccds-user-setup.sh
# ------------------
# Performs per-user Claude Code Dev Studio setup:
#   1. Copies the 7 generalist agents to ~/.claude/agents/
#   2. Injects / updates the JIT protocol block in ~/.claude/CLAUDE.md
#
# Called by:
#   - install-playbook.sh  (after promoting the install tree)
#   - ccds setup           (dispatcher, package installs and manual re-runs)
#
# Usage: ccds-user-setup.sh <install_root> [--dry-run]
#
# <install_root> must contain:
#   agents/<name>.md   for each generalist
#   scripts/jit-claude.md

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
INSTALL_ROOT="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

[[ -n "$INSTALL_ROOT" ]] || { echo "ERROR: usage: ccds-user-setup.sh <install_root> [--dry-run]" >&2; exit 2; }
[[ -d "$INSTALL_ROOT" ]] || { echo "ERROR: install_root does not exist: $INSTALL_ROOT" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'; C_RESET=$'\033[0m'
[[ -t 1 ]] || { C_GREEN=''; C_YELLOW=''; C_RESET=''; }

log_step() { printf '==> %s\n' "$1"; }
log_ok()   { printf "${C_GREEN}OK  %s${C_RESET}\n" "$1"; }
log_warn() { printf "${C_YELLOW}!!  %s${C_RESET}\n" "$1" >&2; }
log_info() { printf '    %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Generalist agent list (must match Install-Playbook.ps1 $Script:GeneralistAgents)
# ---------------------------------------------------------------------------
GENERALIST_AGENTS=(
    api-expert
    deploy-checklist
    plan-architect
    pr-code-reviewer
    secure-auditor
    test-writer-runner
    ux-design-critic
)

# ---------------------------------------------------------------------------
# Step 1 — Copy generalist agents to ~/.claude/agents/
# ---------------------------------------------------------------------------
install_generalist_agents() {
    local src_dir="$INSTALL_ROOT/agents"
    local dst_dir="$HOME/.claude/agents"

    if (( DRY_RUN )); then
        log_info "DRY RUN -- would copy ${#GENERALIST_AGENTS[@]} generalist agents to $dst_dir"
        return
    fi

    mkdir -p "$dst_dir"
    local copied=0
    for name in "${GENERALIST_AGENTS[@]}"; do
        local src="$src_dir/${name}.md"
        local dst="$dst_dir/${name}.md"
        if [[ -f "$src" ]]; then
            cp -f "$src" "$dst"
            copied=$(( copied + 1 ))
        else
            log_warn "Generalist agent not found in package: agents/${name}.md"
        fi
    done
    log_ok "Copied $copied/${#GENERALIST_AGENTS[@]} generalist agents to $dst_dir"
}

# ---------------------------------------------------------------------------
# Step 2 — Inject / update JIT block in ~/.claude/CLAUDE.md
# ---------------------------------------------------------------------------
MARKER_BEGIN='# >>> ccds >>>'
MARKER_END='# <<< ccds <<<'

set_claude_playbook_block() {
    local jit_src="$INSTALL_ROOT/scripts/jit-claude.md"
    local claude_home="$HOME/.claude"
    local claude_md="$claude_home/CLAUDE.md"

    if (( DRY_RUN )); then
        log_info "DRY RUN -- would inject/update JIT block in $claude_md"
        return
    fi

    if [[ ! -f "$jit_src" ]]; then
        log_warn "jit-claude.md not found at $jit_src -- skipping CLAUDE.md injection"
        return
    fi

    local block_content
    block_content="$(cat "$jit_src")"

    mkdir -p "$claude_home"
    [[ -f "$claude_md" ]] || touch "$claude_md"

    local tmp
    tmp="$(mktemp)"

    if grep -qF "$MARKER_BEGIN" "$claude_md"; then
        # Replace existing block in place
        awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" -v block="$block_content" '
            BEGIN { in_block=0; printed=0 }
            $0 == b { in_block=1; if (!printed) { print block; printed=1 } next }
            $0 == e { in_block=0; next }
            in_block { next }
            { print }
        ' "$claude_md" > "$tmp"
        mv "$tmp" "$claude_md"
        log_ok "Updated JIT block in $claude_md"
    else
        # Append block
        {
            cat "$claude_md"
            printf '\n%s\n' "$block_content"
        } > "$tmp"
        mv "$tmp" "$claude_md"
        log_ok "Injected JIT block into $claude_md"
    fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
log_step "Installing generalist agents to $HOME/.claude/agents"
install_generalist_agents

log_step "Updating JIT block in $HOME/.claude/CLAUDE.md"
set_claude_playbook_block

if (( DRY_RUN )); then
    printf '\n%sDRY RUN -- no changes made.%s\n' "$C_YELLOW" "$C_RESET"
else
    printf '\n%sUser setup complete.%s\n' "$C_GREEN" "$C_RESET"
    printf 'Generalists : %s/.claude/agents/ (%d agents)\n' "$HOME" "${#GENERALIST_AGENTS[@]}"
    printf 'JIT block   : %s/.claude/CLAUDE.md\n' "$HOME"
fi
