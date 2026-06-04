#!/usr/bin/env python3
"""ADR-0007 migration: convert *-expert / common-* / api / ux agent files into skills.

Reads .claude/agents/*.md, writes skills/<name>/SKILL.md for every file that becomes
a skill. Domain architects (<pack>-architect) and the 5 core agents are left in place
(authored separately). Fixes the three known mojibake byte-sequences and rewrites
`<x>-expert` cross-references to their new skill names. Idempotent; does not delete
source files (a later step removes the migrated experts from .claude/agents/).
"""
import json, re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENTS = ROOT / ".claude" / "agents"
SKILLS = ROOT / "skills"

PACKS = ["saas","ai","infra","game","mobile","dataplat","ecom","fintech",
         "devtool","desktop","ext","embed","media","orch"]
DOMAIN_AGENTS = {f"{p}-architect" for p in PACKS}
CORE_AGENTS = {"plan-architect","pr-code-reviewer","secure-auditor",
               "test-writer-runner","deploy-checklist"}
# special renames (file stem -> skill name)
RENAME = {"api-expert":"api-design", "ux-design-critic":"ux-design"}

MOJIBAKE = {
    "â€”": "—",   # â€”  -> em dash —
    "â†’": "→",   # â†’  -> arrow →   (stored bytes c3a2 e280a0 e28099)
    "â€“": "–",   # â€“  -> en dash –
}

def fix_mojibake(text: str) -> str:
    for bad, good in MOJIBAKE.items():
        text = text.replace(bad, good)
    return text

def skill_name(stem: str) -> str:
    if stem in RENAME:
        return RENAME[stem]
    if stem.endswith("-expert"):
        return stem[:-len("-expert")]
    return stem

def split_frontmatter(raw: str):
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", raw, re.S)
    if not m:
        return None, raw
    return m.group(1), m.group(2)

def load_catalog():
    cat = json.load(open(ROOT / "catalog.json", encoding="utf-8"))
    return {e["name"]: e.get("description","").strip() for e in cat}

def rewrite_refs(body: str) -> str:
    # `<pack>-...-expert` -> `<pack>-...`  (now a skill); leave non-backtick prose alone
    body = re.sub(r"`([a-z0-9]+(?:-[a-z0-9]+)*)-expert`", r"`\1`", body)
    body = body.replace("`api-expert`", "`api-design`")
    body = body.replace("`ux-design-critic`", "`ux-design`")
    return body

def main():
    desc_by_name = load_catalog()
    made, skipped = [], []
    for path in sorted(AGENTS.glob("*.md")):
        stem = path.stem
        if stem in DOMAIN_AGENTS or stem in CORE_AGENTS:
            skipped.append(stem); continue
        name = skill_name(stem)
        raw = fix_mojibake(path.read_text(encoding="utf-8"))
        fm, body = split_frontmatter(raw)
        body = rewrite_refs(body).strip()
        desc = desc_by_name.get(stem, "").strip()
        if not desc:
            print(f"  WARN no catalog desc for {stem}", file=sys.stderr)
        out = SKILLS / name / "SKILL.md"
        out.parent.mkdir(parents=True, exist_ok=True)
        content = f"---\nname: {name}\ndescription: {desc}\n---\n\n{body}\n"
        out.write_text(content, encoding="utf-8")
        made.append(name)
    print(f"created {len(made)} skills:")
    for n in made: print(f"  skills/{n}/SKILL.md")
    print(f"\nleft as agents ({len(skipped)}): {', '.join(sorted(skipped))}")

if __name__ == "__main__":
    main()
