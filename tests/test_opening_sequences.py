"""Source-only independent ledger/report and false-green launcher witnesses."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sequence_bounds", ROOT / "scripts/check_engine_environment.py")
bounds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bounds)
spec = importlib.util.spec_from_file_location("sequence_runner", ROOT / "scripts/check_opening_sequences.py")
runner = importlib.util.module_from_spec(spec)
with mock.patch.dict(sys.modules, {"check_engine_environment": bounds}):
    spec.loader.exec_module(runner)


def empty_fixture():
    return {"context": "opening-seed-7", "initial_feed": 16, "recipe_input": 1,
            "stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0, "player": 0},
            "entities": {}, "parts": {"collector": 1, "belt": 1, "processor": 1, "wheel": 1, "shaft": 3},
            "links": [], "drive_links": [], "inventories": {}, "remaining": 0}


class OpeningSequencesTests(unittest.TestCase):
    def test_independent_ledger_rejects_wrong_quantity_or_type(self):
        fixture = empty_fixture()
        runner.ledger(fixture)
        for key, value in (("source", 15), ("source", True), ("held", -1), ("output", 2)):
            altered = copy.deepcopy(fixture)
            altered["stock"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                runner.ledger(altered)

    def test_independent_parts_and_live_link_checks_are_not_total_only(self):
        for alter in (lambda s: s["parts"].update(shaft=True),
                      lambda s: s["parts"].update(collector=0),
                      lambda s: s["drive_links"].append(["retired-wheel", "missing-collector"]),
                      lambda s: s["inventories"].update(P=True)):
            state = empty_fixture()
            alter(state)
            with self.assertRaises(ValueError):
                runner.ledger(state)

    def test_pass_marker_or_claimed_seed_list_is_not_actual_coverage(self):
        with tempfile.TemporaryDirectory() as temporary:
            for report in ({"status": "pass"}, {"schema": 1, "status": "pass", "seeds": runner.SEEDS,
                                                "random_steps": 64, "cases": []}):
                with self.assertRaises(ValueError):
                    runner.verify(report, Path(temporary))

    def test_real_runner_zero_exit_marker_without_report_fails_and_retains_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / "source-repository"
            runner.subprocess.run(["git", "init", "-q", str(repository)], check=True)
            runner.subprocess.run(["git", "-C", str(repository), "-c", "user.name=Synthetic Test",
                                   "-c", "user.email=synthetic@example.invalid", "commit", "--allow-empty", "-qm",
                                   "Synthetic runner provenance"], check=True)
            binary = root / "synthetic-engine"
            binary.write_text(f"#!{sys.executable}\nimport sys\n"
                              "print('4.7.2.stable.official.ed1daf0bf' if '--version' in sys.argv else 'OPENING_SEQUENCES_PASS')\n")
            binary.chmod(0o700)
            command = ["check_opening_sequences.py", "--godot", str(binary), "--sha256",
                       hashlib.sha256(binary.read_bytes()).hexdigest(), "--artifacts", str(root / "runs")]
            with mock.patch.object(runner, "ROOT", repository), mock.patch.object(sys, "argv", command), mock.patch.object(runner.shutil, "disk_usage",
                    return_value=SimpleNamespace(free=64 * 1024**3)), mock.patch.object(bounds, "MAX_ARTIFACT_BYTES", runner.MAX_BYTES):
                with self.assertRaises(OSError):
                    runner.main()
            receipt = json.loads(next((root / "runs").glob("run-*/result.json")).read_text())
            self.assertEqual(receipt["status"], "fail")
            self.assertEqual(receipt["stages"][-1]["exit"], 0)
            self.assertEqual(len(receipt["source_hashes"]), 8)
