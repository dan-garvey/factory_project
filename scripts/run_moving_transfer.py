#!/usr/bin/env python3
"""Bounded native moving-port transfer fixture; invoke through run_local.py heavy."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import check_engine_environment as bounds
from check_opening_session import ActorGroup, publish, read_json

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'experiments/engine-environment/godot'
FILES = bounds.FILES + ('mechanics/authority.gd', 'rider/authority.gd', 'rotary/authority.gd') + tuple('moving-transfer/' + name for name in (
    'authority.gd', 'view.gd', 'check.gd', 'probe.gd', 'observer.gd', 'main.tscn'))
RUNNERS = ('run_moving_transfer.py', 'check_engine_environment.py', 'check_opening_session.py')
MAX_BYTES = 256 * 1024**2
VERSION = '4.7.2.stable.official.ed1daf0bf'
EPSILON = 0.00002


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(value, message):
    if not value:
        raise ValueError('Moving-transfer oracle: ' + message)


def ledger(stock):
    require(set(stock) == {'carrier', 'receiver'} and all(type(v) is int and v >= 0 for v in stock.values())
            and sum(stock.values()) == 3, 'literal integral nonnegative 3 A ledger')


def stopped(state):
    require(state['running'] is False and state['pending'] is False
            and state['queued_transfers'] == 0, 'final fixture actually stopped without pending work')


def near_vector(left, right):
    return len(left) == len(right) == 3 and all(abs(a - b) <= EPSILON for a, b in zip(left, right))


def subtract(left, right):
    return [a - b for a, b in zip(left, right)]


def length(value):
    return sum(x * x for x in value) ** 0.5


def point(body, local):
    return [body['position'][axis] + sum(body['basis'][column][axis] * local[column] for column in range(3)) for axis in range(3)]


def geometry(native):
    carrier, receiver = native['carrier'], native['receiver']
    for body, half, layer, mask in ((carrier, [1.5, .175, 1.5], 4, 1), (receiver, [.275, .05, .275], 1, 4)):
        require(all(type(body[key]) is int and body[key] != 0 for key in ('id', 'rid', 'space', 'shape_rid')), 'actual opaque native identities')
        require(body['shape_type'] == 3 and near_vector(body['shape_data'], half) and body['layer'] == layer and body['mask'] == mask,
                'actual native box dimensions and collision layers')
    require(carrier['space'] == receiver['space'] and native['same_world'] is True, 'native bodies share the real world')
    outlet, inlet = point(carrier, [1.4, .3, 0]), point(receiver, [-.55, 0, 0])
    outward = [x / length(carrier['basis'][0]) for x in carrier['basis'][0]]
    inward = [-x / length(receiver['basis'][0]) for x in receiver['basis'][0]]
    distance = length(subtract(outlet, inlet))
    facing = -sum(a * b for a, b in zip(outward, inward))
    require(near_vector(native['outlet'], outlet) and near_vector(native['inlet'], inlet)
            and near_vector(native['outward'], outward) and near_vector(native['inward'], inward)
            and abs(native['distance'] - distance) <= EPSILON and abs(native['facing'] - facing) <= EPSILON, 'native basis-to-port geometry')
    require(native['geometric'] is (distance <= .08 and facing >= .995), 'literal frozen distance AND facing gate')
    return native['geometric']


def verify_cuts(cuts):
    require(bool(cuts), 'all natural cuts retained')
    registered, inside, serial, previous = False, False, 0, None
    identities = None
    for index, row in enumerate(cuts, 1):
        ledger(row['stock'])
        sample = row['observation']
        native = sample['native']
        eligible_geometry = geometry(native)
        require(sample['cut'] == index and type(native['frame']) is int, 'contiguous authoritative observation sequence')
        pair = [(native[key]['id'], native[key]['rid'], native[key]['shape_rid'], native[key]['space']) for key in ('carrier', 'receiver')]
        if identities is None: identities = pair
        require(pair == identities, 'native container identities persist without replacement')
        require(not registered or sample['registered'] is True, 'registration cannot regress')
        if sample['registered'] and not registered:
            require(native['initial_native'] and near_vector(native['carrier']['basis'][0], [1, 0, 0]), 'first readiness is actual initial native registration')
        registered = sample['registered']
        if registered:
            require(near_vector(native['carrier']['position'], [0, .75, 0]), 'registered native carrier retains the fixture centre')
        eligible = registered and eligible_geometry
        entered, left = eligible and not inside, not eligible and inside
        if entered: serial += 1
        window = sample['window']
        require(sample['eligible'] is eligible and window['inside'] is eligible and window['entered'] is entered
                and window['left'] is left and window['id'] == serial and type(window['spent']) is bool, 'every-cut enter/leave/visit identity')
        if previous is not None:
            old = previous['observation']
            require(native['frame'] == old['native']['frame'] + 1 and sample['previous']['cut'] == old['cut']
                    and sample['previous']['frame'] == old['native']['frame']
                    and near_vector(sample['previous']['outlet'], old['native']['outlet']), 'every consecutive natural physics cut, including no-request intervals')
            require(abs(sample['port_displacement'] - length(subtract(native['outlet'], old['native']['outlet']))) <= EPSILON, 'consecutive actual native port displacement')
            require(row['stock']['carrier'] <= previous['stock']['carrier'] and row['stock']['receiver'] >= previous['stock']['receiver'], 'no hidden replenishment between requests')
            if inside and eligible and old['window']['spent']:
                require(window['spent'], 'used contact cannot reopen while still present')
        else:
            require(sample['previous'] == {} and sample['port_displacement'] == 0, 'first cut explicitly has no prior observation')
        previous, inside = row, eligible


def verify(report, mode):
    """Literal geometry, immutable histories and finite ledger; no second model."""
    import math
    control = mode == 'wrong_facing_control'
    expected = {'readiness', 'wrong_facing'} if control else {'readiness', 'stationary', 'distance_only', 'offsite', 'moving', 'moving_competition', 'final'}
    require(report['status'] == 'pass' and not report['failures'] and report['checks'] >= 20
            and report['mode'] == mode and set(report['cases']) == expected, 'native completion and consumer coverage')
    require(type(report['owner']) is int and report['owner'] != 0, 'actual sole owner identity')
    verify_cuts(report['cuts'])
    cache, accepted, previous, visits = {}, [], {'carrier': 3, 'receiver': 0}, set()
    for order, row in enumerate(report['events'], 1):
        event = row['event']
        before, after, disposition, intent = (event[key] for key in ('before', 'after', 'disposition', 'intent'))
        ledger(before)
        ledger(after)
        require(event['owner'] == report['owner'] and event['order'] == order and before == previous, 'one ordered continuous quantity owner')
        key = (intent['actor'], intent['request'])
        if event['duplicate']:
            require(key in cache and intent == cache[key][0] and disposition == cache[key][1] and before == after,
                    'exact immutable historical disposition replay before current eligibility')
        elif key in cache:
            require(intent != cache[key][0] and disposition['reason'] == 'request_payload_reuse'
                    and disposition['accepted'] is False and before == after, 'payload reuse cannot retarget cached identity')
        else:
            cache[key] = (intent, disposition)
            require(disposition['order'] == order and disposition['before'] == before and disposition['after'] == after, 'new original disposition matches its real admission')
        if disposition['accepted'] and not event['duplicate']:
            sample, native = disposition['observation'], disposition['native']
            require(after == {'carrier': before['carrier'] - 1, 'receiver': before['receiver'] + 1}
                    and type(intent['amount']) is int and intent['amount'] == 1 and intent['kind'] == 'A', 'one typed conserved admission')
            geometry(native)
            require(sample['registered'] and sample['eligible'] and sample['window']['inside'] and not sample['window']['spent']
                    and native['geometric'] and native['frame'] == sample['native']['frame']
                    and native['carrier'] == sample['native']['carrier'] and native['receiver'] == sample['native']['receiver'], 'fresh native geometry is the observed eligible cut')
            require(sample['window']['id'] not in visits, 'one accepted unit per measured visit')
            visits.add(sample['window']['id'])
            accepted.append(event)
        else:
            require(before == after, 'all refusals/replays have no material delta')
        previous = after
    queued = report['queued']
    require([entry['queue_id'] for entry in queued] == list(range(1, len(queued) + 1)), 'ordered explicit queue identities')
    finals = [row['event'] for row in report['events'] if row['event']['queue_id']]
    require([event['queue_id'] for event in finals] == list(range(1, len(queued) + 1)), 'one FIFO final disposition per queued intent')
    for entry, final in zip(queued, finals):
        ledger(entry['stock'])
        require(entry['status'] == 'queued' and entry['final'] is False and final['final'] is True
                and final['status'] == 'completed' and entry['intent'] == final['intent']
                and final['disposition']['native']['frame'] > entry['submitted_frame'], 'queued intake is distinct from next-cut final admission')
    bootstrap = report['cases']['readiness']['bootstrap']
    require(bootstrap['disposition']['reason'] == 'native_not_ready' and report['events'][0]['event'] == bootstrap,
            'first pre-ready refusal is raw evidence')
    if control:
        final = report['cases']['wrong_facing']['final']
        native = final['observation']['native']
        require(not accepted and final['stock'] == {'carrier': 3, 'receiver': 0}
                and native['distance'] < EPSILON and native['facing'] < -.999 and not native['geometric'], 'coincident native points discriminate wrong facing')
        return
    require(len(accepted) == 3 and visits == {1, 2, 3} and previous == {'carrier': 0, 'receiver': 3}, 'exactly the finite original three admissions across three actual visits')
    distance_only = report['cases']['distance_only']
    require(distance_only['disposition']['reason'] == 'ports_ineligible' and distance_only['disposition']['native']['distance'] > .08
            and distance_only['disposition']['native']['facing'] >= .995 and distance_only['before'] == distance_only['after'], 'actual distance-only refusal with passing facing')
    stationary = report['cases']['stationary']
    require(stationary['first'] == accepted[0] and stationary['competitor']['disposition']['reason'] == 'window_spent'
            and stationary['first']['current']['native']['frame'] == stationary['competitor']['current']['native']['frame'], 'same-cut actual competition')
    replay = report['cases']['offsite']['replay']
    require(replay['duplicate'] and replay['disposition'] == accepted[0]['disposition']
            and replay['disposition']['native']['geometric'] and not replay['current']['native']['geometric'], 'original receipt separate from changed current geometry')
    require(report['cases']['moving'] == accepted[1:], 'actual manual and sensor admission records retained')
    cuts = {row['observation']['cut']: row['observation'] for row in report['cuts']}
    for moving_index, event in enumerate(accepted[1:]):
        sample = event['disposition']['observation']
        native, drive = sample['native'], sample['drive']
        axis = native['carrier']['basis'][0]
        expected_goal = [math.cos(drive['phase']), 0, -math.sin(drive['phase'])]
        completed_axis = drive['completed']['basis'][0]
        require(event['intent']['actor'] == ('P' if moving_index == 0 else 'sensor') and sample['intermediate'] and drive['pending']
                and length(subtract(axis, expected_goal)) > EPSILON and length(subtract(axis, completed_axis)) > EPSILON
                and sample['port_displacement'] > .000001 and length(native['angular_velocity']) > .00001,
                'genuinely moving native pose differs from requested AND completed goal')
        following = cuts[sample['cut'] + 1]
        require(length(subtract(following['native']['outlet'], native['outlet'])) > .000001,
                'native motion continues after actual admission')
        require(abs(drive['phase'] - drive['committed'] * math.pi / 16) <= EPSILON
                and abs(drive['source_phase'] - drive['committed'] * math.pi / 8) <= EPSILON, 'unchanged inherited literal 20:40 signed source law')
    competition = report['cases']['moving_competition']
    require(competition['manual'] == accepted[1] and competition['sensor']['disposition']['reason'] == 'window_spent'
            and competition['sensor']['current']['sample']['cut'] == accepted[1]['current']['sample']['cut'], 'manual FIFO admission wins over fresh same-cut sensor request')
    final = report['cases']['final']
    stopped(final['state'])
    require(final['state']['stock'] == {'carrier': 0, 'receiver': 3} and final['empty']['disposition']['reason'] == 'source_empty'
            and final['retry']['duplicate'] and final['retry']['disposition'] == accepted[0]['disposition'], 'empty source and old retry cannot create stock')
    if mode == 'ordinary_scene_input':
        require(any(item['stage'] == 'manual_native_visit' and item['code'] == 80 and item['pressed'] is True
                    for item in report['inputs']), 'ordinary moving manual transfer originates in real P input')
        require(report['scene'] == 'res://moving-transfer/main.tscn' and report['view_script'] == 'res://moving-transfer/view.gd'
                and report['authority_script'] == 'res://moving-transfer/authority.gd', 'actual ordinary scene and sole authority')
        require({item['name'] for item in report['captures']} == {'stationary-one-unit', 'moving-handoff', 'all-three-received'}, 'ordinary viewport capture coverage')
        for item in report['captures']:
            require(Path(item['path']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), 'actual PNG')
            state, visible = item['state'], item['visible']
            require(visible['counts'] == state['stock'] == visible['presented']['stock']
                    and visible['presented']['cut'] == state['observation']['cut'], 'actual view displays current sole stock/native cut')
            for field, holder in (('deck', 'carrier'), ('dock', 'receiver')):
                require(all(near_vector(visible[field][key], state['observation']['native'][holder][key]) for key in ('position',))
                        and all(near_vector(a, b) for a, b in zip(visible[field]['basis'], state['observation']['native'][holder]['basis'])), 'actual displayed native body pose')


def worker(spec):
    directory = Path(spec['run'])
    group = ActorGroup(directory)
    receipt = {'status': 'running', 'worker_pid': os.getpid(), 'worker_pgid': os.getpgrp()}
    stopped = []
    old = {number: signal.signal(number, lambda number, _frame: stopped.append(number)) for number in (signal.SIGINT, signal.SIGTERM)}
    try:
        require(os.getpid() == os.getpgrp(), 'worker must inherit helper-owned group leadership')
        process = group.launch('engine', spec['command'], spec['project'], dict(os.environ, **spec['environment']))
        group.actors['engine']['expected_exit'] = True
        deadline = time.monotonic() + spec['timeout']
        while process.poll() is None:
            group.pump()
            if stopped: raise InterruptedError('owned worker interrupted')
            require(time.monotonic() < deadline, 'native stage deadline')
        require(process.returncode == 0, 'native engine exit')
        if spec['check']:
            report = read_json(Path(spec['report']))
            require(report['pid'] == process.pid, 'report does not belong to launched actual engine')
            verify(report, spec['mode'])
        receipt['status'] = 'pass' if spec['check'] else 'completed'
    except BaseException as error:
        receipt.update(status='interrupted' if stopped else 'fail', error=str(error))
        raise
    finally:
        try:
            group.close()
        finally:
            for number, handler in old.items(): signal.signal(number, handler)
            receipt.update(actors=group.evidence(), peak_live_engines=group.peak_live)
            publish(directory / 'lifetime.json', receipt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--check', action='store_true', help='run the real shared authority witness')
    parser.add_argument('--render', action='store_true', help='also drive/capture the ordinary scene; requires --check')
    parser.add_argument('--duration-seconds', type=int, help='ordinary interactive run limit 1..900')
    args = parser.parse_args()
    if args.render and not args.check: parser.error('--render requires --check')
    if args.check and args.duration_seconds is not None: parser.error('--duration-seconds selects interactive mode only')
    duration = 900 if args.duration_seconds is None else args.duration_seconds
    if not 1 <= duration <= 900: parser.error('--duration-seconds must be1..900')
    binary, artifacts = args.godot, args.artifacts
    if (not binary.is_absolute() or binary.resolve() != binary or not binary.is_file()
            or not os.access(binary, os.X_OK) or not re.fullmatch('[0-9a-f]{64}', args.sha256) or sha(binary) != args.sha256):
        parser.error('Use the explicit existing executable and verified lowercase SHA256')
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error('Use an owned external artifact root without symlinks')
    artifacts.mkdir(parents=True, exist_ok=True, mode=0o700)
    ownership = subprocess.run(['git', '-C', str(artifacts), 'rev-parse', '--is-inside-work-tree', '--is-inside-git-dir'], capture_output=True, text=True, timeout=5)
    if ownership.returncode == 0 and 'true' in ownership.stdout.splitlines(): parser.error('Keep artifacts outside Git')
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error('Require22GiB free and less than256MiB retained evidence')
    run = Path(tempfile.mkdtemp(prefix='moving_transfer-', dir=artifacts))
    receipt = {'schema': 1, 'status': 'running', 'revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
               'started': datetime.now(timezone.utc).isoformat(), 'binary': str(binary), 'binary_sha256': args.sha256,
               'source_hashes': {}, 'runner_hashes': {}, 'stages': [], 'modes': {}, 'user_play': 'not_assessed'}
    print('Moving-transfer fixture evidence: ' + str(run), flush=True)
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    deadline = time.monotonic() + 1800
    code = 0
    try:
        def execute(name, command, project, environment, seconds):
            result = bounds.execute_bounded(command, cwd=project, env=environment, log=run / (name + '.log'),
                    artifacts=artifacts, timeout=min(seconds, deadline - time.monotonic()))
            receipt['stages'].append({'name': name, 'command': command, 'exit': result.returncode})
            require(result.returncode == 0 and 'ERROR:' not in (run / (name + '.log')).read_text(errors='replace'), 'stage failed: ' + name)
        execute('version', [str(binary), '--version'], ROOT, os.environ.copy(), 15)
        require((run / 'version.log').read_text().strip() == VERSION, 'existing supported engine version')
        originals = {name: (PROJECT / name).read_bytes() for name in FILES}
        require(all(not (PROJECT / name).is_symlink() for name in FILES) and sum(map(len, originals.values())) <= 2 * 1024**2, 'regular bounded source copy')
        receipt['source_hashes'] = {name: hashlib.sha256(data).hexdigest() for name, data in originals.items()}
        runners = run / 'runners'
        runners.mkdir()
        for name in RUNNERS:
            (runners / name).write_bytes((ROOT / 'scripts' / name).read_bytes())
            receipt['runner_hashes'][name] = sha(runners / name)
        modes = [('wrong-facing', 'wrong_facing_control'), ('headless', 'headless_authority')] if args.check else [('interactive', 'ordinary_interactive')]
        if args.render: modes.append(('render', 'ordinary_scene_input'))
        for name, mode in modes:
            directory = run / name
            project = directory / 'project'
            for relative, data in originals.items():
                target = project / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            environment = {}
            for key, folder in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('TMPDIR', 'tmp')]:
                path = directory / folder
                path.mkdir()
                environment[key] = str(path)
            execute(name + '-import', [str(binary), '--headless', '--editor', '--path', str(project), '--import'], project, dict(os.environ, **environment), 120)
            instrumentation = None
            if name == 'render':
                config = project / 'project.godot'
                before = config.read_bytes()
                require(b'[autoload]' not in before, 'explicit support required for existing autoloads')
                config.write_bytes(before + b'\n[autoload]\nMovingTransferObserver="*res://moving-transfer/observer.gd"\n')
                instrumentation = {'kind': 'copied_post_import_autoload', 'post_import_config_sha256': hashlib.sha256(before).hexdigest(),
                                   'runtime_config_sha256': sha(config), 'observer_sha256': receipt['source_hashes']['moving-transfer/observer.gd']}
            command = [str(binary), '--path', str(project)]
            if name in ('headless', 'wrong-facing'): command += ['--headless', '--script', 'res://moving-transfer/check.gd']
            else: command += ['res://moving-transfer/main.tscn', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
            captures = directory / 'captures'
            captures.mkdir()
            report = directory / 'report.json'
            command += ['--', '--transfer-seconds=' + str(120 if args.check else duration)]
            if name == 'wrong-facing': command += ['--transfer-control=wrong_facing']
            if args.check: command += ['--transfer-report=' + str(report), '--transfer-captures=' + str(captures)]
            spec = {'run': str(directory), 'project': str(project), 'command': command, 'environment': environment,
                    'timeout': 150 if args.check else duration + 15, 'check': args.check, 'mode': mode, 'report': str(report)}
            spec_path = directory / 'spec.json'
            publish(spec_path, spec)
            receipt['modes'][name] = {'spec': spec, 'instrumentation': instrumentation}
            execute(name + '-runtime', [sys.executable, '-B', str(runners / 'run_moving_transfer.py'), '--worker', str(spec_path)], ROOT, os.environ.copy(), spec['timeout'] + 5)
            lifetime = read_json(directory / 'lifetime.json')
            require(lifetime['peak_live_engines'] == 1 and lifetime['status'] in ('pass', 'completed')
                    and all(actor['exit'] == 0 and actor['reaped'] and actor['pgid_at_launch'] == lifetime['worker_pgid'] for actor in lifetime['actors'].values()), 'one actual reaped engine in its owned group')
            receipt['modes'][name]['lifetime'] = lifetime
            try:
                os.killpg(lifetime['worker_pgid'], 0)
            except ProcessLookupError:
                receipt['modes'][name]['group_gone'] = True
            else:
                raise ValueError('Owned native process group survived cleanup')
            if args.check:
                native = read_json(report)
                verify(native, mode)
                receipt['modes'][name]['report_sha256'] = sha(report)
            for relative, digest in receipt['source_hashes'].items():
                expected = instrumentation['runtime_config_sha256'] if relative == 'project.godot' and instrumentation else digest
                require(sha(project / relative) == expected, 'runtime changed copied source ' + relative)
        require(all(sha(runners / name) == digest for name, digest in receipt['runner_hashes'].items()), 'captured runners changed')
        require(sha(binary) == args.sha256, 'pinned executable changed')
        receipt['status'] = 'pass' if args.check else 'completed'
    except KeyboardInterrupt:
        code = 130
        receipt['status'] = 'interrupted'
    except BaseException as error:
        code = 1
        receipt.update(status='fail', error=str(error))
        print(str(error), file=sys.stderr)
    finally:
        for name in receipt['modes']:
            path = run / name / 'lifetime.json'
            if path.exists(): receipt['modes'][name]['lifetime'] = read_json(path)
        receipt.update(finished=datetime.now(timezone.utc).isoformat(), owned_bytes=bounds.owned_bytes(artifacts))
        publish(run / 'result.json', receipt)
    print('Moving-transfer fixture ' + receipt['status'] + '; evidence=' + str(run), flush=True)
    return code


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--worker':
        worker(read_json(Path(sys.argv[2])))
    else:
        sys.exit(main())
