"""Cheap OS lifecycle controls and refusal oracles; these are not game backends."""
from contextlib import redirect_stderr
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
with mock.patch.object(sys, 'path', [str(ROOT / 'scripts'), *sys.path]):
    spec = importlib.util.spec_from_file_location('normal_shared_launcher', ROOT / 'scripts/run_shared_opening.py')
    launcher = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(launcher)


class SharedLauncherTests(unittest.TestCase):
    def test_invalid_mode_or_bounds_never_start_a_process(self):
        cases = ((['--clients', '3'], 'invalid choice: 3'),
                 (['--duration-seconds', '1101'], 'Duration must be1..1100 seconds and port0..65535'),
                 (['--duration-seconds', '0'], 'Duration must be1..1100 seconds and port0..65535'),
                 (['--legacy-fixture'], 'unrecognized arguments: --legacy-fixture'),
                 (['--observer', '/missing.gd'], '--observer requires --smoke'))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / 'not-an-engine'
            executable.write_bytes(b'#!/bin/sh\nexit 67\n')
            executable.chmod(0o700)
            common = ['--godot', str(executable), '--sha256', launcher.sha(executable),
                      '--artifacts', str(root / 'artifacts')]
            for extra, refusal in cases:
                error = io.StringIO()
                with self.subTest(extra=extra), redirect_stderr(error), mock.patch.object(launcher.subprocess, 'Popen') as child:
                    with self.assertRaises(SystemExit) as refused:
                        launcher.main([*common, *extra])
                    self.assertEqual(refused.exception.code, 2)
                    child.assert_not_called()
                    self.assertIn(refusal, error.getvalue())

    def test_regular_capture_refuses_symlinks_pipes_and_large_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source.gd'
            source.write_bytes(b'owned')
            self.assertEqual(launcher.regular_bytes(source, 5), b'owned')
            link = root / 'alias.gd'
            link.symlink_to(source)
            pipe = root / 'pipe.gd'
            os.mkfifo(pipe)
            for path, limit in ((link, 20), (pipe, 20), (source, 4)):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    launcher.regular_bytes(path, limit)

    def test_observation_refuses_shadow_authority_wrong_identity_and_quantities(self):
        value = {'schema': 1, 'status': 'pass', 'actor': 'P', 'pid': 123,
                 'scene': launcher.SCENE, 'script': 'res://opening/shared_opening.gd',
                 'session_path': '/root/OpeningShared/Session',
                 'view': {'ready': True, 'connecting': False, 'model_is_session': True,
                          'client_world_is_null': True, 'auto_advance': False, 'save_ready': False,
                          'save_owned': False, 'save_disabled': True, 'load_disabled': True,
                          'model_script': 'res://opening-session/session.gd', 'save_slot': '',
                          'namespace': 'owned-', 'session_namespace': 'owned-', 'sequence': 0, 'session_sequence': 0},
                 'projection': {'context': 'authority', 'initial_feed': 16, 'recipe_input': 1,
                      'options': {'opening': True, 'physical': True},
                      'actors': {role: {'ready': True, 'native_epoch': 1,
                                        'position': [0.0, 1.0, 0.0], 'capabilities': {'build_reach': 4.0}}
                                 for role in ('P', 'Q')},
                      'stock': {'source': 16, 'collector': 0, 'belt': 0,
                      'input': 0, 'held': 0, 'output': 0, 'player': 0}, 'inventories': {},
                      'parts': {'collector': 1, 'belt': 1, 'processor': 1, 'wheel': 1, 'shaft': 3},
                      'entities': {}, 'drive_links': []}}
        launcher.validate_observation(value, 'P', 123, 'authority')
        for kind in ('identity', 'pid', 'authority', 'clock', 'save', 'profile', 'quantity'):
            bad = copy.deepcopy(value)
            if kind == 'identity': bad['actor'] = 'Q'
            elif kind == 'pid': bad['pid'] = 124
            elif kind == 'authority': bad['view']['client_world_is_null'] = False
            elif kind == 'clock': bad['view']['auto_advance'] = True
            elif kind == 'save': bad['view']['save_owned'] = True
            elif kind == 'profile': bad['projection']['options']['physical'] = False
            else:
                bad['projection']['stock']['source'] = 15
                bad['projection']['stock']['collector'] = True
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                launcher.validate_observation(bad, 'P', 123, 'authority')

    def start_control(self, root, missing_client=False):
        # File rendezvous stand in ONLY for subprocess lifetime. No Model,
        # game projection, transport or gameplay acceptance is simulated.
        server = ("import json,os,time\nfrom pathlib import Path\n"
                  f"p=Path({str(root)!r})\n"
                  "(p/'server-ready.json').write_text(json.dumps({'pid':os.getpid(),'context':'lifecycle-control'}))\n"
                  "(p/'server-status.json').write_text(json.dumps({'roles':{'P':1,'Q':2}}))\n"
                  "while not (p/'server.stop').exists(): time.sleep(.005)\n"
                  "(p/'server-report.json').write_text(json.dumps({'status':'lifecycle-control-only'}))\n")
        actors = {'server': {'command': [sys.executable, '-c', server], 'project': str(root), 'environment': {}}}
        for role in ('P', 'Q'):
            script = ("import os,time\nfrom pathlib import Path\n"
                      f"p=Path({str(root)!r})\n(p/{(role+'.pid')!r}).write_text(str(os.getpid()))\n"
                      f"while not (p/{(role+'.close')!r}).exists(): time.sleep(.005)\n")
            actors[role] = {'command': ['/missing-owned-client'] if missing_client and role == 'P'
                           else [sys.executable, '-c', script], 'project': str(root), 'environment': {}}
        specification = {'run': str(root), 'roles': ['P', 'Q'], 'smoke': False,
                         'controller_pid': os.getpid(), 'duration_seconds': 30, 'actors': actors}
        path = root / 'spec.json'
        path.write_text(json.dumps(specification))
        log = (root / 'worker.log').open('wb')
        process = subprocess.Popen([sys.executable, '-B', str(ROOT / 'scripts/run_shared_opening.py'),
                                    '--cohort-worker', str(path)], stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        return process, log

    def ready_control(self, root, process):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            path = root / 'cohort-state.json'
            if path.exists() and json.loads(path.read_text())['phase'] == 'ready' and all(
                    (root / (role + '.pid')).exists() for role in ('P', 'Q')):
                return
            if process.poll() is not None:
                self.fail((root / 'worker.log').read_text())
            time.sleep(.005) # Bounded file rendezvous, not a timing-based verdict.
        self.fail('Owned lifecycle control never reached its actual ready boundary')

    def finish_control(self, process, log):
        try:
            process.wait(timeout=4)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=2)
            log.close()

    def assert_reaped(self, root):
        result = json.loads((root / 'cohort.json').read_text())
        for actor in result['actors'].values():
            self.assertTrue(actor['reaped'])
            self.assertEqual(actor['pgid_at_launch'], result['worker_pgid'])
            self.assertFalse(Path('/proc', str(actor['pid'])).exists())
        return result

    def test_one_owned_window_exit_stops_and_reaps_other_children(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            process, log = self.start_control(root)
            try:
                self.ready_control(root, process)
                (root / 'P.close').touch()
            finally:
                self.finish_control(process, log)
            result = self.assert_reaped(root)
            self.assertEqual(process.returncode, 0)
            self.assertEqual(result['reason'], 'window_closed')
            self.assertEqual(result['actors']['P']['exit'], 0)
            self.assertEqual(result['actors']['Q']['exit'], -signal.SIGTERM)
            self.assertEqual(result['peak_live_engines'], 3)

    def test_real_sigint_preserves_owned_cleanup_and_interrupted_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            process, log = self.start_control(root)
            try:
                self.ready_control(root, process)
                process.send_signal(signal.SIGINT)
            finally:
                self.finish_control(process, log)
            result = self.assert_reaped(root)
            self.assertEqual(result['status'], 'interrupted')
            self.assertEqual(result['reason'], 'worker_signal')
            self.assertEqual(result['actors']['server']['exit'], 0)

    def test_partial_startup_failure_preserves_failure_and_reaps_server(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            process, log = self.start_control(root, missing_client=True)
            self.finish_control(process, log)
            result = self.assert_reaped(root)
            self.assertEqual(process.returncode, 1)
            self.assertEqual(result['status'], 'fail')
            self.assertIn('missing-owned-client', result['error'])
            self.assertEqual(set(result['actors']), {'server'})
            self.assertEqual(result['actors']['server']['exit'], 0)


if __name__ == '__main__':
    unittest.main()
