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
import re
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


class TestCliParity(FixtureCase):
    """Check 10: bin/ccds.sh and bin/ccds.ps1 must dispatch the same command
    set ("fixes and releases should be for every outlet").

    The fixture writes minimal fake dispatchers carrying only the structures
    the parser anchors to — the bash `elif [[ "$COMMAND" == "..." ]]` chain
    and the PowerShell `switch ($Command)` block — with deliberately uneven
    whitespace to prove the parser tolerates formatting.
    """

    def write_dispatchers(self, bash_cmds, ps1_cmds):
        chain = []
        for i, cmd in enumerate(bash_cmds):
            kw = "if  " if i == 0 else "elif"
            pad = " " * (10 - len(cmd))  # ragged alignment like the real file
            chain.append(f'{kw} [[ "$COMMAND" == "{cmd}"{pad}]]; then cmd_{cmd}')
        write(os.path.join(self.root, "bin", "ccds.sh"),
              "#!/usr/bin/env bash\nCOMMAND=\"$1\"\n"
              + "\n".join(chain)
              + "\nelse\n    exit 2\nfi\n")

        cases = "\n".join(f"    '{cmd}'  {{ Invoke-Command -Name {cmd} }}"
                          for cmd in ps1_cmds)
        write(os.path.join(self.root, "bin", "ccds.ps1"),
              "param([string]$Command)\n"
              "switch ($Command) {\n"
              + cases
              + "\n    default { exit 2 }\n}\n")

    def test_no_dispatchers_is_exempt(self):
        # Library-only fixture trees ship no bin/; parity must not fire.
        r = self.lint()
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertNotIn("cli-parity", r.stdout)

    def test_matching_surfaces_pass(self):
        self.write_dispatchers(["sync", "verify", "doctor"],
                               ["sync", "verify", "doctor"])
        r = self.lint()
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertNotIn("cli-parity", r.stdout)

    def test_bash_only_command_fails_naming_it(self):
        self.write_dispatchers(["sync", "doctor"], ["sync"])
        r = self.lint()
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("cli-parity", r.stdout)
        self.assertIn("'doctor'", r.stdout)
        self.assertIn("missing from bin/ccds.ps1", r.stdout)

    def test_ps1_only_command_fails_naming_it(self):
        self.write_dispatchers(["sync"], ["sync", "setup"])
        r = self.lint()
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("cli-parity", r.stdout)
        self.assertIn("'setup'", r.stdout)
        self.assertIn("missing from bin/ccds.sh", r.stdout)

    def test_missing_twin_dispatcher_fails(self):
        self.write_dispatchers(["sync"], ["sync"])
        os.remove(os.path.join(self.root, "bin", "ccds.ps1"))
        r = self.lint()
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("cli-parity", r.stdout)
        self.assertIn("bin/ccds.ps1 is missing", r.stdout)


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
        # Enforcement layer (ADR-0011) added PreToolUse/PostToolUse/PreCompact
        # alongside the original SessionStart/Stop.
        self.assertEqual(
            sorted(hooks["hooks"].keys()),
            ["PostToolUse", "PreCompact", "PreToolUse", "SessionStart", "Stop"])
        for script in ("session-start.sh", "stop-gate.sh",
                       "stop-evidence-gate.py", "pretooluse-risk-guard.py",
                       "risk-deny-list.txt", "precompact-handoff.py",
                       "posttooluse-evidence-log.py", "agent-evidence.sql"):
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


EVIDENCE_GATE = os.path.join(HOOKS_SRC, "stop-evidence-gate.py")


@unittest.skipUnless(os.path.isfile(EVIDENCE_GATE),
                     "stop-evidence-gate.py not on this branch yet")
class TestEvidenceGate(unittest.TestCase):
    """The delivery gate (Primitive 1): a Stop hook that blocks turn-end unless
    the open cycle has an evidence artifact carrying a PASS/FAIL verdict.

    Opt-in: disarmed (exit 0) with no cycle marker; armed by .claude/loop-cycle
    or CCDS_LOOP_CYCLE. python3 hook, so this runs wherever python3 does."""

    def setUp(self):
        self.proj = tempfile.mkdtemp(prefix="ccds-evidence-test-")
        self.addCleanup(shutil.rmtree, self.proj, ignore_errors=True)
        os.makedirs(os.path.join(self.proj, ".claude"))

    def gate(self, cycle_env=None):
        env = {k: v for k, v in os.environ.items() if k != "CCDS_LOOP_CYCLE"}
        env["CLAUDE_PROJECT_DIR"] = self.proj
        if cycle_env is not None:
            env["CCDS_LOOP_CYCLE"] = cycle_env
        return subprocess.run([sys.executable, EVIDENCE_GATE],
                              input="{}", capture_output=True, text=True, env=env)

    def arm_marker(self, cycle_id):
        write(os.path.join(self.proj, ".claude", "loop-cycle"), cycle_id + "\n")

    def write_evidence(self, cycle_id, **fields):
        payload = {"cycle_id": cycle_id, "verdict": "PASS", "task": "t",
                   "proof": {"cmd": "pytest", "count": "42/42"}, "agent": "x"}
        payload.update(fields)
        write(os.path.join(self.proj, ".claude", "evidence", cycle_id + ".json"),
              json.dumps(payload))

    def test_disarmed_is_noop(self):
        # No marker, no env -> gate must not block an ad-hoc session.
        self.assertEqual(self.gate().returncode, 0)

    def test_armed_without_evidence_blocks(self):
        self.arm_marker("cyc-1")
        r = self.gate()
        self.assertEqual(r.returncode, 2)
        self.assertIn("no evidence artifact", r.stderr)
        self.assertIn("cyc-1", r.stderr)

    def test_valid_pass_verdict_allows(self):
        self.arm_marker("cyc-1")
        self.write_evidence("cyc-1", verdict="PASS")
        r = self.gate()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_fail_verdict_also_allows(self):
        # Honest FAIL is compliance; blocking it would teach the model to omit.
        self.arm_marker("cyc-1")
        self.write_evidence("cyc-1", verdict="FAIL")
        self.assertEqual(self.gate().returncode, 0)

    def test_missing_verdict_field_blocks(self):
        self.arm_marker("cyc-1")
        self.write_evidence("cyc-1", verdict=None)
        r = self.gate()
        self.assertEqual(r.returncode, 2)
        self.assertIn("valid\nverdict".replace("\n", " "), r.stderr.replace("\n", " "))

    def test_bogus_verdict_value_blocks(self):
        self.arm_marker("cyc-1")
        self.write_evidence("cyc-1", verdict="DONE")
        self.assertEqual(self.gate().returncode, 2)

    def test_malformed_json_blocks(self):
        self.arm_marker("cyc-1")
        write(os.path.join(self.proj, ".claude", "evidence", "cyc-1.json"),
              "{not json")
        r = self.gate()
        self.assertEqual(r.returncode, 2)
        self.assertIn("invalid JSON", r.stderr)

    def test_stale_cycle_id_mismatch_blocks(self):
        # Evidence file for cyc-1 must not satisfy an open cycle of cyc-2.
        self.arm_marker("cyc-2")
        self.write_evidence("cyc-1", verdict="PASS")  # wrong file name AND id
        write(os.path.join(self.proj, ".claude", "evidence", "cyc-2.json"),
              json.dumps({"cycle_id": "cyc-1", "verdict": "PASS"}))
        r = self.gate()
        self.assertEqual(r.returncode, 2)
        self.assertIn("does not match", r.stderr)

    def test_env_var_arms_the_gate(self):
        # CCDS_LOOP_CYCLE arms even with no marker file.
        r = self.gate(cycle_env="cyc-env")
        self.assertEqual(r.returncode, 2)
        self.assertIn("cyc-env", r.stderr)

    def test_env_var_overrides_marker(self):
        self.arm_marker("cyc-marker")
        self.write_evidence("cyc-env", verdict="PASS")
        r = self.gate(cycle_env="cyc-env")
        self.assertEqual(r.returncode, 0, r.stderr)


RISK_GUARD = os.path.join(HOOKS_SRC, "pretooluse-risk-guard.py")


@unittest.skipUnless(os.path.isfile(RISK_GUARD),
                     "pretooluse-risk-guard.py not on this branch yet")
class TestRiskGuard(unittest.TestCase):
    """Primitive 2: PreToolUse Bash guard. Deny-list hit -> exit 2 (block);
    fleet-SSH loop -> exit 1 (non-blocking WARN); benign -> exit 0. Runs the
    real hook against the real shipped risk-deny-list.txt."""

    def guard(self, command, tool_name="Bash"):
        payload = {"tool_name": tool_name, "tool_input": {"command": command}}
        return subprocess.run([sys.executable, RISK_GUARD],
                              input=json.dumps(payload),
                              capture_output=True, text=True)

    # --- deny-list: every mandated pattern must block (exit 2) ---
    DENY = [
        "rm -rf /",
        "rm -rf /*",
        "sudo rm -fr  /  ",
        "rm -rf *",
        "mkfs.ext4 /dev/sda1",
        "dd if=/dev/zero of=/dev/sda bs=1M",
        ":(){ :|:& };:",
        'psql -c "DROP DATABASE prod"',
        "DROP TABLE users",
        "TRUNCATE TABLE sessions",
        'psql -c "TRUNCATE users;"',
        "zpool destroy tank",
    ]

    def test_denylist_patterns_block(self):
        for cmd in self.DENY:
            r = self.guard(cmd)
            self.assertEqual(r.returncode, 2, "should BLOCK: %r\n%s" % (cmd, r.stderr))
            self.assertIn("BLOCKED", r.stderr)

    # --- benign commands must pass untouched (exit 0) ---
    ALLOW = [
        "ls -la",
        "git status",
        "rm -rf ./build",
        "rm -rf /tmp/mycache",
        "dd if=/dev/zero of=./disk.img bs=1M count=100",
        "truncate -s 0 app.log",
        "ssh web1 uptime",
        "grep -rf patterns.txt src/",
        'psql -h localhost -c "SELECT * FROM users"',
    ]

    def test_benign_commands_allowed(self):
        for cmd in self.ALLOW:
            r = self.guard(cmd)
            self.assertEqual(r.returncode, 0, "should ALLOW: %r\n%s" % (cmd, r.stderr))

    # --- fleet SSH loops: non-blocking WARN (exit 1) ---
    def test_fleet_ssh_loop_warns_nonblocking(self):
        r = self.guard("for h in web1 web2 web3; do ssh $h uptime; done")
        self.assertEqual(r.returncode, 1)
        self.assertIn("WARN", r.stderr)

    def test_parallel_ssh_warns(self):
        r = self.guard("parallel-ssh -h hosts.txt uptime")
        self.assertEqual(r.returncode, 1)

    # --- robustness: never block on our own failure / non-Bash / empty ---
    def test_deny_beats_warn_when_both_match(self):
        # a fleet loop that also drops a table must BLOCK, not merely warn
        r = self.guard("for h in db1 db2; do ssh $h 'psql -c \"DROP TABLE t\"'; done")
        self.assertEqual(r.returncode, 2, r.stderr)

    def test_non_bash_tool_is_inert(self):
        r = self.guard("rm -rf /", tool_name="Read")
        self.assertEqual(r.returncode, 0)

    def test_empty_command_allowed(self):
        r = self.guard("   ")
        self.assertEqual(r.returncode, 0)

    def test_malformed_stdin_fails_open(self):
        r = subprocess.run([sys.executable, RISK_GUARD],
                           input="not json", capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)


HANDOFF_HOOK = os.path.join(HOOKS_SRC, "precompact-handoff.py")


@unittest.skipUnless(os.path.isfile(HANDOFF_HOOK),
                     "precompact-handoff.py not on this branch yet")
class TestHandoffWriter(unittest.TestCase):
    """Primitive 3: PreCompact hook snapshots operational state to
    .claude/handoff.md so a compacted/fresh context can rebuild bearings."""

    def setUp(self):
        self.proj = tempfile.mkdtemp(prefix="ccds-handoff-test-")
        self.addCleanup(shutil.rmtree, self.proj, ignore_errors=True)
        os.makedirs(os.path.join(self.proj, ".claude"))

    def run_hook(self, trigger="auto", cycle_env=None):
        env = {k: v for k, v in os.environ.items() if k != "CCDS_LOOP_CYCLE"}
        env["CLAUDE_PROJECT_DIR"] = self.proj
        if cycle_env is not None:
            env["CCDS_LOOP_CYCLE"] = cycle_env
        return subprocess.run(
            [sys.executable, HANDOFF_HOOK],
            input=json.dumps({"trigger": trigger, "cwd": self.proj}),
            capture_output=True, text=True, env=env)

    def handoff(self):
        return read(os.path.join(self.proj, ".claude", "handoff.md"))

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.proj,
                       capture_output=True, text=True, check=True)

    def init_repo(self):
        self.git("init", "-q")
        self.git("config", "user.email", "t@t.t")
        self.git("config", "user.name", "t")
        write(os.path.join(self.proj, "a.txt"), "one\n")
        self.git("add", "a.txt")
        self.git("commit", "-q", "-m", "first commit")

    def add_evidence(self, cycle_id, verdict, task):
        write(os.path.join(self.proj, ".claude", "evidence", cycle_id + ".json"),
              json.dumps({"cycle_id": cycle_id, "verdict": verdict,
                          "task": task, "proof": {}, "agent": "x",
                          "ts": "2026-07-06T10:00:00"}))

    def test_writes_handoff_always_exit_0(self):
        r = self.run_hook()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(os.path.join(self.proj, ".claude", "handoff.md")))

    def test_records_cycle_and_trigger(self):
        self.run_hook(trigger="manual", cycle_env="ship-auth")
        h = self.handoff()
        self.assertIn("ship-auth", h)
        self.assertIn("compaction trigger: manual", h)

    def test_lists_recent_evidence_with_verdicts(self):
        self.add_evidence("cyc-1", "PASS", "wire the gate")
        self.add_evidence("cyc-2", "FAIL", "flaky smoke")
        self.run_hook()
        h = self.handoff()
        self.assertIn("cyc-1", h)
        self.assertIn("PASS", h)
        self.assertIn("cyc-2", h)
        self.assertIn("FAIL", h)
        self.assertIn("wire the gate", h)

    def test_captures_git_state(self):
        self.init_repo()
        # an uncommitted change so status --short is non-empty
        write(os.path.join(self.proj, "b.txt"), "two\n")
        self.run_hook()
        h = self.handoff()
        self.assertIn("first commit", h)          # last-5 commits
        self.assertIn("b.txt", h)                 # git status --short

    def test_non_git_dir_is_noted_not_fatal(self):
        r = self.run_hook()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("not a git repo", self.handoff())

    def test_overwrites_prior_snapshot(self):
        self.run_hook(cycle_env="cyc-old")
        self.run_hook(cycle_env="cyc-new")
        h = self.handoff()
        self.assertIn("cyc-new", h)
        self.assertNotIn("cyc-old", h)


EVIDENCE_LOG = os.path.join(HOOKS_SRC, "posttooluse-evidence-log.py")


@unittest.skipUnless(os.path.isfile(EVIDENCE_LOG),
                     "posttooluse-evidence-log.py not on this branch yet")
class TestEvidenceLog(unittest.TestCase):
    """Primitive 4 (durable tier + secret guard): PostToolUse hook that fires on
    writes to .claude/evidence/*.json — validates, secret-scans (exit 2), and
    optionally mirrors to Postgres via psql (no-op without CCDS_EVIDENCE_DSN)."""

    def setUp(self):
        self.proj = tempfile.mkdtemp(prefix="ccds-evlog-test-")
        self.addCleanup(shutil.rmtree, self.proj, ignore_errors=True)
        self.ev_dir = os.path.join(self.proj, ".claude", "evidence")
        os.makedirs(self.ev_dir)
        # dir for a fake `psql` on PATH (records its argv to a file)
        self.bindir = os.path.join(self.proj, "bin")
        os.makedirs(self.bindir)
        self.psql_log = os.path.join(self.proj, "psql-argv.txt")

    def write_evidence(self, cycle_id="cyc-1", **fields):
        payload = {"cycle_id": cycle_id, "verdict": "PASS", "task": "t",
                   "proof": {"cmd": "pytest", "count": "42/42"}, "agent": "x"}
        payload.update(fields)
        path = os.path.join(self.ev_dir, cycle_id + ".json")
        write(path, json.dumps(payload))
        return path

    def stub_psql(self, exit_code=0):
        shim = os.path.join(self.bindir, "psql")
        write(shim, "#!/usr/bin/env bash\n"
                    'printf "%%s\\n" "$@" >> "%s"\nexit %d\n' % (self.psql_log, exit_code))
        os.chmod(shim, 0o755)

    def run_hook(self, file_path, dsn=None, with_psql=False):
        env = {k: v for k, v in os.environ.items() if k != "CCDS_EVIDENCE_DSN"}
        if with_psql:
            env["PATH"] = self.bindir + os.pathsep + env["PATH"]
        else:
            # scrub any real psql so "no psql" paths are deterministic
            env["PATH"] = self.bindir
            write(os.path.join(self.bindir, ".keep"), "")
        if dsn is not None:
            env["CCDS_EVIDENCE_DSN"] = dsn
        payload = {"tool_name": "Write", "tool_input": {"file_path": file_path}}
        return subprocess.run([sys.executable, EVIDENCE_LOG],
                              input=json.dumps(payload),
                              capture_output=True, text=True, env=env)

    def test_non_evidence_write_is_inert(self):
        p = os.path.join(self.proj, "src", "main.py")
        write(p, "print(1)")
        r = self.run_hook(p)
        self.assertEqual(r.returncode, 0)

    def test_clean_evidence_no_dsn_is_noop_exit0(self):
        p = self.write_evidence()
        r = self.run_hook(p)  # no DSN
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_malformed_json_blocks(self):
        p = os.path.join(self.ev_dir, "bad.json")
        write(p, "{not json")
        r = self.run_hook(p)
        self.assertEqual(r.returncode, 2)
        self.assertIn("not valid JSON", r.stderr)

    def test_missing_verdict_blocks(self):
        p = self.write_evidence(verdict=None)
        r = self.run_hook(p)
        self.assertEqual(r.returncode, 2)
        self.assertIn("valid verdict", r.stderr)

    def test_secret_in_proof_blocks(self):
        # planted fake AWS key shape — must be caught before it can be mirrored
        p = self.write_evidence(proof={"log": "using AKIAIOSFODNN7EXAMPLE now"})
        r = self.run_hook(p)
        self.assertEqual(r.returncode, 2)
        self.assertIn("secret", r.stderr)

    def test_private_key_blocks(self):
        p = self.write_evidence(proof={"k": "-----BEGIN RSA PRIVATE KEY-----"})
        r = self.run_hook(p)
        self.assertEqual(r.returncode, 2)

    def test_dsn_set_invokes_psql_with_row(self):
        self.stub_psql(exit_code=0)
        p = self.write_evidence(cycle_id="ship-9")
        r = self.run_hook(p, dsn="postgresql://u@h/db", with_psql=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        argv = read(self.psql_log)
        self.assertIn("ship-9", argv)                 # row passed via --set ev=
        self.assertIn("ON_ERROR_STOP=1", argv)
        self.assertIn("agent_evidence", argv)         # DDL+insert in the -c body

    def test_psql_failure_does_not_block_turn(self):
        self.stub_psql(exit_code=1)
        p = self.write_evidence()
        r = self.run_hook(p, dsn="postgresql://u@h/db", with_psql=True)
        self.assertEqual(r.returncode, 0)             # infra hiccup never blocks
        self.assertIn("mirror failed", r.stderr)

    def test_dsn_set_but_no_psql_noops(self):
        p = self.write_evidence()
        r = self.run_hook(p, dsn="postgresql://u@h/db", with_psql=False)
        self.assertEqual(r.returncode, 0)
        self.assertIn("psql not on PATH", r.stderr)


EVIDENCE_TO_EVALS = os.path.join(SCRIPTS, "evidence-to-evals.py")


@unittest.skipUnless(os.path.isfile(EVIDENCE_TO_EVALS),
                     "evidence-to-evals.py not on this branch yet")
class TestEvidenceToEvals(unittest.TestCase):
    """Primitive 5: recurring FAIL verdicts -> eval stubs in the EXISTING
    scenarios.json schema, emitted to a separate review file."""

    def setUp(self):
        # a repo-shaped root with the loop-verify skill the stub references
        self.root = tempfile.mkdtemp(prefix="ccds-e2e-test-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        shutil.copytree(os.path.join(REPO_ROOT, "skills", "loop-verify"),
                        os.path.join(self.root, "skills", "loop-verify"))
        self.project = os.path.join(self.root, "proj")
        os.makedirs(os.path.join(self.project, ".claude", "evidence"))
        self.out = os.path.join(self.root, "evals", "loop-compliance",
                                "generated-stubs.json")

    def add(self, cycle_id, verdict, task):
        write(os.path.join(self.project, ".claude", "evidence", cycle_id + ".json"),
              json.dumps({"cycle_id": cycle_id, "verdict": verdict, "task": task}))

    def run_script(self, *args):
        return run(EVIDENCE_TO_EVALS, self.root, "--project", self.project, *args)

    def stubs(self):
        return json.loads(read(self.out))["scenarios"]

    def test_recurring_fail_emits_stub(self):
        self.add("c1", "FAIL", "flaky auth smoke")
        self.add("c2", "FAIL", "flaky auth smoke")
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        stubs = self.stubs()
        self.assertEqual(len(stubs), 1)
        self.assertEqual(stubs[0]["id"], "regression-flaky-auth-smoke")
        self.assertIn("flaky auth smoke", stubs[0]["_source"])

    def test_below_threshold_not_emitted(self):
        self.add("c1", "FAIL", "one-off blip")
        r = self.run_script()  # default threshold 2
        self.assertIn("new stubs=0", r.stdout)
        self.assertFalse(os.path.exists(self.out))

    def test_pass_verdicts_ignored(self):
        self.add("c1", "PASS", "healthy task")
        self.add("c2", "PASS", "healthy task")
        r = self.run_script()
        self.assertIn("new stubs=0", r.stdout)

    def test_threshold_flag(self):
        self.add("c1", "FAIL", "t")
        r = self.run_script("--threshold", "1")
        self.assertEqual(len(self.stubs()), 1)

    def test_emitted_stubs_have_valid_schema(self):
        self.add("c1", "FAIL", "some task")
        self.add("c2", "FAIL", "some task")
        self.run_script()
        for s in self.stubs():
            for key in ("id", "skill", "prompt", "pass_if", "fail_if"):
                self.assertIn(key, s)
            for pat in s["pass_if"] + s["fail_if"]:
                re.compile(pat)  # must not raise
            self.assertTrue(os.path.isdir(
                os.path.join(self.root, "skills", s["skill"])))

    def test_stub_passes_real_compliance_validator(self):
        # Strongest proof of compatibility: feed the generated stub to the real
        # eval-loop-compliance.py loader as scenarios.json; it must validate.
        if not os.path.isfile(EVAL_COMPLIANCE):
            self.skipTest("eval-loop-compliance.py not on this branch")
        self.add("c1", "FAIL", "regression candidate")
        self.add("c2", "FAIL", "regression candidate")
        self.run_script()
        write(os.path.join(self.root, "evals", "loop-compliance", "scenarios.json"),
              json.dumps({"scenarios": self.stubs()}))
        r = run(EVAL_COMPLIANCE, self.root, "--dry-run")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("valid", r.stdout)

    def test_already_promoted_id_is_skipped(self):
        self.add("c1", "FAIL", "known task")
        self.add("c2", "FAIL", "known task")
        # simulate the task already promoted into the curated set
        write(os.path.join(self.root, "evals", "loop-compliance", "scenarios.json"),
              json.dumps({"scenarios": [{"id": "regression-known-task",
                                         "skill": "loop-verify", "prompt": "x",
                                         "pass_if": [], "fail_if": []}]}))
        r = self.run_script()
        self.assertIn("new stubs=0", r.stdout)

    def test_dry_run_writes_nothing(self):
        self.add("c1", "FAIL", "t"); self.add("c2", "FAIL", "t")
        r = self.run_script("--dry-run")
        self.assertEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(self.out))

    def test_bad_skill_errors(self):
        r = self.run_script("--skill", "no-such-skill")
        self.assertEqual(r.returncode, 2)
        self.assertIn("no skills/", r.stderr)


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
        # assertion restored: it was clipped during a merge-conflict resolution
        self.assertEqual(r.returncode, 2)


@unittest.skipUnless(os.path.isfile(EVAL_COMPLIANCE) and shutil.which("bash")
                     and sys.platform != "win32",
                     "claude shim is a bash script (POSIX shells only)")
class TestLoopComplianceBaseline(unittest.TestCase):
    """--record / baseline-compare paths, exercised through the REAL live-run
    plumbing with a fake `claude` on PATH (no API calls). Runs against a
    synthetic root so the repo's committed baseline is never touched."""

    COMPLIANT = ("I can't call the incident resolved yet. I ran npm test and "
                 "read the output: 42/42 pass; running the smoke check now - "
                 "evidence first, then the status update.")

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="ccds-baseline-test-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        # Minimal fixture root: the real scenarios file + the one skill it needs.
        scenarios = json.loads(read(os.path.join(
            REPO_ROOT, "evals", "loop-compliance", "scenarios.json")))
        scenarios["scenarios"] = [s for s in scenarios["scenarios"]
                                  if s["id"] == "verify-under-deadline"]
        write(os.path.join(self.root, "evals", "loop-compliance", "scenarios.json"),
              json.dumps(scenarios))
        shutil.copytree(os.path.join(REPO_ROOT, "skills", "loop-verify"),
                        os.path.join(self.root, "skills", "loop-verify"))
        # claude shim: prints a canned compliant reply whatever the args.
        bindir = os.path.join(self.root, "bin")
        shim = os.path.join(bindir, "claude")
        write(shim, "#!/usr/bin/env bash\nprintf '%s' \"$CLAUDE_SHIM_REPLY\"\n")
        os.chmod(shim, 0o755)
        self.env = {**os.environ,
                    "PATH": bindir + os.pathsep + os.environ["PATH"],
                    "CLAUDE_SHIM_REPLY": self.COMPLIANT}

    def eval_(self, *args):
        return subprocess.run([sys.executable, EVAL_COMPLIANCE, self.root, *args],
                              capture_output=True, text=True, env=self.env)

    def baseline(self):
        return json.loads(read(os.path.join(
            self.root, "evals", "loop-compliance", "baseline.json")))

    def test_record_writes_baseline(self):
        r = self.eval_("--votes", "1", "--record")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        b = self.baseline()
        self.assertEqual(b["scenarios"]["verify-under-deadline"],
                         {"passes": 1, "votes": 1})
        self.assertEqual(b["votes"], 1)

    def test_second_run_compares_against_baseline(self):
        self.eval_("--votes", "1", "--record")
        r = self.eval_("--votes", "1")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("[baseline 1/1", r.stdout)
        self.assertIn("no regressions", r.stdout)

    def test_regression_is_named(self):
        self.eval_("--votes", "1", "--record")
        self.env["CLAUDE_SHIM_REPLY"] = ("Status update: the incident is "
                                         "resolved. Everything is fine.")
        r = self.eval_("--votes", "1")
        self.assertEqual(r.returncode, 1)
        self.assertIn("REGRESSED: verify-under-deadline", r.stdout)


EVAL_ROUTING = os.path.join(SCRIPTS, "eval-routing.py")


@unittest.skipUnless(os.path.isfile(EVAL_ROUTING),
                     "eval-routing.py not on this branch yet")
class TestRoutingEval(unittest.TestCase):
    """Deterministic (TF-IDF) paths of the routing eval. The --llm path
    spends API tokens and is release-time only; its plumbing was proven live
    once (2026-07-03, 2 prompts) and shares load/rank code with these."""

    def synthetic_root(self, golden_cases):
        """Tiny catalog + golden.json in a temp root shaped like the repo."""
        root = tempfile.mkdtemp(prefix="ccds-routing-test-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        catalog = [
            {"name": "saas-billing", "pack": "saas", "kind": "skill",
             "scope": "project", "model": "",
             "description": "Billing integration specialist. Auto-invoked "
                            "when Stripe webhooks are handled or proration "
                            "logic is added."},
            {"name": "game-netcode", "pack": "game", "kind": "skill",
             "scope": "project", "model": "",
             "description": "Multiplayer netcode specialist. Auto-invoked for "
                            "client prediction, rollback, and lag "
                            "compensation."},
            {"name": "embed-power", "pack": "embed", "kind": "skill",
             "scope": "project", "model": "",
             "description": "Power management specialist. Owns sleep modes, "
                            "duty cycling, and battery-life budgeting."},
        ]
        write(os.path.join(root, "catalog.json"), json.dumps(catalog))
        write(os.path.join(root, "evals", "routing", "golden.json"),
              json.dumps({"cases": golden_cases}))
        return root

    OBVIOUS = {"id": "billing-webhooks",
               "prompt": "Stripe webhooks keep failing so billing proration "
                         "is wrong.",
               "expect": ["saas-billing"]}

    def test_real_repo_deterministic_green(self):
        r = run(EVAL_ROUTING, REPO_ROOT)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("RESULT: PASS", r.stdout)
        self.assertIn("Failures  : 0", r.stdout)

    def test_real_repo_ambiguity_mode_is_informational(self):
        r = run(EVAL_ROUTING, REPO_ROOT, "--ambiguity")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("summary (ambiguity)", r.stdout)

    def test_obvious_match_passes(self):
        root = self.synthetic_root([self.OBVIOUS])
        r = run(EVAL_ROUTING, root, "--top-k", "1")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("PASS  billing-webhooks", r.stdout)

    def test_wrong_expect_fails(self):
        wrong = dict(self.OBVIOUS, id="billing-mislabeled",
                     expect=["game-netcode"])
        root = self.synthetic_root([wrong])
        r = run(EVAL_ROUTING, root, "--top-k", "1")
        self.assertEqual(r.returncode, 1)
        self.assertIn("FAIL  billing-mislabeled", r.stdout)
        self.assertIn("RESULT: FAIL", r.stdout)

    def test_known_gap_warns_but_passes(self):
        gap = dict(self.OBVIOUS, id="billing-gap", expect=["game-netcode"])
        gap["known_gap"] = True
        gap["note"] = "documented for the test"
        root = self.synthetic_root([gap])
        r = run(EVAL_ROUTING, root, "--top-k", "1")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("WARN  billing-gap", r.stdout)
        self.assertIn("Known gaps: 1", r.stdout)

    def test_unknown_expect_name_exits_2(self):
        bad = dict(self.OBVIOUS, expect=["saas-billing", "no-such-skill"])
        root = self.synthetic_root([bad])
        r = run(EVAL_ROUTING, root)
        self.assertEqual(r.returncode, 2)
        self.assertIn("no-such-skill", r.stderr)

    def test_negative_prompt_passes_under_floor(self):
        neg = {"id": "neg-poem", "prompt": "Write a sonnet about the ocean.",
               "expect": [], "negative": True}
        root = self.synthetic_root([neg])
        r = run(EVAL_ROUTING, root)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("PASS  neg-poem", r.stdout)

    def test_dry_run_validates_only(self):
        r = run(EVAL_ROUTING, REPO_ROOT, "--dry-run")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("case(s) valid", r.stdout)
        self.assertNotIn("RESULT:", r.stdout)


class TestMarketplaceFreshLint(unittest.TestCase):
    """Lint check 11: a stale generated plugin copy is a local lint error,
    not just a CI failure (added after a skill edit merged red, 2026-07-04)."""

    STALE_TARGET = os.path.join(REPO_ROOT, "plugins", "ccds-loops",
                                "skills", "loop-verify", "SKILL.md")

    def tearDown(self):
        # Restore by REGENERATING, never `git checkout -- plugins`: checkout
        # restores HEAD, which silently reverts a developer's correct-but-
        # uncommitted regen (that exact clobber shipped a stale tree in the
        # first version of this very fix — PR #45 round 1).
        subprocess.run([sys.executable, BUILD_MARKETPLACE, REPO_ROOT],
                       capture_output=True)

    def test_stale_plugin_copy_fails_then_selfheals(self):
        with open(self.STALE_TARGET, "a", encoding="utf-8") as f:
            f.write("<!-- stale-probe -->\n")
        r = run(LINT_PLAYBOOK, REPO_ROOT)
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("marketplace-fresh", r.stdout)
        # the check regenerates in place: a second run must pass
        r2 = run(LINT_PLAYBOOK, REPO_ROOT)
        self.assertEqual(r2.returncode, 0, r2.stdout)


EXPORT_HARNESS = os.path.join(SCRIPTS, "export-harness.py")


@unittest.skipUnless(os.path.isfile(EXPORT_HARNESS),
                     "export-harness.py not on this branch yet")
class TestExportHarness(unittest.TestCase):
    """Structural tests for the loop-pack harness exporter. Live activation
    was verified manually with Codex CLI reading the exported AGENTS.md
    (2026-07-03); these tests guard the format."""

    LOOP_SKILLS = ["loop-compound", "loop-debug", "loop-long-horizon",
                   "loop-parallel", "loop-review", "loop-verify"]

    def setUp(self):
        self.out = tempfile.mkdtemp(prefix="ccds-export-test-")
        self.addCleanup(shutil.rmtree, self.out, ignore_errors=True)

    def test_cursor_export_shape(self):
        r = run(EXPORT_HARNESS, "--target", "cursor", REPO_ROOT, "--out", self.out)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        rules = os.path.join(self.out, ".cursor", "rules")
        self.assertEqual(sorted(os.listdir(rules)),
                         [f"{n}.mdc" for n in self.LOOP_SKILLS])
        mdc = read(os.path.join(rules, "loop-verify.mdc"))
        self.assertTrue(mdc.startswith("---\ndescription: "), mdc[:60])
        self.assertIn("alwaysApply: false", mdc)
        self.assertIn("## Iron law", mdc)

    def test_agents_md_export_shape(self):
        r = run(EXPORT_HARNESS, "--target", "agents-md", REPO_ROOT, "--out", self.out)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        content = read(os.path.join(self.out, "AGENTS.md"))
        for name in self.LOOP_SKILLS:
            self.assertIn(f"## {name}", content)
        # bundled reference must be inlined, not left as a dangling link
        self.assertIn("feature_list.json", content)
        self.assertNotIn("](references/", content)

    def test_unknown_target_errors(self):
        r = run(EXPORT_HARNESS, "--target", "vim", REPO_ROOT, "--out", self.out)
        self.assertEqual(r.returncode, 2)


LOOP_EDIT_HOOK = os.path.join(SCRIPTS, "hooks", "loop-skill-edited.py")


@unittest.skipUnless(os.path.isfile(LOOP_EDIT_HOOK),
                     "loop-skill-edited.py not on this branch yet")
class TestLoopSkillEditedHook(unittest.TestCase):
    """PostToolUse tripwire: reminds that the live compliance baseline goes
    stale when loop-* wording changes. Tripwire, not gate: always exit 0."""

    def hook(self, stdin_text):
        return subprocess.run([sys.executable, LOOP_EDIT_HOOK],
                              input=stdin_text, capture_output=True, text=True)

    def test_fires_on_loop_skill_edit(self):
        r = self.hook(json.dumps(
            {"tool_input": {"file_path": "/x/skills/loop-verify/SKILL.md"}}))
        self.assertEqual(r.returncode, 0)
        out = json.loads(r.stdout)
        self.assertIn("eval-loop-compliance.py",
                      out["hookSpecificOutput"]["additionalContext"])

    def test_fires_on_scenario_edit_windows_path(self):
        r = self.hook(json.dumps(
            {"tool_input": {"file_path": "D:\\r\\evals\\loop-compliance\\scenarios.json"}}))
        self.assertIn("additionalContext", r.stdout)

    def test_silent_on_non_loop_edit(self):
        r = self.hook(json.dumps(
            {"tool_input": {"file_path": "/x/skills/saas-billing/SKILL.md"}}))
        self.assertEqual((r.returncode, r.stdout), (0, ""))

    def test_silent_on_malformed_input(self):
        r = self.hook("not json at all")
        self.assertEqual((r.returncode, r.stdout), (0, ""))


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
                     "ccds.sh is a bash dispatcher (POSIX shells only)")
class TestCcdsDoctor(unittest.TestCase):
    """`ccds doctor` proactive environment checks.

    Stages an installed-layout copy of the dispatcher (bin/ + scripts/ +
    catalog.json + version.txt) in a temp dir and points HOME at a synthetic
    healthy ~/.claude, so every check runs against a controlled environment.
    CCDS_DOCTOR_RELEASE_URL (test-only override, documented in bin/ccds.sh)
    points the version check at an unreachable local port so tests never
    touch the network and deterministically exercise the offline WARN path.
    """

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="ccds-doctor-test-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

        # Stage an installed-layout root (scripts/Sync-AgentPacks.sh present,
        # not under /usr/share/ccds -> LAYOUT_KIND="installed").
        self.inst = os.path.join(self.root, "playbook")
        os.makedirs(os.path.join(self.inst, "bin"))
        os.makedirs(os.path.join(self.inst, "scripts"))
        shutil.copy(os.path.join(REPO_ROOT, "bin", "ccds.sh"),
                    os.path.join(self.inst, "bin", "ccds.sh"))
        shutil.copy(os.path.join(REPO_ROOT, "Sync-AgentPacks.sh"),
                    os.path.join(self.inst, "scripts", "Sync-AgentPacks.sh"))
        shutil.copy(os.path.join(REPO_ROOT, "verify-agents.sh"),
                    os.path.join(self.inst, "scripts", "verify-agents.sh"))
        shutil.copy(os.path.join(SCRIPTS, "ccds-user-setup.sh"),
                    os.path.join(self.inst, "scripts", "ccds-user-setup.sh"))
        shutil.copy(os.path.join(REPO_ROOT, "catalog.json"),
                    os.path.join(self.inst, "catalog.json"))
        write(os.path.join(self.inst, "version.txt"), "0.0.1\n")

        # Synthetic healthy HOME: core-agent sentinel, every global skill,
        # exactly one ccds marker block.
        self.home = os.path.join(self.root, "home")
        write(os.path.join(self.home, ".claude", "agents", "plan-architect.md"),
              "---\nname: plan-architect\ndescription: test\n---\nbody\n")
        for name in self._global_skills():
            write(os.path.join(self.home, ".claude", "skills", name, "SKILL.md"),
                  f"---\nname: {name}\ndescription: test\n---\nbody\n")
        write(os.path.join(self.home, ".claude", "CLAUDE.md"),
              "# my own notes\n\n# >>> ccds >>>\nblock body\n# <<< ccds <<<\n")

    @staticmethod
    def _global_skills():
        """Parse GLOBAL_SKILLS out of the setup script (same source doctor uses)."""
        src = read(os.path.join(SCRIPTS, "ccds-user-setup.sh"))
        block = src.split("GLOBAL_SKILLS=(", 1)[1].split(")", 1)[0]
        return [ln.strip() for ln in block.splitlines()
                if ln.strip() and not ln.strip().startswith("#")]

    def doctor(self):
        env = {**os.environ,
               "HOME": self.home,
               # unreachable (discard-port) URL: forces the offline WARN path
               "CCDS_DOCTOR_RELEASE_URL": "http://127.0.0.1:9/releases/latest"}
        return subprocess.run(
            [BASH, os.path.join(self.inst, "bin", "ccds.sh"), "doctor"],
            capture_output=True, text=True, env=env)

    def test_healthy_home_passes(self):
        r = self.doctor()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("RESULT: PASS", r.stdout)
        self.assertIn("FAIL  : 0", r.stdout)

    def test_missing_core_agent_fails(self):
        os.remove(os.path.join(self.home, ".claude", "agents", "plan-architect.md"))
        r = self.doctor()
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("FAIL  agents-installed", r.stdout)
        self.assertIn("remedy: run 'ccds setup'", r.stdout)

    def test_missing_global_skill_fails(self):
        shutil.rmtree(os.path.join(self.home, ".claude", "skills", "loop-compound"))
        r = self.doctor()
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("FAIL  skills-installed", r.stdout)
        self.assertIn("loop-compound", r.stdout)

    def test_bom_in_skill_fails(self):
        p = os.path.join(self.home, ".claude", "skills", "loop-verify", "SKILL.md")
        with open(p, "rb") as f:
            content = f.read()
        with open(p, "wb") as f:
            f.write(b"\xef\xbb\xbf" + content)
        r = self.doctor()
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("FAIL  bom-scan", r.stdout)

    def test_duplicate_marker_block_fails(self):
        md = os.path.join(self.home, ".claude", "CLAUDE.md")
        write(md, read(md) + "\n# >>> ccds >>>\ndupe\n# <<< ccds <<<\n")
        r = self.doctor()
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("FAIL  claude-md-block", r.stdout)

    def test_offline_version_check_warns_not_fails(self):
        r = self.doctor()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("WARN  version", r.stdout)
        self.assertIn("could not check", r.stdout)


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
