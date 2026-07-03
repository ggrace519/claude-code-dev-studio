#!/usr/bin/env python3
"""
eval-loop-compliance.py — pressure-test the loop-* process skills.

RED/GREEN for prose (INNOVATIONS.md 2026-07-03 #4): each scenario in
evals/loop-compliance/scenarios.json puts a skill's iron law under a
conflicting incentive ("production is bleeding money, just say it's done").
The skill body is injected via --append-system-prompt, the scenario prompt is
sent with `claude -p`, and the reply is scored against coarse shape patterns:
every `pass_if` regex must match, no `fail_if` regex may match. A scenario
passes on a majority of votes (default 3 — single runs are noisy).

A skill that fails gets its WORDING strengthened, then re-run — compliance is
a measurable property of the text (superpowers moved it 33%→72% with wording
changes alone).

This spends real API tokens: run at release time or after editing a loop-*
skill, not per-PR.

Usage:
    python3 scripts/eval-loop-compliance.py [repo-root] [options]

Options:
    --votes N          runs per scenario, majority decides (default 3)
    --model NAME       model alias passed to claude -p (default haiku)
    --only ID          run a single scenario
    --dry-run          validate scenarios.json + skill files, run nothing
    --score-file ID F  offline: score the text in file F against scenario ID
                       (no API call — this is what the pytest suite exercises)

Exit codes: 0 = all pass, 1 = failures, 2 = config error.
"""

import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def parse_args(argv):
    args = {"root": None, "votes": 3, "model": "haiku", "only": None,
            "dry_run": False, "score_file": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--votes":
            args["votes"] = int(argv[i + 1]); i += 2
        elif a == "--model":
            args["model"] = argv[i + 1]; i += 2
        elif a == "--only":
            args["only"] = argv[i + 1]; i += 2
        elif a == "--dry-run":
            args["dry_run"] = True; i += 1
        elif a == "--score-file":
            args["score_file"] = (argv[i + 1], argv[i + 2]); i += 3
        elif a.startswith("--"):
            print(f"ERROR: unknown flag {a}", file=sys.stderr); sys.exit(2)
        else:
            args["root"] = a; i += 1
    args["root"] = os.path.abspath(args["root"] or os.path.dirname(SCRIPT_DIR))
    return args


def load_scenarios(root):
    path = os.path.join(root, "evals", "loop-compliance", "scenarios.json")
    if not os.path.isfile(path):
        print(f"ERROR: not found: {path}", file=sys.stderr); sys.exit(2)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    scenarios = data.get("scenarios", [])
    problems = []
    for s in scenarios:
        for key in ("id", "skill", "prompt", "pass_if", "fail_if"):
            if key not in s:
                problems.append(f"{s.get('id', '<no id>')}: missing '{key}'")
        for pat in s.get("pass_if", []) + s.get("fail_if", []):
            try:
                re.compile(pat)
            except re.error as e:
                problems.append(f"{s.get('id')}: bad regex {pat!r} ({e})")
        skill_md = os.path.join(root, "skills", s.get("skill", ""), "SKILL.md")
        if not os.path.isfile(skill_md):
            problems.append(f"{s.get('id')}: skill file missing: {skill_md}")
    if problems:
        for p in problems:
            print(f"ERROR: {p}", file=sys.stderr)
        sys.exit(2)
    return scenarios


def score(scenario, output):
    """Return (passed, reasons). Every pass_if must match; no fail_if may."""
    reasons = []
    for pat in scenario["pass_if"]:
        if not re.search(pat, output):
            reasons.append(f"pass_if not matched: {pat!r}")
    for pat in scenario["fail_if"]:
        if re.search(pat, output):
            reasons.append(f"fail_if matched: {pat!r}")
    return (not reasons, reasons)


def run_vote(scenario, root, model):
    skill_md = os.path.join(root, "skills", scenario["skill"], "SKILL.md")
    with open(skill_md, encoding="utf-8") as f:
        skill_body = f.read()
    sys_prompt = ("You have the following skill loaded. It applies to this "
                  "request; follow it.\n\n" + skill_body)
    r = subprocess.run(
        ["claude", "-p", scenario["prompt"],
         "--append-system-prompt", sys_prompt, "--model", model],
        capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        raise RuntimeError(f"claude -p failed (exit {r.returncode}): {r.stderr.strip()[:200]}")
    return r.stdout


def main():
    args = parse_args(sys.argv[1:])
    scenarios = load_scenarios(args["root"])
    if args["only"]:
        scenarios = [s for s in scenarios if s["id"] == args["only"]]
        if not scenarios:
            print(f"ERROR: no scenario with id {args['only']!r}", file=sys.stderr)
            return 2

    if args["score_file"]:
        sid, path = args["score_file"]
        matches = [s for s in scenarios if s["id"] == sid]
        if not matches:
            print(f"ERROR: no scenario with id {sid!r}", file=sys.stderr)
            return 2
        with open(path, encoding="utf-8") as f:
            output = f.read()
        passed, reasons = score(matches[0], output)
        print(f"{sid}: {'PASS' if passed else 'FAIL'}")
        for reason in reasons:
            print(f"  {reason}")
        return 0 if passed else 1

    if args["dry_run"]:
        print(f"{len(scenarios)} scenario(s) valid; skills present; regexes compile.")
        for s in scenarios:
            print(f"  {s['id']:28s} -> {s['skill']}")
        return 0

    failures = 0
    for s in scenarios:
        votes = []
        for v in range(args["votes"]):
            output = run_vote(s, args["root"], args["model"])
            passed, reasons = score(s, output)
            votes.append(passed)
            tag = "pass" if passed else "fail"
            print(f"  {s['id']} vote {v + 1}/{args['votes']}: {tag}"
                  + ("" if passed else f"  ({'; '.join(reasons)})"))
        majority = sum(votes) > args["votes"] / 2
        print(f"{s['id']}: {'PASS' if majority else 'FAIL'} "
              f"({sum(votes)}/{args['votes']} votes)")
        failures += 0 if majority else 1

    print()
    print("=== loop-compliance summary ===")
    print(f"Scenarios : {len(scenarios)}")
    print(f"Failures  : {failures}")
    print("RESULT: " + ("FAIL" if failures else "PASS"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
