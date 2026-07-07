#!/usr/bin/env python3
"""
evidence-to-evals.py — turn recurring FAIL verdicts into eval stubs.

Closes the compound loop mechanically (loop-compound: "second occurrence ->
write it where the next session reads it"). It scans the evidence sink for tasks
that have FAILed repeatedly and emits pressure-test STUBS in the EXISTING
evals/loop-compliance/scenarios.json schema — so a recurring failure becomes a
command, not a good intention.

Source, in --source auto (default): Postgres when CCDS_EVIDENCE_DSN is set and
psql is on PATH (durable tier, cross-session), else the local
.claude/evidence/*.json files. Force with --source local|postgres.

Output: evals/loop-compliance/generated-stubs.json, a REVIEW file with the same
{"scenarios": [...]} shape as the curated set but deliberately separate — the
live runner reads scenarios.json only, so emitting here never disturbs the
committed compliance baseline. A human completes each stub's prompt/pass_if/
fail_if, moves the good ones into scenarios.json, and re-records the baseline.
Stubs whose id already exists in scenarios.json are skipped: once a failure has
been promoted to a real eval, it stops being re-emitted.

Stubs are schema-valid (required keys, compilable regexes, a real `skill` dir)
so `eval-loop-compliance.py --dry-run` accepts them after promotion.

Usage:
    python3 scripts/evidence-to-evals.py [repo-root] [options]

Options:
    --project DIR      where .claude/evidence/ lives (default: repo-root)
    --source MODE      auto | local | postgres      (default auto)
    --threshold N      min FAIL count to flag a task (default 2)
    --skill NAME       loop-* skill the stub pressure-tests (default loop-verify)
    --out PATH         output file (default evals/loop-compliance/generated-stubs.json)
    --dry-run          print the summary; write nothing

Exit codes: 0 = ran (with or without findings); 2 = config error.
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

DEFAULT_SKILL = "loop-verify"


def _kebab(text):
    s = re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")
    return s or "unnamed"


def scan_local(project, threshold):
    """Return {task: count} for FAIL verdicts in .claude/evidence/*.json."""
    counts = {}
    for p in glob.glob(os.path.join(project, ".claude", "evidence", "*.json")):
        try:
            with open(p, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError):
            continue
        if isinstance(d, dict) and d.get("verdict") == "FAIL":
            task = (d.get("task") or "").strip() or "(untitled task)"
            counts[task] = counts.get(task, 0) + 1
    return {t: n for t, n in counts.items() if n >= threshold}


def scan_postgres(threshold):
    """Return {task: count} via psql, or None if unavailable."""
    dsn = os.environ.get("CCDS_EVIDENCE_DSN", "").strip()
    if not dsn or not shutil.which("psql"):
        return None
    q = ("SELECT coalesce(task,'(untitled task)'), count(*) "
         "FROM agent_evidence WHERE verdict='FAIL' "
         "GROUP BY 1 HAVING count(*) >= %d ORDER BY 2 DESC;" % int(threshold))
    try:
        r = subprocess.run(["psql", dsn, "-tAF", "\t", "-c", q],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    counts = {}
    for line in r.stdout.splitlines():
        if "\t" not in line:
            continue
        task, _, n = line.rpartition("\t")
        try:
            counts[task.strip()] = int(n)
        except ValueError:
            continue
    return counts


def make_stub(task, count, source, skill, used_ids):
    base = "regression-" + _kebab(task)[:48]
    sid, i = base, 2
    while sid in used_ids:
        sid = "%s-%d" % (base, i)
        i += 1
    used_ids.add(sid)
    return {
        "id": sid,
        "skill": skill,
        "prompt": ("STUB — reconstruct the situation that produced this "
                   "recurring failure as a realistic user prompt. Task %r "
                   "recorded a FAIL verdict %d time(s) (source: %s)."
                   % (task, count, source)),
        "pass_if": [r"(?i)(verif|evidence|root cause|reproduce|fix|test)"],
        "fail_if": [],
        "_generated": True,
        "_source": "recurring FAIL: %r x%d (%s)" % (task, count, source),
        "_todo": ("Replace prompt/pass_if/fail_if with a real pressure-test, "
                  "move into scenarios.json, then re-record the baseline "
                  "(scripts/eval-loop-compliance.py --record)."),
    }


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--project", default=None)
    ap.add_argument("--source", choices=("auto", "local", "postgres"), default="auto")
    ap.add_argument("--threshold", type=int, default=2)
    ap.add_argument("--skill", default=DEFAULT_SKILL)
    ap.add_argument("--out", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    project = os.path.abspath(args.project) if args.project else root
    out = args.out or os.path.join(root, "evals", "loop-compliance",
                                   "generated-stubs.json")

    if args.threshold < 1:
        print("ERROR: --threshold must be >= 1", file=sys.stderr)
        return 2
    if not os.path.isdir(os.path.join(root, "skills", args.skill)):
        print("ERROR: --skill %r has no skills/%s/ dir" % (args.skill, args.skill),
              file=sys.stderr)
        return 2

    # --- gather counts from the chosen source ---
    if args.source == "postgres":
        counts = scan_postgres(args.threshold)
        if counts is None:
            print("ERROR: --source postgres but CCDS_EVIDENCE_DSN unset or psql "
                  "unavailable / query failed", file=sys.stderr)
            return 2
        source = "postgres"
    elif args.source == "local":
        counts, source = scan_local(project, args.threshold), "local"
    else:  # auto
        counts = scan_postgres(args.threshold)
        source = "postgres"
        if counts is None:
            counts, source = scan_local(project, args.threshold), "local"

    # --- skip tasks already promoted to a real scenario ---
    existing_ids = set()
    scen_path = os.path.join(root, "evals", "loop-compliance", "scenarios.json")
    try:
        with open(scen_path, encoding="utf-8") as f:
            existing_ids = {s.get("id") for s in json.load(f).get("scenarios", [])}
    except (OSError, json.JSONDecodeError, ValueError):
        pass

    used_ids = set()
    stubs = []
    for task, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        base_id = "regression-" + _kebab(task)[:48]
        if base_id in existing_ids:
            continue  # already an eval
        stubs.append(make_stub(task, n, source, args.skill, used_ids))

    print("evidence-to-evals: source=%s, threshold=%d, recurring tasks=%d, "
          "new stubs=%d" % (source, args.threshold, len(counts), len(stubs)))
    for s in stubs:
        print("  %-40s <- %s" % (s["id"], s["_source"]))

    if args.dry_run:
        print("(dry-run: wrote nothing)")
        return 0
    if not stubs:
        print("(no new recurring failures; wrote nothing)")
        return 0

    doc = {
        "$comment": ("GENERATED review stubs from recurring FAIL verdicts "
                     "(scripts/evidence-to-evals.py). NOT read by "
                     "eval-loop-compliance.py — review each stub, complete "
                     "prompt/pass_if/fail_if, move keepers into scenarios.json, "
                     "then re-record the baseline. Regenerated on each run."),
        "generated_from": "source=%s threshold=%d" % (source, args.threshold),
        "scenarios": stubs,
    }
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    print("wrote %d stub(s) -> %s" % (len(stubs), os.path.relpath(out, root)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
