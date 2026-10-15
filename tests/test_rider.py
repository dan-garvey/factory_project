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
spec = importlib.util.spec_from_file_location('rider_runner', ROOT / 'scripts/run_rider.py')
rider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rider)


class RiderEntryTests(unittest.TestCase):
    def test_invalid_modes_refuse_for_the_intended_reason_before_artifacts_or_engine(self):
        cases = [
            (['--render'], '--render requires --check'),
            (['--check', '--smoke'], '--smoke selects normal entry separately'),
            (['--render', '--smoke'], '--render requires --check'),
            (['--check', '--duration-seconds', '100'], '--duration-seconds selects normal play only'),
            (['--smoke', '--duration-seconds', '100'], '--duration-seconds selects normal play only'),
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
                with mock.patch.object(sys, 'argv', ['rider', '--godot', str(binary),
                        '--sha256', hashlib.sha256(binary.read_bytes()).hexdigest(), '--artifacts', str(target), *flags]), \
                        redirect_stderr(stderr), mock.patch.object(rider.bounds, 'execute_bounded',
                            side_effect=AssertionError('Invalid arguments reached engine execution')) as engine:
                    with self.assertRaises(SystemExit) as error:
                        rider.main()
                    self.assertEqual(error.exception.code, 2)
                    self.assertIn(diagnostic, stderr.getvalue())
                    self.assertFalse(target.exists())
                    engine.assert_not_called()

    def test_missing_runtime_and_wrong_pin_leave_no_owned_artifacts(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            binary = base / 'engine'
            binary.write_bytes(b'unexecuted source-only fixture')
            binary.chmod(0o700)
            for path, digest in [(base / 'missing', hashlib.sha256(binary.read_bytes()).hexdigest()), (binary, '0' * 64)]:
                target = base / 'artifacts'
                stderr = io.StringIO()
                with self.subTest(path=path), redirect_stderr(stderr), mock.patch.object(sys, 'argv', [
                        'rider', '--godot', str(path), '--sha256', digest, '--artifacts', str(target), '--smoke']), \
                        mock.patch.object(rider.bounds, 'execute_bounded') as engine:
                    with self.assertRaises(SystemExit) as error:
                        rider.main()
                    self.assertEqual(error.exception.code, 2)
                    self.assertIn('exact verified lowercase SHA256', stderr.getvalue())
                    self.assertFalse(target.exists())
                    engine.assert_not_called()
