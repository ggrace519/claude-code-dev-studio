#!/usr/bin/env python3
"""
build-catalog.py — generates catalog.json from agent and skill files.

Indexes two artifact kinds (ADR-0007):
  - agents:  .claude/agents/*.md            (kind=agent,  scope=global, always loaded)
  - skills:  skills/<name>/SKILL.md         (kind=skill,  scope=global|project)

Cross-cutting skills (common-*, playbook-conventions, sync-agents, api-design,
ux-design, security-checklist, code-review-checklist) are scope=global (installed once
to ~/.claude/skills/). Domain skills are scope=project (JIT-copied per project).

Usage:
    python3 scripts/build-catalog.py [repo-root] [output-path]
"""

import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(SCRIPT_DIR)
OUTPUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO_ROOT, "catalog.json")

AGENTS_DIR = os.path.join(REPO_ROOT, ".claude", "agents")
SKILLS_DIR = os.path.join(REPO_ROOT, "skills")

CORE_AGENTS = {
    "plan-architect", "pr-code-reviewer", "secure-auditor",
    "test-writer-runner", "deploy-checklist",
}
# skills installed globally (always available), not JIT per project
GLOBAL_META_SKILLS = {
    "playbook-conventions", "sync-agents", "api-design", "ux-design",
    "security-checklist", "code-review-checklist",
}
PACKS = {"saas", "ai", "infra", "game", "mobile", "dataplat", "ecom", "fintech",
         "devtool", "desktop", "ext", "embed", "media", "orch"}


def frontmatter(content: str):
    m = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
    return m.group(1) if m else None


def field(fm: str, name: str) -> str:
    m = re.search(rf'^{name}:\s*(.+)$', fm, re.MULTILINE)
    return m.group(1).strip().strip('"').strip("'") if m else ""


def pack_of(name: str) -> str:
    if name in CORE_AGENTS or name in GLOBAL_META_SKILLS:
        return "core"
    if name.startswith("common-"):
        return "common"
    prefix = name.split("-", 1)[0]
    return prefix if prefix in PACKS else "core"


def agent_entries():
    out = []
    for fname in sorted(f for f in os.listdir(AGENTS_DIR) if f.endswith(".md")):
        name = fname[:-3]
        fm = frontmatter(open(os.path.join(AGENTS_DIR, fname), encoding="utf-8").read())
        if fm is None:
            print(f"Warning: no frontmatter in agents/{fname}", file=sys.stderr)
            continue
        out.append({
            "name": field(fm, "name") or name,
            "pack": pack_of(name),
            "kind": "agent",
            "scope": "global",
            "model": field(fm, "model"),
            "description": field(fm, "description"),
        })
    return out


def skill_entries():
    out = []
    if not os.path.isdir(SKILLS_DIR):
        return out
    for name in sorted(os.listdir(SKILLS_DIR)):
        sp = os.path.join(SKILLS_DIR, name, "SKILL.md")
        if not os.path.isfile(sp):
            continue
        fm = frontmatter(open(sp, encoding="utf-8").read())
        if fm is None:
            print(f"Warning: no frontmatter in skills/{name}/SKILL.md", file=sys.stderr)
            continue
        scope = "global" if (name in GLOBAL_META_SKILLS or name.startswith("common-")) else "project"
        out.append({
            "name": field(fm, "name") or name,
            "pack": pack_of(name),
            "kind": "skill",
            "scope": scope,
            "model": "",
            "description": field(fm, "description"),
        })
    return out


catalog = agent_entries() + skill_entries()
with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
    json.dump(catalog, f, indent=2, ensure_ascii=False)
    f.write("\n")

n_agents = sum(1 for e in catalog if e["kind"] == "agent")
n_skills = sum(1 for e in catalog if e["kind"] == "skill")
print(f"catalog.json -> {OUTPUT}  ({n_agents} agents + {n_skills} skills = {len(catalog)} entries)")
