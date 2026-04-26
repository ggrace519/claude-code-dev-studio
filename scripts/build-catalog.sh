#!/usr/bin/env bash
# build-catalog.sh — generates catalog.json from agent .md files
# Usage: ./scripts/build-catalog.sh [agents-dir] [output-path]
# Defaults: .claude/agents  →  catalog.json (repo root)
# Requirements: bash 4+, awk, sed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENTS_PATH="${1:-$REPO_ROOT/.claude/agents}"
OUTPUT_PATH="${2:-$REPO_ROOT/catalog.json}"

if [[ ! -d "$AGENTS_PATH" ]]; then
  echo "Error: agents directory not found: $AGENTS_PATH" >&2
  exit 1
fi

GENERALISTS="api-expert deploy-checklist plan-architect pr-code-reviewer secure-auditor test-writer-runner ux-design-critic"

is_generalist() {
  local name="$1"
  for g in $GENERALISTS; do [[ "$g" == "$name" ]] && return 0; done
  return 1
}

derive_pack() {
  local basename="$1"
  if is_generalist "$basename"; then
    echo "core"
  elif [[ "$basename" =~ ^([^-]+)- ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "core"
  fi
}

# Extract a single-line YAML field value from frontmatter text
extract_field() {
  local field="$1" fm="$2"
  echo "$fm" | awk -v f="$field" '
    $0 ~ "^"f": " { sub("^"f": *",""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }
  '
}

# Extract and clean description block
extract_description() {
  local fm="$1"
  # Grab lines after "description: |" that start with two spaces
  echo "$fm" | awk '
    /^description:/ { in_desc=1; next }
    in_desc && /^  / { sub(/^  /,""); printf "%s ", $0; next }
    in_desc { exit }
  ' | sed \
      -e 's/\\n/ /g' \
      -e 's/<example>[^<]*<\/example>//g' \
      -e 's/  */ /g' \
      -e 's/^ //;s/ $//'
}

count=0
printf '[\n' > "$OUTPUT_PATH.tmp"

first=1
for f in $(ls "$AGENTS_PATH"/*.md 2>/dev/null | sort); do
  basename=$(basename "$f" .md)
  content=$(<"$f")

  # Extract frontmatter between first --- and second ---
  fm=$(echo "$content" | awk '/^---/{if(++c==2) exit; next} c==1')
  [[ -z "$fm" ]] && { echo "Warning: no frontmatter in $f, skipping" >&2; continue; }

  name=$(extract_field "name" "$fm")
  [[ -z "$name" ]] && name="$basename"
  model=$(extract_field "model" "$fm")
  pack=$(derive_pack "$basename")
  desc=$(extract_description "$fm")

  # JSON-escape: backslash, double-quote
  name_j=$(echo "$name" | sed 's/\\/\\\\/g;s/"/\\"/g')
  model_j=$(echo "$model" | sed 's/\\/\\\\/g;s/"/\\"/g')
  pack_j=$(echo "$pack" | sed 's/\\/\\\\/g;s/"/\\"/g')
  desc_j=$(echo "$desc" | sed 's/\\/\\\\/g;s/"/\\"/g')

  [[ $first -eq 0 ]] && printf ',\n' >> "$OUTPUT_PATH.tmp"
  printf '  {\n    "name": "%s",\n    "pack": "%s",\n    "model": "%s",\n    "description": "%s"\n  }' \
    "$name_j" "$pack_j" "$model_j" "$desc_j" >> "$OUTPUT_PATH.tmp"
  first=0
  (( count++ )) || true
done

printf '\n]\n' >> "$OUTPUT_PATH.tmp"
mv "$OUTPUT_PATH.tmp" "$OUTPUT_PATH"
echo "catalog.json written -> $OUTPUT_PATH  ($count entries)"
