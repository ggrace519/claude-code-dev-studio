#!/usr/bin/env bash
# ccds-user-setup.sh
# ------------------
# Performs per-user Claude Code Dev Studio setup (ADR-0007):
#   1. Copies all 19 always-on agents to ~/.claude/agents/
#   2. Copies the cross-cutting (global) skills to ~/.claude/skills/
#   3. Injects / updates the ccds pointer block in ~/.claude/CLAUDE.md
#
# Called by:
#   - install-playbook.sh  (after promoting the install tree)
#   - ccds setup           (dispatcher, package installs and manual re-runs)
#
# Usage: ccds-user-setup.sh <install_root> [--dry-run]
#
# <install_root> must contain:
#   agents/<name>.md           for each always-on agent
#   skills/<name>/SKILL.md      for each skill (global ones are copied to ~/.claude/skills)
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
# Cross-cutting skills installed globally to ~/.claude/skills/
# (must match Install-Playbook.ps1 $Script:GlobalSkills and catalog scope=global)
# ---------------------------------------------------------------------------
GLOBAL_SKILLS=(
    playbook-conventions
    sync-agents
    api-design
    ux-design
    security-checklist
    code-review-checklist
    common-a11y
    common-i18n
    common-privacy
    common-notifications
    common-product-analytics
)

# ---------------------------------------------------------------------------
# Step 1 — Copy all always-on agents to ~/.claude/agents/
# ---------------------------------------------------------------------------
install_agents() {
    local src_dir="$INSTALL_ROOT/agents"
    local dst_dir="$HOME/.claude/agents"
    local total
    total=$(find "$src_dir" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

    if (( DRY_RUN )); then
        log_info "DRY RUN -- would copy $total always-on agents to $dst_dir"
        return
    fi

    mkdir -p "$dst_dir"
    local copied=0
    for src in "$src_dir"/*.md; do
        [[ -f "$src" ]] || continue
        cp -f "$src" "$dst_dir/$(basename "$src")"
        copied=$(( copied + 1 ))
    done
    log_ok "Copied $copied always-on agents to $dst_dir"
}

# ---------------------------------------------------------------------------
# Step 1b — Copy cross-cutting (global) skills to ~/.claude/skills/
# ---------------------------------------------------------------------------
install_global_skills() {
    local src_dir="$INSTALL_ROOT/skills"
    local dst_dir="$HOME/.claude/skills"

    if (( DRY_RUN )); then
        log_info "DRY RUN -- would copy ${#GLOBAL_SKILLS[@]} cross-cutting skills to $dst_dir"
        return
    fi

    mkdir -p "$dst_dir"
    local copied=0
    for name in "${GLOBAL_SKILLS[@]}"; do
        local src="$src_dir/${name}"
        if [[ -d "$src" && -f "$src/SKILL.md" ]]; then
            rm -rf "${dst_dir:?}/${name}"
            cp -rf "$src" "$dst_dir/${name}"
            copied=$(( copied + 1 ))
        else
            log_warn "Global skill not found in package: skills/${name}/SKILL.md"
        fi
    done
    log_ok "Copied $copied/${#GLOBAL_SKILLS[@]} cross-cutting skills to $dst_dir"
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

    mkdir -p "$claude_home"
    [[ -f "$claude_md" ]] || touch "$claude_md"

    # Backup before any mutation. Timestamped so reinstalls keep history.
    local backup="$claude_md.ccds-backup-$(date +%Y%m%d-%H%M%S)"
    cp -p "$claude_md" "$backup"
    log_info "Backed up existing CLAUDE.md to $(basename "$backup")"

    local tmp
    tmp="$(mktemp)"

    # Strip ALL existing ccds blocks (handles duplicates, CRLF, trailing whitespace
    # on marker lines). Anything outside the markers is preserved verbatim.
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
        BEGIN { in_block=0 }
        {
            check = $0
            sub(/[[:space:]\r]+$/, "", check)
            if (check == b) { in_block=1; next }
            if (check == e) { in_block=0; next }
            if (!in_block) print
        }
    ' "$claude_md" > "$tmp"

    # Trim trailing blank lines from the surviving user content, then append
    # a single fresh ccds block separated by one blank line.
    local cleaned
    cleaned="$(mktemp)"
    awk 'NF { for (i=1;i<=hold;i++) print ""; hold=0; print; next }
         { hold++ }' "$tmp" > "$cleaned"

    if [[ -s "$cleaned" ]]; then
        printf '\n' >> "$cleaned"
    fi
    cat "$jit_src" >> "$cleaned"
    # Ensure file ends with a single newline.
    if [[ "$(tail -c1 "$cleaned" | od -An -c | tr -d ' ')" != '\n' ]]; then
        printf '\n' >> "$cleaned"
    fi

    # Canary: legacy installs (pre-marker era, or hand-edited) may have left
    # JIT content in CLAUDE.md without markers. We can't safely auto-strip it,
    # but we can warn so the user can clean up by hand or restore the backup.
    if grep -qF "## Playbook JIT Agent Loading" "$tmp"; then
        log_warn "Detected legacy 'Playbook JIT Agent Loading' content outside markers."
        log_warn "Inspect $claude_md and (if duplicated) restore from $(basename "$backup")."
    fi

    mv "$cleaned" "$claude_md"
    rm -f "$tmp"
    log_ok "Refreshed JIT block in $claude_md"
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
log_step "Installing always-on agents to $HOME/.claude/agents"
install_agents

log_step "Installing cross-cutting skills to $HOME/.claude/skills"
install_global_skills

log_step "Updating ccds block in $HOME/.claude/CLAUDE.md"
set_claude_playbook_block

if (( DRY_RUN )); then
    printf '\n%sDRY RUN -- no changes made.%s\n' "$C_YELLOW" "$C_RESET"
else
    printf '\n%sUser setup complete.%s\n' "$C_GREEN" "$C_RESET"
    printf 'Agents      : %s/.claude/agents/ (19 always-on)\n' "$HOME"
    printf 'Skills      : %s/.claude/skills/ (%d cross-cutting)\n' "$HOME" "${#GLOBAL_SKILLS[@]}"
    printf 'ccds block  : %s/.claude/CLAUDE.md\n' "$HOME"
fi
