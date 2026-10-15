import importlib.util
import os
from pathlib import Path
import subprocess
import signal
import select
import sys
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("engine_probe", ROOT / "scripts/check_engine_environment.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class EngineEnvironmentTests(unittest.TestCase):
    def test_partial_line_output_is_capped_and_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch.object(probe, "MAX_LOG_BYTES", 4096):
                with self.assertRaisesRegex(ValueError, "log allowance"):
                    probe.execute_bounded([sys.executable, "-c", "import os;os.write(1,b'x'*32768)"],
                                          cwd=root, env=os.environ.copy(), log=root / "stage.log",
                                          artifacts=root, timeout=5)
            self.assertEqual((root / "stage.log").stat().st_size, 4096)

    def test_runner_retains_failure_receipt_when_log_cap_is_hit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "noisy-engine"
            binary.write_text(f"#!{sys.executable}\nimport os\nos.write(1,b'x'*32768)\n")
            binary.chmod(0o700)
            with mock.patch.object(probe, "MAX_LOG_BYTES", 4096), mock.patch.object(
                    probe.shutil, "disk_usage", return_value=SimpleNamespace(free=64 * 1024**3)):
                with self.assertRaisesRegex(ValueError, "log allowance"):
                    probe.run(binary, root / "evidence")
            run = next((root / "evidence").glob("run-*"))
            self.assertEqual((run / "version.log").stat().st_size, 4096)
            self.assertIn('"status": "fail"', (run / "result.json").read_text())

    def test_finite_output_and_nonzero_status_are_retained(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = probe.execute_bounded([sys.executable, "-c", "import os;os.write(1,b'complete');raise SystemExit(7)"],
                                           cwd=root, env=os.environ.copy(), log=root / "stage.log",
                                           artifacts=root, timeout=5)
            self.assertEqual(result.returncode, 7)
            self.assertEqual((root / "stage.log").read_bytes(), b"complete")

    def test_owned_artifact_growth_is_checked_while_process_runs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            code = "from pathlib import Path;import signal;Path('cache').write_bytes(b'x'*8192);signal.pause()"
            with mock.patch.object(probe, "MAX_ARTIFACT_BYTES", 4096):
                with self.assertRaisesRegex(ValueError, "artifact/cache allowance"):
                    probe.execute_bounded([sys.executable, "-c", code], cwd=root,
                                          env=os.environ.copy(), log=root / "stage.log",
                                          artifacts=root, timeout=5)
            self.assertEqual((root / "cache").stat().st_size, 8192)

    def test_process_group_cleanup_with_live_or_exited_leader(self):
        # A pipe barrier proves the descendant is ready before the leader pauses
        # or exits. No retry/sleep chooses the tested lifetime boundary.
        for leader_exits, keep_stdout in ((False, True), (True, True), (True, False)):
            with self.subTest(leader_exits=leader_exits, keep_stdout=keep_stdout):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    child = ("import os,signal;from pathlib import Path;"
                             "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
                             "Path('descendant.pid').write_text(str(os.getpid()));"
                             "os.write(int(os.environ['READY_FD']),b'1');signal.pause()")
                    code = ("import os,subprocess,sys,signal;"
                            "read_fd,write_fd=os.pipe();"
                            "env=dict(os.environ,READY_FD=str(write_fd));"
                            f"subprocess.Popen([sys.executable,'-c',{child!r}],env=env,"
                            f"pass_fds=(write_fd,),stdout={'None' if keep_stdout else 'subprocess.DEVNULL'},"
                            f"stderr={'None' if keep_stdout else 'subprocess.DEVNULL'});"
                            "os.close(write_fd);assert os.read(read_fd,1)==b'1';os.close(read_fd);"
                            + ("sys.exit(0)" if leader_exits else "signal.pause()"))
                    try:
                        if keep_stdout:
                            with self.assertRaises(subprocess.TimeoutExpired):
                                probe.execute_bounded([sys.executable, "-c", code], cwd=root,
                                                      env=os.environ.copy(), log=root / "stage.log",
                                                      artifacts=root, timeout=1)
                        else:
                            result = probe.execute_bounded([sys.executable, "-c", code], cwd=root,
                                                           env=os.environ.copy(), log=root / "stage.log",
                                                           artifacts=root, timeout=5)
                            self.assertEqual(result.returncode, 0)
                        pid = int((root / "descendant.pid").read_text())
                        try:
                            descriptor = os.pidfd_open(pid)
                        except ProcessLookupError:
                            descriptor = None
                        if descriptor is not None:
                            try:
                                self.assertTrue(select.select([descriptor], [], [], 2)[0],
                                                "owned descendant did not exit after cleanup")
                            finally:
                                os.close(descriptor)
                        # Readable pidfd proves exit, including an orphan zombie
                        # awaiting host reaping, without racing a /proc lookup.
                    finally:
                        if (root / "descendant.pid").exists():
                            try:
                                os.kill(int((root / "descendant.pid").read_text()), signal.SIGKILL)
                            except ProcessLookupError:
                                pass

    def test_requested_missing_runtime_is_failure_not_skip_or_download(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "evidence"
            with self.assertRaisesRegex(ValueError, "missing"):
                probe.run(Path(temporary) / "missing-godot", output)
            self.assertFalse(output.exists())

    def test_marker_without_independent_report_is_not_passing_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "fake-godot"
            binary.write_text(f"#!{sys.executable}\nimport sys\n"
                              "print('4.7.2.stable.fake' if '--version' in sys.argv else 'FACTORY_HEADLESS_PASS')\n")
            binary.chmod(0o700)
            with mock.patch.object(probe.shutil, "disk_usage", return_value=SimpleNamespace(free=64 * 1024**3)):
                with self.assertRaises(FileNotFoundError):
                    probe.run(binary, root / "evidence")
            receipt = next((root / "evidence").glob("run-*/result.json"))
            self.assertIn('"status": "fail"', receipt.read_text())

    def test_prototype_options_cannot_be_silently_ignored(self):
        for options in (["--prototype-render"], ["--godot", "/missing/engine"],
                        ["--prototype-artifacts", "/tmp/unused"]):
            with self.subTest(options=options):
                environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
                result = subprocess.run([sys.executable, "-B", str(ROOT / "scripts/check.py"), *options],
                                        capture_output=True, text=True, env=environment)
                self.assertEqual(result.returncode, 2)
                self.assertIn("required together", result.stderr)


if __name__ == "__main__":
    unittest.main()
