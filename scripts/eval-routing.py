#!/usr/bin/env python3
"""
eval-routing.py — routing eval for the catalog's description surface.

CLAUDE.md: "Descriptions are the routing surface." This harness treats routing
as a retrieval problem: every golden prompt in evals/routing/golden.json is
scored against every catalog entry by TF-IDF cosine over lowercase word tokens
of `name + description` (document frequencies from the catalog corpus itself).
A positive case passes when any of its acceptable targets lands in the top-K
(default 3); a negative case ("write a haiku") passes when its best score
stays under --floor. Cases marked "known_gap" report WARN, not FAIL — a
documented gap stays visible without breaking CI.

Be honest about what this measures: the deterministic mode is an
ambiguity/regression LINT — a lexical proxy for routing, cheap and
reproducible, good at catching description drift, keyword collisions, and
vocabulary that no user would ever hit. It is NOT a routing-accuracy
measurement; the model routes semantically, not lexically. --llm is the
accuracy mode: it asks `claude -p` to pick the single catalog entry per prompt
(majority of --votes). That spends real API tokens — release time only.

--ambiguity ignores golden.json entirely and reports catalog description
pairs whose cosine exceeds --threshold (description text only — names are
excluded so shared pack prefixes don't inflate the score). Informational:
always exits 0.

Usage:
    python3 scripts/eval-routing.py [repo-root] [options]

Options:
    --top-k N        positive passes if an expected name is in top-N (default 3)
    --floor F        negative passes if its top-1 score is below F (default
                     0.12 — calibrated 2026-07-03: the worst real-catalog
                     negative scores 0.104 ("write a haiku" grazing
                     loop-compound on the shared token "write"); expected-hit
                     scores for positives run 0.096-0.457, but the floor gates
                     negatives only)
    --ambiguity      report catalog description pairs with cosine >= --threshold
    --threshold F    ambiguity report floor (default 0.25 — calibrated
                     2026-07-03: yields 13 pairs on the 115-entry catalog,
                     all real sibling overlaps; 0.30 hides all but 3, 0.20
                     admits noise)
    --llm            route each golden prompt via `claude -p`; EXPENSIVE
    --votes N        llm runs per prompt, majority decides (default 3)
    --model NAME     model alias passed to claude -p (default haiku)
    --only ID        run a single golden case
    --dry-run        validate golden.json against catalog.json, run nothing

Exit codes: 0 = all pass, 1 = failures, 2 = config error.
"""

import json
import math
import os
import re
import subprocess
import sys
from collections import Counter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

TOKEN_RE = re.compile(r"[a-z0-9]+")


def parse_args(argv):
    args = {"root": None, "top_k": 3, "floor": 0.12, "ambiguity": False,
            "threshold": 0.25, "llm": False, "votes": 3, "model": "haiku",
            "only": None, "dry_run": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--top-k":
            args["top_k"] = int(argv[i + 1]); i += 2
        elif a == "--floor":
            args["floor"] = float(argv[i + 1]); i += 2
        elif a == "--ambiguity":
            args["ambiguity"] = True; i += 1
        elif a == "--threshold":
            args["threshold"] = float(argv[i + 1]); i += 2
        elif a == "--llm":
            args["llm"] = True; i += 1
        elif a == "--votes":
            args["votes"] = int(argv[i + 1]); i += 2
        elif a == "--model":
            args["model"] = argv[i + 1]; i += 2
        elif a == "--only":
            args["only"] = argv[i + 1]; i += 2
        elif a == "--dry-run":
            args["dry_run"] = True; i += 1
        elif a.startswith("--"):
            print(f"ERROR: unknown flag {a}", file=sys.stderr); sys.exit(2)
        else:
            args["root"] = a; i += 1
    args["root"] = os.path.abspath(args["root"] or os.path.dirname(SCRIPT_DIR))
    return args


def tokenize(text):
    return TOKEN_RE.findall(text.lower())


def load_catalog(root):
    path = os.path.join(root, "catalog.json")
    if not os.path.isfile(path):
        print(f"ERROR: not found: {path}", file=sys.stderr); sys.exit(2)
    with open(path, encoding="utf-8") as f:
        catalog = json.load(f)
    if not catalog:
        print("ERROR: catalog.json is empty", file=sys.stderr); sys.exit(2)
    return catalog


def load_golden(root, catalog_names):
    path = os.path.join(root, "evals", "routing", "golden.json")
    if not os.path.isfile(path):
        print(f"ERROR: not found: {path}", file=sys.stderr); sys.exit(2)
    with open(path, encoding="utf-8") as f:
        cases = json.load(f).get("cases", [])
    problems, seen = [], set()
    for c in cases:
        cid = c.get("id", "<no id>")
        for key in ("id", "prompt", "expect"):
            if key not in c:
                problems.append(f"{cid}: missing '{key}'")
        if cid in seen:
            problems.append(f"{cid}: duplicate id")
        seen.add(cid)
        for name in c.get("expect", []):
            if name not in catalog_names:
                problems.append(f"{cid}: expect name not in catalog: {name!r}")
        if c.get("negative") and c.get("expect"):
            problems.append(f"{cid}: negative case must have empty expect")
        if not c.get("negative") and not c.get("expect"):
            problems.append(f"{cid}: positive case needs at least one expect")
    if problems:
        for p in problems:
            print(f"ERROR: {p}", file=sys.stderr)
        sys.exit(2)
    return cases


class Tfidf:
    """TF-IDF vectors over the catalog corpus; cosine via normalized dot."""

    def __init__(self, docs):
        self.n = len(docs)
        self.df = Counter()
        for tokens in docs:
            self.df.update(set(tokens))
        self.idf = {t: math.log(self.n / df) for t, df in self.df.items()}

    def vector(self, tokens, count_oov=False):
        """Normalized TF-IDF vector. With count_oov (queries), tokens outside
        the catalog vocabulary still contribute to the norm at max idf —
        unknown vocabulary is evidence the prompt is off-catalog, so it should
        pull the cosine down rather than silently vanish."""
        tf = Counter(tokens)
        oov_idf = math.log(self.n)
        vec = {t: c * self.idf[t] for t, c in tf.items() if t in self.idf}
        sq = sum(w * w for w in vec.values())
        if count_oov:
            sq += sum((c * oov_idf) ** 2 for t, c in tf.items()
                      if t not in self.idf)
        norm = math.sqrt(sq)
        return {t: w / norm for t, w in vec.items()} if norm else {}

    @staticmethod
    def cosine(a, b):
        if len(b) < len(a):
            a, b = b, a
        return sum(w * b[t] for t, w in a.items() if t in b)


def rank(model, entry_vecs, prompt):
    qv = model.vector(tokenize(prompt), count_oov=True)
    scored = [(model.cosine(qv, ev), name) for name, ev in entry_vecs]
    scored.sort(key=lambda s: (-s[0], s[1]))
    return scored


def run_deterministic(cases, catalog, args):
    # Score against name + description: both are visible to the router.
    docs = [tokenize(e["name"] + " " + e["description"]) for e in catalog]
    model = Tfidf(docs)
    entry_vecs = [(e["name"], model.vector(d)) for e, d in zip(catalog, docs)]

    failures = warns = 0
    for c in cases:
        scored = rank(model, entry_vecs, c["prompt"])
        top = scored[:args["top_k"]]
        top_str = " ".join(f"{n}({s:.3f})" for s, n in top)
        if c.get("negative"):
            passed = top[0][0] < args["floor"]
            detail = f"top1: {top_str.split(' ')[0]} floor {args['floor']}"
        else:
            passed = any(n in c["expect"] for _, n in top)
            detail = f"top{args['top_k']}: {top_str}"
        if passed:
            print(f"  PASS  {c['id']:28s} {detail}")
        elif c.get("known_gap"):
            warns += 1
            print(f"  WARN  {c['id']:28s} known gap — {detail}")
            if c.get("note"):
                print(f"        note: {c['note']}")
        else:
            failures += 1
            print(f"  FAIL  {c['id']:28s} {detail}"
                  + ("" if c.get("negative") else f"  wanted: {c['expect']}"))
    return failures, warns


def run_ambiguity(catalog, args):
    # Descriptions only: names share pack prefixes, which would inflate cosine.
    docs = [tokenize(e["description"]) for e in catalog]
    model = Tfidf(docs)
    vecs = [(e["name"], model.vector(d)) for e, d in zip(catalog, docs)]
    pairs = []
    for i in range(len(vecs)):
        for j in range(i + 1, len(vecs)):
            s = model.cosine(vecs[i][1], vecs[j][1])
            if s >= args["threshold"]:
                pairs.append((s, vecs[i][0], vecs[j][0]))
    pairs.sort(key=lambda p: (-p[0], p[1], p[2]))
    for s, a, b in pairs:
        print(f"  {s:.3f}  {a} <-> {b}")
    print()
    print("=== routing-eval summary (ambiguity) ===")
    print(f"Entries   : {len(catalog)}")
    print(f"Pairs >= {args['threshold']}: {len(pairs)}")
    print("RESULT: PASS (informational)")
    return 0


LLM_PROMPT = """A user gave this task to a development assistant:

{prompt}

The assistant routes tasks using this catalog of agents and skills
(one per line, "name: description"):

{listing}

Which single catalog entry should handle the task? Reply with exactly one
catalog name, or NONE if no entry applies. Reply with only the name."""


def llm_vote(prompt, listing, names, model_alias):
    r = subprocess.run(
        ["claude", "-p", LLM_PROMPT.format(prompt=prompt, listing=listing),
         "--model", model_alias],
        capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        raise RuntimeError(
            f"claude -p failed (exit {r.returncode}): {r.stderr.strip()[:200]}")
    reply = r.stdout.strip()
    if reply in names:
        return reply
    if "NONE" in reply:
        return "NONE"
    # Tolerate prose around the name: longest catalog name present wins.
    hits = [n for n in names if re.search(rf"\b{re.escape(n)}\b", reply)]
    return max(hits, key=len) if hits else reply.split()[-1] if reply else ""


def run_llm(cases, catalog, args):
    listing = "\n".join(f"{e['name']}: {e['description']}" for e in catalog)
    names = {e["name"] for e in catalog}
    failures = 0
    for c in cases:
        votes = []
        for v in range(args["votes"]):
            choice = llm_vote(c["prompt"], listing, names, args["model"])
            votes.append(choice)
            print(f"  {c['id']} vote {v + 1}/{args['votes']}: {choice}")
        winner, count = Counter(votes).most_common(1)[0]
        if c.get("negative"):
            passed = winner == "NONE"
        else:
            passed = winner in c["expect"] and count > args["votes"] / 2
        print(f"{c['id']}: {'PASS' if passed else 'FAIL'} "
              f"(winner {winner!r}, {count}/{args['votes']} votes)")
        failures += 0 if passed else 1
    return failures


def main():
    args = parse_args(sys.argv[1:])
    catalog = load_catalog(args["root"])
    if args["ambiguity"]:
        return run_ambiguity(catalog, args)

    names = {e["name"] for e in catalog}
    cases = load_golden(args["root"], names)
    if args["only"]:
        cases = [c for c in cases if c["id"] == args["only"]]
        if not cases:
            print(f"ERROR: no case with id {args['only']!r}", file=sys.stderr)
            return 2

    positives = sum(1 for c in cases if not c.get("negative"))
    negatives = len(cases) - positives

    if args["dry_run"]:
        print(f"{len(cases)} case(s) valid ({positives} positive, "
              f"{negatives} negative); all expect names exist in the "
              f"{len(catalog)}-entry catalog.")
        return 0

    if args["llm"]:
        failures, warns = run_llm(cases, catalog, args), 0
        mode = "llm"
    else:
        failures, warns = run_deterministic(cases, catalog, args)
        mode = "deterministic"

    print()
    print(f"=== routing-eval summary ({mode}) ===")
    print(f"Cases     : {len(cases)} ({positives} positive, {negatives} negative)")
    print(f"Failures  : {failures}")
    print(f"Known gaps: {warns} (WARN)")
    print("RESULT: " + ("FAIL" if failures else "PASS"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
