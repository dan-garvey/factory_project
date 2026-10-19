#!/usr/bin/env python3
"""Exercise actual host checkpoints/restarts; reuse attributed accepted seeds."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

import check_engine_environment as bounds
from check_opening_session import ActorGroup, FILES, ledger, publish, read_json, sha
from run_opening import capture_resume, _same_value as same

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'experiments/engine-environment/godot'
SOURCES = (*FILES, 'save-tests/checkpoint_file.gd', 'opening-session/checkpoint_controls.gd')
CASES = ('paused', 'blocked', 'identity-replay')
MAX_BYTES = 256 * 1024**2
RUNNERS = ('check_shared_checkpoint.py', 'check_opening_session.py', 'check_engine_environment.py', 'run_opening.py')


def require(value, message):
    if not value:
        raise ValueError(message)


def seed_oracle(capture, name):
    # Literal existing witnesses, not a simulation or a replacement Core.
    source, output, remaining, enabled, order, revision = {
        'paused': (12, 0, 1, False, 10, 15),
        'blocked': (11, 1, 0, True, 9, 33),
        'identity-replay': (11, 0, 2, False, 14, 20)}[name]
    wheel = 'wheel-2' if name == 'identity-replay' else 'wheel-1'
    require(all(type(capture[key]) is int for key in ('schema', 'initial_feed', 'recipe_input', 'order', 'revision', 'remaining'))
            and capture['schema'] == 1, 'Seed counters are not typed Core integers')
    require(capture['context'] == 'save-fixture-1' and capture['initial_feed'] == 16
            and capture['recipe_input'] == 1 and capture['options'] == {'opening': True}, 'Wrong accepted seed fixture')
    require(same(capture['stock'], {'source': source, 'collector': 1, 'belt': 1, 'input': 1, 'held': 1, 'output': output}),
            'Seed material locations differ from the independent literal witness')
    require(same(capture['inventories'], {'P': 1} if name == 'identity-replay' else {}), 'Seed actor ownership differs')
    require(capture['remaining'] == remaining and capture['power_enabled'] is enabled
            and capture['order'] == order and capture['revision'] == revision
            and len(capture['requests']) == order, 'Seed phase/power/order/cache differs')
    require(capture['entities'] == {kind: {'kind': kind.split('-')[0], 'cell': [x, 0]}
                                  for kind, x in [(wheel, -1), ('collector-1', 0), ('belt-1', 1), ('processor-1', 2)]},
            'Seed identities or actual positions differ')
    require(same(capture['parts'], dict.fromkeys(('collector', 'belt', 'processor', 'wheel', 'shaft'), 0)), 'Seed parts differ')
    require(capture['next_ids'] == {'collector': 2, 'belt': 2, 'processor': 2, 'wheel': 3 if name == 'identity-replay' else 2},
            'Seed generation counter changed')
    require(capture['links'] == [['collector-1', 'belt-1'], ['belt-1', 'processor-1']], 'Seed material topology differs')
    require(len(capture['drive_links']) == 3 and {frozenset(x) for x in capture['drive_links']} ==
            {frozenset(x) for x in [(wheel, 'collector-1'), ('collector-1', 'belt-1'), ('belt-1', 'processor-1')]},
            'Seed drive topology differs')


def capture_seed(directory, name, target):
    manifest, produced = read_json(directory / 'manifest.json'), read_json(directory / 'produce.json')
    require(manifest['status'] == produced['status'] == 'pass', 'Seed producer was not accepted')
    for relative in ('model.gd', 'save-tests/checkpoint_file.gd'):
        data = (PROJECT / relative).read_bytes()
        pin = manifest['sources'][relative]
        actual = ('sha256:' + hashlib.sha256(data).hexdigest() if pin.startswith('sha256:') else
                  hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest())
        require(pin == actual, 'Accepted seed Core/Store source no longer matches: ' + relative)
    source = directory / (name + '.save')
    data = capture_resume(source)
    digest = hashlib.sha256(data).hexdigest()
    require(digest == produced['cases'][name]['file_sha256'], 'Accepted seed bytes changed')
    target.write_bytes(data)
    target.chmod(0o400)
    return {'kind': 'accepted_producer_reuse_not_new_host_production', 'source': str(source), 'sha256': digest,
            'manifest_sha256': sha(directory / 'manifest.json'), 'producer_report_sha256': sha(directory / 'produce.json'),
            'core_store_pins': {key: manifest['sources'][key] for key in ('model.gd', 'save-tests/checkpoint_file.gd')}}


def worker(spec):
    run = Path(spec['run'])
    group = ActorGroup(run)
    result = {'status': 'running', 'case': spec['case'], 'worker_pid': os.getpid(), 'worker_pgid': os.getpgrp(),
              'operations': [], 'authorities': []}
    sequences = {'P': 0, 'Q': 0}
    started = time.monotonic()
    try:
        require(os.getpgrp() == os.getpid(), 'Worker is not the helper-owned group leader')

        def launch(role):
            actor = spec['actors'][role]
            process = group.launch(role, actor['command'], actor['project'], dict(os.environ, **actor['environment']))
            require(os.getpgid(process.pid) == os.getpgrp(), 'Actor escaped the owned process group')
            return process

        def authority(number, previous=None):
            role = 'authority-' + str(number)
            actor = spec['actors'][role]
            directory = Path(actor['directory'])
            incoming = directory / 'incoming.factory'
            if previous:
                incoming.write_bytes(Path(previous['persistence']['save_file']).read_bytes())
            else:
                incoming.write_bytes(Path(spec['seed']).read_bytes())
            incoming.chmod(0o400)
            process = launch(role)
            group.wait(lambda: (directory / 'ready.json').exists())
            ready = read_json(directory / 'ready.json')
            require(ready['pid'] == process.pid and ready['clock_frozen'] is (number < 3), 'Wrong authority/clock readiness')
            require(ready['persistence']['resume']['accepted'] is True
                    and ready['persistence']['resume']['source_sha256'] == sha(incoming), 'Actual Store did not restore captured input')
            if previous:
                require(same(ready['persistence']['loaded_checkpoint'], previous['checkpoint']), 'Restart changed the full actual checkpoint')
            else:
                seed_oracle(ready['persistence']['loaded_checkpoint'], spec['case'])
            result['authorities'].append({'role': role, 'ready': ready})
            return role, directory, ready

        def send(roles, operation, payload=None):
            for role in roles:
                sequences[role] += 1
                publish(run / role / 'controls/control.json', {'sequence': sequences[role], 'operation': operation, 'payload': payload or {}})
            paths = {role: run / role / f'controls/ack-{sequences[role]}.json' for role in roles}
            group.wait(lambda: all(path.exists() for path in paths.values()))
            values = {role: read_json(path) for role, path in paths.items()}
            for role, value in values.items():
                require(value['status'] == 'pass' and not value['failures'] and value['data']['live_model'] is False,
                        'Real transport operation failed or client owns a Model')
                ledger(value['data']['snapshot'])
            result['operations'].append({'roles': roles, 'operation': operation, 'payload': payload, 'responses': values})
            return {role: value['data'] for role, value in values.items()}

        def stop_authority(role, directory):
            group.actors[role]['expected_exit'] = True
            (directory / 'stop').touch()
            group.wait(lambda: group.actors[role]['process'].poll() is not None)
            report = read_json(directory / 'report.json')
            require(group.actors[role]['process'].returncode == 0 and report['status'] == 'pass', 'Authority failed its actual save/stop')
            persisted = report['persistence']
            require(persisted['accepted'] is True and persisted['save']['accepted'] is True and persisted['input_preserved'] is True,
                    'Actual Store publication refused')
            output = Path(persisted['save_file'])
            require(sha(output) == persisted['saved_sha256'] and not Path(str(output) + '.pending').exists(), 'Published checkpoint is absent/corrupt/pending')
            require(sha(Path(persisted['resume_input'])) == persisted['input_sha256'], 'Host changed its captured input')
            result['authorities'][-1]['report'] = report
            return report

        def lost():
            deadline = time.monotonic() + 10
            while True:
                values = send(('P', 'Q'), 'snapshot')
                if all(not value['ready'] for value in values.values()):
                    return values
                require(time.monotonic() < deadline, 'Clients did not observe real server loss')

        def rejoin(before, ready):
            values = send(('P', 'Q'), 'join')
            for role, value in values.items():
                require(value['namespace'] != before[role]['namespace'] and value['request_sequence'] == 0
                        and value['context'] == ready['context'] and value['ready'], 'Rejoin lost identity/context/fresh caller namespace')
            return values

        def port_released():
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as released:
                released.bind(('127.0.0.1', spec['port']))

        first, first_dir, initial = authority(1)
        for role in ('P', 'Q'):
            launch(role)
        group.wait(lambda: all((run / role / 'controls/ready.json').exists() for role in ('P', 'Q')))
        initial_clients = send(('P', 'Q'), 'snapshot')
        require(all(v['context'] == initial['context'] and v['ready'] for v in initial_clients.values()), 'Peers did not join the restored real authority')
        saved1 = stop_authority(first, first_dir)
        require(saved1['tick_count'] == 0 and same(saved1['checkpoint'], initial['persistence']['loaded_checkpoint']), 'Frozen host changed restored work')
        require(saved1['persistence']['saved_sha256'] == spec['seed_sha256'], 'Literal frozen Store roundtrip changed encoded bytes')
        disconnected = lost()
        port_released()

        second, second_dir, ready2 = authority(2, saved1)
        rejoin(disconnected, ready2)
        if spec['case'] == 'identity-replay':
            refused = send(('P',), 'submit', {'action': 'connect_drive', 'from': 'wheel-1', 'to': 'collector-1'})['P']['outcome']
            require(refused['accepted'] is False and refused['reason'] == 'missing_entity', 'Retired identity retargeted its replacement')
        action = {'action': 'retrieve', 'entity': 'processor-1'} if spec['case'] == 'blocked' else {'action': 'set_power', 'active': True}
        fresh = send(('Q',), 'submit', action)['Q']
        require(fresh['queued']['queued'] is True and fresh['queued']['accepted'] is False
                and fresh['outcome']['accepted'] is True and fresh['outcome']['duplicate'] is False, 'Fresh resumed command was not actually admitted')
        saved2 = stop_authority(second, second_dir)
        require(saved2['tick_count'] == 0, 'Frozen command/capture branch advanced factory time')
        old = saved1['checkpoint']
        current = saved2['checkpoint']
        extra = 2 if spec['case'] == 'identity-replay' else 1
        require(current['order'] == old['order'] + extra and len(current['requests']) == len(old['requests']) + extra
                and current['revision'] == old['revision'] + 1, 'Fresh command/cache/order capture differs')
        require(all(same(current[key], old[key]) for key in ('context', 'entities', 'parts', 'links', 'drive_links', 'next_ids', 'remaining')),
                'Capture changed unrelated identity/topology/held phase')
        if spec['case'] == 'blocked':
            stock = dict(old['stock'], output=0)
            require(current['stock'] == stock and current['inventories'] == {'Q': 1}, 'Actual resumed retrieval was lost or duplicated')
        else:
            require(current['stock'] == old['stock'] and current['inventories'] == old['inventories']
                    and current['power_enabled'] is True, 'Power command consumed/misattributed retained material')
        require(all(same(record, current['requests'][key]) for key, record in old['requests'].items()), 'Host save forgot old cached dispositions')
        disconnected = lost()
        port_released()

        third, third_dir, ready3 = authority(3, saved2)
        rejoin(disconnected, ready3)
        stale = send(('Q',), 'old_namespace')['Q']['outcome']
        require(stale['accepted'] is False and stale['reason'] == 'stale_namespace', 'Old applied request was replayed after host restore')
        retrievals = 0
        deadline = time.monotonic() + 150
        while True:
            observed = send(('Q',), 'snapshot')['Q']['snapshot']
            if observed['stock']['player'] == 16:
                break
            require(time.monotonic() < deadline, 'Actual restored host did not finish retained production')
            if observed['stock']['output']:
                outcome = send(('Q',), 'submit', {'action': 'retrieve', 'entity': 'processor-1'})['Q']['outcome']
                require(outcome['accepted'] is True and outcome['duplicate'] is False, 'Real continued retrieval refused/duplicated')
                retrievals += 1
        repeated = send(('Q',), 'retry')['Q']['outcome']
        require(repeated['accepted'] is True and repeated['duplicate'] is True, 'Within-connection exact retry lost its cached disposition')
        final = send(('P', 'Q'), 'snapshot')
        expected_inventory = {'P': 1, 'Q': 15} if spec['case'] == 'identity-replay' else {'Q': 16}
        for value in final.values():
            snapshot = value['snapshot']
            require(snapshot['inventories'] == expected_inventory and all(snapshot['stock'][key] == 0
                    for key in ('source', 'collector', 'belt', 'input', 'held', 'output')), 'Independent final actor/material locations differ')
        for role in ('P', 'Q'):
            group.actors[role]['expected_exit'] = True
        send(('P', 'Q'), 'finish')
        group.wait(lambda: all(group.actors[role]['process'].poll() is not None for role in ('P', 'Q')))
        saved3 = stop_authority(third, third_dir)
        require(saved3['tick_count'] > 0 and saved3['snapshot']['inventories'] == expected_inventory
                and saved3['checkpoint']['order'] == current['order'] + retrievals
                and len(saved3['checkpoint']['requests']) == len(current['requests']) + retrievals,
                'Live host cache/capture contains extra old replay or lost admitted work')
        require(all(same(record, saved3['checkpoint']['requests'][key]) for key, record in current['requests'].items()),
                'Live continuation rewrote previously captured dispositions')
        port_released()
        result.update(status='pass', retrievals=retrievals, final=saved3['snapshot'], listener_released=True)
    except BaseException as error:
        result.update(status='fail', error=str(error))
        raise
    finally:
        try:
            group.close()
        except BaseException as error:
            result.update(status='fail', cleanup_error=str(error))
            raise
        finally:
            result.update(actors=group.evidence(), peak_live_engines=group.peak_live, elapsed_seconds=time.monotonic() - started)
            publish(run / 'cohort.json', result)
    print('SHARED_CHECKPOINT_PASS', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True, help='explicit accepted producer directory; inputs are preserved')
    parser.add_argument('--case', choices=(*CASES, 'all'), default='all')
    parser.add_argument('--negative', action='store_true', help='run only expected pre-admission refusal controls')
    args = parser.parse_args()
    require(args.godot.is_absolute() and args.godot.resolve() == args.godot and args.godot.is_file()
            and os.access(args.godot, os.X_OK) and sha(args.godot) == args.sha256, 'Use the existing verified executable/SHA pin')
    artifacts = args.artifacts
    require(artifacts.is_absolute() and artifacts.resolve() == artifacts and not artifacts.is_relative_to(ROOT), 'Use an owned external artifact root')
    artifacts.mkdir(parents=True, exist_ok=True, mode=0o700)
    ownership = subprocess.run(['git', '-C', str(artifacts), 'rev-parse', '--is-inside-work-tree', '--is-inside-git-dir'], capture_output=True, text=True, timeout=5)
    require(not (ownership.returncode == 0 and 'true' in ownership.stdout.splitlines()), 'Artifacts must remain outside Git')
    require(shutil.disk_usage(artifacts).free >= 22 * 1024**3 and bounds.owned_bytes(artifacts) < MAX_BYTES, 'Insufficient floor/headroom or retained evidence allowance')
    require(args.fixtures.is_absolute() and args.fixtures.resolve() == args.fixtures, 'Use an explicit accepted fixture directory')
    run = Path(tempfile.mkdtemp(prefix='checkpoints-', dir=artifacts))
    receipt = {'status': 'running', 'revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
               'mode': 'authority_checkpoint_diagnostic_not_ui', 'source_hashes': {}, 'runner_hashes': {}, 'cases': {}, 'stages': [],
               'binary': str(args.godot), 'binary_sha256': args.sha256, 'fixture_source': str(args.fixtures)}
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    deadline = time.monotonic() + 1800
    print('Shared host checkpoint evidence: ' + str(run), flush=True)
    try:
        def execute(name, command, project, environment, timeout, expected_exit=0):
            result = bounds.execute_bounded(command, cwd=project, env=environment, log=run / (name + '.log'),
                                            artifacts=artifacts, timeout=min(timeout, deadline - time.monotonic()))
            receipt['stages'].append({'name': name, 'command': command, 'exit': result.returncode,
                                      'expected_exit': expected_exit})
            require(result.returncode == expected_exit, 'Stage exit differs: ' + name)
            if expected_exit == 0:
                require('ERROR:' not in (run / (name + '.log')).read_text(errors='replace'), 'Stage failed: ' + name)
        execute('version', [str(args.godot), '--version'], ROOT, os.environ.copy(), 15)
        require((run / 'version.log').read_text().strip() == '4.7.2.stable.official.ed1daf0bf', 'Unsupported runtime version')
        originals = {name: (PROJECT / name).read_bytes() for name in SOURCES}
        require(all(not (PROJECT / name).is_symlink() for name in SOURCES)
                and sum(map(len, originals.values())) <= 2 * 1024**2, 'Unsafe/oversized source copy')
        receipt['source_hashes'] = {name: hashlib.sha256(data).hexdigest() for name, data in originals.items()}
        runner_dir = run / 'runners'
        runner_dir.mkdir()
        for name in RUNNERS:
            (runner_dir / name).write_bytes((ROOT / 'scripts' / name).read_bytes())
            receipt['runner_hashes'][name] = sha(runner_dir / name)

        projects = []

        def prepare(directory, label):
            project = directory / 'project'
            for relative, data in originals.items():
                target = project / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            environment = {}
            for variable, folder in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('TMPDIR', 'tmp')]:
                path = directory / folder
                path.mkdir()
                environment[variable] = str(path)
            projects.append(project)
            execute(label + '-import', [str(args.godot), '--headless', '--editor', '--path', str(project), '--import'],
                    project, dict(os.environ, **environment), 120)
            return project, environment

        if args.negative:
            controls = run / 'controls'
            controls.mkdir()
            seed = controls / 'accepted-seed.factory'
            provenance = capture_seed(args.fixtures, 'paused', seed)
            receipt['negative_seed'] = provenance
            project, environment = prepare(controls, 'controls')
            execute('produce-controls', [str(args.godot), '--headless', '--path', str(project), '--script',
                    'res://opening-session/checkpoint_controls.gd', '--', '--output-dir=' + str(controls)],
                    project, dict(os.environ, **environment), 15)
            require('CHECKPOINT_CONTROLS_READY' in (run / 'produce-controls.log').read_text(), 'Real Core control production did not finish')
            receipt['valid_incompatible_controls'] = {name: sha(controls / (name + '.factory')) for name in ('neutral', 'actor')}
            receipt['refusals'] = {}
            for name in ('corrupt', 'truncated', 'neutral', 'actor', 'old-output', 'input-is-output',
                         'pending-file', 'pending-directory', 'lifecycle-collision', 'outside-run',
                         'input-observe-response', 'input-report-buffer', 'input-status-buffer',
                         'output-report-buffer', 'output-ready-buffer', 'output-observe-buffer', 'pending-lifecycle'):
                directory = run / name
                directory.mkdir()
                incoming, output = directory / 'incoming.factory', directory / 'worksite.factory'
                if name == 'input-report-buffer': incoming = directory / 'report.json.writing'
                elif name == 'input-status-buffer': incoming = directory / 'status.json.writing'
                data = seed.read_bytes()
                if name == 'corrupt': data = data[:-1] + bytes([data[-1] ^ 1])
                elif name == 'truncated': data = data[:-3]
                elif name in ('neutral', 'actor'): data = (controls / (name + '.factory')).read_bytes()
                incoming.write_bytes(data)
                incoming.chmod(0o400)
                preserved = {incoming: sha(incoming)}
                pending = Path(str(output) + '.pending')
                reason = 'resume_refused:integrity_mismatch' if name in ('corrupt', 'truncated') else 'incompatible_opening'
                if name == 'old-output':
                    output.write_bytes(seed.read_bytes())
                    preserved[output] = sha(output)
                elif name == 'input-is-output':
                    output = incoming
                elif name == 'pending-file':
                    pending.write_bytes(b'owned pending collision sentinel')
                    preserved[pending] = sha(pending)
                elif name == 'pending-directory':
                    pending.mkdir()
                    (pending / 'sentinel').write_bytes(b'owned pending directory sentinel')
                    preserved[pending / 'sentinel'] = sha(pending / 'sentinel')
                if name in ('old-output', 'input-is-output', 'pending-file', 'pending-directory'):
                    reason = 'save_destination_or_pending_exists'
                ready, status, report, stop = (directory / path for path in ('ready.json', 'status.json', 'report.json', 'stop'))
                observation = []
                if name == 'lifecycle-collision':
                    output, reason = report, 'checkpoint_path_conflicts_with_lifecycle'
                elif name == 'outside-run':
                    output, reason = controls / 'outside.factory', 'checkpoint_path_outside_owned_run'
                elif name in ('input-observe-response', 'input-report-buffer', 'input-status-buffer',
                              'output-report-buffer', 'output-ready-buffer', 'output-observe-buffer', 'pending-lifecycle'):
                    reason = 'checkpoint_path_conflicts_with_lifecycle'
                    if name == 'input-observe-response':
                        observation = ['--observe-request=' + str(directory / 'observe-request.json'), '--observe-response=' + str(incoming)]
                    elif name == 'output-report-buffer': output = Path(str(report) + '.writing')
                    elif name == 'output-ready-buffer': output = Path(str(ready) + '.writing')
                    elif name == 'output-observe-buffer':
                        output = directory / 'observe-response.json.writing'
                        observation = ['--observe-response=' + str(directory / 'observe-response.json')]
                    elif name == 'pending-lifecycle': report = Path(str(output) + '.pending')
                protected = (incoming, output, Path(str(output) + '.pending'))
                suppress_report = report in protected or Path(str(report) + '.writing') in protected
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as candidate:
                    candidate.bind(('127.0.0.1', 0))
                    port = candidate.getsockname()[1]
                command = [str(args.godot), '--headless', '--path', str(project), '--script', 'res://opening-session/server.gd',
                           '--', '--legacy-fixture', '--session-port=' + str(port), '--ready-file=' + str(ready), '--status-file=' + str(status),
                           '--report-file=' + str(report), '--stop-file=' + str(stop), '--resume-input=' + str(incoming),
                           '--save-file=' + str(output), *observation]
                execute('refuse-' + name, command, project, dict(os.environ, **environment), 10, expected_exit=1)
                text = (run / ('refuse-' + name + '.log')).read_text()
                raw = None if suppress_report else read_json(report)
                if suppress_report:
                    require('HOST_CHECKPOINT_REPORT_SUPPRESSED' in text
                            and (report in preserved or not report.exists()), 'Unsafe refusal diagnostic was published: ' + name)
                else:
                    require(raw['status'] == 'fail' and raw['ready'] is False and raw['persistence']['accepted'] is False
                            and raw['persistence']['reason'] == reason, 'Wrong actual refusal: ' + name)
                require(not ready.exists() and not status.exists() and 'OPENING_SESSION_SERVER_READY' not in text,
                        'Refused authority admitted a fresh fallback: ' + name)
                require(text.count('ERROR:') == 1 and 'ERROR: Host checkpoint refused: ' + reason in text,
                        'Expected refusal masked another engine error: ' + name)
                require(all(path.is_file() and sha(path) == digest for path, digest in preserved.items()),
                        'Refusal damaged an earlier input/output/sentinel: ' + name)
                require(output in preserved or output == report or not output.exists(), 'Refusal published an output: ' + name)
                if raw is not None:
                    require(type(raw['pid']) is int and not Path('/proc', str(raw['pid'])).exists(), 'Refused authority still lives')
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as released:
                    released.bind(('127.0.0.1', port))
                receipt['refusals'][name] = {'expectation': 'matched', 'expected_product_status': 'fail', 'raw_report': raw,
                        'diagnostic_report_suppressed': suppress_report, 'stderr_refusal': 'Host checkpoint refused: ' + reason,
                        'preserved': {str(path): digest for path, digest in preserved.items()}, 'listener_released': True}
            require(sha(seed) == provenance['sha256'] == sha(Path(provenance['source'])), 'Original accepted seed changed')

        for name in (() if args.negative else CASES if args.case == 'all' else (args.case,)):
            case_dir = run / name
            case_dir.mkdir()
            seed = case_dir / 'accepted-seed.factory'
            provenance = capture_seed(args.fixtures, name, seed)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as candidate:
                candidate.bind(('127.0.0.1', 0))
                port = candidate.getsockname()[1]
            spec = {'run': str(case_dir), 'case': name, 'port': port, 'seed': str(seed), 'seed_sha256': sha(seed), 'actors': {}}
            for role in ('authority-1', 'authority-2', 'authority-3', 'P', 'Q'):
                directory = case_dir / role
                project, environment = prepare(directory, name + '-' + role)
                command = [str(args.godot), '--headless', '--path', str(project), '--script',
                           'res://opening-session/server.gd' if role.startswith('authority') else 'res://opening-session/transport_check.gd',
                           '--', '--legacy-fixture', '--session-port=' + str(port)]
                if role.startswith('authority'):
                    if role != 'authority-3': command += ['--frozen-clock']
                    command += ['--ready-file=' + str(directory / 'ready.json'), '--status-file=' + str(directory / 'status.json'),
                                '--report-file=' + str(directory / 'report.json'), '--stop-file=' + str(directory / 'stop'),
                                '--resume-input=' + str(directory / 'incoming.factory'), '--save-file=' + str(directory / 'worksite.factory')]
                else:
                    (directory / 'controls').mkdir()
                    command += ['--session-role=' + role, '--control-dir=' + str(directory / 'controls')]
                spec['actors'][role] = {'project': str(project), 'directory': str(directory), 'environment': environment, 'command': command}
            spec_path = case_dir / 'spec.json'
            publish(spec_path, spec)
            execute(name + '-cohort', [sys.executable, '-B', str(runner_dir / 'check_shared_checkpoint.py'), '--worker', str(spec_path)],
                    ROOT, os.environ.copy(), 240)
            cohort = read_json(case_dir / 'cohort.json')
            require(cohort['status'] == 'pass' and cohort['peak_live_engines'] == 3
                    and all(actor['exit'] == 0 and actor['reaped'] and actor['pgid_at_launch'] == cohort['worker_pgid']
                            for actor in cohort['actors'].values()), 'Authority/client lifetime evidence differs')
            require(sha(seed) == provenance['sha256'] == sha(Path(provenance['source'])), 'Original accepted seed changed')
            receipt['cases'][name] = {'seed': provenance, 'cohort': cohort}
        for project in projects:
            for relative, digest in receipt['source_hashes'].items():
                require(sha(project / relative) == digest, 'Runtime changed copied source')
        require(sha(args.godot) == args.sha256, 'Pinned executable changed')
        require(all(sha(runner_dir / name) == digest for name, digest in receipt['runner_hashes'].items()), 'Captured runner changed')
        receipt['status'] = 'pass'
    except BaseException as error:
        receipt.update(status='fail', error=str(error))
        raise
    finally:
        receipt['owned_bytes'] = bounds.owned_bytes(artifacts)
        publish(run / 'result.json', receipt)
    print('Shared checkpoint passed; evidence=' + str(run), flush=True)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--worker':
        worker(read_json(Path(sys.argv[2])))
    else:
        main()
