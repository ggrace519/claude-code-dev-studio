#!/usr/bin/env python3
"""
Tests for the playbook's build/lint scripts.

Each test builds a minimal synthetic library (one agent + a couple of skills)
in a temp directory, generates its catalog with build-catalog.py, then runs
the script under test against the fixture via subprocess — the scripts are
CLI tools, so the tests exercise them exactly the way CI and users do.

Run: python3 -m unittest discover -s tests -v
"""

import getpass
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

    def test_skill_voice_fails(self):
        write(os.path.join(self.root, "skills", "saas-billing", "SKILL.md"),
              SKILL_TMPL.format(name="saas-billing",
                                description="Billing integration specialist. Auto-invoked when webhooks are handled.",
                                body="You do NOT own billing topology."))
        self.regen_catalog()
        r = self.lint()
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("skill-voice", r.stdout)

    def test_skill_voice_exempts_playbook_conventions(self):
        # Fixture's playbook-conventions body mentions the orchestrator on purpose.
        r = self.lint()
        self.assertNotIn("skills/playbook-conventions: ", r.stdout)

    def test_dated_model_fails(self):
        write(self.agent_path(),
              AGENT_TMPL.format(extra="").replace("model: opus", "model: claude-opus-4-7"))
        self.regen_catalog()
        r = self.lint()
        self.assertEqual(r.returncode, 1)
        self.assertIn("model-values", r.stdout)


@unittest.skipUnless(os.path.isfile(BUILD_MARKETPLACE),
                     "build-marketplace.py not on this branch yet")
class TestBuildMarketplace(unittest.TestCase):
    """Runs the marketplace generator against the real repo tree (read-only
    inputs; output goes to the checked-in plugins/ dir, which the test
    regenerates and asserts is git-clean elsewhere — here we assert shape)."""

    def test_generates_valid_marketplace(self):
        # No --version: the committed tree is unversioned (git-commit-driven),
        # so a bare regen must reproduce it byte-for-byte (this is what the
        # marketplace-freshness CI job asserts).
        r = run(BUILD_MARKETPLACE, REPO_ROOT)
        self.assertEqual(r.returncode, 0, r.stderr)
        m = json.loads(read(os.path.join(REPO_ROOT, ".claude-plugin", "marketplace.json")))
        self.assertEqual(m["name"], "ccds")
        self.assertEqual(len(m["plugins"]), 15)
        for p in m["plugins"]:
            self.assertNotIn("version", p, "default tree must be unversioned")
            pdir = os.path.join(REPO_ROOT, p["source"].lstrip("./"))
            manifest = json.loads(read(os.path.join(pdir, ".claude-plugin", "plugin.json")))
            self.assertNotIn("version", manifest, p["name"])

    def test_explicit_version_pins_plugins(self):
        try:
            r = run(BUILD_MARKETPLACE, REPO_ROOT, "--version", "0.0.0-test")
            self.assertEqual(r.returncode, 0, r.stderr)
            m = json.loads(read(os.path.join(REPO_ROOT, ".claude-plugin", "marketplace.json")))
            self.assertEqual(m["metadata"]["version"], "0.0.0-test")
            self.assertTrue(all(p["version"] == "0.0.0-test" for p in m["plugins"]))
        finally:
            # restore the checked-in (unversioned) tree
            subprocess.run(["git", "-C", REPO_ROOT, "checkout", "--", ".claude-plugin", "plugins"],
                           capture_output=True)


PACKAGING = os.path.join(REPO_ROOT, "packaging")
POSTINST = os.path.join(PACKAGING, "postinst")
USER_SETUP = os.path.join(SCRIPTS, "ccds-user-setup.sh")
BASH = shutil.which("bash")

# Cross-cutting skills the per-user setup installs to ~/.claude/skills/.
# Mirrors GLOBAL_SKILLS in scripts/ccds-user-setup.sh.
GLOBAL_SKILLS = (
    "playbook-conventions", "sync-agents", "api-design", "ux-design",
    "security-checklist", "code-review-checklist", "common-a11y",
    "common-i18n", "common-privacy", "common-notifications",
    "common-product-analytics",
)


@unittest.skipUnless(BASH and sys.platform != "win32",
                     "postinst is a bash maintainer script (POSIX shells only)")
class TestDebPostinst(unittest.TestCase):
    """Regression tests for the Debian/RPM postinst per-user setup.

    Stages the package library exactly as build-release.sh does
    (/usr/share/ccds layout), then drives packaging/postinst against it with
    a patched INSTALL_ROOT and PATH stubs for the privilege-drop tools — so
    the test never needs root and never touches the real $HOME.

    Guards the bug where the postinst only populated ~/.claude when $SUDO_USER
    was set, silently installing nothing for root-shell / GUI / CI / Docker
    installs.
    """

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="ccds-deb-test-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

        # Stage the package library: /usr/share/ccds/{agents,skills,scripts}
        self.pkg = os.path.join(self.root, "usr", "share", "ccds")
        os.makedirs(os.path.join(self.pkg, "agents"))
        os.makedirs(os.path.join(self.pkg, "scripts"))
        for md in os.listdir(os.path.join(REPO_ROOT, ".claude", "agents")):
            if md.endswith(".md"):
                shutil.copy(os.path.join(REPO_ROOT, ".claude", "agents", md),
                            os.path.join(self.pkg, "agents", md))
        shutil.copytree(os.path.join(REPO_ROOT, "skills"),
                        os.path.join(self.pkg, "skills"))
        shutil.copy(USER_SETUP, os.path.join(self.pkg, "scripts", "ccds-user-setup.sh"))
        shutil.copy(os.path.join(SCRIPTS, "jit-claude.md"),
                    os.path.join(self.pkg, "scripts", "jit-claude.md"))

        # postinst hardcodes INSTALL_ROOT=/usr/share/ccds; point it at our stage.
        with open(POSTINST, encoding="utf-8") as f:
            src = f.read()
        patched = src.replace('INSTALL_ROOT="/usr/share/ccds"',
                              'INSTALL_ROOT="%s"' % self.pkg)
        self.assertIn('INSTALL_ROOT="%s"' % self.pkg, patched,
                      "postinst INSTALL_ROOT assignment changed shape")
        self.postinst = os.path.join(self.root, "postinst")
        with open(self.postinst, "w", encoding="utf-8", newline="\n") as f:
            f.write(patched)

        self.home = os.path.join(self.root, "home")
        os.makedirs(self.home)
        self.stubbin = os.path.join(self.root, "stubbin")
        os.makedirs(self.stubbin)

    def _stub(self, name, body):
        path = os.path.join(self.stubbin, name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("#!/bin/bash\n" + body + "\n")
        os.chmod(path, 0o755)

    def _run(self, env_overrides):
        env = {"HOME": self.home, "PATH": self.stubbin + os.pathsep + os.environ["PATH"]}
        env.update(env_overrides)
        return subprocess.run([BASH, self.postinst],
                              capture_output=True, text=True, env=env)

    def test_syntax_valid(self):
        r = subprocess.run([BASH, "-n", POSTINST], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_identifiable_user_populates_home(self):
        # runuser stub: "runuser -u USER -- bash SETUP ROOT" -> drop first 3 args,
        # exec the rest in-process so setup runs against our fake $HOME.
        self._stub("runuser", 'shift 3\nexec "$@"')
        # Use the real current user so the postinst's `getent passwd` probe accepts
        # the candidate; the runuser stub keeps execution in-process (no real drop).
        r = self._run({"SUDO_USER": getpass.getuser()})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("Running per-user setup", r.stdout)

        agents = os.path.join(self.home, ".claude", "agents")
        self.assertTrue(os.path.isdir(agents), r.stdout + r.stderr)
        self.assertEqual(len([f for f in os.listdir(agents) if f.endswith(".md")]), 19)

        skills = os.path.join(self.home, ".claude", "skills")
        for name in GLOBAL_SKILLS:
            self.assertTrue(os.path.isfile(os.path.join(skills, name, "SKILL.md")),
                            "missing cross-cutting skill: " + name)

        claude_md = read(os.path.join(self.home, ".claude", "CLAUDE.md"))
        self.assertIn("# >>> ccds >>>", claude_md)
        self.assertIn("# <<< ccds <<<", claude_md)

    def test_headless_root_prints_instructions_and_no_op(self):
        # No identifiable user: SUDO_USER/PKEXEC_UID unset, logname fails.
        self._stub("logname", "exit 1")
        r = self._run({})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("ccds setup", r.stdout)
        # The bug under test: nothing must be silently half-installed, but also
        # the install must not error out — ~/.claude stays untouched here.
        self.assertFalse(os.path.isdir(os.path.join(self.home, ".claude", "agents")))


if __name__ == "__main__":
    unittest.main()
