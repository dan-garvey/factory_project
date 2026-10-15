import importlib.util
import os
from pathlib import Path
import subprocess
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
