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
                       Dated IDs (claude-opus-4-7, ...) rot and are errors.
  7. token-budget      Always-on agent descriptions stay within budget (~chars/4
                       estimate). Warn-only: the budget is advisory.
  8. skill-voice       Skill bodies carry no agent-era language (persona,
                       ownership blocks, orchestrator choreography, per-skill
                       Output Format). See docs/skill-authoring.md.
  9. process-skill     loop-* process skills carry the compliance layer:
                       trigger-style description ("Use when/before/after ..."),
                       exactly one '## Iron law' section, and a
                       '## Rationalizations' table (ADR-0010,
                       docs/skill-authoring.md "Process skills").
 10. cli-parity        bin/ccds.sh and bin/ccds.ps1 dispatch the same command
                       set ("fixes and releases should be for every outlet") —
                       a command added to one dispatcher must ship in the
                       other, in the same PR. Skipped when a tree ships
                       neither dispatcher (test fixtures).
 12. release-parity   build-release.sh (.deb/.rpm) and build-release.ps1 (ZIP)
                       stage the same payload, minus a declared Windows-only
                       set — the two lists are hand-maintained and had already
                       drifted six files apart. Skipped when a tree ships
                       neither builder (test fixtures).
 11. marketplace-fresh plugins/ + marketplace.json are byte-identical to what
                       build-marketplace.py regenerates — catches skill edits
                       that forget the regen locally, instead of in CI.
                       Skipped when the tree has no plugins/ (test fixtures).

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
    prefix_re = re.compile(r'^(' + '|'.join(sorted(PACKS)) + r'|common|loop)-')

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
                err("skill-voice", f"skills/{d}: {label} — see docs/skill-authoring.md")


# --- 9: process-skill layer (loop-* skills) -----------------------------------
# Process skills encode work loops; the rules exist because wording is what
# holds under pressure (docs/skill-authoring.md "Process skills", ADR-0010).
PROCESS_PREFIX = "loop-"
TRIGGER_RE = re.compile(r'\bUse (when|before|after|proactively)\b')


def check_process_skills():
    for d in skill_dirs():
        if not d.startswith(PROCESS_PREFIX):
            continue
        content = read(os.path.join(SKILLS_DIR, d, "SKILL.md"))
        fm = frontmatter(content)
        desc = field(fm, "description") if fm else ""
        if not TRIGGER_RE.search(desc):
            err("process-skill",
                f"skills/{d}: description is not trigger-style — needs a 'Use when/before/after …' clause")
        body = re.sub(r'^---\s*\n.*?\n---', '', content, count=1, flags=re.DOTALL)
        laws = len(re.findall(r'^## Iron law\s*$', body, re.MULTILINE))
        if laws != 1:
            err("process-skill",
                f"skills/{d}: needs exactly one '## Iron law' section (found {laws}) — two laws is zero laws")
        if not re.search(r'^## Rationalizations\s*$', body, re.MULTILINE):
            err("process-skill", f"skills/{d}: missing the '## Rationalizations' table")


# --- 10: cli-parity ------------------------------------------------------------
# The two dispatchers must expose the same command surface forever ("fixes and
# releases should be for every outlet"). Both parsers anchor to the real
# dispatch structures — the bash `elif [[ "$COMMAND" == "..." ]]` chain and the
# PowerShell `switch ($Command)` block — and tolerate whitespace/formatting.
# version/help are handled before either structure and are exempt by design.
BASH_DISPATCH_RE = re.compile(
    r'\[\[\s*"\$COMMAND"\s*==\s*"([a-z][a-z0-9-]*)"\s*\]\]\s*;?\s*then')
PS1_CASE_LABEL_RE = re.compile(r"^\s*'([a-z][a-z0-9-]*)'\s*\{", re.MULTILINE)
PS1_SWITCH_RE = re.compile(r'switch\s*\(\s*\$Command\s*\)\s*\{')


def parse_bash_commands(path):
    return set(BASH_DISPATCH_RE.findall(read(path)))


def parse_ps1_commands(path):
    src = read(path)
    m = PS1_SWITCH_RE.search(src)
    if m is None:
        return None
    # Take the balanced-brace region of the switch statement, then collect its
    # quoted case labels ('default' is unquoted and thus ignored).
    start = m.end() - 1
    depth = 0
    end = len(src)
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    return set(PS1_CASE_LABEL_RE.findall(src[start:end]))


def check_cli_parity():
    bash_path = os.path.join(REPO_ROOT, "bin", "ccds.sh")
    ps1_path = os.path.join(REPO_ROOT, "bin", "ccds.ps1")
    if not os.path.isfile(bash_path) and not os.path.isfile(ps1_path):
        return  # fixture/library-only trees ship no dispatchers
    if not os.path.isfile(bash_path):
        err("cli-parity", "bin/ccds.ps1 present but bin/ccds.sh is missing")
        return
    if not os.path.isfile(ps1_path):
        err("cli-parity", "bin/ccds.sh present but bin/ccds.ps1 is missing")
        return
    bash_cmds = parse_bash_commands(bash_path)
    ps1_cmds = parse_ps1_commands(ps1_path)
    if not bash_cmds:
        err("cli-parity", 'could not parse any commands from the bin/ccds.sh '
                          'dispatch chain (elif [[ "$COMMAND" == "..." ]])')
        return
    if not ps1_cmds:
        err("cli-parity", "could not parse any commands from the bin/ccds.ps1 "
                          "switch ($Command) dispatch block")
        return
    for cmd in sorted(bash_cmds - ps1_cmds):
        err("cli-parity", f"command '{cmd}' is dispatched in bin/ccds.sh but missing "
                          f"from bin/ccds.ps1 — CLI changes ship in both dispatchers")
    for cmd in sorted(ps1_cmds - bash_cmds):
        err("cli-parity", f"command '{cmd}' is dispatched in bin/ccds.ps1 but missing "
                          f"from bin/ccds.sh — CLI changes ship in both dispatchers")


# --- 11: marketplace freshness -------------------------------------------------
def _tree_digest(*paths):
    import hashlib
    h = {}
    for base in paths:
        if os.path.isfile(base):
            h[base] = hashlib.sha256(open(base, "rb").read()).hexdigest()
        elif os.path.isdir(base):
            for dirpath, _, files in os.walk(base):
                for f in sorted(files):
                    fp = os.path.join(dirpath, f)
                    h[fp] = hashlib.sha256(open(fp, "rb").read()).hexdigest()
    return h


def check_marketplace_fresh():
    """Same contract as catalog-fresh, for the generated plugin tree: the
    committed-or-working plugins/ must be byte-identical to a fresh regen.
    Git-free (hashes before/after regen), so a correct-but-uncommitted regen
    passes. CI has always enforced this remotely; a local lint failure beats
    a red main (added after a skill edit merged without the regen, 2026-07-04)."""
    plugins_dir = os.path.join(REPO_ROOT, "plugins")
    mp_json = os.path.join(REPO_ROOT, ".claude-plugin", "marketplace.json")
    builder = os.path.join(SCRIPT_DIR, "build-marketplace.py")
    if not os.path.isdir(plugins_dir) or not os.path.isfile(builder):
        return  # test fixtures / partial trees
    before = _tree_digest(plugins_dir, mp_json)
    r = subprocess.run([sys.executable, builder, REPO_ROOT],
                       capture_output=True, text=True)
    if r.returncode != 0:
        err("marketplace-fresh", f"build-marketplace.py failed: {r.stderr.strip()[:150]}")
        return
    after = _tree_digest(plugins_dir, mp_json)
    changed = sorted(os.path.relpath(k, REPO_ROOT)
                     for k in set(before) | set(after)
                     if before.get(k) != after.get(k))
    if changed:
        err("marketplace-fresh",
            "plugins/ or marketplace.json was stale -- the regen just refreshed it; "
            "commit the regenerated tree (changed: " + ", ".join(changed[:3])
            + (", ..." if len(changed) > 3 else ")"))


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
                err("model-values",
                     f"{label}: model '{model}' is a dated ID — prefer a tier alias ({'/'.join(sorted(MODEL_ALIASES))})")

    est_tokens = agent_desc_chars // 4
    if est_tokens > AGENT_DESC_TOKEN_BUDGET:
        warn("token-budget",
             f"always-on agent descriptions ≈ {est_tokens} tokens (budget {AGENT_DESC_TOKEN_BUDGET}); trim descriptions")


# --- 12: release-parity ---------------------------------------------------------
# The two release builders stage the payload from independent, hand-maintained
# lists with no cross-check, and they had already drifted six files apart: the
# packages shipped bin/ccds.ps1 WITHOUT scripts/Sync-AgentPacks.ps1 (a
# dispatcher that could only print "Cannot locate Sync-AgentPacks.ps1") and no
# bash completion at all, while the ZIP shipped both.
#
# The contract: the ZIP payload is the deb payload plus a declared set of
# Windows-only files. Adding a cross-platform file to one builder then fails
# here; adding a Windows-only one requires declaring it below.
WINDOWS_ONLY_PAYLOAD = {
    "bin/ccds.ps1",
    "scripts/Sync-AgentPacks.ps1",
    "scripts/Verify-Agents.ps1",
    "scripts/ccds-completion.ps1",
    "scripts/claude-completion.ps1",
}
# `cp [-r] "$REPO_ROOT/<src>" "$PKG_ROOT/<dst>"` — a trailing slash on the
# destination means "keep the source basename", as cp itself does.
DEB_COPY_RE = re.compile(
    r'cp (?:-r )?"\$REPO_ROOT/([^"]+)"\s+"\$PKG_ROOT/([^"]*)"')
PS_COPY_RE = re.compile(r"Src = '([^']+)'\s*;\s*Dst = '([^']+)'")


def _deb_payload(src):
    out = set()
    for m in DEB_COPY_RE.finditer(src):
        source, dest = m.group(1), m.group(2)
        if dest == "" or dest.endswith("/"):
            dest += source.rstrip("/").split("/")[-1]
        out.add(dest.replace("\\", "/").lstrip("./"))
    return out


def _zip_payload(src):
    return {m.group(2).replace("\\", "/") for m in PS_COPY_RE.finditer(src)}


def check_release_parity():
    sh_path = os.path.join(REPO_ROOT, "build-release.sh")
    ps_path = os.path.join(REPO_ROOT, "build-release.ps1")
    if not os.path.isfile(sh_path) or not os.path.isfile(ps_path):
        return  # fixture trees ship no builders
    deb = _deb_payload(read(sh_path))
    zipped = _zip_payload(read(ps_path))
    if not deb or not zipped:
        err("release-parity",
            "could not parse a payload from build-release.sh (cp \"$REPO_ROOT/…\" "
            "\"$PKG_ROOT/…\") or build-release.ps1 ($copyMap Src/Dst rows)")
        return
    for path in sorted(zipped - deb - WINDOWS_ONLY_PAYLOAD):
        err("release-parity",
            f"'{path}' is staged into the ZIP but not the .deb/.rpm — add it to "
            f"build-release.sh, or declare it in WINDOWS_ONLY_PAYLOAD if it is "
            f"Windows-only")
    for path in sorted(deb - zipped):
        err("release-parity",
            f"'{path}' is staged into the .deb/.rpm but not the ZIP — add it to "
            f"build-release.ps1's $copyMap")
    for path in sorted(WINDOWS_ONLY_PAYLOAD & deb):
        err("release-parity",
            f"'{path}' is declared Windows-only but the .deb/.rpm stages it — "
            f"remove it from build-release.sh or from WINDOWS_ONLY_PAYLOAD")


def main():
    for d in (AGENTS_DIR, SKILLS_DIR):
        if not os.path.isdir(d):
            print(f"ERROR: not found: {d}", file=sys.stderr)
            return 2

    check_skill_refs()
    check_catalog_fresh()
    check_urls()
    check_skill_voice()
    check_process_skills()
    check_cli_parity()
    check_release_parity()
    check_marketplace_fresh()
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
