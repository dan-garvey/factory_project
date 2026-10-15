"""Synthetic compiler/admission fixtures; canonical tooling tests need no Godot."""
import contextlib
import hashlib
import importlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

from test_tooling import GitFixture


with mock.patch.object(sys, "path", [str(Path(__file__).resolve().parents[1] / "scripts"), *sys.path]):
    checker = importlib.import_module("check")
    coordinator = importlib.import_module("check_commit")
    compiler = importlib.import_module("check_gdscript")


class CommitGateTests(GitFixture):
    def game(self, text="GOOD"):
        project = self.repo / checker.GODOT_PROJECT
        project.mkdir(parents=True, exist_ok=True)
        (project / "project.godot").write_text("config_version=5\n")
        script = project / "fixture.gd"
        script.write_text(text)
        self.git("add", str(checker.GODOT_PROJECT))
        return script

    def invoke(self):
        with mock.patch.object(checker, "ROOT", self.repo), mock.patch.dict(os.environ, self.env, clear=True), \
                mock.patch.object(sys, "argv", ["check_commit.py"]):
            return coordinator.main()

    def test_one_top_level_permit_selected_from_exact_staged_delta(self):
        with mock.patch.object(coordinator.run_local, "run", return_value=0) as admission:
            self.assertEqual(self.invoke(), 0)
            self.assertEqual(admission.call_count, 1)
            self.assertEqual(admission.call_args.args[1], "check")
            self.assertNotIn("--parse-gdscript", admission.call_args.args[2])
            self.assertIn(self.git("write-tree").stdout.strip(), admission.call_args.args[2])
        self.game()
        for key, value in (("factory.godotExecutable", "/explicit/engine"),
                           ("factory.godotSHA256", "a" * 64),
                           ("factory.godotArtifacts", str(self.base / "outputs"))):
            self.git("config", "--local", key, value)
        with mock.patch.object(coordinator.run_local, "run", return_value=37) as admission:
            self.assertEqual(self.invoke(), 37)
            self.assertEqual(admission.call_count, 1)
            self.assertEqual(admission.call_args.args[1], "heavy")
            command = admission.call_args.args[2]
            self.assertIn("--parse-gdscript", command)
            self.assertNotIn("run_local.py", " ".join(command))

    def test_real_hook_non_game_commit_needs_no_engine_and_one_check_permit(self):
        self.git("config", "--unset", "core.hooksPath")
        self.run_command("bash", "scripts/install-hooks.sh")
        (self.repo / "README.md").write_text("ordinary documentation\n")
        self.git("add", "README.md")
        result = self.git("commit", "-m", "Engine-free source commit")
        self.assertEqual(result.stdout.count("local resources: admitted check"), 1)
        self.assertNotIn("admitted heavy", result.stdout)

    def test_missing_local_runtime_blocks_game_hook_without_engine_or_commit(self):
        self.game()
        self.git("config", "--unset", "core.hooksPath")
        self.run_command("bash", "scripts/install-hooks.sh")
        before = self.git("rev-parse", "HEAD").stdout
        result = self.git("commit", "-m", "Must refuse missing runtime", success=False)
        self.assertIn("repository-local factory.godotExecutable", result.stdout)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout, before)
        self.assertNotIn("admitted heavy", result.stdout)

    def test_cheap_staged_path_refuses_game_without_nested_admission(self):
        self.game()
        result = self.run_command(sys.executable, "-B", "scripts/check.py", "--staged", success=False)
        self.assertIn("scripts/check_commit.py", result.stdout)
        self.assertNotIn("local resources: admitted", result.stdout)

    def test_global_runtime_settings_and_unsupported_script_roots_do_not_bypass(self):
        self.game()
        global_config = self.base / "global-config"
        global_config.write_text("[factory]\n godotExecutable=/global/engine\n godotSHA256=" + "a" * 64 + "\n godotArtifacts=/global/artifacts\n")
        self.env["GIT_CONFIG_GLOBAL"] = str(global_config)
        with contextlib.redirect_stderr(io.StringIO()), mock.patch.object(coordinator.run_local, "run") as admission:
            self.assertEqual(self.invoke(), 1)
            admission.assert_not_called()
        (self.repo / "outside.gd").write_text("unsupported root\n")
        self.git("add", "outside.gd")
        result = self.run_command(sys.executable, "-B", "scripts/check.py", "--staged", success=False)
        self.assertIn("outside the supported prototype project", result.stdout)

    def test_expected_tree_rejects_changed_index_before_admission(self):
        before = self.git("write-tree").stdout.strip()
        (self.repo / "later.txt").write_text("later staging\n")
        self.git("add", "later.txt")
        result = self.run_command(sys.executable, "-B", "scripts/check.py", "--staged",
                                  "--expected-tree", before, success=False)
        self.assertIn("index changed before admission", result.stdout)

    def test_raw_staged_game_bytes_and_post_parser_index_guard(self):
        script = self.game("BAD staged source\n")
        helper = self.repo / "scripts/check_gdscript.py"
        # This synthetic parser deliberately tests snapshot transport only.
        # Actual Godot old-fail/new-pass is separate retained engine evidence.
        helper.write_text("from pathlib import Path\n"
                          "p=Path(__file__).resolve().parents[1]/'experiments/engine-environment/godot/fixture.gd'\n"
                          "print('RAW_GDSCRIPT '+p.read_text())\n"
                          "raise SystemExit(1 if 'BAD' in p.read_text() else 0)\n")
        self.git("add", "scripts/check_gdscript.py")
        script.write_text("GOOD working source\n")
        command = (sys.executable, "-B", "scripts/check.py", "--staged", "--parse-gdscript",
                   "--godot", "/unused/synthetic", "--godot-sha256", "a" * 64,
                   "--prototype-artifacts", str(self.base / "outputs"))
        result = self.run_command(*command, success=False)
        self.assertIn("BAD staged source", result.stdout)
        self.git("add", str(script.relative_to(self.repo)))
        script.write_text("BAD unstaged source\n")
        result = self.run_command(*command)
        self.assertIn("GOOD working source", result.stdout)
        self.assertEqual(script.read_text(), "BAD unstaged source\n")
        later = self.repo / "later.txt"
        later.write_text("index mutation witness\n")
        helper.write_text("import subprocess\n"
                          f"subprocess.run(['git','-C',{str(self.repo)!r},'add','later.txt'],check=True)\n")
        self.git("add", "scripts/check_gdscript.py")
        result = self.run_command(*command, success=False)
        self.assertIn("index changed during checks", result.stdout)


class CompilerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="synthetic compiler ")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.source = self.base / "source"
        self.project = self.source / checker.GODOT_PROJECT
        self.project.mkdir(parents=True)
        (self.project / "project.godot").write_text("config_version=5\n")
        (self.project / "one.gd").write_text("GOOD fixture\n")
        (self.project / "two.gd").write_text("GOOD second fixture\n")
        self.binary = self.base / "synthetic-engine"
        self.calls = self.base / "calls.jsonl"
        self.binary.write_text(f"#!{sys.executable}\nimport sys,json\nfrom pathlib import Path\n"
                               f"with Path({str(self.calls)!r}).open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\n"
                               f"if '--version' in sys.argv: print({compiler.VERSION!r})\n"
                               "elif '--editor' in sys.argv: print('synthetic import')\n"
                               "else:\n"
                               " assert '--check-only' in sys.argv\n"
                               " name=sys.argv[sys.argv.index('--script')+1].removeprefix('res://')\n"
                               " if 'BAD' in Path(name).read_text(): print('SCRIPT ERROR: synthetic compile refusal')\n")
        self.binary.chmod(0o700)
        self.digest = compiler.sha256(self.binary)
        self.outputs = self.base / "evidence"

    def invoke(self, binary=None, digest=None):
        command = ["check_gdscript.py", "--godot", str(binary or self.binary), "--sha256", digest or self.digest,
                   "--artifacts", str(self.outputs), "--source-tree", "1" * 40]
        with mock.patch.object(compiler, "ROOT", self.source), mock.patch.object(compiler, "PROJECT", self.project), \
                mock.patch.object(sys, "argv", command), mock.patch.object(compiler.shutil, "disk_usage",
                return_value=SimpleNamespace(free=64 * 1024**3)), \
                mock.patch.object(compiler.bounds, "MAX_ARTIFACT_BYTES", compiler.MAX_BYTES):
            compiler.main()

    def test_import_alone_is_insufficient_and_every_script_is_checked(self):
        self.invoke()
        receipt = json.loads(next(self.outputs.glob("parse-*/result.json")).read_text())
        self.assertEqual(receipt["status"], "pass")
        self.assertEqual(receipt["parsed_scripts"], ["one.gd", "two.gd"])
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        scripts = [call for call in calls if "--script" in call]
        self.assertEqual(len(scripts), 2)
        self.assertTrue(all("--check-only" in call and "--headless" in call for call in scripts))
        self.assertEqual(receipt["source_hashes"]["one.gd"], hashlib.sha256(b"GOOD fixture\n").hexdigest())

    def test_zero_exit_with_compiler_error_refuses_and_retains_diagnostics(self):
        (self.project / "two.gd").write_text("BAD compiler witness\n")
        with self.assertRaisesRegex(ValueError, "compilation failed"):
            self.invoke()
        session = next(self.outputs.glob("parse-*"))
        receipt = json.loads((session / "result.json").read_text())
        self.assertEqual(receipt["status"], "fail")
        self.assertEqual(receipt["stages"][-1]["exit"], 0)
        self.assertIn("synthetic compile refusal", (session / "script-001.log").read_text())

    def test_missing_changed_or_unpinned_runtime_never_starts(self):
        for binary, digest in ((self.base / "missing", self.digest), (self.binary, "0" * 64), (self.binary, "bad")):
            with self.subTest(binary=binary, digest=digest), contextlib.redirect_stderr(io.StringIO()), \
                    self.assertRaises(SystemExit):
                self.invoke(binary, digest)
        self.assertFalse(self.calls.exists())
        self.assertFalse(self.outputs.exists())

    def test_pinned_wrong_version_is_a_failure_before_import(self):
        self.binary.write_text(self.binary.read_text().replace(compiler.VERSION, "4.7.1.stable.unsupported"))
        with self.assertRaisesRegex(ValueError, "not the separately verified supported Godot"):
            self.invoke(digest=compiler.sha256(self.binary))
        receipt = json.loads(next(self.outputs.glob("parse-*/result.json")).read_text())
        self.assertEqual(receipt["status"], "fail")
        self.assertEqual([stage["name"] for stage in receipt["stages"]], ["version"])
