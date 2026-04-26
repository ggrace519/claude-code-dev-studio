#!/usr/bin/env python3
"""
build-catalog.py — generates catalog.json from agent .md files.

Usage:
    python3 scripts/build-catalog.py [agents-dir] [output-path]

Defaults:
    agents-dir  = .claude/agents  (relative to repo root)
    output-path = catalog.json    (repo root)
"""

import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)

agents_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO_ROOT, ".claude", "agents")
output_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO_ROOT, "catalog.json")

if not os.path.isdir(agents_path):
    print(f"Error: agents directory not found: {agents_path}", file=sys.stderr)
    sys.exit(1)

GENERALISTS = {
    "api-expert", "deploy-checklist", "plan-architect",
    "pr-code-reviewer", "secure-auditor", "test-writer-runner", "ux-design-critic"
}

def derive_pack(basename: str) -> str:
    if basename in GENERALISTS:
        return "core"
    m = re.match(r'^([^-]+)-', basename)
    return m.group(1) if m else "core"

def extract_frontmatter(content: str) -> str | None:
    """Return the text between the first and second --- delimiters."""
    m = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
    return m.group(1) if m else None

def extract_field(fm: str, field: str) -> str:
    m = re.search(rf'^{field}:\s*(.+)$', fm, re.MULTILINE)
    return m.group(1).strip() if m else ""

def extract_description(fm: str) -> str:
    """
    Pull the YAML block-scalar description, strip indentation,
    collapse escaped newlines (\\n) and stray backslashes, remove example tags.
    """
    m = re.search(r'^description:\s*\|?\s*\n((?:  .+\n?)*)', fm, re.MULTILINE)
    if not m:
        return ""
    raw = m.group(1)
    # Strip two-space indent
    lines = [line[2:] if line.startswith("  ") else line for line in raw.splitlines()]
    text = " ".join(lines)
    # Remove <example>...</example> blocks
    text = re.sub(r'<example>.*?</example>', '', text, flags=re.DOTALL)
    # Collapse literal \\n sequences (double-escaped newlines in YAML)
    text = text.replace('\\n', ' ')
    # Remove stray backslashes
    text = text.replace('\\', '')
    # Collapse whitespace
    text = re.sub(r'\s{2,}', ' ', text).strip()
    return text

catalog = []
md_files = sorted(f for f in os.listdir(agents_path) if f.endswith(".md"))

for fname in md_files:
    fpath = os.path.join(agents_path, fname)
    basename = fname[:-3]

    with open(fpath, encoding="utf-8") as f:
        content = f.read()

    fm = extract_frontmatter(content)
    if fm is None:
        print(f"Warning: no frontmatter in {fname}, skipping", file=sys.stderr)
        continue

    catalog.append({
        "name":        extract_field(fm, "name") or basename,
        "pack":        derive_pack(basename),
        "model":       extract_field(fm, "model"),
        "description": extract_description(fm),
    })

with open(output_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(catalog, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"catalog.json written -> {output_path}  ({len(catalog)} entries)")
