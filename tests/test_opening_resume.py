import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from test_opening_startup import launcher, observed_start


class OpeningResumeTests(unittest.TestCase):
    def test_regular_bounded_input_is_read_without_modification(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.factory"
            original = b"explicit local input"
            source.write_bytes(original)
            self.assertEqual(launcher.capture_resume(source), original)
            with mock.patch.object(launcher, "RESUME_LIMIT", 4):
                with self.assertRaisesRegex(ValueError, "allowance"):
                    launcher.capture_resume(source)
            self.assertEqual(source.read_bytes(), original)

    def test_symlinks_special_files_and_private_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "original.factory"
            source.write_bytes(b"preserve")
            link = root / "link.factory"
            link.symlink_to(source)
            fifo = root / "pipe.factory"
            os.mkfifo(fifo)
            private = root / ".beads"
            private.mkdir()
            hidden = private / "source.factory"
            hidden.write_bytes(b"preserve")
            for path in (link, fifo, hidden, Path("relative.factory"), root, Path("/dev/null")):
                with self.subTest(path=path):
                    with self.assertRaises((ValueError, OSError)):
                        launcher.capture_resume(path)
            self.assertEqual(source.read_bytes(), b"preserve")

    def test_checkout_and_bare_administration_inputs_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            for bare in (False, True):
                repo = Path(directory) / ("bare-repo" if bare else "checkout")
                subprocess.run(["git", "init", *(('--bare',) if bare else ()), str(repo)],
                               check=True, capture_output=True)
                source = repo / "source.factory"
                source.write_bytes(b"preserve")
                with self.assertRaisesRegex(ValueError, "Git"):
                    launcher.capture_resume(source)
                self.assertEqual(source.read_bytes(), b"preserve")

    def test_incompatible_flag_combinations_fail_before_engine(self):
        for flags in (("--smoke", "--check"), ("--render",)):
            with self.subTest(flags=flags), mock.patch.object(sys, "argv", [
                    "run_opening.py", "--godot", sys.executable, "--artifacts", "/unused",
                    "--resume", "/unused.factory", *flags]), mock.patch.object(launcher.bounds, "execute_bounded") as engine:
                with self.assertRaises(SystemExit) as error:
                    launcher.main()
                self.assertEqual(error.exception.code, 2)
                engine.assert_not_called()

    def test_resumed_scene_report_cannot_be_fresh_or_falsely_owned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            slot = root / "worksite.factory"
            slot.write_bytes(b"observer separately verifies this through Store")
            expected = {"checkpoint": {"schema": 1, "saved_marker": "retained"},
                        "state": observed_start(slot)["state"]}
            report = {"schema": 1, "scene": launcher.SMOKE_SCENE, "script": "res://opening/opening.gd",
                      "loaded": expected["checkpoint"], "state": expected["state"],
                      "continued_from_source": True, "slot_matches_loaded": True,
                      "view": {"save_slot": str(slot), "save_ready": True, "save_owned": True,
                               "save_disabled": False, "load_disabled": False, "confirmed": False,
                               "confirm_disabled": True, "selected": "", "pending": "", "entity_ids": [],
                               "request_sequence": 0, "namespace_nonempty": True}}
            path = root / "report.json"
            path.write_text(json.dumps(report))
            self.assertEqual(launcher.read_resume_report(path, expected, slot), report)
            for change in (lambda d: d.update(schema=True), lambda d: d.update(loaded={}),
                           lambda d: d.update(continued_from_source=False), lambda d: d.update(slot_matches_loaded=False),
                           lambda d: d["view"].update(save_owned=False), lambda d: d["view"].update(selected="retired"),
                           lambda d: d["state"]["stock"].update(source=15),
                           lambda d: d["state"]["parts"].update(wheel=True)):
                invalid = json.loads(json.dumps(report))
                change(invalid)
                path.write_text(json.dumps(invalid))
                with self.assertRaises(ValueError):
                    launcher.read_resume_report(path, expected, slot)
            path.write_text(json.dumps(observed_start(slot)))
            with self.assertRaises(ValueError):
                launcher.read_resume_report(path, expected, slot)


if __name__ == "__main__":
    unittest.main()
