"""CLI admission controls with a valid base; these never stand in for game tests."""
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
with mock.patch.object(sys, 'path', [str(ROOT / 'scripts'), *sys.path]):
    spec = importlib.util.spec_from_file_location('precision_runner', ROOT / 'scripts/run_precision.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)


class PrecisionRunnerTests(unittest.TestCase):
    def assert_refuses(self, extra, diagnostic):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / 'validly-pinned-unused-executable'
            binary.write_text('#!/bin/sh\nexit 0\n')
            binary.chmod(0o700)
            argv = ['run_precision.py', '--godot', str(binary), '--sha256', hashlib.sha256(binary.read_bytes()).hexdigest(),
                    '--artifacts', str(root / 'artifacts'), *extra]
            error = io.StringIO()
            with mock.patch.object(sys, 'argv', argv), mock.patch.object(runner.bounds, 'execute_bounded') as execute:
                with redirect_stderr(error), self.assertRaises(SystemExit) as stopped:
                    runner.main()
                self.assertEqual(stopped.exception.code, 2)
                self.assertIn(diagnostic, error.getvalue())
                execute.assert_not_called()

    def test_render_requires_check_before_any_engine_launch(self):
        self.assert_refuses(['--render'], '--render requires --check')

    def test_invalid_interactive_duration_refuses_before_engine(self):
        for duration in ('0', '901'):
            with self.subTest(duration=duration):
                self.assert_refuses(['--duration-seconds', duration], '--duration-seconds must be1..900')


if __name__ == '__main__':
    unittest.main()
