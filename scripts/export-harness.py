#!/usr/bin/env python3
"""
export-harness.py — export the loop-* process skills to foreign harness formats.

The loop pack is the library's most harness-agnostic content (no domain
assumptions, no Claude-specific APIs), so it is the first cargo for
multi-harness distribution (INNOVATIONS.md 2026-07-03 #6). Two targets:

  cursor     .cursor/rules/<name>.mdc — Cursor project rules. Frontmatter
             carries the trigger description (Agent-Requested rule form,
             alwaysApply: false); the agent attaches a rule when its
             description matches the task.
  agents-md  AGENTS.md — the cross-tool instructions file read by Codex CLI
             and the wider AGENTS.md ecosystem. One section per skill,
             prefixed with its trigger line.

Bundled references/*.md are inlined into the exported artifact (foreign
harnesses have no progressive-disclosure convention to rely on).

Output goes to dist/harness-export/<target>/ (override with --out). Generation
is deterministic: sorted inputs, no timestamps.

Usage:
    python3 scripts/export-harness.py --target cursor|agents-md [repo-root] [--out DIR]
"""

import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

MDC_TMPL = """---
description: {description}
alwaysApply: false
---

{body}
"""

AGENTS_MD_HEADER = """# Agent-loop process skills (ccds `loop-` pack)

Process rules for how to run coding work loops. Each section names its
trigger; when a trigger applies to the current task, the section's rules are
not optional. Exported from Claude Code Dev Studio
(https://github.com/ggrace519/claude-code-dev-studio); license
PolyForm-Noncommercial-1.0.0.
"""


def parse_skill(path):
    content = open(path, encoding="utf-8").read()
    m = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)$', content, re.DOTALL)
    if not m:
        raise ValueError(f"no frontmatter in {path}")
    fm, body = m.group(1), m.group(2)
    d = re.search(r'^description:\s*(.+)$', fm, re.MULTILINE)
    return (d.group(1).strip() if d else ""), body.strip()


def inline_references(body, skill_dir):
    """Replace links to bundled references/*.md with the file content —
    foreign harnesses won't chase relative links the way Claude Code does."""
    refs_dir = os.path.join(skill_dir, "references")
    if not os.path.isdir(refs_dir):
        return body
    for ref in sorted(os.listdir(refs_dir)):
        if not ref.endswith(".md"):
            continue
        ref_content = open(os.path.join(refs_dir, ref), encoding="utf-8").read().strip()
        # Demote the reference's headings one level so it nests under the skill.
        ref_content = re.sub(r'^(#+)', r'#\1', ref_content, flags=re.MULTILINE)
        body = re.sub(r'\[([^\]]+)\]\(references/' + re.escape(ref) + r'\)',
                      r'\1 (inlined below)', body)
        body += f"\n\n{ref_content}"
    return body


def export_cursor(skills, out_dir):
    rules_dir = os.path.join(out_dir, ".cursor", "rules")
    os.makedirs(rules_dir, exist_ok=True)
    for name, desc, body in skills:
        path = os.path.join(rules_dir, f"{name}.mdc")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(MDC_TMPL.format(description=desc, body=body))
        print(f"  {os.path.relpath(path, out_dir)}")


def export_agents_md(skills, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    parts = [AGENTS_MD_HEADER]
    for name, desc, body in skills:
        # Demote skill headings one level under the per-skill section heading.
        demoted = re.sub(r'^(#+)', r'#\1', body, flags=re.MULTILINE)
        parts.append(f"## {name}\n\n**Trigger:** {desc}\n\n{demoted}")
    path = os.path.join(out_dir, "AGENTS.md")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n\n".join(parts) + "\n")
    print(f"  {os.path.relpath(path, out_dir)}")


def main():
    argv = sys.argv[1:]
    target, out, root = None, None, None
    i = 0
    while i < len(argv):
        if argv[i] == "--target":
            target = argv[i + 1]; i += 2
        elif argv[i] == "--out":
            out = argv[i + 1]; i += 2
        elif argv[i].startswith("--"):
            print(f"ERROR: unknown flag {argv[i]}", file=sys.stderr); return 2
        else:
            root = argv[i]; i += 1
    if target not in ("cursor", "agents-md"):
        print("ERROR: --target cursor|agents-md is required", file=sys.stderr)
        return 2
    root = os.path.abspath(root or os.path.dirname(SCRIPT_DIR))
    out = os.path.abspath(out or os.path.join(root, "dist", "harness-export", target))

    skills_dir = os.path.join(root, "skills")
    names = sorted(d for d in os.listdir(skills_dir)
                   if d.startswith("loop-")
                   and os.path.isfile(os.path.join(skills_dir, d, "SKILL.md")))
    if not names:
        print("ERROR: no loop-* skills found — run from a repo with the loop pack",
              file=sys.stderr)
        return 2

    skills = []
    for name in names:
        skill_dir = os.path.join(skills_dir, name)
        desc, body = parse_skill(os.path.join(skill_dir, "SKILL.md"))
        skills.append((name, desc, inline_references(body, skill_dir)))

    print(f"exporting {len(skills)} loop skills -> {out} ({target})")
    if target == "cursor":
        export_cursor(skills, out)
    else:
        export_agents_md(skills, out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
