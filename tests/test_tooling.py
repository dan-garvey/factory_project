"""Real disposable Git fixtures; no real Beads database or network access.

Pre-link and refusal cases intentionally model a new, not-yet-linked worktree.
They never invoke br. Sentinel files stand in for databases to prove preservation.
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class GitFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="factory tooling ")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.repo = self.base / "main checkout"
        self.repo.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TERMINAL_PROMPT="0", PYTHONDONTWRITEBYTECODE="1")
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", os.devnull)
        (self.repo / ".beads").mkdir()
        (self.repo / ".beads/.gitignore").write_text("*.db\n*.db-*\n")
        (self.repo / ".beads/issues.jsonl").write_text('{"id":"factory-fixture"}\n')
        (self.repo / "scripts").mkdir()
        for name in ("link-beads-worktree.sh", "install-hooks.sh", "check.py", "run_local.py"):
            shutil.copy2(ROOT / "scripts" / name, self.repo / "scripts" / name)
        (self.repo / ".githooks").mkdir()
        shutil.copy2(ROOT / ".githooks/pre-commit", self.repo / ".githooks/pre-commit")
        (self.repo / "tests").mkdir()
        (self.repo / "tests/test_probe.py").write_text(
            "from pathlib import Path\nimport unittest\n"
            "class Probe(unittest.TestCase):\n"
            "    def test_probe(self):\n"
            "        self.assertFalse(Path('FAIL').exists(), 'staged failure witness')\n"
        )
        self.git("add", ".")
        self.git("commit", "-m", "Seed disposable fixture")

    def run_command(self, *args, cwd=None, success=True):
        result = subprocess.run(args, cwd=cwd or self.repo, env=self.env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def git(self, *args, success=True):
        return self.run_command("git", *args, success=success)


class SharedBeadsTests(GitFixture):
    def worktree(self):
        (self.repo / ".beads/beads.db").write_text("canonical sentinel, never open as SQLite")
        target = self.base / "linked checkout"
        self.git("worktree", "add", "--detach", str(target))
        return target

    def link(self, target, success=True):
        return self.run_command("bash", str(self.repo / "scripts/link-beads-worktree.sh"),
                                str(target), success=success)

    def test_main_is_unchanged(self):
        (self.repo / ".beads/beads.db").write_text("sentinel")
        before = self.git("status", "--porcelain").stdout
        self.link(self.repo)
        self.assertFalse((self.repo / ".beads").is_symlink())
        self.assertEqual(self.git("status", "--porcelain").stdout, before)

    def test_link_archives_clean_snapshot_and_is_idempotent(self):
        target = self.worktree()
        original = (target / ".beads/issues.jsonl").read_bytes()
        self.link(target)
        self.assertTrue((target / ".beads").is_symlink())
        self.assertEqual((target / ".beads").resolve(), (self.repo / ".beads").resolve())
        backups = list((self.repo / ".git").glob("beads-worktree-backup.*/.beads/issues.jsonl"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), original)
        self.link(target)
        self.assertEqual(len(list((self.repo / ".git").glob("beads-worktree-backup.*"))), 1)

    def test_refuses_existing_database_and_preserves_it(self):
        target = self.worktree()
        database = target / ".beads/beads.db"
        database.write_text("independent issues sentinel")
        self.link(target, success=False)
        self.assertEqual(database.read_text(), "independent issues sentinel")
        self.assertFalse((target / ".beads").is_symlink())

    def test_refuses_modified_tracked_snapshot(self):
        target = self.worktree()
        export = target / ".beads/issues.jsonl"
        export.write_text("unexported work sentinel\n")
        self.link(target, success=False)
        self.assertEqual(export.read_text(), "unexported work sentinel\n")

    def test_refuses_staged_snapshot(self):
        target = self.worktree()
        export = target / ".beads/issues.jsonl"
        export.write_text("staged work sentinel\n")
        self.run_command("git", "add", ".beads/issues.jsonl", cwd=target)
        self.link(target, success=False)
        self.assertEqual(export.read_text(), "staged work sentinel\n")

    def test_refuses_ignored_untracked_data(self):
        target = self.worktree()
        unexpected = target / ".beads/other.db"
        unexpected.write_text("ignored but valuable sentinel")
        self.link(target, success=False)
        self.assertEqual(unexpected.read_text(), "ignored but valuable sentinel")

    def test_refuses_other_symlink(self):
        target = self.worktree()
        # Move the clean snapshot aside only in the disposable test fixture.
        (target / ".beads").rename(target / "snapshot")
        (target / ".beads").symlink_to(target / "snapshot", target_is_directory=True)
        self.link(target, success=False)
        self.assertEqual((target / ".beads").resolve(), target / "snapshot")

    def test_missing_canonical_database_fails(self):
        self.link(self.repo, success=False)
        self.assertFalse((self.repo / ".beads").is_symlink())


class StagedGateTests(GitFixture):
    def check(self, success=True):
        return self.run_command(sys.executable, "-B", "scripts/check.py", "--staged", success=success)

    def test_clean_candidate_and_index_are_preserved(self):
        before = self.git("write-tree").stdout
        self.check()
        self.assertEqual(self.git("write-tree").stdout, before)
        self.assertEqual(self.git("status", "--porcelain").stdout, "")

    def test_unstaged_failure_does_not_contaminate_candidate(self):
        (self.repo / "FAIL").write_text("only in working tree")
        self.check()
        self.assertEqual((self.repo / "FAIL").read_text(), "only in working tree")

    def test_staged_failure_is_not_hidden_by_passing_working_tree(self):
        witness = self.repo / "FAIL"
        witness.write_text("bad staged candidate")
        self.git("add", "FAIL")
        witness.unlink()
        before = self.git("write-tree").stdout
        result = self.check(success=False)
        self.assertIn("staged failure witness", result.stdout)
        self.assertEqual(self.git("write-tree").stdout, before)
        self.assertFalse(witness.exists())

    def test_candidate_tests_not_working_tree_tests_are_executed(self):
        probe = self.repo / "tests/test_probe.py"
        passing = probe.read_text()
        probe.write_text(passing.replace("Path('FAIL').exists()", "True"))
        self.git("add", "tests/test_probe.py")
        probe.write_text(passing)
        result = self.check(success=False)
        self.assertIn("staged failure witness", result.stdout)

    def test_missing_tests_fail_closed(self):
        self.git("rm", "tests/test_probe.py")
        self.check(success=False)

    def test_skipped_tests_are_not_green_evidence(self):
        probe = self.repo / "tests/test_probe.py"
        probe.write_text(probe.read_text().replace("    def test_probe(self):", "    @unittest.skip('no evidence')\n    def test_probe(self):"))
        self.git("add", "tests/test_probe.py")
        result = self.check(success=False)
        self.assertIn("skipped tooling tests", result.stdout)

    def test_checkout_filters_cannot_hide_staged_failure(self):
        (self.repo / ".git/info/attributes").write_text("tests/test_probe.py filter=mask\n")
        self.git("config", "filter.mask.smudge", "sed 's/self.assertFalse(True,/self.assertFalse(False,/'")
        probe = self.repo / "tests/test_probe.py"
        probe.write_text(probe.read_text().replace("Path('FAIL').exists()", "True"))
        self.git("add", "tests/test_probe.py")
        self.assertIn("self.assertFalse(True,", self.git("show", ":tests/test_probe.py").stdout)
        result = self.check(success=False)
        self.assertIn("staged failure witness", result.stdout)

    def test_runtime_database_is_rejected(self):
        (self.repo / ".beads/beads.db").write_text("must stay local")
        self.git("add", "--force", ".beads/beads.db")
        result = self.check(success=False)
        self.assertIn("runtime data", result.stdout)

    def test_runtime_lock_is_rejected(self):
        (self.repo / ".beads/.write.lock").write_text("runtime coordination only")
        self.git("add", "--force", ".beads/.write.lock")
        result = self.check(success=False)
        self.assertIn("runtime data", result.stdout)

    def test_shared_directory_symlink_is_rejected(self):
        self.git("rm", "-r", ".beads")
        (self.repo / ".beads").symlink_to(self.base / "shared", target_is_directory=True)
        self.git("add", ".beads")
        result = self.check(success=False)
        self.assertIn("symlinks/submodules", result.stdout)

    def test_index_changes_during_validation_are_rejected(self):
        external = self.repo / "external.txt"
        external.write_text("another agent staged this")
        probe = self.repo / "tests/test_probe.py"
        probe.write_text(
            "import subprocess\nimport unittest\n"
            "class Probe(unittest.TestCase):\n"
            "    def test_probe(self):\n"
            f"        subprocess.run(['git', '-C', {str(self.repo)!r}, 'add', 'external.txt'], check=True)\n"
        )
        self.git("add", "tests/test_probe.py")
        result = self.check(success=False)
        self.assertIn("index changed", result.stdout)
        self.assertIn("external.txt", self.git("diff", "--cached", "--name-only").stdout)

    def test_installed_hook_blocks_actual_bad_commit(self):
        self.git("config", "--unset", "core.hooksPath")
        self.run_command("bash", "scripts/install-hooks.sh")
        witness = self.repo / "FAIL"
        witness.write_text("staged failure")
        self.git("add", "FAIL")
        witness.unlink()
        before = self.git("rev-parse", "HEAD").stdout
        self.git("commit", "-m", "Must not land", success=False)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout, before)

    def test_installer_preserves_existing_hook_configuration(self):
        self.run_command("bash", "scripts/install-hooks.sh", success=False)
        self.assertEqual(self.git("config", "--get", "core.hooksPath").stdout.strip(), os.devnull)

    def test_installer_does_not_disable_default_hooks(self):
        self.git("config", "--unset", "core.hooksPath")
        hook = self.repo / ".git/hooks/post-commit"
        hook.write_text("#!/usr/bin/env bash\nexit 0\n")
        hook.chmod(0o755)
        result = self.run_command("bash", "scripts/install-hooks.sh", success=False)
        self.assertIn("existing executable default hook", result.stdout)
        self.git("config", "--get", "core.hooksPath", success=False)
        self.assertTrue(os.access(hook, os.X_OK))


if __name__ == "__main__":
    unittest.main()
