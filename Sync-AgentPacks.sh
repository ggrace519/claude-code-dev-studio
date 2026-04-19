#!/usr/bin/env bash
# Sync-AgentPacks.sh
# ------------------
# *nix port of Sync-AgentPacks.ps1. Activates Claude Code agent packs from the
# dev-studio library into a target project. Mirrors the PS1 feature set:
#
#   - Pack selection by prefix
#   - Generalists-included-by-default (--no-generalists to skip)
#   - Copy and Symlink modes (symlinks on *nix don't need elevation)
#   - Manifest-tracked idempotence (.pack-manifest.json, same schema as PS1)
#   - Dry-run preview
#   - Optional activation-ADR emission
#   - Library-self-target guard (--allow-library-target override)
#
# Canonical design rationale: DECISIONS.md ADR-0004.
# Manifest schema contract: interchangeable with Sync-AgentPacks.ps1 output.
#
# Requirements: bash 4+, realpath, standard POSIX tools (cp, rm, mkdir, find,
# sort, date).

set -euo pipefail

# ---------------------------------------------------------------------------
# Config / defaults
# ---------------------------------------------------------------------------

SCHEMA_VERSION=1
LIBRARY_ROOT_DEFAULT="${CLAUDE_CODE_DEV_STUDIO:-$HOME/coding-projects/claude-code-dev-studio}"

VALID_PREFIXES=(game saas mobile ai dataplat ecom fintech devtool desktop ext embed media orch infra common)

MODE="copy"
NO_GENERALISTS=0
DRY_RUN=0
WRITE_ADR=0
ALLOW_LIBRARY_TARGET=0
LIBRARY_ROOT="$LIBRARY_ROOT_DEFAULT"
TARGET_PROJECT=""
PACKS_CSV=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
Usage: Sync-AgentPacks.sh --target-project PATH --packs LIST [options]

Activate Claude Code agent packs from the dev-studio library into a target
project. Mirrors Sync-AgentPacks.ps1 — see DECISIONS.md ADR-0004.

Required:
  --target-project PATH   Project root (absolute path recommended).
  --packs LIST            Comma-separated pack prefixes, no trailing hyphen.
                          Valid: game, saas, mobile, ai, dataplat, ecom,
                                 fintech, devtool, desktop, ext, embed, media,
                                 orch, infra, common

Options:
  --library-root PATH     Override library location.
                          Default: $CLAUDE_CODE_DEV_STUDIO env var, or
                          ~/coding-projects/claude-code-dev-studio
  --mode MODE             copy (default) or symlink
  --no-generalists        Skip the 7 generalist agents
  --dry-run               Show plan without writing
  --write-adr             Append activation ADR to <target>/DECISIONS.md
  --allow-library-target  Override self-target guard (not recommended)
  -h, --help              Show this help

Examples:
  # Activate SaaS + common for a new project, emit activation ADR:
  ./Sync-AgentPacks.sh --target-project ~/code/acme-saas --packs saas,common --write-adr

  # Preview before applying:
  ./Sync-AgentPacks.sh --target-project ~/code/game --packs game,common --dry-run

  # Switch packs on an existing project (manifest tracks removals):
  ./Sync-AgentPacks.sh --target-project ~/code/app --packs ai,common
EOF
}

err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN:  %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

# Portable realpath — fail clearly if not available.
resolve_path() {
    if command -v realpath >/dev/null 2>&1; then
        realpath "$1"
    else
        err "realpath not found. Install GNU coreutils (Linux: package coreutils; macOS: brew install coreutils)."
    fi
}

in_array() {
    local needle="$1"; shift
    local hay
    for hay in "$@"; do
        [[ "$hay" == "$needle" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Arg parsing (long-options; minimal short form for -h)
# ---------------------------------------------------------------------------

while (( $# > 0 )); do
    case "$1" in
        --target-project)   TARGET_PROJECT="$2"; shift 2 ;;
        --packs)            PACKS_CSV="$2"; shift 2 ;;
        --library-root)     LIBRARY_ROOT="$2"; shift 2 ;;
        --mode)             MODE="$2"; shift 2 ;;
        --no-generalists)   NO_GENERALISTS=1; shift ;;
        --dry-run)          DRY_RUN=1; shift ;;
        --write-adr)        WRITE_ADR=1; shift ;;
        --allow-library-target) ALLOW_LIBRARY_TARGET=1; shift ;;
        -h|--help)          usage; exit 0 ;;
        --)                 shift; break ;;
        -*)                 err "Unknown option: $1 (see --help)" ;;
        *)                  err "Unexpected positional arg: $1 (see --help)" ;;
    esac
done

[[ -n "$TARGET_PROJECT" ]] || { usage; err "--target-project is required"; }
[[ -n "$PACKS_CSV" ]]      || { usage; err "--packs is required"; }

case "$MODE" in
    copy|symlink) ;;
    *) err "--mode must be 'copy' or 'symlink' (got: $MODE)" ;;
esac

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------

[[ -d "$TARGET_PROJECT" ]] || err "TargetProject does not exist: $TARGET_PROJECT"
[[ -d "$LIBRARY_ROOT"   ]] || err "LibraryRoot does not exist: $LIBRARY_ROOT"

LIB_AGENTS="$LIBRARY_ROOT/.claude/agents"
TGT_CLAUDE="$TARGET_PROJECT/.claude"
TGT_AGENTS="$TGT_CLAUDE/agents"
MANIFEST="$TGT_AGENTS/.pack-manifest.json"

[[ -d "$LIB_AGENTS" ]] || err "Library agents folder not found: $LIB_AGENTS"

# --- Self-target guard (ADR-0004) ---------------------------------------------
RESOLVED_TARGET="$(resolve_path "$TARGET_PROJECT")"
RESOLVED_LIBRARY="$(resolve_path "$LIBRARY_ROOT")"
RESOLVED_TARGET="${RESOLVED_TARGET%/}"
RESOLVED_LIBRARY="${RESOLVED_LIBRARY%/}"

# Case-insensitive compare (macOS default FS is case-insensitive).
if [[ "${RESOLVED_TARGET,,}" == "${RESOLVED_LIBRARY,,}" ]]; then
    if (( ALLOW_LIBRARY_TARGET == 0 )); then
        err "TargetProject resolves to LibraryRoot ($RESOLVED_TARGET).
Refusing to sync the library onto itself -- a later re-run with a narrower
--packs list would delete library files based on the manifest written here.

If you really need this (e.g., the library IS your working project),
pass --allow-library-target. Not recommended."
    else
        warn "Self-target override active (--allow-library-target). Library at '$RESOLVED_LIBRARY' will be treated as a consumer project."
    fi
fi

# --- Parse and validate pack list ---------------------------------------------
IFS=',' read -r -a PACKS <<< "$PACKS_CSV"
for p in "${PACKS[@]}"; do
    p_trimmed="$(echo "$p" | tr -d '[:space:]')"
    [[ -n "$p_trimmed" ]] || continue
    if ! in_array "$p_trimmed" "${VALID_PREFIXES[@]}"; then
        err "Unknown pack: '$p_trimmed'. Valid: ${VALID_PREFIXES[*]}"
    fi
done

# ---------------------------------------------------------------------------
# Enumerate library + compute sets
# ---------------------------------------------------------------------------

# Library files (basenames only)
mapfile -t LIB_FILES < <(find "$LIB_AGENTS" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort)

# Generalists = files whose basename does NOT start with <known-prefix>-
GENERALISTS=()
for f in "${LIB_FILES[@]}"; do
    base="${f%.md}"
    is_pack=0
    for pfx in "${VALID_PREFIXES[@]}"; do
        if [[ "$base" == "$pfx-"* ]]; then
            is_pack=1; break
        fi
    done
    (( is_pack == 0 )) && GENERALISTS+=("$f")
done

# Desired set (associative array acting as hash-set)
declare -A DESIRED=()
if (( NO_GENERALISTS == 0 )); then
    for g in "${GENERALISTS[@]}"; do DESIRED["$g"]=1; done
fi
for p in "${PACKS[@]}"; do
    p_trimmed="$(echo "$p" | tr -d '[:space:]')"
    [[ -n "$p_trimmed" ]] || continue
    for f in "${LIB_FILES[@]}"; do
        base="${f%.md}"
        if [[ "$base" == "${p_trimmed}-"* ]]; then
            DESIRED["$f"]=1
        fi
    done
done

# ---------------------------------------------------------------------------
# Load existing manifest (if any)
# ---------------------------------------------------------------------------

declare -A PREV=()
if [[ -f "$MANIFEST" ]]; then
    # Extract managedFiles entries; tolerate minor formatting variation.
    while IFS= read -r line; do
        [[ -n "$line" ]] && PREV["$line"]=1
    done < <(
        python3 - "$MANIFEST" 2>/dev/null <<'PY' || grep -oE '"[^"]+\.md"' "$MANIFEST" | tr -d '"'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    for n in d.get("managedFiles", []):
        print(n)
except Exception:
    sys.exit(1)
PY
    )
fi

# ---------------------------------------------------------------------------
# Compute deltas
# ---------------------------------------------------------------------------

TO_ADD=()
TO_REMOVE=()
TO_KEEP=()

# Sorted enumeration for stable output
mapfile -t ALL_NAMES < <(printf '%s\n' "${!DESIRED[@]}" "${!PREV[@]}" | sort -u)

for name in "${ALL_NAMES[@]}"; do
    in_desired=0; in_prev=0
    [[ -n "${DESIRED[$name]+x}" ]] && in_desired=1
    [[ -n "${PREV[$name]+x}"    ]] && in_prev=1
    if   (( in_desired == 1 && in_prev == 0 )); then TO_ADD+=("$name")
    elif (( in_desired == 0 && in_prev == 1 )); then TO_REMOVE+=("$name")
    elif (( in_desired == 1 && in_prev == 1 )); then TO_KEEP+=("$name")
    fi
done

# ---------------------------------------------------------------------------
# Plan output
# ---------------------------------------------------------------------------

echo
mode_label="$MODE"
[[ $DRY_RUN -eq 1 ]] && mode_label="$mode_label, DRY RUN"
gen_label="+ generalists"
[[ $NO_GENERALISTS -eq 1 ]] && gen_label="(no generalists)"

printf '=== Sync plan  [Mode=%s]\n' "$mode_label"
printf 'Library : %s\n' "$LIB_AGENTS"
printf 'Target  : %s\n' "$TGT_AGENTS"
printf 'Packs   : %s %s\n' "$PACKS_CSV" "$gen_label"
echo
printf '  + Add    : %d\n' "${#TO_ADD[@]}"
printf '  - Remove : %d\n' "${#TO_REMOVE[@]}"
printf '  = Keep   : %d\n' "${#TO_KEEP[@]}"

if (( ${#TO_ADD[@]} > 0 )); then
    echo '  Adding:'
    for n in "${TO_ADD[@]}"; do printf '    + %s\n' "$n"; done
fi
if (( ${#TO_REMOVE[@]} > 0 )); then
    echo '  Removing:'
    for n in "${TO_REMOVE[@]}"; do printf '    - %s\n' "$n"; done
fi

if (( DRY_RUN == 1 )); then
    echo
    echo 'DRY RUN - no changes made.'
    exit 0
fi

# ---------------------------------------------------------------------------
# Apply changes
# ---------------------------------------------------------------------------

mkdir -p "$TGT_AGENTS"

# Removes
for f in "${TO_REMOVE[@]}"; do
    rm -f -- "$TGT_AGENTS/$f"
done

# Adds
for f in "${TO_ADD[@]}"; do
    src="$LIB_AGENTS/$f"
    tgt="$TGT_AGENTS/$f"
    [[ -e "$tgt" || -L "$tgt" ]] && rm -f -- "$tgt"
    case "$MODE" in
        copy)    cp -- "$src" "$tgt" ;;
        symlink) ln -s -- "$src" "$tgt" ;;
    esac
done

# ---------------------------------------------------------------------------
# Write manifest (BOM-less UTF-8, same schema as PS1)
# ---------------------------------------------------------------------------

mapfile -t SORTED_MANAGED < <(printf '%s\n' "${!DESIRED[@]}" | sort)

# Hand-rolled JSON (no jq dep). Keys: schema, updated, libraryRoot, mode,
# packs, generalists, managedFiles.
IFS=',' read -r -a PACKS_ARR <<< "$PACKS_CSV"
PACKS_JSON_ELEMS=()
for p in "${PACKS_ARR[@]}"; do
    p_trimmed="$(echo "$p" | tr -d '[:space:]')"
    [[ -n "$p_trimmed" ]] && PACKS_JSON_ELEMS+=("\"$p_trimmed\"")
done
PACKS_JSON="$(IFS=,; echo "${PACKS_JSON_ELEMS[*]}")"

FILES_JSON_ELEMS=()
for n in "${SORTED_MANAGED[@]}"; do FILES_JSON_ELEMS+=("\"$n\""); done
FILES_JSON="$(IFS=,; echo "${FILES_JSON_ELEMS[*]}")"

GEN_BOOL=true
[[ $NO_GENERALISTS -eq 1 ]] && GEN_BOOL=false

MODE_CAPITAL="Copy"
[[ "$MODE" == "symlink" ]] && MODE_CAPITAL="Symlink"

UPDATED_ISO="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

# Emit without BOM. bash writes plain UTF-8 already; no BOM unless explicitly
# added. printf on Linux/macOS is BOM-free.
printf '{\n  "schema":  %s,\n  "updated":  "%s",\n  "libraryRoot":  "%s",\n  "mode":  "%s",\n  "packs":  [%s],\n  "generalists":  %s,\n  "managedFiles":  [%s]\n}\n' \
    "$SCHEMA_VERSION" "$UPDATED_ISO" "$LIBRARY_ROOT" "$MODE_CAPITAL" "$PACKS_JSON" "$GEN_BOOL" "$FILES_JSON" > "$MANIFEST"

echo
printf 'OK Sync complete. %d agents installed; manifest: %s\n' "${#DESIRED[@]}" "$MANIFEST"

# ---------------------------------------------------------------------------
# Optional ADR append (BOM-less UTF-8; same text pattern as PS1)
# ---------------------------------------------------------------------------

if (( WRITE_ADR == 1 )); then
    DECISIONS="$TARGET_PROJECT/DECISIONS.md"
    TODAY="$(date +%Y-%m-%d)"
    PACK_LIST=""
    for p in "${PACKS_ARR[@]}"; do
        p_trimmed="$(echo "$p" | tr -d '[:space:]')"
        [[ -z "$p_trimmed" ]] && continue
        [[ -n "$PACK_LIST" ]] && PACK_LIST="$PACK_LIST, "
        PACK_LIST="${PACK_LIST}\`${p_trimmed}-\`"
    done
    GEN_NOTE=" (plus generalists)"
    [[ $NO_GENERALISTS -eq 1 ]] && GEN_NOTE=""

    {
        echo ''
        echo '---'
        echo ''
        echo "## ADR - Activate agent packs ($TODAY)"
        echo ''
        echo "**Date:** $TODAY"
        echo '**Status:** Accepted'
        echo '**Phase:** Initialize'
        echo ''
        echo '### Context'
        echo "Project requires archetype-specific agent specialists in addition to the seven generalists shipped by the playbook. Library at \`$LIBRARY_ROOT\` provides 105 reusable agents; this project does not need all of them."
        echo ''
        echo '### Decision'
        echo "Activate the following packs: ${PACK_LIST}${GEN_NOTE}."
        echo ''
        echo "Sync mechanism: $MODE_CAPITAL (managed by \`Sync-AgentPacks.sh\`; see \`.claude/agents/.pack-manifest.json\`)."
        echo ''
        echo '### Consequences'
        echo "- ${#DESIRED[@]} agent files installed under \`.claude/agents/\`."
        echo '- Re-running the script with a different pack list adds/removes agents accordingly; files not listed in the manifest are left untouched.'
        echo '- Library updates are picked up by re-running the sync (copy mode) or automatically (symlink mode).'
    } >> "$DECISIONS"
    printf 'OK ADR appended to %s\n' "$DECISIONS"
fi
