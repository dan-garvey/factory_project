"""Resource admission tests use disposable Git worktrees and tiny commands."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("run_local", ROOT / "scripts/run_local.py")
resources = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resources)


class ResourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="factory resources ")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.repo = self.base / "main checkout"
        self.repo.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TERMINAL_PROMPT="0", PYTHONDONTWRITEBYTECODE="1")
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Resource fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", os.devnull)
        (self.repo / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/run_local.py", self.repo / "scripts/run_local.py")
        (self.repo / ".beads").mkdir()
        (self.repo / ".beads/.gitignore").write_text("*.db\n")
        (self.repo / ".beads/issues.jsonl").write_text('{"id":"factory-fixture"}\n')
        self.git("add", "scripts/run_local.py", ".beads/.gitignore", ".beads/issues.jsonl")
        self.git("commit", "-m", "Seed disposable resource fixture")
        # A sentinel enables the shared-worktree helper without opening SQLite.
        (self.repo / ".beads/beads.db").write_text("never a real database")
        self.linked = self.base / "linked checkout"
        self.git("worktree", "add", "--detach", str(self.linked))
        self.command("bash", str(ROOT / "scripts/link-beads-worktree.sh"), str(self.linked))
        self.assertTrue((self.linked / ".beads").is_symlink())
        self.common = resources.common_git_dir(self.repo)

    def command(self, *command, cwd=None, env=None):
        result = subprocess.run(command, cwd=cwd or self.repo, env=env or self.env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def git(self, *arguments):
        return self.command("git", *arguments)

    def wrapped(self, mode, code="pass", cwd=None, env=None, jobs=8):
        return subprocess.run(
            [sys.executable, "-B", "scripts/run_local.py", mode, "--no-wait",
             "--jobs", str(jobs), "--disk-floor-gib", "0", "--memory-reserve-gib", "0",
             "--", sys.executable, "-B", "-c", code],
            cwd=cwd or self.linked, env=env or self.env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
        )

    def test_worktrees_share_admission_and_checks_can_coexist(self):
        self.assertEqual(resources.common_git_dir(self.linked), self.common)
        with resources.admission(self.common, "check", wait=False):
            self.assertEqual(self.wrapped("check").returncode, 0)
            self.assertEqual(self.wrapped("heavy").returncode, 0)
            self.assertEqual(self.wrapped("benchmark").returncode, 75)

    def test_heavy_lane_serializes_but_allows_checks(self):
        with resources.admission(self.common, "heavy", wait=False):
            self.assertEqual(self.wrapped("check").returncode, 0)
            self.assertEqual(self.wrapped("heavy").returncode, 75)
            self.assertEqual(self.wrapped("benchmark").returncode, 75)
        self.assertEqual(self.wrapped("heavy").returncode, 0)

    def test_benchmark_excludes_checks_heavy_and_other_measurements(self):
        with resources.admission(self.common, "benchmark", wait=False):
            for mode in ("check", "heavy", "benchmark"):
                with self.subTest(mode=mode):
                    self.assertEqual(self.wrapped(mode).returncode, 75)
        self.assertEqual(self.wrapped("benchmark").returncode, 0)

    def test_child_failure_releases_all_locks_and_preserves_exit_status(self):
        self.assertEqual(self.wrapped("heavy", "raise SystemExit(7)").returncode, 7)
        self.assertEqual(self.wrapped("benchmark").returncode, 0)

    def test_floor_failures_do_not_start_child_and_release_locks(self):
        marker = self.base / "must not run"
        for disk, memory, reason in ((19, 64, "free disk"), (64, 7, "MemAvailable")):
            with self.subTest(reason=reason), mock.patch.object(
                resources.shutil, "disk_usage", return_value=types.SimpleNamespace(free=disk * resources.GIB)
            ), mock.patch.object(resources, "available_memory", return_value=memory * resources.GIB):
                with self.assertRaisesRegex(resources.AdmissionError, reason):
                    resources.run(self.repo, "heavy", [sys.executable, "-c",
                                  f"from pathlib import Path; Path({str(marker)!r}).touch()"], wait=False)
                self.assertFalse(marker.exists())
                with resources.admission(self.common, "benchmark", wait=False):
                    pass

    def test_capacity_is_probed_only_after_admission(self):
        def memory_probe():
            with self.assertRaises(resources.AdmissionError):
                with resources.admission(self.common, "benchmark", wait=False):
                    pass
            return 64 * resources.GIB

        with mock.patch.object(resources, "available_memory", side_effect=memory_probe), mock.patch.object(
            resources.shutil, "disk_usage", return_value=types.SimpleNamespace(free=64 * resources.GIB)
        ):
            self.assertEqual(resources.run(self.repo, "heavy", [sys.executable, "-c", "pass"], wait=False), 0)
        with resources.admission(self.common, "benchmark", wait=False), mock.patch.object(
            resources, "check_capacity"
        ) as capacity:
            with self.assertRaises(resources.AdmissionError):
                resources.run(self.repo, "heavy", [sys.executable, "-c", "pass"], wait=False)
            capacity.assert_not_called()

    def test_check_mode_remains_available_below_capacity_floors(self):
        with mock.patch.object(resources, "check_capacity", side_effect=AssertionError("must not probe")):
            self.assertEqual(resources.run(self.repo, "check", [sys.executable, "-c", "pass"], wait=False), 0)

    def test_child_parallelism_defaults_replace_inherited_larger_values(self):
        variables = ("CMAKE_BUILD_PARALLEL_LEVEL", "CARGO_BUILD_JOBS", "CTEST_PARALLEL_LEVEL")
        env = dict(self.env, **{variable: "48" for variable in variables})
        code = f"import json, os; print(json.dumps([os.environ[key] for key in {variables!r}]))"
        result = self.wrapped("check", code, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["8", "8", "8"])
        self.assertEqual(json.loads(self.wrapped("check", code, jobs=3).stdout), ["3", "3", "3"])

    def test_memavailable_units_and_missing_measurement(self):
        meminfo = self.base / "meminfo"
        meminfo.write_text("MemFree: 1 kB\nMemAvailable: 8388608 kB\n")
        self.assertEqual(resources.available_memory(meminfo), 8 * resources.GIB)
        meminfo.write_text("MemFree: 1 kB\n")
        with self.assertRaisesRegex(ValueError, "MemAvailable is missing"):
            resources.available_memory(meminfo)


if __name__ == "__main__":
    unittest.main()
