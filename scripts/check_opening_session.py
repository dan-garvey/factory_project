#!/usr/bin/env python3
"""Bounded loopback proof. One outer heavy permit; at most three live engines."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import selectors
import shutil
import socket
import subprocess
import sys
import tempfile
import time

import check_engine_environment as bounds

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'experiments/engine-environment/godot'
FILES = bounds.FILES + ('opening-session/session.gd', 'opening-session/server.gd')
UI_FILES = ('opening/shared_opening.gd', 'opening/shared_opening.tscn', 'opening/shared_check.gd', 'opening/character_presenter.gd')
MAX_BYTES = 256 * 1024**2
MAX_LOG_BYTES = 8 * 1024**2


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    if path.stat().st_size > 8 * 1024**2:
        raise ValueError('Diagnostic exceeds its allowance: ' + str(path))
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError('Expected a structured object: ' + str(path))
    return value


def publish(path, value):
    temporary = path.with_suffix('.writing')
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


class ActorGroup:
    """Children inherit the one group owned by execute_bounded's worker leader."""
    def __init__(self, directory, log_limit=MAX_LOG_BYTES):
        self.directory = directory
        self.log_limit = log_limit
        self.selector = selectors.DefaultSelector()
        self.actors = {}
        self.peak_live = 0

    def launch(self, role, command, cwd, environment):
        if role in self.actors or sum(x['process'].poll() is None for x in self.actors.values()) >= 3:
            raise ValueError('Refuse a duplicate role or more than three live engines')
        log_path = self.directory / (role + '.log')
        log = log_path.open('xb')
        try:
            process = subprocess.Popen(command, cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        except BaseException:
            log.close()
            raise
        os.set_blocking(process.stdout.fileno(), False)
        actor = {'process': process, 'log': log, 'path': log_path, 'retained': 0,
                 'tail': b'', 'expected_exit': False, 'command': command,
                 'pgid_at_launch': os.getpgid(process.pid), 'lines': b'',
                 'ui_ready': None, 'ui_expected': None, 'ui_responses': {}}
        self.actors[role] = actor
        self.selector.register(process.stdout, selectors.EVENT_READ, role)
        self.peak_live = max(self.peak_live, sum(x['process'].poll() is None for x in self.actors.values()))
        return process

    def pump(self):
        for key, _ in self.selector.select(0.025):
            actor = self.actors[key.data]
            chunk = os.read(key.fd, 64 * 1024)
            if not chunk:
                self.selector.unregister(key.fileobj)
                continue
            allowed = self.log_limit - actor['retained']
            actor['log'].write(chunk[:allowed])
            actor['log'].flush()
            actor['retained'] += min(len(chunk), allowed)
            if len(chunk) > allowed:
                raise ValueError('Actor log allowance exceeded: ' + str(actor['path']))
            text = actor['tail'] + chunk
            actor['tail'] = text[-16:]
            if b'ERROR:' in text:
                raise ValueError('Engine error; inspect ' + str(actor['path']))
            actor['lines'] += chunk
            while b'\n' in actor['lines']:
                line, actor['lines'] = actor['lines'].split(b'\n', 1)
                self._line(key.data, line.rstrip(b'\r'))
            if len(actor['lines']) > 65536:
                raise ValueError('Actor output line exceeds its allowance')
        for role, actor in self.actors.items():
            code = actor['process'].poll()
            if code is not None and (code != 0 or not actor['expected_exit']):
                raise ValueError(f'{role} exited unexpectedly with {code}; inspect {actor["path"]}')

    def _line(self, role, line):
        actor = self.actors[role]
        if line.startswith(b'OPENING_UI_FAIL '):
            raise ValueError('Actual UI failure; inspect ' + str(actor['path']))
        if line.startswith(b'OPENING_UI_READY '):
            if actor['ui_ready'] is not None:
                raise ValueError('Duplicate UI readiness marker')
            actor['ui_ready'] = json.loads(line.removeprefix(b'OPENING_UI_READY '))
        if line.startswith(b'OPENING_UI_RESPONSE '):
            marker = json.loads(line.removeprefix(b'OPENING_UI_RESPONSE '))
            expected = actor['ui_expected']
            if (not isinstance(marker, dict) or type(marker.get('id')) is not int
                    or marker.get('status') != 'pass' or expected is None
                    or marker['id'] != expected['id'] or marker['id'] in actor['ui_responses']):
                raise ValueError('Malformed, mismatched or duplicate UI completion marker')
            actor['ui_responses'][marker['id']] = marker

    def expect_ui(self, role, command):
        actor = self.actors[role]
        if actor['ui_expected'] is not None:
            raise ValueError('Only one outstanding UI control is supported')
        actor['ui_expected'] = command

    def ui_response(self, role, directory):
        actor = self.actors[role]
        command = actor['ui_expected']
        if command is None:
            raise ValueError('A UI response needs its exact outstanding control')
        ident = command['id']
        self.wait(lambda: ident in actor['ui_responses'], timeout=35)
        # The producer closes the file BEFORE this marker. Parse once; neither
        # partial existence nor retrying malformed JSON is acceptance evidence.
        result = read_json(directory / f'response-{ident}.json')
        if (type(result.get('id')) is not int or result['id'] != ident or result.get('status') != 'pass'
                or result.get('input') != command or not isinstance(result.get('facts'), dict)):
            raise ValueError('Actual UI response does not match the completed control')
        actor['ui_expected'] = None
        return result

    def wait(self, predicate, timeout=25):
        deadline = time.monotonic() + timeout
        while True:
            self.pump()
            if predicate():
                return
            if time.monotonic() >= deadline:
                raise TimeoutError('Cohort boundary timed out; preserve all actor logs')

    def close(self):
        failure = None
        for actor in self.actors.values():
            if actor['process'].poll() is None:
                actor['process'].terminate()
        for actor in self.actors.values():
            process = actor['process']
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
            # Reaped leaders have finite pipe contents. Retain/check their tail
            # too; a zero exit must not hide a final compiler/runtime ERROR.
            while True:
                try:
                    chunk = os.read(process.stdout.fileno(), 64 * 1024)
                except BlockingIOError:
                    break
                if not chunk:
                    break
                allowed = self.log_limit - actor['retained']
                actor['log'].write(chunk[:allowed])
                actor['retained'] += min(len(chunk), allowed)
                if len(chunk) > allowed or b'ERROR:' in actor['tail'] + chunk:
                    failure = ValueError('Actor final output refused; inspect ' + str(actor['path']))
                actor['tail'] = chunk[-16:]
            process.stdout.close()
            actor['log'].close()
        self.selector.close()
        if failure:
            raise failure

    def evidence(self):
        return {role: {'pid': actor['process'].pid, 'exit': actor['process'].returncode,
                       'pgid_at_launch': actor['pgid_at_launch'],
                       'reaped': actor['process'].returncode is not None,
                       'command': actor['command'], 'log': str(actor['path']),
                       'retained_log_bytes': actor['retained']}
                for role, actor in self.actors.items()}


def ledger(snapshot):
    stock = snapshot['stock']
    values = [stock[k] for k in ('source', 'collector', 'belt', 'input', 'held', 'output', 'player')]
    if any(type(x) is not int or x < 0 for x in values) or sum(values) != 16:
        raise ValueError('Actual shared state violates the independent 16-item ledger')
    if (any(type(x) is not int or x < 0 for x in snapshot['inventories'].values())
            or stock['player'] != sum(snapshot['inventories'].values())):
        raise ValueError('Actor inventory and shared total differ')
    for kind in ('collector', 'belt', 'processor', 'wheel'):
        used = sum(entity['kind'] == kind for entity in snapshot['entities'].values())
        if type(snapshot['parts'][kind]) is not int or snapshot['parts'][kind] < 0 or snapshot['parts'][kind] + used != 1:
            raise ValueError('Finite construction part accounting differs: ' + kind)
    if (type(snapshot['parts']['shaft']) is not int or snapshot['parts']['shaft'] < 0
            or snapshot['parts']['shaft'] + len(snapshot['drive_links']) != 3):
        raise ValueError('Finite shaft accounting differs')


def ui_cohort_worker(spec):
    """Same sole ActorGroup lifecycle; the sealed driver owns input/oracles only."""
    run = Path(spec['run'])
    group = ActorGroup(run)
    result = {'status': 'running', 'mode': 'actual_ui', 'frozen_clock': spec['frozen_clock'],
              'worker_pid': os.getpid(), 'worker_pgid': os.getpgrp(), 'exchanges': [], 'boundaries': []}
    sequences = {'P': 0, 'Q': 0}
    observation = 0
    started = time.monotonic()
    try:
        if os.getpgrp() != os.getpid():
            raise ValueError('UI worker must remain the bounded helper-owned group leader')
        for role in ('server', 'P', 'Q'):
            actor = spec['actors'][role]
            process = group.launch(role, actor['command'], actor['project'], dict(os.environ, **actor['environment']))
            if os.getpgid(process.pid) != os.getpgrp():
                raise ValueError('UI actor escaped the owned group')
            if role == 'server':
                group.wait(lambda: (run / 'server-ready.json').is_file())
                if read_json(run / 'server-ready.json')['pid'] != process.pid:
                    raise ValueError('Wrong server readiness owner')
        # This means actual scene/controller startup, not network welcome.
        group.wait(lambda: all(group.actors[role]['ui_ready'] is not None for role in ('P', 'Q')))

        def exchange(commands):
            if not commands or any(role not in ('P', 'Q') for role in commands):
                raise ValueError('UI exchange needs one or both actual client roles')
            sent = {}
            for role, command in commands.items():
                if not isinstance(command, dict):
                    raise ValueError('UI input must be a structured command')
                next_id = sequences[role] + 1
                if 'id' in command and (type(command['id']) is not int or command['id'] != next_id):
                    raise ValueError('UI driver id does not match the next owned id')
                sent[role] = dict(command, id=next_id)
                sequences[role] = next_id
                group.expect_ui(role, sent[role])
                if command.get('action') == 'quit':
                    group.actors[role]['expected_exit'] = True
            # Publish every role's request before waiting on either producer.
            for role, command in sent.items():
                publish(run / role / 'controls/control.json', command)
            replies = {role: group.ui_response(role, run / role / 'controls') for role in sent}
            for role, reply in replies.items():
                facts = reply['facts']
                if (not facts.get('model_is_session') or not facts.get('client_world_is_null')
                        or facts.get('auto_advance') is not False):
                    raise ValueError('Client has a shadow authority or local clock')
                if facts.get('ready'):
                    if facts.get('actor') != role:
                        raise ValueError('UI role differs from transport-bound identity')
                    ledger(facts['projection'])
            result['exchanges'].append({'commands': sent, 'responses': replies})
            return replies

        def observe_server():
            nonlocal observation
            if group.actors['server']['process'].poll() is not None:
                return read_json(run / 'server-report.json')
            observation += 1
            publish(run / 'observe-request.json', {'id': observation})
            path = run / 'observe-response.json'
            group.wait(lambda: path.is_file() and read_json(path).get('id') == observation)
            value = read_json(path)
            ledger(value['snapshot'])
            return value

        def wait_role_absent(role):
            if role not in ('P', 'Q'):
                raise ValueError('Unknown fixture role')
            group.wait(lambda: group.actors['server']['process'].poll() is not None
                       or role not in read_json(run / 'server-status.json')['roles'])
            return observe_server()

        def transport_boundary(kind, roles=()):
            roles = tuple(roles) or ('P', 'Q')
            if any(role not in ('P', 'Q') for role in roles):
                raise ValueError('Unknown private barrier role')
            if kind in ('hold_admission', 'hold_outcomes'):
                path = run / ('admission.hold' if kind == 'hold_admission' else 'outcomes.hold')
                temporary = path.with_suffix('.writing')
                temporary.write_text(','.join(roles))
                temporary.replace(path)
            elif kind in ('wait_received', 'wait_outcomes'):
                key = 'pending_roles' if kind == 'wait_received' else 'held_roles'
                group.wait(lambda: set(roles).issubset(read_json(run / 'server-status.json')[key]))
            elif kind in ('release_admission', 'release_outcomes'):
                path = run / ('admission.hold' if kind == 'release_admission' else 'outcomes.hold')
                path.unlink(missing_ok=True)  # Our test control marker, never a resource lock.
                key = 'pending_roles' if kind == 'release_admission' else 'held_roles'
                group.wait(lambda: not set(roles).intersection(read_json(run / 'server-status.json')[key]))
            elif kind == 'stop_server':
                group.actors['server']['expected_exit'] = True
                (run / 'server.stop').touch()
                group.wait(lambda: (run / 'server-report.json').is_file()
                           and group.actors['server']['process'].poll() is not None)
            else:
                raise ValueError('Unknown private transport boundary: ' + kind)
            observed = observe_server()
            result['boundaries'].append({'kind': kind, 'roles': roles, 'server': observed})
            return observed

        driver = Path(spec['driver'])
        if sha(driver) != spec['driver_sha256']:
            raise ValueError('Captured UI case driver changed before import')
        module_spec = importlib.util.spec_from_file_location('sealed_opening_ui_cases', driver)
        module = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(module)
        verdict = module.run_ui_cases(exchange, frozen_clock=spec['frozen_clock'],
                                      wait_role_absent=wait_role_absent, observe_server=observe_server,
                                      transport_boundary=transport_boundary)
        if not isinstance(verdict, dict) or verdict.get('status') != 'pass':
            raise ValueError('Actual-input scenario driver did not establish its declared cases')
        result['scenario'] = verdict
        if group.actors['server']['process'].poll() is None:
            transport_boundary('stop_server')
        alive = {role: {'action': 'quit'} for role in ('P', 'Q') if group.actors[role]['process'].poll() is None}
        if alive:
            exchange(alive)
        group.wait(lambda: all(actor['process'].poll() is not None for actor in group.actors.values()))
        server = read_json(run / 'server-report.json')
        ledger(server['snapshot'])
        if server['status'] != 'pass' or server['server_relay'] is not False or server['clock_frozen'] != spec['frozen_clock']:
            raise ValueError('Actual server lifecycle/clock configuration differs')
        if (not spec['frozen_clock'] and server['tick_count'] < 1) or (spec['frozen_clock'] and server['tick_count'] != 0):
            raise ValueError('Declared frozen/live server clock was not observed')
        result.update(status='pass', final=server['snapshot'])
    except BaseException as error:
        result.update(status='fail', error=str(error))
        if isinstance(getattr(error, 'report', None), dict):
            result['scenario'] = error.report
        raise
    finally:
        try:
            group.close()
        except BaseException as error:
            result.update(status='fail', error=str(error))
            raise
        finally:
            result.update(actors=group.evidence(), peak_live_engines=group.peak_live,
                          elapsed_seconds=time.monotonic() - started)
            (run / 'cohort.json').write_text(json.dumps(result, indent=2) + '\n')
    print('OPENING_SESSION_UI_PASS', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--port', type=int, default=0, help='zero chooses one unused loopback UDP port; bind conflict fails')
    parser.add_argument('--ui', action='store_true', help='actual two-UI physical consumer')
    parser.add_argument('--clock', choices=('frozen', 'live'), default='frozen')
    parser.add_argument('--ui-driver', type=Path, help='explicit sealed local pure case driver')
    args = parser.parse_args()
    if not args.ui or not args.ui_driver:
        parser.error('The physical shared proof requires --ui and an explicit UI driver')
    binary, artifacts = args.godot, args.artifacts
    if not binary.is_absolute() or binary.resolve() != binary or not binary.is_file() or not os.access(binary, os.X_OK) or sha(binary) != args.sha256:
        parser.error('Use the explicit existing verified executable and SHA256 pin')
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error('Use an external absolute artifact root without symlinks')
    artifacts.mkdir(parents=True, exist_ok=True, mode=0o700)
    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    ownership = subprocess.run(['git', '-C', str(artifacts), 'rev-parse', '--is-inside-work-tree', '--is-inside-git-dir'], capture_output=True, text=True, env=environment, timeout=5)
    if ownership.returncode == 0 and 'true' in ownership.stdout.splitlines():
        parser.error('Keep session diagnostics outside Git worktrees/administration')
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error('Require22GiB free and less than256MiB retained session diagnostics')
    if not 0 <= args.port <= 65535:
        parser.error('Use an explicit bounded port or zero for one kernel selection')
    port = args.port
    if not port:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
    run = Path(tempfile.mkdtemp(prefix='session-', dir=artifacts))
    receipt = {'status': 'running', 'mode': 'actual_ui', 'started': datetime.now(timezone.utc).isoformat(),
               'profile': 'physical',
               'source_hashes': {}, 'runner_hashes': {name: sha(path) for name, path in
               [('check_opening_session.py', Path(__file__)), ('check_engine_environment.py', Path(bounds.__file__))]},
               'port': port, 'loopback': '127.0.0.1', 'user_play': 'not_assessed', 'stages': [],
               'binary': str(binary), 'binary_sha256': args.sha256,
               'revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()}
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    deadline = time.monotonic() + 1200
    print('Shared opening transport evidence: ' + str(run), flush=True)
    try:
        version = bounds.execute_bounded([str(binary), '--version'], cwd=ROOT, env=os.environ.copy(),
                                         log=run / 'version.log', artifacts=artifacts, timeout=15)
        if version.returncode or (run / 'version.log').read_text().strip() != '4.7.2.stable.official.ed1daf0bf':
            raise ValueError('Require the separately verified supported Godot version')
        receipt['stages'].append({'name': 'version', 'exit': version.returncode})
        from run_opening import FILES as OFFLINE_FILES
        files = tuple(dict.fromkeys((*OFFLINE_FILES, *FILES, *UI_FILES)))
        originals = {}
        for name in files:
            path = PROJECT / name
            if path.is_symlink() or not path.is_file():
                raise ValueError('Missing/unsafe session source: ' + name)
            originals[name] = path.read_bytes()
            receipt['source_hashes'][name] = hashlib.sha256(originals[name]).hexdigest()
        if sum(map(len, originals.values())) > 2 * 1024**2:
            raise ValueError('Session sources exceed2MiB allowance')
        spec = {'run': str(run), 'port': port, 'actors': {}, 'ui': True, 'frozen_clock': args.clock == 'frozen',
                'profile': 'physical'}
        driver = args.ui_driver
        if not driver.is_absolute() or driver.resolve() != driver or not driver.is_file() or driver.stat().st_size > 128 * 1024:
            raise ValueError('Use the explicit bounded regular local pure UI driver')
        captured = run / 'ui_case_driver.py'
        captured.write_bytes(driver.read_bytes())
        spec.update(driver=str(captured), driver_sha256=sha(captured))
        receipt['ui_driver'] = {'source': str(driver), 'captured': str(captured), 'sha256': sha(captured)}
        for role in ('server', 'P', 'Q'):
            directory = run / role
            project = directory / 'project'
            for name, data in originals.items():
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            env = {}
            for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('TMPDIR', 'tmp')]:
                path = directory / name
                path.mkdir()
                env[key] = str(path)
            (directory / 'controls').mkdir()
            log = run / ('import-' + role + '.log')
            result = bounds.execute_bounded([str(binary), '--headless', '--editor', '--path', str(project), '--import'], cwd=project,
                                            env=dict(os.environ, **env), log=log, artifacts=artifacts, timeout=min(120, deadline - time.monotonic()))
            if result.returncode or 'ERROR:' in log.read_text(errors='replace'):
                raise ValueError('Session import failed: ' + str(log))
            command = [str(binary), '--path', str(project)]
            if role == 'server':
                command += ['--headless']
            else:
                command += ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
            command += ['--script', 'res://opening-session/server.gd' if role == 'server'
                        else 'res://opening/shared_check.gd',
                        '--', '--session-port=' + str(port)]
            if role == 'server':
                command += ['--actor-roster=P,Q']
                if args.clock == 'frozen':
                    command += ['--frozen-clock']
                command += ['--ready-file=' + str(run / 'server-ready.json'),
                            '--status-file=' + str(run / 'server-status.json'), '--stop-file=' + str(run / 'server.stop'),
                            '--report-file=' + str(run / 'server-report.json'),
                            '--admission-hold-file=' + str(run / 'admission.hold'),
                            '--outcome-hold-file=' + str(run / 'outcomes.hold'),
                            '--observe-request=' + str(run / 'observe-request.json'),
                            '--observe-response=' + str(run / 'observe-response.json')]
            else:
                command += ['--session-role=' + role]
                command += ['--ui-control-root=' + str(directory / 'controls'), '--ui-defer-connect']
            spec['actors'][role] = {'project': str(project), 'environment': env, 'command': command}
            receipt['stages'].append({'name': 'import-' + role, 'exit': result.returncode})
        spec_path = run / 'cohort-spec.json'
        spec_path.write_text(json.dumps(spec, indent=2) + '\n')
        command = [sys.executable, '-B', str(Path(__file__).resolve()), '--cohort-worker', str(spec_path)]
        result = bounds.execute_bounded(command, cwd=ROOT, env=os.environ.copy(), log=run / 'cohort.log', artifacts=artifacts,
                                        timeout=min(900, deadline - time.monotonic()))
        receipt['stages'].append({'name': 'server-two-clients', 'exit': result.returncode})
        marker = 'OPENING_SESSION_UI_PASS'
        if result.returncode or marker not in (run / 'cohort.log').read_text():
            raise ValueError('Real server/two-client proof failed; inspect retained cohort/actor diagnostics')
        receipt['cohort'] = read_json(run / 'cohort.json')
        if receipt['cohort']['status'] != 'pass' or receipt['cohort']['peak_live_engines'] != 3:
            raise ValueError('Cohort did not establish bounded actual three-engine success')
        if any(actor['exit'] != 0 or not actor['reaped']
               or actor['pgid_at_launch'] != receipt['cohort']['worker_pgid']
               for actor in receipt['cohort']['actors'].values()):
            raise ValueError('Actor group ownership or teardown evidence differs')
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as released:
            released.bind(('127.0.0.1', port))
        receipt['listener_released'] = True
        for role in ('server', 'P', 'Q'):
            for name, digest in receipt['source_hashes'].items():
                if sha(run / role / 'project' / name) != digest:
                    raise ValueError('Runtime changed original copied session source: ' + name)
        if sha(binary) != args.sha256:
            raise ValueError('Pinned runtime changed during session')
        receipt['status'] = 'pass'
    except BaseException as error:
        receipt.update(status='fail', error=str(error))
        raise
    finally:
        receipt.update(owned_bytes=bounds.owned_bytes(artifacts), finished=datetime.now(timezone.utc).isoformat())
        (run / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Shared physical UI passed; evidence=' + str(run), flush=True)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--cohort-worker':
        ui_cohort_worker(read_json(Path(sys.argv[2])))
    else:
        main()
