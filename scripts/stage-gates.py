#!/usr/bin/env python3
"""
ccds gate staging engine (ADR-0013) — Gates 2/3/4 of the quality pipeline.

Called by both Sync-AgentPacks twins after skill staging (one implementation
instead of a bash+PowerShell pair, because JSON merging in shell is how user
files get corrupted). Stages into a target project, stack-matched via
templates/stack-matrix.json:

  Gate 2a  .claude/settings.json           merge-with-backup: ADD missing
                                           permissions.deny entries only;
                                           never remove/reorder; key order
                                           preserved. Absent -> created.
  Gate 2b  CLAUDE.md                       managed block between
                                           `# >>> ccds-standards >>>` markers
                                           (strip-and-append + backup, same
                                           semantics as ccds-user-setup.sh);
                                           text outside markers preserved.
  Gate 3   .pre-commit-config.yaml         created only when absent.
  Gate 4   .github/workflows/ccds-quality.yml   created only when absent.

Never-destroy rules: files we CREATE are recorded in the sync manifest
(managedGateFiles, with sha256) and removed on --clean only while unmodified;
files we EDIT (settings.json, CLAUDE.md) are recorded in gateEdits — --clean
strips the standards block but deliberately leaves deny rules in place
(protective, harmless, and removing them would re-open Gate 2). Every write
of a pre-existing user file takes a timestamped .ccds-backup-* first.

Exit codes: 0 (including "nothing to do"); 2 only for unusable invocation
(missing target). Gate staging must never fail the surrounding sync.
"""

import argparse
import datetime
import hashlib
import json
import os
import sys

STD_BEGIN = "# >>> ccds-standards >>>"
STD_END = "# <<< ccds-standards <<<"
MANIFEST_REL = os.path.join(".claude", "skills", ".skill-manifest.json")
SCHEMA_VERSION = 3


def log(msg):
    print("gates: " + msg)


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write_text(path, content):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def sha256(content):
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def backup(path, dry):
    if not os.path.isfile(path):
        return None
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dst = "%s.ccds-backup-%s" % (path, stamp)
    if not dry:
        write_text(dst, read_text(path))
    return dst


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError, ValueError):
        return None


def detect_stacks(target, matrix):
    found = ["base"]
    for name, spec in matrix.get("stacks", {}).items():
        if name == "base":
            continue
        if any(os.path.isfile(os.path.join(target, sig))
               for sig in spec.get("signals", [])):
            found.append(name)
    return found


# --------------------------------------------------------------------------
# Gate 2a: settings.json deny merge
# --------------------------------------------------------------------------

def stage_settings(target, templates, dry, edits):
    deny_spec = load_json(os.path.join(templates, "settings-deny.json"))
    if not deny_spec or not isinstance(deny_spec.get("deny"), list):
        log("settings: deny template missing/unreadable; skipped")
        return
    wanted = deny_spec["deny"]
    path = os.path.join(target, ".claude", "settings.json")
    rel = ".claude/settings.json"

    if not os.path.isfile(path):
        content = json.dumps({"permissions": {"deny": wanted}}, indent=2) + "\n"
        log("settings: created %s (%d deny rules — the hard layer under the "
            "ccds-guard hook)" % (rel, len(wanted)))
        if not dry:
            write_text(path, content)
        edits.append(rel)
        return

    data = load_json(path)
    if not isinstance(data, dict):
        log("settings: %s exists but is not valid JSON — left untouched. "
            "Fix it, then re-run ccds sync." % rel)
        return
    perms = data.setdefault("permissions", {})
    if not isinstance(perms, dict):
        log("settings: %s has a non-object permissions key — left untouched."
            % rel)
        return
    deny = perms.setdefault("deny", [])
    if not isinstance(deny, list):
        log("settings: %s has a non-array permissions.deny — left untouched."
            % rel)
        return
    missing = [r for r in wanted if r not in deny]
    if not missing:
        log("settings: deny rules already present (up to date)")
        return
    bak = backup(path, dry)
    deny.extend(missing)
    log("settings: added %d missing deny rules to %s (backup: %s)"
        % (len(missing), rel, os.path.basename(bak) if bak else "n/a"))
    if not dry:
        write_text(path, json.dumps(data, indent=2) + "\n")
    edits.append(rel)


# --------------------------------------------------------------------------
# Gate 2b: CLAUDE.md standards block
# --------------------------------------------------------------------------

def strip_standards_block(content):
    """Remove ALL ccds-standards blocks; preserve everything else verbatim."""
    out, skipping = [], False
    for line in content.splitlines():
        check = line.rstrip("\r\t ")
        if check == STD_BEGIN:
            skipping = True
            continue
        if check == STD_END:
            skipping = False
            continue
        if not skipping:
            out.append(line)
    text = "\n".join(out)
    return text.rstrip("\n")


def stage_claude_block(target, templates, dry, edits):
    block_path = os.path.join(templates, "claude-standards.md")
    if not os.path.isfile(block_path):
        log("standards: template missing; skipped")
        return
    block = read_text(block_path).rstrip("\n")
    path = os.path.join(target, "CLAUDE.md")
    existing = read_text(path) if os.path.isfile(path) else ""
    kept = strip_standards_block(existing)
    new_content = (kept + "\n\n" if kept else "") + block + "\n"
    if new_content == existing:
        log("standards: CLAUDE.md block up to date")
        return
    bak = backup(path, dry)
    log("standards: %s ccds-standards block in CLAUDE.md%s"
        % ("updated" if STD_BEGIN in existing else "added",
           " (backup: %s)" % os.path.basename(bak) if bak else ""))
    if not dry:
        write_text(path, new_content)
    edits.append("CLAUDE.md")


# --------------------------------------------------------------------------
# Gates 3/4: created-only-when-absent files
# --------------------------------------------------------------------------

def assemble(templates, matrix, stacks, key):
    parts = []
    for name in stacks:
        frag = matrix["stacks"].get(name, {}).get(key)
        if not frag:
            continue
        frag_path = os.path.join(templates, frag)
        if os.path.isfile(frag_path):
            parts.append(read_text(frag_path).rstrip("\n"))
    return ("\n".join(parts) + "\n") if parts else None


def stage_created_file(target, rel, content, prior, dry, created, label):
    path = os.path.join(target, rel)
    prior_entry = next((e for e in prior if e.get("path") == rel), None)
    if os.path.isfile(path):
        current = read_text(path)
        if prior_entry and prior_entry.get("sha256") == sha256(current):
            if current == content:
                log("%s: up to date" % label)
                created.append({"path": rel, "sha256": sha256(content)})
                return
            # ours and unmodified by the user -> safe to refresh
            log("%s: refreshed %s (template changed)" % (label, rel))
            if not dry:
                write_text(path, content)
            created.append({"path": rel, "sha256": sha256(content)})
            return
        if prior_entry:
            log("%s: %s has your edits — kept as-is (ccds never overwrites "
                "your changes)" % (label, rel))
            created.append(prior_entry)
        else:
            log("%s: %s already exists — kept as-is. Compare with the ccds "
                "template if you want the staged checks." % (label, rel))
        return
    log("%s: created %s" % (label, rel))
    if not dry:
        write_text(path, content)
    created.append({"path": rel, "sha256": sha256(content)})


# --------------------------------------------------------------------------
# Manifest
# --------------------------------------------------------------------------

def update_manifest(target, created, edits, dry):
    path = os.path.join(target, MANIFEST_REL)
    data = load_json(path)
    if not isinstance(data, dict):
        data = {"schema": SCHEMA_VERSION}
    data["schema"] = max(int(data.get("schema") or 0), SCHEMA_VERSION)
    data["managedGateFiles"] = created
    data["gateEdits"] = sorted(set(edits))
    if not dry:
        write_text(path, json.dumps(data, indent=2) + "\n")


def clean(target, dry):
    manifest = load_json(os.path.join(target, MANIFEST_REL)) or {}
    for entry in manifest.get("managedGateFiles", []):
        rel, want = entry.get("path"), entry.get("sha256")
        if not rel:
            continue
        path = os.path.join(target, rel)
        if not os.path.isfile(path):
            continue
        if sha256(read_text(path)) == want:
            log("clean: removing %s (ccds-created, unmodified)" % rel)
            if not dry:
                os.remove(path)
        else:
            log("clean: %s has your edits — kept" % rel)
    claude_md = os.path.join(target, "CLAUDE.md")
    if os.path.isfile(claude_md):
        content = read_text(claude_md)
        if STD_BEGIN in content:
            kept = strip_standards_block(content)
            backup(claude_md, dry)
            log("clean: removed ccds-standards block from CLAUDE.md")
            if not dry:
                if kept:
                    write_text(claude_md, kept + "\n")
                else:
                    os.remove(claude_md)
    if "gateEdits" in manifest and ".claude/settings.json" in \
            manifest.get("gateEdits", []):
        log("clean: deny rules in .claude/settings.json left in place "
            "(protective; remove by hand if you truly want them gone)")


def main():
    ap = argparse.ArgumentParser(description="ccds gate staging (ADR-0013)")
    ap.add_argument("--target", required=True)
    ap.add_argument("--templates",
                    default=os.path.join(os.path.dirname(
                        os.path.dirname(os.path.abspath(__file__))),
                        "templates"))
    ap.add_argument("--clean", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    target = os.path.abspath(args.target)
    if not os.path.isdir(target):
        print("gates: target not a directory: %s" % target, file=sys.stderr)
        return 2
    if args.clean:
        clean(target, args.dry_run)
        return 0

    matrix = load_json(os.path.join(args.templates, "stack-matrix.json"))
    if not matrix:
        log("stack matrix missing/unreadable (%s); gates skipped"
            % os.path.join(args.templates, "stack-matrix.json"))
        return 0

    stacks = detect_stacks(target, matrix)
    log("detected stack(s): %s" % ", ".join(stacks))

    prior = (load_json(os.path.join(target, MANIFEST_REL)) or {}) \
        .get("managedGateFiles", [])
    created, edits = [], []

    stage_settings(target, args.templates, args.dry_run, edits)
    stage_claude_block(target, args.templates, args.dry_run, edits)

    precommit = assemble(args.templates, matrix, stacks, "precommit")
    if precommit:
        stage_created_file(target, ".pre-commit-config.yaml", precommit,
                           prior, args.dry_run, created, "pre-commit")
    ci = assemble(args.templates, matrix, stacks, "ci")
    if ci:
        stage_created_file(target, ".github/workflows/ccds-quality.yml", ci,
                           prior, args.dry_run, created, "ci")

    update_manifest(target, created, edits, args.dry_run)
    if args.dry_run:
        log("dry run — nothing written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
