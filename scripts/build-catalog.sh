#!/usr/bin/env bash
# build-catalog.sh — generates catalog.json from agent + skill files (ADR-0007).
#
# Indexes .claude/agents/*.md (kind=agent) and skills/<name>/SKILL.md (kind=skill).
# This is a thin wrapper around build-catalog.py, which is the canonical generator
# (the dual agent+skill layout is impractical to parse robustly in pure bash/awk).
#
# Usage: ./scripts/build-catalog.sh [repo-root] [output-path]
# Requirements: python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v python3 >/dev/null 2>&1 || {
    echo "Error: python3 is required to build the catalog." >&2
    exit 1
}

exec python3 "$SCRIPT_DIR/build-catalog.py" "$@"
