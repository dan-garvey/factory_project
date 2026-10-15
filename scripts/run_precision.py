#!/usr/bin/env python3
"""Bounded later-control precision fixture; invoke through run_local.py heavy."""
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
FILES = bounds.FILES + tuple('precision/' + name for name in (
    'authority.gd', 'controller.gd', 'view.gd', 'check.gd', 'oracles.gd', 'observer.gd', 'main.tscn'))
RUNNERS = ('run_precision.py', 'check_engine_environment.py', 'check_opening_session.py')
MAX_BYTES = 256 * 1024**2
VERSION = '4.7.2.stable.official.ed1daf0bf'
INPUTS = {'exact': (2, 1, 0), 'missing': (2, 0, 0), 'insufficient': (1, 1, 0),
          'surplus': (3, 1, 0), 'unlisted': (2, 1, 1), 'substitution': (1, 1, 1)}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(value, message):
    if not value:
        raise ValueError('Precision oracle: ' + message)


def verify(report, mode):
    """Independent literal quantities/coverage; never simulate the processor."""
    expected = {prefix + name for name in INPUTS for prefix in ('manual_', 'automatic_')} | {'phase_backpressure'}
    if mode == 'ordinary_scene_input': expected.add('circuit_checkbox')
    require(report['status'] == 'pass' and not report['failures'] and report['checks'] > 1000
            and report['mode'] == mode and set(report['cases']) == expected, 'native completion/coverage')
    for row in report['events']:
        state = row['state']
        require(type(state['owner']) is int and state['owner'] != 0, 'actual opaque owner identity')
        totals = dict.fromkeys(('A', 'B', 'X'), 0)
        for location in ('source', 'input', 'held', 'returns', 'reject'):
            stock = state['locations'][location]
            require(set(stock) == set(totals), 'material identities at actual holder')
            for material, count in stock.items():
                require(type(count) is int and count >= 0, 'typed nonnegative raw stock')
                totals[material] += count
        for field in ('output', 'finished', 'current_job', 'output_job', 'next_job', 'remaining'):
            require(type(state[field]) is int and state[field] >= 0, 'typed job/product counters')
        totals['A'] += 2 * (state['output'] + state['finished'])
        totals['B'] += state['output'] + state['finished']
        require(totals == {'A': 8, 'B': 4, 'X': 1}, 'literal species ledger including C = 2A + B')
        ids = state['finished_jobs'] + ([state['output_job']] if state['output_job'] else []) + ([state['current_job']] if state['current_job'] else [])
        require(sorted(ids) == list(range(1, state['next_job'])) and all(type(value) is int for value in ids), 'unique retained job generations')
        if row['kind'] == 'step' and row['event']['started']:
            require(row['event']['started'] == {'A': 2, 'B': 1, 'X': 0}, 'whole exact bill captured')
    for name, values in INPUTS.items():
        for prefix in ('manual_', 'automatic_'):
            case = report['cases'][prefix + name]
            require(case['same_owner'] is True and case['before']['owner'] == case['final']['owner'], 'recovery replaced owner/reset invalid state')
            require(case['before']['locations']['input'] == dict(zip(('A', 'B', 'X'), values)), 'actual initial case differs')
            final = case['final']
            count = 1 if prefix == 'manual_' else 4
            require(final['finished'] == count and final['finished_jobs'] == list(range(1, count + 1))
                    and final['output'] == final['current_job'] == final['remaining'] == 0, 'actual finite completion differs')
        if name in ('surplus', 'unlisted', 'substitution'):
            held = report['cases']['automatic_' + name]['meter_only']
            require(held and held['output'] == held['finished'] == held['current_job'] == 0, 'metering alone bypassed invalid input')
    blocked = report['cases']['phase_backpressure']['blocked']
    require(blocked['current_job'] == 2 and blocked['output_job'] == 1 and blocked['remaining'] == 0
            and blocked['locations']['held'] == {'A': 2, 'B': 1, 'X': 0}, 'actual blocked held phase')
    if mode == 'ordinary_scene_input':
        require(report['scene'] == 'res://precision/main.tscn' and report['view_script'] == 'res://precision/view.gd'
                and report['authority_script'] == 'res://precision/authority.gd', 'ordinary actual scene/owner')
        require({item['name'] for item in report['captures']} == {'wrong-retained', 'automatic-four-products', 'paused-held-output'}, 'real capture coverage')
        for item in report['captures']:
            require(Path(item['path']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), 'actual PNG')
            for location in ('source', 'input', 'held', 'returns', 'reject'):
                require(item['visible'][location] == item['state']['locations'][location], 'visible native tokens disagree with material owner')
            require(all(item['visible'][location] == item['state'][location] for location in ('output', 'finished')), 'visible products disagree with material owner')


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
    parser.add_argument('--duration-seconds', type=int, default=900, help='ordinary interactive run limit 1..900')
    args = parser.parse_args()
    if args.render and not args.check: parser.error('--render requires --check')
    if not 1 <= args.duration_seconds <= 900: parser.error('--duration-seconds must be1..900')
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
    run = Path(tempfile.mkdtemp(prefix='precision-', dir=artifacts))
    receipt = {'schema': 1, 'status': 'running', 'revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
               'started': datetime.now(timezone.utc).isoformat(), 'binary': str(binary), 'binary_sha256': args.sha256,
               'source_hashes': {}, 'runner_hashes': {}, 'stages': [], 'modes': {}, 'user_play': 'not_assessed'}
    print('Precision fixture evidence: ' + str(run), flush=True)
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
        modes = [('headless', 'headless_authority')] if args.check else [('interactive', 'ordinary_interactive')]
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
                config.write_bytes(before + b'\n[autoload]\nPrecisionObserver="*res://precision/observer.gd"\n')
                instrumentation = {'kind': 'copied_post_import_autoload', 'post_import_config_sha256': hashlib.sha256(before).hexdigest(),
                                   'runtime_config_sha256': sha(config), 'observer_sha256': receipt['source_hashes']['precision/observer.gd']}
            command = [str(binary), '--path', str(project)]
            if name == 'headless': command += ['--headless', '--script', 'res://precision/check.gd']
            else: command += ['res://precision/main.tscn', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
            captures = directory / 'captures'
            captures.mkdir()
            report = directory / 'report.json'
            command += ['--', '--precision-seconds=' + str(120 if args.check else args.duration_seconds)]
            if args.check: command += ['--precision-report=' + str(report), '--precision-captures=' + str(captures)]
            spec = {'run': str(directory), 'project': str(project), 'command': command, 'environment': environment,
                    'timeout': 150 if args.check else args.duration_seconds + 15, 'check': args.check, 'mode': mode, 'report': str(report)}
            spec_path = directory / 'spec.json'
            publish(spec_path, spec)
            receipt['modes'][name] = {'spec': spec, 'instrumentation': instrumentation}
            execute(name + '-runtime', [sys.executable, '-B', str(runners / 'run_precision.py'), '--worker', str(spec_path)], ROOT, os.environ.copy(), spec['timeout'] + 5)
            lifetime = read_json(directory / 'lifetime.json')
            require(lifetime['peak_live_engines'] == 1 and lifetime['status'] in ('pass', 'completed')
                    and all(actor['exit'] == 0 and actor['reaped'] and actor['pgid_at_launch'] == lifetime['worker_pgid'] for actor in lifetime['actors'].values()), 'one actual reaped engine in its owned group')
            receipt['modes'][name]['lifetime'] = lifetime
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
    print('Precision fixture ' + receipt['status'] + '; evidence=' + str(run), flush=True)
    return code


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--worker':
        worker(read_json(Path(sys.argv[2])))
    else:
        sys.exit(main())
