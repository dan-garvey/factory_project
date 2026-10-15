"""Real cheap child lifecycle controls; no engine or network service is started."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
with mock.patch.object(sys, 'path', [str(ROOT / 'scripts'), *sys.path]):
    spec = importlib.util.spec_from_file_location('opening_session_check', ROOT / 'scripts/check_opening_session.py')
    session = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(session)


class OpeningSessionTests(unittest.TestCase):
    def test_ui_waits_for_closed_response_marker_before_single_parse(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            command = {'id': 1, 'action': 'observe'}
            final = {'id': 1, 'status': 'pass', 'input': command, 'facts': {'complete': True}}
            script = ("from pathlib import Path\nimport time\n"
                      f"p=Path({str(path / 'response-1.json')!r})\n"
                      "p.write_text('{')\ntime.sleep(.05)\n"
                      f"p.write_text({json.dumps(final)!r})\n"
                      "print('OPENING_UI_RESPONSE {\"id\":1,\"status\":\"pass\"}',flush=True)\ntime.sleep(10)\n")
            group = session.ActorGroup(path)
            try:
                group.launch('P', [sys.executable, '-c', script], directory, os.environ.copy())
                group.expect_ui('P', command)
                with mock.patch.object(session, 'read_json', wraps=session.read_json) as read:
                    result = group.ui_response('P', path)
                    self.assertEqual(read.call_count, 1)
                self.assertTrue(result['facts']['complete'])
            finally:
                group.close()

    def test_ui_malformed_completed_response_is_not_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            script = ("from pathlib import Path\nimport time\n"
                      f"Path({str(path / 'response-1.json')!r}).write_text('{{')\n"
                      "print('OPENING_UI_RESPONSE {\"id\":1,\"status\":\"pass\"}',flush=True)\ntime.sleep(10)\n")
            group = session.ActorGroup(path)
            try:
                group.launch('P', [sys.executable, '-c', script], directory, os.environ.copy())
                group.expect_ui('P', {'id': 1, 'action': 'observe'})
                with mock.patch.object(session, 'read_json', wraps=session.read_json) as read, self.assertRaises(json.JSONDecodeError):
                    group.ui_response('P', path)
                self.assertEqual(read.call_count, 1)
            finally:
                group.close()

    def test_three_child_limit_and_all_children_reaped(self):
        with tempfile.TemporaryDirectory() as directory:
            group = session.ActorGroup(Path(directory))
            try:
                for role in ('server', 'P', 'Q'):
                    group.launch(role, [sys.executable, '-c', 'import time;time.sleep(10)'], directory, os.environ.copy())
                self.assertEqual(group.peak_live, 3)
                self.assertTrue(all(actor['pgid_at_launch'] == os.getpgrp() for actor in group.actors.values()))
                with self.assertRaisesRegex(ValueError, 'three live engines'):
                    group.launch('fourth', [sys.executable, '-c', 'pass'], directory, os.environ.copy())
                self.assertEqual(len(group.actors), 3)
            finally:
                group.close()
            self.assertTrue(all(actor['process'].returncode is not None for actor in group.actors.values()))
            self.assertTrue(all(actor['process'].stdout.closed for actor in group.actors.values()))

    def test_zero_exit_cannot_hide_error_output(self):
        with tempfile.TemporaryDirectory() as directory:
            group = session.ActorGroup(Path(directory))
            try:
                process = group.launch('server', [sys.executable, '-c', "print('SCRIPT ERROR: concrete zero-exit witness',flush=True)"], directory, os.environ.copy())
                group.actors['server']['expected_exit'] = True
                with self.assertRaisesRegex(ValueError, 'Engine error'):
                    group.wait(lambda: process.poll() is not None, timeout=3)
            finally:
                group.close()
            self.assertIn('concrete zero-exit witness', (Path(directory) / 'server.log').read_text())

    def test_partial_line_flood_is_capped_and_child_stopped(self):
        with tempfile.TemporaryDirectory() as directory:
            group = session.ActorGroup(Path(directory), log_limit=32)
            try:
                process = group.launch('server', [sys.executable, '-c', "import os,time;os.write(1,b'x'*4096);time.sleep(10)"], directory, os.environ.copy())
                with self.assertRaisesRegex(ValueError, 'log allowance'):
                    group.wait(lambda: False, timeout=3)
            finally:
                group.close()
            self.assertEqual((Path(directory) / 'server.log').stat().st_size, 32)
            self.assertIsNotNone(process.returncode)

    def test_independent_ledger_rejects_negative_or_boolean_ownership(self):
        state = {'stock': {'source': 16, 'collector': 0, 'belt': 0, 'input': 0, 'held': 0, 'output': 0, 'player': 0},
                 'inventories': {}, 'parts': {'collector': 1, 'belt': 1, 'processor': 1, 'wheel': 1, 'shaft': 3},
                 'entities': {}, 'drive_links': []}
        session.ledger(state)
        for kind in ('stock', 'inventory', 'parts', 'shaft'):
            bad = copy.deepcopy(state)
            if kind == 'stock': bad['stock']['collector'] = False
            elif kind == 'inventory':
                bad['stock'].update(source=15, player=1)
                bad['inventories']['P'] = True
            elif kind == 'parts':
                bad['parts']['collector'] = -1
                bad['entities'] = {'a': {'kind': 'collector'}, 'b': {'kind': 'collector'}}
            else:
                bad['parts']['shaft'] = -1
                bad['drive_links'] = [[str(i), str(i + 1)] for i in range(4)]
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                session.ledger(bad)


if __name__ == '__main__':
    unittest.main()
