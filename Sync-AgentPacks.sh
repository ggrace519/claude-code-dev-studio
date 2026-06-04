#!/usr/bin/env bash
# Sync-AgentPacks.sh  (ADR-0007)
# ------------------------------
# Activates Claude Code Dev Studio *domain skills* from the library into a target
# project's .claude/skills/. The 19 agents are always-on (installed globally), so this
# script no longer copies agents — it stages the per-project, JIT skill layer.
#
#   - Pack selection by prefix; copies only scope=project skills (<pack>-*).
#   - Cross-cutting skills (common-*, playbook-conventions, api-design, ux-design,
#     security-checklist, code-review-checklist) are GLOBAL (~/.claude/skills) and are
#     never staged per project.
#   - Manifest-tracked idempotence (.skill-manifest.json).
#   - --clean removes previously-staged skills. --dry-run previews. --write-adr logs it.
#
# Canonical rationale: DECISIONS.md ADR-0004 (mechanism) + ADR-0007 (skills model).
#
# Requirements: bash 4+, realpath, standard POSIX tools.

set -euo pipefail

SCHEMA_VERSION=2
LIBRARY_ROOT_DEFAULT="${CCDS_LIBRARY_ROOT:-$HOME/.claude/playbook}"
VALID_PREFIXES=(game saas mobile ai dataplat ecom fintech devtool desktop ext embed media orch infra)

DRY_RUN=0
WRITE_ADR=0
CLEAN=0
ALLOW_LIBRARY_TARGET=0
LIBRARY_ROOT="$LIBRARY_ROOT_DEFAULT"
TARGET_PROJECT=""
PACKS_CSV=""

usage() {
    cat <<'EOF'
Usage: Sync-AgentPacks.sh --target-project PATH --packs LIST [options]
       Sync-AgentPacks.sh --target-project PATH --clean

Stage Claude Code Dev Studio domain skills into a project's .claude/skills/.
The 19 agents are always-on (global); this stages the per-project skill layer.

Required (activate):
  --target-project PATH   Project root.
  --packs LIST            Comma-separated pack prefixes (no trailing hyphen).
                          Valid: game saas mobile ai dataplat ecom fintech devtool
                                 desktop ext embed media orch infra

Options:
  --library-root PATH     Override library (default: $CCDS_LIBRARY_ROOT or ~/.claude/playbook)
  --clean                 Remove all skills staged by a previous sync (per manifest)
  --dry-run               Show plan without writing
  --write-adr             Append an activation ADR to <target>/DECISIONS.md
  --allow-library-target  Override self-target guard
  -h, --help              Show this help

Examples:
  ./Sync-AgentPacks.sh --target-project ~/code/acme-saas --packs saas --write-adr
  ./Sync-AgentPacks.sh --target-project ~/code/app --packs ai,saas --dry-run
  ./Sync-AgentPacks.sh --target-project ~/code/app --clean
EOF
}

err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN:  %s\n' "$*" >&2; }

resolve_path() { command -v realpath >/dev/null 2>&1 && realpath "$1" || err "realpath not found (install coreutils)."; }
in_array() { local n="$1"; shift; local h; for h in "$@"; do [[ "$h" == "$n" ]] && return 0; done; return 1; }

while (( $# > 0 )); do
    case "$1" in
        --target-project)       TARGET_PROJECT="$2"; shift 2 ;;
        --packs)                PACKS_CSV="$2"; shift 2 ;;
        --library-root)         LIBRARY_ROOT="$2"; shift 2 ;;
        --clean)                CLEAN=1; shift ;;
        --dry-run)              DRY_RUN=1; shift ;;
        --write-adr)            WRITE_ADR=1; shift ;;
        --allow-library-target) ALLOW_LIBRARY_TARGET=1; shift ;;
        -h|--help)              usage; exit 0 ;;
        --)                     shift; break ;;
        -*)                     err "Unknown option: $1 (see --help)" ;;
        *)                      err "Unexpected positional arg: $1 (see --help)" ;;
    esac
done

[[ -n "$TARGET_PROJECT" ]] || { usage; err "--target-project is required"; }
(( CLEAN == 1 )) || [[ -n "$PACKS_CSV" ]] || { usage; err "--packs is required (or use --clean)"; }
[[ -d "$TARGET_PROJECT" ]] || err "TargetProject does not exist: $TARGET_PROJECT"

LIB_SKILLS="$LIBRARY_ROOT/skills"
TGT_SKILLS="$TARGET_PROJECT/.claude/skills"
MANIFEST="$TGT_SKILLS/.skill-manifest.json"

# --- Load previous manifest -------------------------------------------------
declare -A PREV=()
if [[ -f "$MANIFEST" ]]; then
    while IFS= read -r line; do [[ -n "$line" ]] && PREV["$line"]=1; done < <(
        python3 - "$MANIFEST" 2>/dev/null <<'PY' || grep -oE '"[a-z0-9-]+"' "$MANIFEST" | tr -d '"'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for n in d.get("managedSkills", []): print(n)
except Exception:
    sys.exit(1)
PY
    )
fi

# --- Clean mode -------------------------------------------------------------
if (( CLEAN == 1 )); then
    if (( ${#PREV[@]} == 0 )); then echo "Nothing to clean (no manifest)."; exit 0; fi
    echo "=== Clean plan"
    for n in "${!PREV[@]}"; do printf '    - %s\n' "$n"; done
    if (( DRY_RUN == 1 )); then echo; echo "DRY RUN - no changes made."; exit 0; fi
    for n in "${!PREV[@]}"; do rm -rf -- "${TGT_SKILLS:?}/$n"; done
    rm -f -- "$MANIFEST"
    printf 'OK Removed %d staged skills from %s\n' "${#PREV[@]}" "$TGT_SKILLS"
    exit 0
fi

[[ -d "$LIBRARY_ROOT" ]] || err "LibraryRoot does not exist: $LIBRARY_ROOT"
[[ -d "$LIB_SKILLS"   ]] || err "Library skills folder not found: $LIB_SKILLS"

# --- Self-target guard ------------------------------------------------------
RT="$(resolve_path "$TARGET_PROJECT")"; RL="$(resolve_path "$LIBRARY_ROOT")"
if [[ "${RT%/,,}" == "${RL%/,,}" || "${RT,,}" == "${RL,,}" ]] && (( ALLOW_LIBRARY_TARGET == 0 )); then
    err "TargetProject resolves to LibraryRoot. Refusing to sync onto the library (use --allow-library-target to override)."
fi

# --- Validate packs ---------------------------------------------------------
IFS=',' read -r -a PACKS <<< "$PACKS_CSV"
for p in "${PACKS[@]}"; do
    pt="$(echo "$p" | tr -d '[:space:]')"; [[ -n "$pt" ]] || continue
    in_array "$pt" "${VALID_PREFIXES[@]}" || err "Unknown pack: '$pt'. Valid: ${VALID_PREFIXES[*]}"
done

# --- Desired set: project-scoped skill dirs for the selected packs ----------
# A library skill is project-scoped if its dir name starts with <pack>- and the pack is
# a valid domain prefix (this excludes common-* and the global meta skills by design).
declare -A DESIRED=()
mapfile -t LIB_DIRS < <(find "$LIB_SKILLS" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
for d in "${LIB_DIRS[@]}"; do
    [[ -f "$LIB_SKILLS/$d/SKILL.md" ]] || continue
    for p in "${PACKS[@]}"; do
        pt="$(echo "$p" | tr -d '[:space:]')"; [[ -n "$pt" ]] || continue
        if [[ "$d" == "${pt}-"* ]]; then DESIRED["$d"]=1; fi
    done
done

# --- Compute deltas ---------------------------------------------------------
TO_ADD=(); TO_REMOVE=(); TO_KEEP=()
mapfile -t ALL_NAMES < <(printf '%s\n' "${!DESIRED[@]}" "${!PREV[@]}" | sort -u)
for name in "${ALL_NAMES[@]}"; do
    [[ -z "$name" ]] && continue
    ind=0; inp=0
    [[ -n "${DESIRED[$name]+x}" ]] && ind=1
    [[ -n "${PREV[$name]+x}"    ]] && inp=1
    if   (( ind && ! inp )); then TO_ADD+=("$name")
    elif (( ! ind && inp )); then TO_REMOVE+=("$name")
    elif (( ind && inp ));   then TO_KEEP+=("$name"); fi
done

echo
mode_label="copy"; (( DRY_RUN )) && mode_label="copy, DRY RUN"
printf '=== Sync plan  [Mode=%s]\n' "$mode_label"
printf 'Library : %s\n' "$LIB_SKILLS"
printf 'Target  : %s\n' "$TGT_SKILLS"
printf 'Packs   : %s\n' "$PACKS_CSV"
printf '  + Add    : %d\n  - Remove : %d\n  = Keep   : %d\n' "${#TO_ADD[@]}" "${#TO_REMOVE[@]}" "${#TO_KEEP[@]}"
(( ${#TO_ADD[@]}    )) && { echo '  Adding:';   for n in "${TO_ADD[@]}";    do printf '    + %s\n' "$n"; done; }
(( ${#TO_REMOVE[@]} )) && { echo '  Removing:'; for n in "${TO_REMOVE[@]}"; do printf '    - %s\n' "$n"; done; }

if (( DRY_RUN == 1 )); then echo; echo 'DRY RUN - no changes made.'; exit 0; fi

# --- Apply ------------------------------------------------------------------
mkdir -p "$TGT_SKILLS"
for n in "${TO_REMOVE[@]}"; do rm -rf -- "${TGT_SKILLS:?}/$n"; done
for n in "${TO_ADD[@]}"; do
    rm -rf -- "${TGT_SKILLS:?}/$n"
    cp -r -- "$LIB_SKILLS/$n" "$TGT_SKILLS/$n"
done

# --- Write manifest (BOM-less UTF-8) ----------------------------------------
mapfile -t SORTED < <(printf '%s\n' "${!DESIRED[@]}" | sort)
PACKS_JSON=""; for p in "${PACKS[@]}"; do pt="$(echo "$p" | tr -d '[:space:]')"; [[ -n "$pt" ]] && PACKS_JSON+="${PACKS_JSON:+,}\"$pt\""; done
FILES_JSON=""; for n in "${SORTED[@]}"; do FILES_JSON+="${FILES_JSON:+,}\"$n\""; done
UPDATED_ISO="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
printf '{\n  "schema": %s,\n  "updated": "%s",\n  "libraryRoot": "%s",\n  "packs": [%s],\n  "managedSkills": [%s]\n}\n' \
    "$SCHEMA_VERSION" "$UPDATED_ISO" "$LIBRARY_ROOT" "$PACKS_JSON" "$FILES_JSON" > "$MANIFEST"

echo
printf 'OK Sync complete. %d skills staged; manifest: %s\n' "${#DESIRED[@]}" "$MANIFEST"
printf '   (cross-cutting skills are global in ~/.claude/skills; the 19 agents are always-on)\n'
printf '   Restart or refresh the session so the new skills are discovered.\n'

# --- Optional ADR -----------------------------------------------------------
if (( WRITE_ADR == 1 )); then
    DECISIONS="$TARGET_PROJECT/DECISIONS.md"
    TODAY="$(date +%Y-%m-%d)"
    PACK_LIST=""; for p in "${PACKS[@]}"; do pt="$(echo "$p" | tr -d '[:space:]')"; [[ -n "$pt" ]] && PACK_LIST="${PACK_LIST:+$PACK_LIST, }\`${pt}\`"; done
    {
        echo ''; echo '---'; echo ''
        echo "## ADR - Activate domain skills ($TODAY)"; echo ''
        echo "**Date:** $TODAY"; echo '**Status:** Accepted'; echo '**Phase:** Initialize'; echo ''
        echo '### Context'
        echo "The 19 always-on agents are present globally; this project needs the domain skills for: ${PACK_LIST}."
        echo ''; echo '### Decision'
        echo "Stage the ${PACK_LIST} domain skills into \`.claude/skills/\` (managed by \`Sync-AgentPacks.sh\`; see \`.claude/skills/.skill-manifest.json\`)."
        echo ''; echo '### Consequences'
        echo "- ${#DESIRED[@]} skill folders staged under \`.claude/skills/\`."
        echo '- Re-running with a different pack list adds/removes skills per the manifest; `--clean` removes all staged skills.'
    } >> "$DECISIONS"
    printf 'OK ADR appended to %s\n' "$DECISIONS"
fi
