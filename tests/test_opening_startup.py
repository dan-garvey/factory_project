import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("startup_bounds", ROOT / "scripts/check_engine_environment.py")
bounds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bounds)
spec = importlib.util.spec_from_file_location("opening_launcher", ROOT / "scripts/run_opening.py")
launcher = importlib.util.module_from_spec(spec)
with mock.patch.dict(sys.modules, {"check_engine_environment": bounds}):
    spec.loader.exec_module(launcher)


def observed_start(slot):
    # Declared initial worksite, independently observed in the preceding UI review.
    return {"schema": 1, "scene": "res://opening/opening.tscn", "script": "res://opening/opening.gd",
            "state": {"context": "opening-local-1", "revision": 3, "order": 0,
                      "initial_feed": 16, "recipe_input": 1, "entities": {}, "links": [],
                      "drive_links": [], "inventories": {}, "remaining": 0, "powered": False,
                      "power_enabled": True, "options": {"opening": True},
                      "stock": {"source": 16, "collector": 0, "belt": 0, "input": 0,
                                "held": 0, "output": 0, "player": 0},
                      "parts": {"collector": 1, "belt": 1, "processor": 1, "wheel": 1, "shaft": 3}},
            "view": {"save_slot": str(slot), "save_ready": True, "save_owned": False,
                     "save_disabled": False, "load_disabled": True, "confirmed": False,
                     "request_sequence": 0, "namespace_nonempty": True, "machines": 0, "items": 16}}


class OpeningStartupTests(unittest.TestCase):
    def test_valid_report_cannot_mask_an_engine_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "fake-engine"
            binary.write_text(f"#!{sys.executable}\nimport sys,json\nfrom pathlib import Path\n"
                              "if '--version' in sys.argv:\n print('4.7.2.stable.fake')\n"
                              "elif '--editor' not in sys.argv:\n"
                              " report=next(a.split('=',1)[1] for a in sys.argv if a.startswith('--startup-report='))\n"
                              " slot=next(a.split('=',1)[1] for a in sys.argv if a.startswith('--save-slot='))\n"
                              f" data={observed_start('placeholder')!r}\n"
                              " data['view']['save_slot']=slot\n Path(report).write_text(json.dumps(data))\n"
                              " print('ERROR: controlled fixture error')\n")
            binary.chmod(0o700)
            args = ["run_opening.py", "--godot", str(binary), "--artifacts", str(root / "runs"), "--smoke"]
            with mock.patch.object(sys, "argv", args), mock.patch.object(
                    launcher.shutil, "disk_usage", return_value=SimpleNamespace(free=64 * 1024**3)):
                with self.assertRaisesRegex(ValueError, "interactive failed"):
                    launcher.main()
            session = next((root / "runs").glob("session-*"))
            self.assertEqual(json.loads((session / "result.json").read_text())["status"], "fail")
            self.assertTrue((session / "startup.json").is_file())

    def test_real_launcher_requires_report_even_after_zero_exit_and_marker(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "fake-engine"
            binary.write_text(f"#!{sys.executable}\nimport sys\n"
                              "print('4.7.2.stable.fake' if '--version' in sys.argv else 'OPENING_STARTUP_OBSERVED')\n")
            binary.chmod(0o700)
            args = ["run_opening.py", "--godot", str(binary), "--artifacts", str(root / "runs"), "--smoke"]
            with mock.patch.object(sys, "argv", args), mock.patch.object(
                    launcher.shutil, "disk_usage", return_value=SimpleNamespace(free=64 * 1024**3)):
                with self.assertRaisesRegex(ValueError, "startup observer report"):
                    launcher.main()
            receipt = json.loads(next((root / "runs").glob("session-*/result.json")).read_text())
            self.assertEqual(receipt["status"], "fail")
            self.assertEqual(receipt["stages"][-1], {"name": "interactive", "exit": 0})
            self.assertIn("instrumentation", receipt)

    def test_observed_scene_quantities_and_slot_semantics_are_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            slot = root / "worksite.factory"
            report = root / "startup.json"
            valid = observed_start(slot)
            report.write_text(json.dumps(valid))
            self.assertEqual(launcher.read_smoke_report(report, slot), valid)
            for label, change in (
                    ("wrong scene", lambda r: r.update(scene="res://main.tscn")),
                    ("wrong script", lambda r: r.update(script="res://view.gd")),
                    ("quantity", lambda r: r["state"]["stock"].update(source=15)),
                    ("boolean part", lambda r: r["state"]["parts"].update(wheel=True)),
                    ("load enabled", lambda r: r["view"].update(load_disabled=False)),
                    ("adopted slot", lambda r: r["view"].update(save_owned=True)),
                    ("wrong slot", lambda r: r["view"].update(save_slot=str(root / "another.factory")))):
                with self.subTest(label=label):
                    invalid = json.loads(json.dumps(valid))
                    change(invalid)
                    report.write_text(json.dumps(invalid))
                    with self.assertRaises(ValueError):
                        launcher.read_smoke_report(report, slot)
            report.write_text(json.dumps(valid))
            slot.write_bytes(b"preserved user sentinel")
            with self.assertRaisesRegex(ValueError, "unexpectedly wrote"):
                launcher.read_smoke_report(report, slot)
            self.assertEqual(slot.read_bytes(), b"preserved user sentinel")

    def test_invalid_report_never_becomes_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            report = root / "startup.json"
            for content in (b"not json", b"\xff", b"[]", b'{"schema":true}', b"x" * (64 * 1024 + 1)):
                with self.subTest(content=content[:24]):
                    report.write_bytes(content)
                    with self.assertRaises(ValueError):
                        launcher.read_smoke_report(report, root / "new.factory")

    def test_copy_import_and_instrumented_hashes_are_distinct_and_honest(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            (project / "opening").mkdir()
            (project / launcher.SMOKE_OBSERVER).write_bytes(b"read-only observer")
            copied = b"config_version=5\n"
            imported = copied + b"; simulated editor import change\n"
            config = project / "project.godot"
            config.write_bytes(imported)
            metadata = launcher.instrument_smoke(project, hashlib.sha256(copied).hexdigest())
            hashes = metadata["modified_files"]["project.godot"]
            self.assertEqual(hashes["copied_sha256"], hashlib.sha256(copied).hexdigest())
            self.assertEqual(hashes["post_import_sha256"], hashlib.sha256(imported).hexdigest())
            self.assertEqual(hashes["runtime_sha256"], hashlib.sha256(config.read_bytes()).hexdigest())
            self.assertNotEqual(hashes["runtime_sha256"], hashes["copied_sha256"])
            self.assertEqual(metadata["observer"]["sha256"], hashlib.sha256(b"read-only observer").hexdigest())
            before = config.read_bytes()
            with self.assertRaisesRegex(ValueError, "existing autoloads"):
                launcher.instrument_smoke(project, hashlib.sha256(copied).hexdigest())
            self.assertEqual(config.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
