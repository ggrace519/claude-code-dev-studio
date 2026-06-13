#!/usr/bin/env python3
"""
lint-playbook.py — semantic lint for the playbook's own invariants.

verify-agents checks that files are well-formed (BOM, kebab-case, frontmatter).
This linter checks that what the files SAY is true:

  1. skill-refs        Every `<pack>-*` / cross-cutting skill referenced in an
                       agent body exists as skills/<name>/SKILL.md.
  2. reverse-refs      Every project-scoped skill is referenced by its domain
                       agent's body (the "Skills you compose" manifest).
  3. catalog-fresh     catalog.json is byte-identical to what build-catalog.py
                       regenerates (CLAUDE.md: "Regenerate catalog.json ...
                       after any change").
  4. url-consistency   All repo URLs use the canonical GitHub owner. Historical
                       records (DECISIONS.md, CHANGELOG.md) are exempt.
  5. description-style CLAUDE.md conventions: one-line descriptions, no
                       <example> blocks, no literal \\n escapes, <= 400 chars.
  6. model-values      Agent model is a tier alias (opus/sonnet/haiku/inherit).
                       Dated IDs (claude-opus-4-7, ...) rot and are warned on.
  7. token-budget      Always-on agent descriptions stay within budget (~chars/4
                       estimate). Warn-only: the budget is advisory.
  8. skill-voice       Skill bodies carry no agent-era language (persona,
                       ownership blocks, orchestrator choreography, per-skill
                       Output Format). Warn-only until the skill-content
                       conversion lands; see docs/skill-authoring.md.

Exit codes: 0 = pass (warnings allowed), 1 = one or more errors, 2 = config error.

Usage:
    python3 scripts/lint-playbook.py [repo-root]
"""

import json
import os
import re
import subprocess
import sys
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(SCRIPT_DIR))

AGENTS_DIR = os.path.join(REPO_ROOT, ".claude", "agents")
SKILLS_DIR = os.path.join(REPO_ROOT, "skills")
CATALOG = os.path.join(REPO_ROOT, "catalog.json")

CANONICAL_OWNER = "ggrace519"
REPO_NAME = "claude-code-dev-studio"
# Files that record history verbatim and must not be retroactively altered.
URL_EXEMPT = {"DECISIONS.md", "CHANGELOG.md", "INNOVATIONS.md", "DEMO.md"}
URL_SCAN_EXT = {".md", ".sh", ".ps1", ".py", ".json"}

PACKS = {"saas", "ai", "infra", "game", "mobile", "dataplat", "ecom", "fintech",
         "devtool", "desktop", "ext", "embed", "media", "orch"}
MODEL_ALIASES = {"opus", "sonnet", "haiku", "inherit"}
DESC_MAX_CHARS = 400
AGENT_DESC_TOKEN_BUDGET = 1300  # chars/4 estimate; advertised ~850 real tokens

errors = []
warnings = []


def err(check, msg):
    errors.append(f"[{check}] {msg}")


def warn(check, msg):
    warnings.append(f"[{check}] {msg}")


def frontmatter(content):
    m = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
    return m.group(1) if m else None


def field(fm, name):
    m = re.search(rf'^{name}:\s*(.+)$', fm, re.MULTILINE)
    return m.group(1).strip().strip('"').strip("'") if m else ""


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def agent_files():
    return sorted(f for f in os.listdir(AGENTS_DIR) if f.endswith(".md"))


def skill_dirs():
    return sorted(d for d in os.listdir(SKILLS_DIR)
                  if os.path.isfile(os.path.join(SKILLS_DIR, d, "SKILL.md")))


# --- 1 + 2: skill cross-references -----------------------------------------
def check_skill_refs():
    skills = set(skill_dirs())
    agents = {f[:-3] for f in agent_files()}
    prefix_re = re.compile(r'^(' + '|'.join(sorted(PACKS)) + r'|common)-')

    for fname in agent_files():
        body = read(os.path.join(AGENTS_DIR, fname))
        refs = set(re.findall(r'`([a-z0-9]+(?:-[a-z0-9]+)+)`', body))
        for ref in sorted(refs):
            if ref in skills or ref in agents:
                continue
            if prefix_re.match(ref):
                err("skill-refs", f"{fname} references `{ref}` but skills/{ref}/SKILL.md does not exist")

    for skill in sorted(skills):
        pack = skill.split("-", 1)[0]
        if pack not in PACKS:
            continue  # cross-cutting skills have no single owning agent
        agent_path = os.path.join(AGENTS_DIR, f"{pack}-architect.md")
        if not os.path.isfile(agent_path):
            err("reverse-refs", f"skills/{skill} belongs to pack '{pack}' but {pack}-architect.md is missing")
            continue
        if skill not in read(agent_path):
            err("reverse-refs", f"skills/{skill} is not referenced in {pack}-architect.md (skill manifest drift)")


# --- 3: catalog freshness ---------------------------------------------------
def check_catalog_fresh():
    if not os.path.isfile(CATALOG):
        err("catalog-fresh", "catalog.json is missing")
        return
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        subprocess.run(
            [sys.executable, os.path.join(SCRIPT_DIR, "build-catalog.py"), REPO_ROOT, tmp_path],
            check=True, capture_output=True)
        if read(CATALOG) != read(tmp_path):
            err("catalog-fresh", "catalog.json is stale — run: python3 scripts/build-catalog.py")
    finally:
        os.unlink(tmp_path)


# --- 4: URL consistency ------------------------------------------------------
def check_urls():
    url_re = re.compile(r'github(?:usercontent)?\.com/([A-Za-z0-9_.-]+)/' + re.escape(REPO_NAME))
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        # tests/ deliberately contains wrong-owner URLs as lint counterexamples
        dirnames[:] = [d for d in dirnames if d not in {".git", "node_modules", "dist", "tests"}]
        for fname in filenames:
            if os.path.splitext(fname)[1] not in URL_SCAN_EXT or fname in URL_EXEMPT:
                continue
            path = os.path.join(dirpath, fname)
            try:
                content = read(path)
            except (UnicodeDecodeError, OSError):
                continue
            for owner in url_re.findall(content):
                if owner != CANONICAL_OWNER:
                    rel = os.path.relpath(path, REPO_ROOT)
                    err("url-consistency",
                        f"{rel} points at {owner}/{REPO_NAME} (canonical: {CANONICAL_OWNER}/{REPO_NAME})")


# --- skill-voice: agent-era language inside skill bodies ----------------------
# Skills are reference material, not actors (docs/skill-authoring.md). These
# phrases are migration debt from ADR-0007. Warn-level until the skill-content
# conversion lands everywhere, then promote to error.
SKILL_VOICE_EXEMPT = {"playbook-conventions",  # documents the handoff protocol
                      "sync-agents"}           # procedural meta-skill
SKILL_VOICE_PATTERNS = [
    ("orchestrator choreography", re.compile(r'\borchestrator\b', re.IGNORECASE)),
    ("'You do NOT own' handoff block", re.compile(r'You do NOT own')),
    ("per-skill Output Format section", re.compile(r'^## Output Format', re.MULTILINE)),
    ("agent persona intro", re.compile(r'^You are a ', re.MULTILINE)),
]


def check_skill_voice():
    for d in skill_dirs():
        if d in SKILL_VOICE_EXEMPT:
            continue
        content = read(os.path.join(SKILLS_DIR, d, "SKILL.md"))
        body = re.sub(r'^---\s*\n.*?\n---', '', content, count=1, flags=re.DOTALL)
        for label, pattern in SKILL_VOICE_PATTERNS:
            if pattern.search(body):
                warn("skill-voice", f"skills/{d}: {label} — see docs/skill-authoring.md")


# --- 5 + 6 + 7: descriptions and models --------------------------------------
def check_descriptions_and_models():
    agent_desc_chars = 0
    items = [(os.path.join(AGENTS_DIR, f), f, True) for f in agent_files()]
    items += [(os.path.join(SKILLS_DIR, d, "SKILL.md"), f"skills/{d}", False) for d in skill_dirs()]

    for path, label, is_agent in items:
        fm = frontmatter(read(path))
        if fm is None:
            continue  # verify-agents owns this failure
        desc = field(fm, "description")
        if "<example>" in desc:
            err("description-style", f"{label}: description contains an <example> block")
        if "\\n" in desc:
            err("description-style", f"{label}: description contains a literal \\n escape")
        if len(desc) > DESC_MAX_CHARS:
            err("description-style", f"{label}: description is {len(desc)} chars (max {DESC_MAX_CHARS})")
        if is_agent:
            agent_desc_chars += len(desc)
            model = field(fm, "model")
            if model and model not in MODEL_ALIASES:
                warn("model-values",
                     f"{label}: model '{model}' is a dated ID — prefer a tier alias ({'/'.join(sorted(MODEL_ALIASES))})")

    est_tokens = agent_desc_chars // 4
    if est_tokens > AGENT_DESC_TOKEN_BUDGET:
        warn("token-budget",
             f"always-on agent descriptions ≈ {est_tokens} tokens (budget {AGENT_DESC_TOKEN_BUDGET}); trim descriptions")


def main():
    for d in (AGENTS_DIR, SKILLS_DIR):
        if not os.path.isdir(d):
            print(f"ERROR: not found: {d}", file=sys.stderr)
            return 2

    check_skill_refs()
    check_catalog_fresh()
    check_urls()
    check_skill_voice()
    check_descriptions_and_models()

    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    print()
    print("=== lint-playbook summary ===")
    print(f"Errors   : {len(errors)}")
    print(f"Warnings : {len(warnings)}")
    print("RESULT: " + ("FAIL" if errors else "PASS"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
