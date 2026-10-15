from contextlib import redirect_stderr
import hashlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('workshop_runner', ROOT / 'scripts/run_workshop.py')
workshop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workshop)


class WorkshopEntryTests(unittest.TestCase):
    def test_conflicting_or_ignored_modes_never_launch_an_engine(self):
        cases = [
            (['--render'], '--render requires --check'),
            (['--check', '--smoke'], '--smoke selects normal entry and cannot combine with --check'),
            (['--render', '--smoke'], '--render requires --check'),
            (['--duration-seconds', '0'], 'Use a bounded 1..1700 second normal session'),
            (['--duration-seconds', '1701'], 'Use a bounded 1..1700 second normal session'),
        ]
        for flags, diagnostic in cases:
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as folder:
                base = Path(folder)
                binary = base / 'engine'
                binary.write_bytes(b'source-only executable fixture; never run\n')
                binary.chmod(0o700)
                target = base / 'artifacts'
                stderr = io.StringIO()
                with mock.patch.object(sys, 'argv', ['workshop', '--godot', str(binary),
                        '--sha256', hashlib.sha256(binary.read_bytes()).hexdigest(),
                        '--artifacts', str(target), *flags]), redirect_stderr(stderr), \
                        mock.patch.object(workshop.bounds, 'execute_bounded',
                            side_effect=AssertionError('Invalid modes reached engine execution')) as engine:
                    with self.assertRaises(SystemExit) as error:
                        workshop.main()
                    self.assertEqual(error.exception.code, 2)
                    self.assertIn(diagnostic, stderr.getvalue())
                    self.assertFalse(target.exists())
                    engine.assert_not_called()

    def test_wrong_pin_and_missing_runtime_fail_before_owned_artifacts(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            binary = base / 'engine'
            binary.write_bytes(b'not a verified engine')
            binary.chmod(0o700)
            for path, digest in [(binary, '0' * 64), (base / 'missing', hashlib.sha256(binary.read_bytes()).hexdigest())]:
                target = base / 'artifacts'
                with self.subTest(path=path), mock.patch.object(sys, 'argv', ['workshop', '--godot', str(path),
                        '--sha256', digest, '--artifacts', str(target), '--smoke']), \
                        mock.patch.object(workshop.bounds, 'execute_bounded') as engine:
                    with self.assertRaises(SystemExit):
                        workshop.main()
                    self.assertFalse(target.exists())
                    engine.assert_not_called()
