import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location(
    "factory_beads_backup", Path(__file__).resolve().parents[1] / "scripts/backup_beads.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


# Executed instead of br/gh. No real Beads database, account or network access.
FAKE = r'''
import json, os, pathlib, sys
state = pathlib.Path(os.environ["FACTORY_BACKUP_TEST"])
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
with (state / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"name": name, "args": args, "cwd": os.getcwd()}) + "\n")
mode = (state / "mode").read_text()
if name == "br":
    assert args == ["sync", "--flush-only", "--db", str(pathlib.Path.cwd() / ".beads/beads.db")]
    assert not any(key.startswith("BEADS_") for key in os.environ)
    if mode == "sync_failure":
        print("private diagnostic must not escape", file=sys.stderr)
        sys.exit(1)
    (pathlib.Path.cwd() / ".beads/issues.jsonl").write_bytes((state / "export").read_bytes())
else:
    assert args[:4] == ["api", "--hostname", "github.com", "gists/abc123"]
    value = json.loads((state / "gist.json").read_text())
    if args[4:] == ["--method", "PATCH", "--input", "-"]:
        payload = json.load(sys.stdin)
        (state / "uploaded.json").write_text(json.dumps(payload))
        if mode == "patch_failure":
            print("private diagnostic must not escape", file=sys.stderr)
            sys.exit(1)
        value["files"] = payload["files"]
        if mode == "wrong_content":
            value["files"]["issues.jsonl"]["content"] = "unverified content"
        if mode == "truncated":
            value["files"]["issues.jsonl"]["truncated"] = True
        if mode == "public_after_patch":
            value["public"] = True
        if mode == "bad_json":
            (state / "bad_readback").touch()
        (state / "gist.json").write_text(json.dumps(value))
    else:
        assert args[4:] == ["--method", "GET"]
        if (state / "bad_readback").exists():
            print("invalid response")
            sys.exit(0)
    print(json.dumps(value))
'''


class BackupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="factory gist backup ")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.repo = self.base / "main checkout"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        self.beads = self.repo / ".beads"
        self.beads.mkdir()
        self.original = '{"id":"factory-old","title":"old export"}\n'
        (self.beads / "issues.jsonl").write_text(self.original)
        (self.beads / "config.yaml").write_text("issue-prefix: factory\n")
        (self.beads / "metadata.json").write_text('{"database":"beads.db","jsonl_export":"issues.jsonl"}\n')
        # Excluded contents must never reach gh, even when adjacent to the export.
        (self.beads / "beads.db").write_text("database sentinel")
        (self.beads / "account-telemetry.json").write_text("private account sentinel")
        (self.beads / "beads.db-wal").write_text("WAL sentinel")
        self.config = self.base / "private-config.json"
        self.config.write_text(json.dumps({"gist_id": "abc123", "root": str(self.repo), "visibility": "unlisted"}))
        self.config.chmod(0o600)
        self.state = self.base / "fake state"
        self.state.mkdir()
        self.export = '{"id":"factory-new","title":"flushed issue","status":"open"}\n'
        (self.state / "export").write_text(self.export)
        (self.state / "mode").write_text("ok")
        self.gist = {"id": "abc123", "public": False, "files": {name: {} for name in backup.FILES}}
        self.write_gist()
        binary = self.base / "bin"
        binary.mkdir()
        for name in ("br", "gh"):
            path = binary / name
            path.write_text(f"#!{sys.executable}\n" + FAKE)
            path.chmod(0o700)
        self.environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.environment.update(PATH=str(binary) + os.pathsep + os.environ["PATH"],
                                FACTORY_BACKUP_TEST=str(self.state), PYTHONDONTWRITEBYTECODE="1")
        patch = mock.patch.dict(os.environ, self.environment, clear=True)
        patch.start()
        self.addCleanup(patch.stop)

    def git(self, *args):
        environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        return subprocess.run(["git", "-C", str(self.repo), *args], capture_output=True,
                              text=True, check=True, env=environment).stdout

    def write_gist(self):
        (self.state / "gist.json").write_text(json.dumps(self.gist))

    def calls(self):
        path = self.state / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_backup(self):
        return backup.backup(self.repo, self.config)

    def assert_no_upload(self):
        self.assertFalse((self.state / "uploaded.json").exists())

    def test_flush_then_upload_only_named_files_and_verify_content(self):
        with mock.patch.dict(os.environ, {"BEADS_DB": "/foreign/db", "BEADS_JSONL": "/foreign/export"}):
            at = self.run_backup()
        self.assertIn("+00:00", at)
        calls = self.calls()
        self.assertEqual([call["name"] for call in calls], ["br", "gh", "gh", "gh"])
        self.assertTrue(all(call["cwd"] == str(self.repo) for call in calls))
        payload = json.loads((self.state / "uploaded.json").read_text())
        self.assertEqual(set(payload), {"files"})
        self.assertEqual(set(payload["files"]), set(backup.FILES))
        self.assertEqual(payload["files"]["issues.jsonl"]["content"], self.export)
        self.assertEqual((self.beads / "beads.db").read_text(), "database sentinel")
        self.assertEqual((self.beads / "beads.db-wal").read_text(), "WAL sentinel")
        self.assertNotIn("private account sentinel", json.dumps(payload))

    def test_linked_invocation_uses_canonical_directory_and_preserves_symlink(self):
        (self.repo / "README").write_text("fixture\n")
        self.git("add", "README")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture")
        linked = self.base / "linked checkout"
        self.git("worktree", "add", "--detach", str(linked))
        (linked / ".beads").symlink_to(self.beads, target_is_directory=True)
        backup.backup(linked, self.config)
        self.assertTrue((linked / ".beads").is_symlink())
        self.assertEqual((linked / ".beads").resolve(), self.beads)
        self.assertTrue(all(call["cwd"] == str(self.repo) for call in self.calls()))
        inside = linked / "private-config.json"
        inside.write_text(self.config.read_text())
        inside.chmod(0o600)
        with self.assertRaisesRegex(ValueError, "outside"):
            backup.backup(self.repo, inside)

    def test_public_wrong_id_extra_files_and_unknown_visibility_fail_before_patch(self):
        for change in ({"public": True}, {"public": None}, {"id": "wrong"}, {"files": {}},
                       {"files": {**self.gist["files"], "unrelated.txt": {}}}):
            with self.subTest(change=change):
                (self.state / "gist.json").write_text(json.dumps({**self.gist, **change}))
                with self.assertRaises(ValueError):
                    self.run_backup()
                self.assert_no_upload()

    def test_bad_export_never_reaches_gh(self):
        for export in ("", "not json\n", "[]\n", '{"id":"wrong-prefix"}\n',
                       self.export + self.export,
                       '{"id":"factory-test","title":""}\n'):
            with self.subTest(export=export):
                (self.state / "export").write_text(export)
                with self.assertRaises(ValueError):
                    self.run_backup()
                self.assert_no_upload()
        self.assertTrue(all(call["name"] == "br" for call in self.calls()))

    def test_ordinary_discussion_of_credentials_and_tokens_is_not_rejected(self):
        issue = {"id": "factory-test", "title": "Discuss credential and token handling",
                 "description": "api_key: not configured; keep credentials and account telemetry local"}
        (self.state / "export").write_text(json.dumps(issue) + "\n")
        self.run_backup()
        self.assertTrue((self.state / "uploaded.json").exists())

    def test_size_warning_and_hard_stop_never_silently_truncate(self):
        path = self.base / "large.txt"
        path.write_bytes(b"a" * (backup.MAX_BYTES * 3 // 4))
        output = io.StringIO()
        with mock.patch.object(sys, "stderr", output):
            self.assertEqual(len(backup.read_text(path)), path.stat().st_size)
        self.assertIn("75%", output.getvalue())
        path.write_bytes(b"a" * (backup.MAX_BYTES + 1))
        with self.assertRaisesRegex(ValueError, "nothing is uploaded or truncated"):
            backup.read_text(path)

    def test_bad_metadata_oversized_binary_and_symlink_inputs_are_refused(self):
        path = self.beads / "metadata.json"
        for data in (b"[]", b"{", b"\xff", b"\x00", b" " * (backup.MAX_BYTES + 1)):
            with self.subTest(data_size=len(data)):
                path.write_bytes(data)
                with self.assertRaises(ValueError):
                    self.run_backup()
                self.assert_no_upload()
        path.unlink()
        path.symlink_to(self.config)
        with self.assertRaisesRegex(ValueError, "Symlink"):
            self.run_backup()
        self.assert_no_upload()

    def test_private_config_location_mode_id_and_symlinks(self):
        self.config.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "0600"):
            self.run_backup()
        self.config.chmod(0o600)
        for text in ('{}', '{"gist_id":"../../gists"}', '{"gist_id":"abc123","token":"fixture"}'):
            self.config.write_text(text)
            with self.assertRaises(ValueError):
                self.run_backup()
        alias = self.base / "alias"
        alias.symlink_to(self.base, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Symlink"):
            backup.backup(self.repo, alias / self.config.name)
        with self.assertRaises(ValueError):
            backup.backup(self.repo, Path("relative-config.json"))
        self.assertEqual(self.calls(), [])

    def test_symlink_or_redirected_tracker_settings_fail_before_flush(self):
        path = self.beads / "config.yaml"
        path.unlink()
        path.symlink_to(self.config)
        with self.assertRaisesRegex(ValueError, "Symlink"):
            self.run_backup()
        self.assertEqual(self.calls(), [])
        path.unlink()
        path.write_text("issue-prefix: factory\n")
        (self.beads / "metadata.json").write_text('{"database":"/foreign/db","jsonl_export":"issues.jsonl"}')
        with self.assertRaisesRegex(ValueError, "metadata"):
            self.run_backup()
        self.assertEqual(self.calls(), [])

    def test_configured_root_visibility_and_git_private_config_exception(self):
        value = json.loads(self.config.read_text())
        for change in ({"root": str(self.base)}, {"visibility": "public"}, {"extra": "unexpected"}):
            self.config.write_text(json.dumps({**value, **change}))
            with self.assertRaises(ValueError):
                self.run_backup()
        path = self.repo / ".git/factory-ops/beads-backup.json"
        path.parent.mkdir()
        path.write_text(json.dumps(value))
        path.chmod(0o600)
        backup.backup(self.repo, path)

    def test_sync_failure_preserves_existing_export_and_does_not_call_gh(self):
        (self.state / "mode").write_text("sync_failure")
        with self.assertRaisesRegex(ValueError, "br operation failed") as error:
            self.run_backup()
        self.assertNotIn("private diagnostic", str(error.exception))
        self.assertEqual((self.beads / "issues.jsonl").read_text(), self.original)
        self.assertEqual([call["name"] for call in self.calls()], ["br"])

    def test_upload_failure_and_unverifiable_success_are_failures_without_retry(self):
        for mode in ("patch_failure", "wrong_content", "truncated", "public_after_patch", "bad_json"):
            with self.subTest(mode=mode):
                self.write_gist()
                (self.state / "mode").write_text(mode)
                before = len(self.calls())
                with self.assertRaises(ValueError) as error:
                    self.run_backup()
                self.assertNotIn("private diagnostic", str(error.exception))
                self.assertEqual(len(self.calls()) - before, 3 if mode == "patch_failure" else 4)
                self.assertEqual((self.beads / "beads.db").read_text(), "database sentinel")

    def test_timeout_is_failure_and_diagnostics_are_not_exposed(self):
        with mock.patch.object(backup.subprocess, "run", side_effect=subprocess.TimeoutExpired(
                "gh", 30, output="private output", stderr="private diagnostics")):
            with self.assertRaisesRegex(ValueError, "not verified") as error:
                backup.command(["gh", "api"], self.repo)
        self.assertNotIn("private", str(error.exception))


if __name__ == "__main__":
    unittest.main()
