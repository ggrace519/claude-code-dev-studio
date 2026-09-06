#!/usr/bin/env bash
# ccds-user-setup.sh
# ------------------
# Performs per-user Claude Code Dev Studio setup (ADR-0007):
#   0. Detects enabled ccds content plugins; if any, steps 1-1b are skipped
#      (the plugins already supply that roster -- ADR-0020)
#   1. Copies all 19 always-on agents to ~/.claude/agents/
#   2. Copies the cross-cutting (global) skills to ~/.claude/skills/
#   3. Injects / updates the ccds pointer block in ~/.claude/CLAUDE.md
#   4. Installs the enforcement plugins (ccds-guard, ccds-loops)
#
# Called by:
#   - install-playbook.sh  (after promoting the install tree)
#   - ccds setup           (dispatcher, package installs and manual re-runs)
#   - packaging/postinst   (deb/rpm, via ccds setup's script)
#
# Step 4 lives HERE, not in the installers, because this script is the one
# thing every outlet funnels through (ADR-0016). It used to live only in
# install-playbook.sh / Install-Playbook.ps1, so .deb/.rpm and `ccds setup`
# users silently ran with no ccds-guard and no ccds-loops at all.
#
# Usage: ccds-user-setup.sh <install_root> [--dry-run] [--skip-plugins]
#
# <install_root> must contain:
#   agents/<name>.md           for each always-on agent
#   skills/<name>/SKILL.md      for each skill (global ones are copied to ~/.claude/skills)
#   scripts/jit-claude.md

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
usage() {
    echo "usage: ccds-user-setup.sh <install_root> [--dry-run] [--skip-plugins]" >&2
}

INSTALL_ROOT="${1:-}"
shift || true
DRY_RUN=0
SKIP_PLUGINS=0
# Flags in any order. An unknown flag is an error, not a silent no-op: the old
# positional form ([[ "$2" == --dry-run ]]) would have ignored a misspelled
# --dry-run and made real changes.
while (( $# )); do
    case "$1" in
        --dry-run)      DRY_RUN=1; shift ;;
        --skip-plugins) SKIP_PLUGINS=1; shift ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

[[ -n "$INSTALL_ROOT" ]] || { echo "ERROR: install_root is required" >&2; usage; exit 2; }
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
    inventive-engineer
    common-a11y
    common-i18n
    common-privacy
    common-notifications
    common-product-analytics
    loop-verify
    loop-debug
    loop-review
    loop-parallel
    loop-long-horizon
    loop-compound
)

# ---------------------------------------------------------------------------
# Enforcement plugins (ADR-0012): plugins are the ONLY hook-shipping mechanism.
# Source is the GitHub repo, the same one the marketplace docs name — both are
# overridable so tests never touch a real marketplace or a real CLI.
# ---------------------------------------------------------------------------
MARKETPLACE_SOURCE="${CCDS_MARKETPLACE_SOURCE:-ggrace519/claude-code-dev-studio}"
CLAUDE_CMD="${CCDS_CLAUDE_CMD:-claude}"
ENFORCEMENT_PLUGINS=(ccds-guard ccds-loops)

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
# Step 4 — Install the enforcement plugins (ccds-guard, ccds-loops)
#
# Best-effort by contract: a failure here warns with the exact manual commands
# and never fails setup. Half a playbook beats a failed install — but a silent
# half is what ADR-0016 exists to prevent, so every outcome is reported.
# ---------------------------------------------------------------------------
PLUGINS_STATUS="skipped (--skip-plugins)"

install_plugins() {
    if (( SKIP_PLUGINS )); then
        log_info "Skipping enforcement plugins (--skip-plugins)"
        return
    fi
    if (( DRY_RUN )); then
        PLUGINS_STATUS="dry run"
        log_info "DRY RUN -- would run:"
        log_info "  $CLAUDE_CMD plugin marketplace add $MARKETPLACE_SOURCE"
        for plugin in "${ENFORCEMENT_PLUGINS[@]}"; do
            log_info "  $CLAUDE_CMD plugin install ${plugin}@ccds --scope user"
        done
        return
    fi
    if ! command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
        PLUGINS_STATUS="skipped (claude CLI not on PATH)"
        log_warn "claude CLI not found -- skipping plugin install."
        log_warn "Without these, this install has no security guard and no loop"
        log_warn "enforcement. After installing Claude Code, run:"
        log_warn "  claude plugin marketplace add $MARKETPLACE_SOURCE"
        for plugin in "${ENFORCEMENT_PLUGINS[@]}"; do
            log_warn "  claude plugin install ${plugin}@ccds --scope user"
        done
        return
    fi
    # `marketplace add` fails when the marketplace is already registered. That
    # registration may predate a plugin (ccds-guard did not always exist), so
    # refresh rather than assume the catalog knows about both.
    if ! "$CLAUDE_CMD" plugin marketplace add "$MARKETPLACE_SOURCE" </dev/null >/dev/null 2>&1; then
        log_info "marketplace 'ccds' already registered; refreshing catalog"
        "$CLAUDE_CMD" plugin marketplace update ccds </dev/null >/dev/null 2>&1 \
            || log_warn "could not refresh marketplace 'ccds'; plugin installs may see a stale catalog"
    fi
    PLUGINS_STATUS="installed (${ENFORCEMENT_PLUGINS[*]})"
    for plugin in "${ENFORCEMENT_PLUGINS[@]}"; do
        if "$CLAUDE_CMD" plugin install "${plugin}@ccds" --scope user </dev/null >/dev/null 2>&1; then
            log_ok "${plugin} plugin installed (user scope)"
        else
            PLUGINS_STATUS="partial -- see warnings"
            log_warn "Could not install ${plugin} automatically. Run:"
            log_warn "  claude plugin install ${plugin}@ccds --scope user"
        fi
    done
}

# ---------------------------------------------------------------------------
# Step 0 — Which route supplies the always-on roster?  (ADR-0020)
#
# The 19 agents and the cross-cutting skills reach Claude Code by ONE of two
# routes: the ccds content plugins (ccds-core + the archetype packs, installed
# from the marketplace) or the file copies steps 1/1b write. Both at once puts
# every agent in the roster twice -- the router sees two identical
# descriptions, the stale file copy owns the bare name, and the descriptions
# cost context twice. So when a content plugin is enabled, the copies are
# skipped. Detection is a read-only `claude plugin list --json`; it is not run
# under --skip-plugins (never touch the CLI) or --dry-run (no calls at all).
# `ccds doctor` reports the overlap either way.
# ---------------------------------------------------------------------------
CONTENT_PLUGINS=""

detect_content_plugins() {
    (( SKIP_PLUGINS || DRY_RUN )) && return 0
    command -v "$CLAUDE_CMD" >/dev/null 2>&1 || return 0
    local json
    json="$("$CLAUDE_CMD" plugin list --json </dev/null 2>/dev/null)" || return 0
    # The CLI pretty-prints one field per line: collapse newlines FIRST, then
    # split into one object per line, keep enabled ones, take the "<name>@" id
    # prefix, and drop the hooks-only enforcement pair.
    CONTENT_PLUGINS="$(printf '%s' "$json" | tr -d '\n\r' | tr '{' '\n' \
        | grep '"enabled"[[:space:]]*:[[:space:]]*true' \
        | grep -o '"id"[[:space:]]*:[[:space:]]*"ccds-[a-z]*@' \
        | sed -e 's/.*"\(ccds-[a-z]*\)@/\1/' \
        | grep -v -x -e ccds-guard -e ccds-loops \
        | sort -u | tr '\n' ' ' | sed -e 's/ $//' || true)"
}

# Stale file copies next to enabled plugins: say so, with the exact removal
# command, but never delete a user's files from setup.
warn_stale_file_copies() {
    local -a agent_files=() skill_dirs=()
    local src name
    for src in "$INSTALL_ROOT"/agents/*.md; do
        [[ -f "$src" ]] || continue
        name="$(basename "$src")"
        [[ -f "$HOME/.claude/agents/$name" ]] && agent_files+=("$name")
    done
    for name in "${GLOBAL_SKILLS[@]}"; do
        [[ -f "$HOME/.claude/skills/$name/SKILL.md" ]] && skill_dirs+=("$name")
    done
    (( ${#agent_files[@]} == 0 && ${#skill_dirs[@]} == 0 )) && return 0
    log_warn "File copies from an earlier setup are still present and are loaded in ADDITION to the plugins:"
    log_warn "  ${#agent_files[@]} agent file(s) in $HOME/.claude/agents, ${#skill_dirs[@]} cross-cutting skill(s) in $HOME/.claude/skills"
    log_warn "Remove them (the plugins keep working):"
    if (( ${#agent_files[@]} > 0 )); then
        log_warn "  rm -f $(printf "$HOME/.claude/agents/%s " "${agent_files[@]}")"
    fi
    if (( ${#skill_dirs[@]} > 0 )); then
        log_warn "  rm -rf $(printf "$HOME/.claude/skills/%s " "${skill_dirs[@]}")"
    fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
detect_content_plugins
if [[ -n "$CONTENT_PLUGINS" ]]; then
    log_step "Always-on agents and cross-cutting skills"
    log_ok "Supplied by enabled plugin(s): $CONTENT_PLUGINS -- skipping the file copies so Claude Code does not load the roster twice"
    warn_stale_file_copies
else
    log_step "Installing always-on agents to $HOME/.claude/agents"
    install_agents

    log_step "Installing cross-cutting skills to $HOME/.claude/skills"
    install_global_skills
fi

log_step "Updating ccds block in $HOME/.claude/CLAUDE.md"
set_claude_playbook_block

log_step "Installing enforcement plugins (${ENFORCEMENT_PLUGINS[*]})"
install_plugins

if (( DRY_RUN )); then
    printf '\n%sDRY RUN -- no changes made.%s\n' "$C_YELLOW" "$C_RESET"
else
    printf '\n%sUser setup complete.%s\n' "$C_GREEN" "$C_RESET"
    if [[ -n "$CONTENT_PLUGINS" ]]; then
        printf 'Agents      : from plugins (%s)\n' "$CONTENT_PLUGINS"
        printf 'Skills      : from plugins (%s)\n' "$CONTENT_PLUGINS"
    else
        printf 'Agents      : %s/.claude/agents/ (19 always-on)\n' "$HOME"
        printf 'Skills      : %s/.claude/skills/ (%d cross-cutting)\n' "$HOME" "${#GLOBAL_SKILLS[@]}"
    fi
    printf 'ccds block  : %s/.claude/CLAUDE.md\n' "$HOME"
    printf 'Plugins     : %s\n' "$PLUGINS_STATUS"
fi
