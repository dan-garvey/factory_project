#!/usr/bin/env python3
"""Launch bounded normal loopback play; invoke through run_local.py heavy."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time

import check_engine_environment as bounds
from check_opening_session import ActorGroup, ledger, publish, read_json, sha
from run_opening import capture_resume

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'experiments/engine-environment/godot'
SCENE = 'res://opening/shared_opening.tscn'
OBSERVER = 'opening-session/launch_observer.gd'
FILES = bounds.FILES + (
    'opening/opening.gd', 'opening/example_presenter.gd', 'opening/example_world.gd',
    'opening/shared_opening.gd', 'opening/shared_opening.tscn',
    'opening-session/session.gd', 'opening-session/server.gd', 'save-tests/checkpoint_file.gd')
MAX_BYTES = 256 * 1024**2


class StopRequested(Exception):
    pass


class LaunchGroup(ActorGroup):
    """The accepted lifecycle/log owner, with one smoke completion marker."""
    def _line(self, role, line):
        super()._line(role, line)
        if line.startswith(b'SHARED_OPENING_OBSERVER_FAIL '):
            raise ValueError('Normal-entry observer failed: ' + role)
        if line.startswith(b'SHARED_OPENING_OBSERVED '):
            marker = json.loads(line.removeprefix(b'SHARED_OPENING_OBSERVED '))
            actor = self.actors[role]
            if (role not in ('P', 'Q') or actor.get('observed') is not None
                    or not isinstance(marker, dict) or marker.get('actor') != role
                    or type(marker.get('pid')) is not int or marker['pid'] != actor['process'].pid):
                raise ValueError('Mismatched or duplicate normal-entry completion marker')
            actor['observed'] = marker


def regular_bytes(path, limit):
    if not path.is_absolute() or path.resolve() != path:
        raise ValueError('Use an absolute regular file without symlinks: ' + str(path))
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise ValueError('Input is not a regular file')
        data = source.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Input exceeds its bounded allowance')
    return data


def validate_observation(value, role, pid, context):
    if (type(value.get('schema')) is not int or value['schema'] != 1 or value.get('status') != 'pass'
            or value.get('actor') != role or type(value.get('pid')) is not int or value['pid'] != pid
            or value.get('scene') != SCENE or value.get('script') != 'res://opening/shared_opening.gd'
            or value.get('session_path') != '/root/OpeningShared/Session'):
        raise ValueError('Observer did not see the launched normal scene/process/identity')
    view = value.get('view', {})
    for key, expected in {'ready': True, 'connecting': False, 'model_is_session': True,
                          'client_world_is_null': True, 'auto_advance': False, 'save_ready': False,
                          'save_owned': False, 'save_disabled': True, 'load_disabled': True}.items():
        if view.get(key) is not expected:
            raise ValueError('Actual normal view violates ' + key)
    if (view.get('model_script') != 'res://opening-session/session.gd' or view.get('save_slot') != ''
            or not isinstance(view.get('namespace'), str) or not view['namespace']
            or view['namespace'] != view.get('session_namespace')
            or type(view.get('sequence')) is not int or view['sequence'] < 0
            or type(view.get('session_sequence')) is not int or view['sequence'] != view['session_sequence']):
        raise ValueError('Normal view metadata/save ownership differs from its session')
    snapshot = value.get('projection', {})
    if snapshot.get('context') != context:
        raise ValueError('Observed normal client belongs to a different server')
    if (type(snapshot.get('initial_feed')) is not int or snapshot['initial_feed'] != 16
            or type(snapshot.get('recipe_input')) is not int or snapshot['recipe_input'] != 1
            or snapshot.get('options', {}).get('opening') is not True
            or not set(snapshot.get('inventories', {})).issubset(('P', 'Q'))):
        raise ValueError('Observer did not return the actual opening fixture')
    ledger(snapshot)
    return value


def cohort_worker(spec):
    run = Path(spec['run'])
    group = LaunchGroup(run)
    roles = tuple(spec['roles'])
    stop = run / 'launcher.stop'
    result = {'status': 'running', 'mode': 'smoke' if spec['smoke'] else 'interactive',
              'worker_pid': os.getpid(), 'worker_pgid': os.getpgrp(), 'observations': {}}
    started = time.monotonic()
    exit_code = 0

    def state(phase):
        publish(run / 'cohort-state.json', {'schema': 1, 'phase': phase,
                'controller_pid': spec['controller_pid'], 'worker_pid': os.getpid(),
                'worker_pgid': os.getpgrp(), 'actors': group.evidence(),
                'server': read_json(run / 'server-status.json') if (run / 'server-status.json').exists() else {}})

    def wait(predicate, timeout=25):
        def boundary():
            if stop.exists():
                raise StopRequested(read_json(stop).get('reason', 'stop_requested'))
            return predicate()
        group.wait(boundary, timeout=timeout)

    def stop_server():
        actor = group.actors.get('server')
        if actor and actor['process'].poll() is None and (run / 'server-ready.json').exists():
            actor['expected_exit'] = True
            (run / 'server.stop').touch()
            group.wait(lambda: actor['process'].poll() is not None, timeout=3)

    def signalled(number, _frame):
        publish(stop, {'reason': 'worker_signal', 'signal': number})

    old = {number: signal.signal(number, signalled) for number in (signal.SIGINT, signal.SIGTERM)}
    try:
        if os.getpgrp() != os.getpid():
            raise ValueError('Worker must be the bounded helper-owned process-group leader')
        state('starting')
        for role in ('server', *roles):
            if stop.exists():
                raise StopRequested(read_json(stop).get('reason', 'stop_requested'))
            actor = spec['actors'][role]
            process = group.launch(role, actor['command'], actor['project'], dict(os.environ, **actor['environment']))
            if os.getpgid(process.pid) != os.getpgrp():
                raise ValueError('Normal actor escaped its owned group')
            # A normal zero-exit window close is a lifecycle event below.
            group.actors[role]['expected_exit'] = role != 'server'
            state('starting')
            if role == 'server':
                wait(lambda: (run / 'server-ready.json').exists())
                if read_json(run / 'server-ready.json')['pid'] != process.pid:
                    raise ValueError('Server readiness belongs to a different process')
        def admitted():
            if not spec['smoke'] and any(group.actors[role]['process'].poll() == 0 for role in roles):
                raise StopRequested('window_closed_during_startup')
            return set(read_json(run / 'server-status.json')['roles']) == set(roles)
        wait(admitted)
        ready = read_json(run / 'server-ready.json')
        result['ready'] = ready
        state('ready')
        print('SHARED_OPENING_READY ' + json.dumps({'roles': roles, 'worker_pid': os.getpid()}), flush=True)
        if spec['smoke']:
            wait(lambda: all(group.actors[role].get('observed') is not None for role in roles))
            for role in roles:
                # Marker follows closed/atomic publication. Never retry JSON.
                value = read_json(run / role / 'observation.json')
                result['observations'][role] = validate_observation(value, role,
                    group.actors[role]['process'].pid, ready['context'])
            (run / 'observers.finish').touch()
            wait(lambda: all(group.actors[role]['process'].poll() is not None for role in roles))
            result.update(status='pass', reason='observed_normal_entry')
        else:
            deadline = time.monotonic() + spec['duration_seconds']
            while True:
                group.pump()
                if stop.exists():
                    raise StopRequested(read_json(stop).get('reason', 'stop_requested'))
                closed = [role for role in roles if group.actors[role]['process'].poll() == 0]
                if closed:
                    result.update(status='completed', reason='window_closed', closed_roles=closed)
                    break
                if time.monotonic() >= deadline:
                    result.update(status='completed', reason='duration_limit')
                    break
    except StopRequested as error:
        result.update(status='interrupted' if str(error) in ('interrupt', 'worker_signal') else 'completed', reason=str(error))
    except BaseException as error:
        exit_code = 1
        result.update(status='fail', error=str(error))
    finally:
        try:
            state('stopping')
            stop_server()
        except BaseException as error:
            exit_code = 1
            result.update(status='fail', cleanup_error=str(error))
        try:
            group.close()
        except BaseException as error:
            exit_code = 1
            result.update(status='fail', cleanup_error=str(error))
        finally:
            for number, handler in old.items():
                signal.signal(number, handler)
            result.update(actors=group.evidence(), peak_live_engines=group.peak_live,
                          elapsed_seconds=time.monotonic() - started)
            publish(run / 'cohort.json', result)
            state('finished')
    return exit_code


@contextmanager
def interrupt_control(run, phase):
    """Keep the bounded helper alive while its worker performs owned cleanup."""
    requested = []
    def handler(number, _frame):
        requested.append(number)
        if phase[0] != 'cohort':
            raise KeyboardInterrupt
        publish(run / 'launcher.stop', {'reason': 'interrupt', 'signal': number})
    old = {number: signal.signal(number, handler) for number in (signal.SIGINT, signal.SIGTERM)}
    try:
        yield requested
    finally:
        for number, previous in old.items():
            signal.signal(number, previous)


def instrument(project, observer):
    config = project / 'project.godot'
    original = config.read_bytes()
    if b'[autoload]' in original:
        raise ValueError('Smoke needs explicit support for an existing autoload section')
    target = project / OBSERVER
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(observer)
    config.write_bytes(original + b'\n[autoload]\nSharedLaunchObserver="*res://opening-session/launch_observer.gd"\n')
    return {'kind': 'copied_client_autoload', 'post_import_config_sha256': hashlib.sha256(original).hexdigest(),
            'runtime_config_sha256': sha(config), 'observer_sha256': sha(target)}


def verify_host_checkpoint(server, slot, resumed=None):
    """Verify the publisher boundary; Core/Store alone own the binary schema."""
    persisted = server.get('persistence', {})
    if (persisted.get('accepted') is not True or persisted.get('save', {}).get('accepted') is not True
            or persisted.get('save_file') != str(slot) or persisted.get('input_preserved') is not True):
        raise ValueError('Host did not publish the requested checkpoint: ' + str(persisted.get('save', {})))
    if (not slot.is_file() or Path(str(slot) + '.pending').exists()
            or slot.stat().st_size > 1024**2 or sha(slot) != persisted.get('saved_sha256')):
        raise ValueError('Host checkpoint is absent, pending, oversized or differs from the published hash')
    if resumed:
        if (persisted.get('resume', {}).get('accepted') is not True
                or persisted.get('input_sha256') != resumed['source_sha256']
                or persisted.get('resume_input') != resumed['incoming']
                or sha(Path(resumed['incoming'])) != resumed['source_sha256']):
            raise ValueError('Host did not preserve the actual captured resume input')
    return {'file': str(slot), 'sha256': sha(slot)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--clients', type=int, choices=(1, 2), default=2)
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--duration-seconds', type=int, default=900, help='1..1100 seconds after admission; default15min')
    parser.add_argument('--smoke', action='store_true', help='observe normal entry using a disclosed copied-only autoload, then exit')
    parser.add_argument('--observer', type=Path, help='smoke-only captured independent observer, never a replacement scene')
    parser.add_argument('--save-on-close', action='store_true', help='save the host on orderly session end into this fresh run')
    parser.add_argument('--resume', type=Path, help='reopen a compatible checkpoint; preserve input and save to a fresh output on close')
    args = parser.parse_args(argv)
    if args.observer and not args.smoke:
        parser.error('--observer requires --smoke')
    if not 1 <= args.duration_seconds <= 1100 or not 0 <= args.port <= 65535:
        parser.error('Duration must be1..1100 seconds and port0..65535')
    if (not re.fullmatch('[0-9a-f]{64}', args.sha256) or not args.godot.is_absolute()
            or args.godot.resolve() != args.godot or not args.godot.is_file()
            or not os.access(args.godot, os.X_OK) or sha(args.godot) != args.sha256):
        parser.error('Use the explicit existing executable and verified lowercase SHA256')
    artifacts = args.artifacts
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error('Use an owned external absolute artifact root without symlinks')
    artifacts.mkdir(parents=True, exist_ok=True, mode=0o700)
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    inside = subprocess.run(['git', '-C', str(artifacts), 'rev-parse', '--is-inside-work-tree', '--is-inside-git-dir'],
                            env=env, text=True, capture_output=True, timeout=5)
    if inside.returncode == 0 and 'true' in inside.stdout.splitlines():
        parser.error('Keep artifacts outside Git worktrees and administration')
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error('Require22GiB free and less than256MiB retained evidence')
    run = Path(tempfile.mkdtemp(prefix='shared-', dir=artifacts))
    save_slot = run / 'worksite.factory' if args.save_on_close or args.resume is not None else None
    roles = ('P',) if args.clients == 1 else ('P', 'Q')
    receipt = {'schema': 1, 'status': 'running', 'mode': 'smoke' if args.smoke else 'interactive',
               'revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
               'started': datetime.now(timezone.utc).isoformat(), 'source_hashes': {}, 'stages': [],
               'runner_hashes': {name: sha(ROOT / 'scripts' / name) for name in
                   ('run_shared_opening.py', 'check_opening_session.py', 'check_engine_environment.py', 'run_opening.py')},
               'binary': str(args.godot), 'binary_sha256': args.sha256, 'roles': roles, 'user_play': 'not_assessed'}
    publish(run / 'controller.json', {'schema': 1, 'controller_pid': os.getpid(), 'run': str(run),
                                    'revision': receipt['revision'], 'mode': receipt['mode']})
    print('Shared opening session: ' + str(run), flush=True)
    print('Closing either window ends this session. Ctrl-C stops all owned processes. Client Save/Load is unavailable.', flush=True)
    if save_slot is not None:
        receipt['save_slot'] = str(save_slot)
        print('The host will save on orderly close to: ' + str(save_slot), flush=True)
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    deadline = time.monotonic() + 1800
    phase = ['preparing']
    interruptions = []
    code = 0
    try:
        with interrupt_control(run, phase) as interruptions:
            if args.resume is not None:
                incoming = run / 'incoming.factory'
                incoming.write_bytes(capture_resume(args.resume))
                incoming.chmod(0o400)
                receipt['resume'] = {'source': str(args.resume), 'incoming': str(incoming),
                                     'source_sha256': sha(incoming), 'bytes': incoming.stat().st_size}
            runners = run / 'runners'
            runners.mkdir()
            for name, digest in receipt['runner_hashes'].items():
                data = (ROOT / 'scripts' / name).read_bytes()
                target = runners / name
                target.write_bytes(data)
                if sha(target) != digest:
                    raise ValueError('Runner changed during capture: ' + name)
            def execute(name, command, cwd, environment, timeout):
                result = bounds.execute_bounded(command, cwd=cwd, env=environment, log=run / (name + '.log'),
                                                artifacts=artifacts, timeout=min(timeout, deadline - time.monotonic()))
                receipt['stages'].append({'name': name, 'exit': result.returncode})
                if result.returncode or 'ERROR:' in (run / (name + '.log')).read_text(errors='replace'):
                    raise ValueError('Stage failed: ' + name)
            execute('version', [str(args.godot), '--version'], ROOT, os.environ.copy(), 15)
            if (run / 'version.log').read_text().strip() != '4.7.2.stable.official.ed1daf0bf':
                raise ValueError('Require the separately verified supported Godot version')
            port = args.port
            if port == 0:
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as candidate:
                    candidate.bind(('127.0.0.1', 0))
                    port = candidate.getsockname()[1]
            receipt['port'] = port
            originals = {name: regular_bytes(PROJECT / name, 2 * 1024**2) for name in FILES}
            if sum(map(len, originals.values())) > 2 * 1024**2:
                raise ValueError('Source copy exceeds2MiB')
            receipt['source_hashes'] = {name: hashlib.sha256(data).hexdigest() for name, data in originals.items()}
            observer = None
            if args.smoke:
                source = args.observer or PROJECT / OBSERVER
                observer = regular_bytes(source, 128 * 1024)
                captured = run / 'captured-observer.gd'
                captured.write_bytes(observer)
                receipt['observer'] = {'source': str(source), 'captured': str(captured), 'sha256': sha(captured),
                                       'default': args.observer is None}
            spec = {'run': str(run), 'roles': roles, 'smoke': args.smoke, 'actors': {},
                    'duration_seconds': args.duration_seconds, 'controller_pid': os.getpid()}
            for role in ('server', *roles):
                directory = run / role
                project = directory / 'project'
                for name, data in originals.items():
                    target = project / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
                environment = {}
                for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'),
                                  ('XDG_CACHE_HOME', 'cache'), ('TMPDIR', 'tmp')]:
                    path = directory / name
                    path.mkdir()
                    environment[key] = str(path)
                execute('import-' + role, [str(args.godot), '--headless', '--editor', '--path', str(project), '--import'],
                        project, dict(os.environ, **environment), 120)
                instrumentation = instrument(project, observer) if observer is not None and role != 'server' else None
                command = [str(args.godot), '--path', str(project)]
                if role == 'server':
                    command += ['--headless', '--script', 'res://opening-session/server.gd', '--',
                                '--session-port=' + str(port), '--ready-file=' + str(run / 'server-ready.json'),
                                '--status-file=' + str(run / 'server-status.json'), '--stop-file=' + str(run / 'server.stop'),
                                '--report-file=' + str(run / 'server-report.json')]
                    if save_slot is not None:
                        command += ['--save-file=' + str(save_slot)]
                    if args.resume is not None:
                        command += ['--resume-input=' + receipt['resume']['incoming']]
                else:
                    command += [SCENE, '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--',
                                '--session-port=' + str(port), '--session-role=' + role]
                    if args.smoke:
                        command += ['--launch-report=' + str(directory / 'observation.json'),
                                    '--launch-finish-file=' + str(run / 'observers.finish')]
                spec['actors'][role] = {'project': str(project), 'environment': environment, 'command': command,
                                       'instrumentation': instrumentation}
            spec_path = run / 'cohort-spec.json'
            publish(spec_path, spec)
            receipt['actors'] = spec['actors']
            phase[0] = 'cohort'
            execute('cohort', [sys.executable, '-B', str(runners / 'run_shared_opening.py'), '--cohort-worker', str(spec_path)],
                    ROOT, os.environ.copy(), deadline - time.monotonic())
            receipt['cohort'] = read_json(run / 'cohort.json')
            if receipt['cohort']['status'] not in ('pass', 'completed', 'interrupted'):
                raise ValueError('Owned cohort did not finish successfully')
            server_path = run / 'server-report.json'
            server = read_json(server_path) if server_path.exists() else None
            if server is None:
                if receipt['cohort']['status'] != 'interrupted':
                    raise ValueError('Missing actual server lifecycle report')
                receipt['authority_observation'] = 'interrupted_before_readiness'
            else:
                if server.get('status') != 'pass' or server.get('clock_frozen') is not False:
                    raise ValueError('Server did not finish its actual ordinary live session')
                ledger(server['snapshot'])
                if save_slot is not None:
                    receipt['saved_checkpoint'] = verify_host_checkpoint(server, save_slot, receipt.get('resume'))
            if server is not None and receipt['cohort']['status'] == 'pass' and args.smoke and receipt['observer']['default']:
                snapshot = server['snapshot']
                if server['tick_count'] < 2:
                    raise ValueError('Read-only observer did not witness the current host clock')
                if args.resume is None:
                    if snapshot['order'] != 0 or snapshot['entities'] or snapshot['stock']['source'] != 16 or server['checkpoint']['requests']:
                        raise ValueError('Read-only startup observer changed the real fresh worksite')
                else:
                    loaded = receipt['cohort']['ready']['persistence']['loaded_checkpoint']
                    current = server['checkpoint']
                    if (current['order'] != loaded['order'] or current['revision'] != loaded['revision'] + server['tick_count']
                            or any(current[key] != loaded[key] for key in
                                   ('context', 'entities', 'links', 'parts', 'inventories', 'requests',
                                    'options', 'drive_links', 'power_enabled', 'next_ids'))):
                        raise ValueError('Read-only resumed observer changed retained identities/requests/ownership')
                for role in roles:
                    observed = receipt['cohort']['observations'][role]
                    if (type(observed.get('connected_revision')) is not int
                            or observed['projection']['revision'] < observed['connected_revision'] + 2):
                        raise ValueError('Stored revision was substituted for new host clock observations')
                    view = observed['view']
                    inventory = observed['projection']['inventories'].get(role, 0)
                    if (view.get('sequence') != 0 or view.get('selected') != '' or view.get('pending_link') != ''
                            or view.get('confirmed') is not False or view.get('confirm_disabled') is not (inventory < 4)
                            or view.get('goal', '').splitlines()[-1:] != [f'{inventory} / 4 collected']):
                        raise ValueError('Restored actor goal, selection or fresh caller identity differs')
                    if not (run / role / 'observation.json.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
                        raise ValueError('Missing actual normal-window capture')
            if any(not x['reaped'] or x['pgid_at_launch'] != receipt['cohort']['worker_pgid']
                   for x in receipt['cohort']['actors'].values()):
                raise ValueError('An owned engine was not reaped in its captured group')
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as released:
                released.bind(('127.0.0.1', port))
            receipt['listener_released'] = True
            for role, actor in spec['actors'].items():
                for name, digest in receipt['source_hashes'].items():
                    expected = actor['instrumentation']['runtime_config_sha256'] if name == 'project.godot' and actor['instrumentation'] else digest
                    if sha(Path(actor['project']) / name) != expected:
                        raise ValueError('Copied runtime source changed: ' + role + '/' + name)
                if actor['instrumentation'] and sha(Path(actor['project']) / OBSERVER) != receipt['observer']['sha256']:
                    raise ValueError('Runtime observer changed')
            for name, digest in receipt['runner_hashes'].items():
                if sha(runners / name) != digest:
                    raise ValueError('Captured runner changed')
            if args.smoke and sha(Path(receipt['observer']['captured'])) != receipt['observer']['sha256']:
                raise ValueError('Captured observer changed')
            if sha(args.godot) != args.sha256:
                raise ValueError('Pinned executable changed during play')
            receipt['status'] = receipt['cohort']['status']
            if interruptions:
                code = 128 + interruptions[0]
                receipt['status'] = 'interrupted'
    except KeyboardInterrupt:
        code = 128 + (interruptions[0] if interruptions else signal.SIGINT)
        receipt['status'] = 'interrupted'
    except BaseException as error:
        code = 1
        receipt.update(status='fail', error=str(error))
        print('Shared opening failed: ' + str(error), file=sys.stderr)
    finally:
        if 'resume' in receipt:
            try:
                preserved = hashlib.sha256(capture_resume(args.resume)).hexdigest() == receipt['resume']['source_sha256']
            except (OSError, ValueError, subprocess.SubprocessError):
                preserved = False
            receipt['resume']['original_unchanged'] = preserved
            if not preserved:
                code = 1
                receipt.update(status='fail', error='Original resume input changed during this run')
        if (run / 'cohort.json').exists() and 'cohort' not in receipt:
            receipt['cohort'] = read_json(run / 'cohort.json')
        receipt.update(finished=datetime.now(timezone.utc).isoformat(), owned_bytes=bounds.owned_bytes(artifacts))
        publish(run / 'result.json', receipt)
    print('Shared session ' + receipt['status'] + '; evidence=' + str(run), flush=True)
    return code


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--cohort-worker':
        sys.exit(cohort_worker(read_json(Path(sys.argv[2]))))
    sys.exit(main())
