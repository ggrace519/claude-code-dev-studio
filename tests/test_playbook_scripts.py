#!/usr/bin/env python3
"""
Tests for the playbook's build/lint scripts.

Each test builds a minimal synthetic library (one agent + a couple of skills)
in a temp directory, generates its catalog with build-catalog.py, then runs
the script under test against the fixture via subprocess — the scripts are
CLI tools, so the tests exercise them exactly the way CI and users do.

Run: python3 -m unittest discover -s tests -v
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(REPO_ROOT, "scripts")
BUILD_CATALOG = os.path.join(SCRIPTS, "build-catalog.py")
LINT_PLAYBOOK = os.path.join(SCRIPTS, "lint-playbook.py")
BUILD_MARKETPLACE = os.path.join(SCRIPTS, "build-marketplace.py")

AGENT_TMPL = """---
name: saas-architect
model: opus
description: SaaS domain specialist. Use proactively on multi-tenant work. Owns SaaS architecture and composes the saas-* implementation skills.
---

# SaaS Domain Specialist

Skills you compose: `saas-billing`.
{extra}
"""

SKILL_TMPL = """---
name: {name}
description: {description}
---

# {name}

{body}
"""


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def run(script, *args):
    return subprocess.run([sys.executable, script, *args],
                          capture_output=True, text=True)


class FixtureCase(unittest.TestCase):
    """Builds a minimal valid library in a temp dir; tests mutate it to break."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="ccds-test-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        write(os.path.join(self.root, ".claude", "agents", "saas-architect.md"),
              AGENT_TMPL.format(extra=""))
        write(os.path.join(self.root, "skills", "saas-billing", "SKILL.md"),
              SKILL_TMPL.format(name="saas-billing",
                                description="Billing integration specialist. Auto-invoked when webhooks are handled.",
                                body="Idempotency everywhere."))
        write(os.path.join(self.root, "skills", "playbook-conventions", "SKILL.md"),
              SKILL_TMPL.format(name="playbook-conventions",
                                description="Shared output structure and ADR format.",
                                body="Lead with a summary. Return to the orchestrator when handing off."))
        self.regen_catalog()

    def regen_catalog(self):
        r = run(BUILD_CATALOG, self.root, os.path.join(self.root, "catalog.json"))
        self.assertEqual(r.returncode, 0, r.stderr)

    def agent_path(self):
        return os.path.join(self.root, ".claude", "agents", "saas-architect.md")

    def lint(self):
        return run(LINT_PLAYBOOK, self.root)


class TestBuildCatalog(FixtureCase):

    def test_catalog_contents(self):
        cat = json.loads(read(os.path.join(self.root, "catalog.json")))
        by_name = {e["name"]: e for e in cat}
        self.assertEqual(len(cat), 3)
        self.assertEqual(by_name["saas-architect"]["kind"], "agent")
        self.assertEqual(by_name["saas-architect"]["scope"], "global")
        self.assertEqual(by_name["saas-architect"]["model"], "opus")
        self.assertEqual(by_name["saas-billing"]["kind"], "skill")
        self.assertEqual(by_name["saas-billing"]["scope"], "project")
        self.assertEqual(by_name["playbook-conventions"]["scope"], "global")

    def test_deterministic(self):
        first = read(os.path.join(self.root, "catalog.json"))
        self.regen_catalog()
        second = read(os.path.join(self.root, "catalog.json"))
        self.assertEqual(first, second)


class TestLintPlaybook(FixtureCase):

    def test_clean_fixture_passes(self):
        r = self.lint()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("RESULT: PASS", r.stdout)

    def test_ghost_skill_reference_fails(self):
        write(self.agent_path(), AGENT_TMPL.format(extra="Also pull `saas-ghost`."))
        r = self.lint()
        self.assertEqual(r.returncode, 1)
        self.assertIn("skill-refs", r.stdout)
        self.assertIn("saas-ghost", r.stdout)

    def test_unreferenced_pack_skill_fails(self):
        write(os.path.join(self.root, "skills", "saas-orphan", "SKILL.md"),
              SKILL_TMPL.format(name="saas-orphan",
                                description="Orphan skill no agent references.",
                                body="Content."))
        self.regen_catalog()
        r = self.lint()
        self.assertEqual(r.returncode, 1)
        self.assertIn("reverse-refs", r.stdout)

    def test_stale_catalog_fails(self):
        write(os.path.join(self.root, "skills", "saas-billing", "SKILL.md"),
              SKILL_TMPL.format(name="saas-billing",
                                description="A changed description that is not in the catalog.",
                                body="Idempotency everywhere."))
        r = self.lint()
        self.assertEqual(r.returncode, 1)
        self.assertIn("catalog-fresh", r.stdout)

    def test_wrong_repo_owner_fails(self):
        write(os.path.join(self.root, "skills", "saas-billing", "SKILL.md"),
              SKILL_TMPL.format(name="saas-billing",
                                description="Billing integration specialist. Auto-invoked when webhooks are handled.",
                                body="Install from https://github.com/wrong-owner/claude-code-dev-studio."))
        self.regen_catalog()
        r = self.lint()
        self.assertEqual(r.returncode, 1)
        self.assertIn("url-consistency", r.stdout)

    def test_skill_voice_warns_but_passes(self):
        write(os.path.join(self.root, "skills", "saas-billing", "SKILL.md"),
              SKILL_TMPL.format(name="saas-billing",
                                description="Billing integration specialist. Auto-invoked when webhooks are handled.",
                                body="You do NOT own billing topology."))
        self.regen_catalog()
        r = self.lint()
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("skill-voice", r.stdout)

    def test_skill_voice_exempts_playbook_conventions(self):
        # Fixture's playbook-conventions body mentions the orchestrator on purpose.
        r = self.lint()
        self.assertNotIn("skills/playbook-conventions: ", r.stdout)

    def test_dated_model_warns_but_passes(self):
        write(self.agent_path(),
              AGENT_TMPL.format(extra="").replace("model: opus", "model: claude-opus-4-7"))
        self.regen_catalog()
        r = self.lint()
        self.assertEqual(r.returncode, 0)
        self.assertIn("model-values", r.stdout)


@unittest.skipUnless(os.path.isfile(BUILD_MARKETPLACE),
                     "build-marketplace.py not on this branch yet")
class TestBuildMarketplace(unittest.TestCase):
    """Runs the marketplace generator against the real repo tree (read-only
    inputs; output goes to the checked-in plugins/ dir, which the test
    regenerates and asserts is git-clean elsewhere — here we assert shape)."""

    def test_generates_valid_marketplace(self):
        r = run(BUILD_MARKETPLACE, REPO_ROOT, "--version", "0.0.0-test")
        self.assertEqual(r.returncode, 0, r.stderr)
        m = json.loads(read(os.path.join(REPO_ROOT, ".claude-plugin", "marketplace.json")))
        self.assertEqual(m["name"], "ccds")
        self.assertEqual(len(m["plugins"]), 15)
        for p in m["plugins"]:
            pdir = os.path.join(REPO_ROOT, p["source"].lstrip("./"))
            self.assertTrue(os.path.isfile(os.path.join(pdir, ".claude-plugin", "plugin.json")), p["name"])
        # restore the checked-in version stamp
        subprocess.run(["git", "-C", REPO_ROOT, "checkout", "--", ".claude-plugin", "plugins"],
                       capture_output=True)


if __name__ == "__main__":
    unittest.main()
