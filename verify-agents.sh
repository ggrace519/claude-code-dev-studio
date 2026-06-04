#!/usr/bin/env bash
# verify-agents.sh
# ----------------
# *nix port of Verify-Agents.ps1. Validates all .md agent files under
# .claude/agents/ (or a path passed as first positional arg).
#
# Rules (ADR-0001):
#   1. Filename is lowercase kebab-case (^[a-z0-9]+(-[a-z0-9]+)*\.md$)
#   2. No UTF-8 BOM (EF BB BF)
#   3. Valid YAML frontmatter block (---/--- fences at file start)
#   4. Frontmatter has non-empty 'name' and 'description'
#   5. Frontmatter 'name' matches filename basename
#   6. No duplicate 'name' across the corpus
#
# Exit codes:
#   0 = all files pass
#   1 = one or more validation failures
#   2 = config error (path missing, empty corpus)
#
# Usage:
#   ./verify-agents.sh [AGENTS_PATH] [--quiet]
#
# Requirements: bash 4+, awk, od, head, find.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUIET=0
AGENTS_PATH=""

for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=1 ;;
        -h|--help)
            cat <<EOF
Usage: verify-agents.sh [AGENTS_PATH] [--quiet]

Validate .md agent files against ADR-0001 invariants.

  AGENTS_PATH   Directory to scan. Default: .claude/agents relative to script.
  --quiet       Suppress per-file OK lines; failures and summary always print.
EOF
            exit 0
            ;;
        -*) echo "ERROR: Unknown option: $arg" >&2; exit 2 ;;
        *)  AGENTS_PATH="$arg" ;;
    esac
done

if [[ -z "$AGENTS_PATH" ]]; then
    AGENTS_PATH="$SCRIPT_DIR/.claude/agents"
fi

if [[ ! -d "$AGENTS_PATH" ]]; then
    echo "ERROR: Agents path not found: $AGENTS_PATH" >&2
    exit 2
fi

# Build parallel arrays covering both layouts (ADR-0007):
#   - agents : flat <name>.md          (expected frontmatter name = basename)
#   - skills : <name>/SKILL.md         (expected frontmatter name = parent dir)
# Detect skill layout by presence of */SKILL.md.
PATHS=(); EXPECTED=(); DISPLAY=()
mapfile -t _flat < <(find "$AGENTS_PATH" -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort)
mapfile -t _skills < <(find "$AGENTS_PATH" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -printf '%h\n' | sort)
for f in "${_flat[@]}"; do
    [[ -n "$f" ]] || continue
    PATHS+=("$AGENTS_PATH/$f"); EXPECTED+=("${f%.md}"); DISPLAY+=("$f")
done
for d in "${_skills[@]}"; do
    [[ -n "$d" ]] || continue
    base="$(basename "$d")"
    PATHS+=("$d/SKILL.md"); EXPECTED+=("$base"); DISPLAY+=("$base/SKILL.md")
done

if (( ${#PATHS[@]} == 0 )); then
    echo "ERROR: No agent (.md) or skill (SKILL.md) files found under $AGENTS_PATH" >&2
    exit 2
fi

declare -A SEEN_NAMES=()
FAILURE_COUNT=0
NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'
KEY_RE='^([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*:[[:space:]]*(.*)$'

for i in "${!PATHS[@]}"; do
    full="${PATHS[$i]}"
    expected_name="${EXPECTED[$i]}"
    name="${DISPLAY[$i]}"
    file_errors=()

    # --- Rule 1: name format (kebab-case)
    if ! [[ "$expected_name" =~ $NAME_RE ]]; then
        file_errors+=("Name must be lowercase kebab-case (matches ^[a-z0-9]+(-[a-z0-9]+)*\$)")
    fi

    # --- Rule 2: no UTF-8 BOM
    if [[ -s "$full" ]]; then
        first3=$(head -c 3 "$full" | od -An -tx1 | tr -d ' \n')
        if [[ "$first3" == "efbbbf" ]]; then
            file_errors+=("UTF-8 BOM detected (EF BB BF) -- breaks Claude Code YAML parser (ADR-0001)")
        fi
    fi

    # --- Rule 3 + 4 + 5 + 6: frontmatter parse
    # Extract content between the first two --- fences using awk.
    frontmatter=$(awk '
        BEGIN { state=0 }
        NR==1 && !/^---[[:space:]]*$/ { exit }
        /^---[[:space:]]*$/ {
            if (state==0) { state=1; next }
            if (state==1) { state=2; exit }
        }
        state==1 { print }
    ' "$full" || true)

    if [[ -z "$frontmatter" ]]; then
        file_errors+=("No valid YAML frontmatter block found (expected ---/--- fences at file start)")
    else
        fm_name=""
        fm_description=""
        while IFS= read -r line; do
            line="${line%$'\r'}"
            if [[ "$line" =~ $KEY_RE ]]; then
                key="${BASH_REMATCH[1]}"
                val="${BASH_REMATCH[2]}"
                # Trim trailing whitespace
                val="${val%"${val##*[![:space:]]}"}"
                # Strip wrapping quotes
                if [[ "$val" =~ ^\"(.*)\"$ ]]; then val="${BASH_REMATCH[1]}"; fi
                if [[ "$val" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"; fi
                case "$key" in
                    name)        fm_name="$val" ;;
                    description) fm_description="$val" ;;
                esac
            fi
        done <<< "$frontmatter"

        # Required fields
        if [[ -z "$fm_name" ]]; then
            file_errors+=("Frontmatter missing or empty required field: name")
        fi
        if [[ -z "$fm_description" ]]; then
            file_errors+=("Frontmatter missing or empty required field: description")
        fi

        # Name matches expected (filename basename, or skill dir name)
        if [[ -n "$fm_name" && "$fm_name" != "$expected_name" ]]; then
            file_errors+=("Frontmatter name '$fm_name' does not match expected '$expected_name'")
        fi

        # Duplicate detection
        if [[ -n "$fm_name" ]]; then
            if [[ -n "${SEEN_NAMES[$fm_name]+x}" ]]; then
                file_errors+=("Duplicate name '$fm_name' also used by: ${SEEN_NAMES[$fm_name]}")
            else
                SEEN_NAMES["$fm_name"]="$name"
            fi
        fi
    fi

    if (( ${#file_errors[@]} > 0 )); then
        FAILURE_COUNT=$((FAILURE_COUNT + ${#file_errors[@]}))
        printf 'FAIL %s\n' "$name"
        for e in "${file_errors[@]}"; do
            printf '     - %s\n' "$e"
        done
    elif (( QUIET == 0 )); then
        printf 'OK   %s\n' "$name"
    fi
done

echo
echo '=== verify-agents summary ==='
printf 'Files scanned    : %d\n' "${#PATHS[@]}"
printf 'Unique names     : %d\n' "${#SEEN_NAMES[@]}"
printf 'Failure count    : %d\n' "$FAILURE_COUNT"

if (( FAILURE_COUNT > 0 )); then
    echo 'RESULT: FAIL'
    exit 1
fi

echo 'RESULT: PASS'
exit 0
