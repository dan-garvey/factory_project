import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import run_opening as launcher


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

if __name__ == "__main__":
    unittest.main()
