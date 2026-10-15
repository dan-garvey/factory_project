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
spec = importlib.util.spec_from_file_location('train_runner', ROOT / 'scripts/run_train_rider.py')
train = importlib.util.module_from_spec(spec)
spec.loader.exec_module(train)


class TrainEntryTests(unittest.TestCase):
    def test_train_entry_invalid_modes_fail_at_the_intended_guard(self):
        cases = [
            (['--render'], '--render requires --check'),
            (['--check', '--smoke'], '--smoke selects normal entry separately'),
            (['--check', '--duration-seconds', '100'], '--duration-seconds selects normal play only'),
            (['--smoke', '--duration-seconds', '100'], '--duration-seconds selects normal play only'),
            (['--duration-seconds', '0'], 'Use a bounded 1..1700 second normal session'),
            (['--duration-seconds', '1701'], 'Use a bounded 1..1700 second normal session'),
        ]
        for flags, diagnostic in cases:
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as folder:
                base = Path(folder)
                binary = base / 'engine'
                binary.write_bytes(b'valid source-only executable fixture; never run\n')
                binary.chmod(0o700)
                target = base / 'artifacts'
                stderr = io.StringIO()
                with mock.patch.object(sys, 'argv', ['train', '--godot', str(binary), '--sha256', hashlib.sha256(binary.read_bytes()).hexdigest(),
                        '--artifacts', str(target), *flags]), redirect_stderr(stderr), \
                        mock.patch.object(train.shared.bounds, 'execute_bounded', side_effect=AssertionError('Invalid mode reached engine')) as engine:
                    with self.assertRaises(SystemExit) as error:
                        train.main()
                    self.assertEqual(error.exception.code, 2)
                    self.assertIn(diagnostic, stderr.getvalue())
                    self.assertFalse(target.exists())
                    engine.assert_not_called()

    def test_train_entry_refuses_wrong_pin_before_artifacts(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            binary = base / 'engine'
            binary.write_bytes(b'never executed')
            binary.chmod(0o700)
            target = base / 'artifacts'
            with mock.patch.object(sys, 'argv', ['train', '--godot', str(binary), '--sha256', '0' * 64, '--artifacts', str(target), '--smoke']), \
                    redirect_stderr(io.StringIO()) as stderr, mock.patch.object(train.shared.bounds, 'execute_bounded') as engine:
                with self.assertRaises(SystemExit) as error:
                    train.main()
                self.assertEqual(error.exception.code, 2)
                self.assertIn('exact verified lowercase SHA256', stderr.getvalue())
                self.assertFalse(target.exists())
                engine.assert_not_called()
