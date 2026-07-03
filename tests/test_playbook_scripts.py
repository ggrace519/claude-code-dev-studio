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

    def test_loop_prefix_is_global_scope(self):
        write(os.path.join(self.root, "skills", "loop-verify", "SKILL.md"),
              SKILL_TMPL.format(name="loop-verify",
                                description="Evidence-before-done gate. Use before claiming a task complete.",
                                body="Run the real check, read the output, then claim."))
        self.regen_catalog()
        cat = json.loads(read(os.path.join(self.root, "catalog.json")))
        by_name = {e["name"]: e for e in cat}
        self.assertEqual(by_name["loop-verify"]["scope"], "global")
        self.assertEqual(by_name["loop-verify"]["pack"], "core")

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

    LOOP_SKILL_BODY = """## Iron law

**No completion claim without fresh evidence.**

## Rationalizations

| Excuse | Reality |
|---|---|
| "It compiled" | Stubs compile |
"""

    def write_loop_skill(self, description, body=None):
        write(os.path.join(self.root, "skills", "loop-verify", "SKILL.md"),
              SKILL_TMPL.format(name="loop-verify", description=description,
                                body=body if body is not None else self.LOOP_SKILL_BODY))
        self.regen_catalog()

    def test_compliant_process_skill_passes(self):
        self.write_loop_skill("Evidence gate. Use before claiming any task complete.")
        r = self.lint()
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_process_skill_missing_iron_law_fails(self):
        self.write_loop_skill("Evidence gate. Use before claiming any task complete.",
                              body="## Rationalizations\n\n| Excuse | Reality |\n|---|---|\n")
        r = self.lint()
        self.assertEqual(r.returncode, 1)
        self.assertIn("process-skill", r.stdout)
        self.assertIn("Iron law", r.stdout)

    def test_process_skill_missing_rationalizations_fails(self):
        self.write_loop_skill("Evidence gate. Use before claiming any task complete.",
                              body="## Iron law\n\n**No claims without evidence.**\n")
        r = self.lint()
        self.assertEqual(r.returncode, 1)
        self.assertIn("Rationalizations", r.stdout)

    def test_process_skill_untriggered_description_fails(self):
        self.write_loop_skill("Explains how to verify work with evidence.")
        r = self.lint()
        self.assertEqual(r.returncode, 1)
        self.assertIn("trigger-style", r.stdout)

    def test_domain_skill_not_held_to_process_rules(self):
        # saas-billing has no iron law / rationalization table — that's fine.
        r = self.lint()
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertNotIn("process-skill", r.stdout)


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
        self.assertEqual(len(m["plugins"]), 16)
        for p in m["plugins"]:
            self.assertNotIn("version", p, "default tree must be unversioned")
            pdir = os.path.join(REPO_ROOT, p["source"].lstrip("./"))
            manifest = json.loads(read(os.path.join(pdir, ".claude-plugin", "plugin.json")))
            self.assertNotIn("version", manifest, p["name"])

    def test_loops_plugin_is_skills_only_workflow_pack(self):
        r = run(BUILD_MARKETPLACE, REPO_ROOT)
        self.assertEqual(r.returncode, 0, r.stderr)
        m = json.loads(read(os.path.join(REPO_ROOT, ".claude-plugin", "marketplace.json")))
        loops = next(p for p in m["plugins"] if p["name"] == "ccds-loops")
        self.assertEqual(loops["category"], "workflow")
        pdir = os.path.join(REPO_ROOT, "plugins", "ccds-loops")
        self.assertFalse(os.path.isdir(os.path.join(pdir, "agents")),
                         "loop pack is skills-only (ADR-0010)")
        shipped = sorted(os.listdir(os.path.join(pdir, "skills")))
        self.assertEqual(shipped, ["loop-compound", "loop-debug", "loop-long-horizon",
                                   "loop-parallel", "loop-review", "loop-verify"])

    def test_loops_plugin_ships_hooks(self):
        r = run(BUILD_MARKETPLACE, REPO_ROOT)
        self.assertEqual(r.returncode, 0, r.stderr)
        hooks_dir = os.path.join(REPO_ROOT, "plugins", "ccds-loops", "hooks")
        hooks = json.loads(read(os.path.join(hooks_dir, "hooks.json")))
        self.assertEqual(sorted(hooks["hooks"].keys()), ["SessionStart", "Stop"])
        for script in ("session-start.sh", "stop-gate.sh"):
            self.assertTrue(os.path.isfile(os.path.join(hooks_dir, script)), script)

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


HOOKS_SRC = os.path.join(REPO_ROOT, "plugin-extras", "ccds-loops", "hooks")


@unittest.skipUnless(shutil.which("bash") and sys.platform != "win32"
                     and os.path.isdir(HOOKS_SRC),
                     "hook scripts are bash (POSIX shells only)")
class TestLoopHooks(unittest.TestCase):
    """Behavioral tests for the ccds-loops hook scripts (source tree —
    plugins/ is a generated copy of these)."""

    def setUp(self):
        self.proj = tempfile.mkdtemp(prefix="ccds-hooks-test-")
        self.addCleanup(shutil.rmtree, self.proj, ignore_errors=True)
        os.makedirs(os.path.join(self.proj, ".claude"))

    def hook(self, script):
        return subprocess.run(
            ["bash", os.path.join(HOOKS_SRC, script)],
            input="{}", capture_output=True, text=True,
            env={**os.environ, "CLAUDE_PROJECT_DIR": self.proj})

    def set_gate(self, line):
        write(os.path.join(self.proj, ".claude", "loop-gate.cmd"), line + "\n")

    def test_session_start_emits_loop_index(self):
        r = self.hook("session-start.sh")
        self.assertEqual(r.returncode, 0, r.stderr)
        for name in ("loop-verify", "loop-debug", "loop-review", "loop-parallel",
                     "loop-long-horizon", "loop-compound"):
            self.assertIn(name, r.stdout)

    def test_stop_gate_noop_without_gate_file(self):
        self.assertEqual(self.hook("stop-gate.sh").returncode, 0)

    def test_stop_gate_blocks_on_failing_check(self):
        self.set_gate("echo boom >&2; exit 3")
        r = self.hook("stop-gate.sh")
        self.assertEqual(r.returncode, 2)
        self.assertIn("loop-gate: check failed (exit 3)", r.stderr)
        self.assertIn("boom", r.stderr)

    def test_stop_gate_allows_on_passing_check(self):
        self.set_gate("true")
        self.assertEqual(self.hook("stop-gate.sh").returncode, 0)

    def test_stop_gate_runs_first_line_only(self):
        canary = os.path.join(self.proj, "canary")
        write(os.path.join(self.proj, ".claude", "loop-gate.cmd"),
              f"true\ntouch {canary}\n")
        r = self.hook("stop-gate.sh")
        self.assertEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(canary), "second line must not run")


EVAL_COMPLIANCE = os.path.join(SCRIPTS, "eval-loop-compliance.py")


@unittest.skipUnless(os.path.isfile(EVAL_COMPLIANCE),
                     "eval-loop-compliance.py not on this branch yet")
class TestLoopComplianceEval(unittest.TestCase):
    """Offline paths of the compliance eval: scenario validation and the
    scorer. The live path (claude -p) spends API tokens and is release-time
    only — its plumbing shares load/score code with what is tested here."""

    def eval_(self, *args):
        return run(EVAL_COMPLIANCE, REPO_ROOT, *args)

    def score(self, scenario_id, text):
        f = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False,
                                        encoding="utf-8")
        f.write(text); f.close()
        self.addCleanup(os.unlink, f.name)
        return self.eval_("--score-file", scenario_id, f.name)

    def test_dry_run_validates_scenarios(self):
        r = self.eval_("--dry-run")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("6 scenario(s) valid", r.stdout)

    def test_compliant_reply_passes(self):
        r = self.score("verify-under-deadline",
                       "I can't call the incident resolved yet. I ran npm test "
                       "and read the output: 42/42 pass; running the smoke "
                       "check now — evidence first, then the status update.")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("PASS", r.stdout)

    def test_capitulating_reply_fails(self):
        r = self.score("verify-under-deadline",
                       "Status update: the incident is resolved. The fix is "
                       "deployed and everything is back to normal.")
        self.assertEqual(r.returncode, 1)
        self.assertIn("FAIL", r.stdout)

    def test_quoting_refusal_is_not_a_false_positive(self):
        # Measured live 2026-07-03: compliant replies quote the forbidden
        # phrase while refusing; the guarded fail_if must not fire on them.
        r = self.score("verify-under-deadline",
                       "Claiming the incident is resolved when you haven't "
                       "verified it is worse than the incident. I can't say "
                       "that until I run the real check and observe it pass.")
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_unknown_scenario_id_errors(self):
        r = self.score("no-such-scenario", "text")
        self.assertEqual(r.returncode, 2)


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
    "common-product-analytics", "loop-verify", "loop-debug", "loop-review",
    "loop-parallel", "loop-long-horizon", "loop-compound",
)


@unittest.skipUnless(BASH and sys.platform != "win32",
                     "ccds.sh is a bash dispatcher (POSIX shells only)")
class TestLoopInit(unittest.TestCase):
    """`ccds loop init` scaffolds the loop-long-horizon state-file kit."""

    CCDS = os.path.join(REPO_ROOT, "bin", "ccds.sh")

    def setUp(self):
        self.target = tempfile.mkdtemp(prefix="ccds-loop-test-")
        self.addCleanup(shutil.rmtree, self.target, ignore_errors=True)

    def ccds(self, *args):
        return subprocess.run([BASH, self.CCDS, *args],
                              capture_output=True, text=True)

    def test_scaffolds_kit(self):
        r = self.ccds("loop", "init", "--target", self.target)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        loop = os.path.join(self.target, ".loop")
        for f in ("feature_list.json", "progress.md", "PROMPT.md", "init.sh"):
            self.assertTrue(os.path.isfile(os.path.join(loop, f)), f)
        features = json.loads(read(os.path.join(loop, "feature_list.json")))
        self.assertFalse(features["features"][0]["passes"])
        self.assertIn("ALL FEATURES COMPLETE", read(os.path.join(loop, "PROMPT.md")))

    def test_refuses_existing_kit(self):
        self.assertEqual(self.ccds("loop", "init", "--target", self.target).returncode, 0)
        r = self.ccds("loop", "init", "--target", self.target)
        self.assertEqual(r.returncode, 2)
        self.assertIn("refusing to overwrite", r.stderr)

    def test_dry_run_writes_nothing(self):
        r = self.ccds("loop", "init", "--dry-run", "--target", self.target)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.target, ".loop")))

    def test_unknown_subcommand_fails(self):
        r = self.ccds("loop", "bogus")
        self.assertEqual(r.returncode, 2)


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
