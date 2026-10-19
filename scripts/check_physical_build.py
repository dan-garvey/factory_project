#!/usr/bin/env python3
"""Bounded Model/Store controls; synthetic actor samples are not character proof.

Invoke through run_local.py heavy. Ordinary character/two-client validation is
separate and must use the same frozen authority and native producer.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

import check_engine_environment as bounds
from check_opening_session import ActorGroup, publish, read_json

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'experiments/engine-environment/godot'
FILES = (*bounds.FILES, 'save-tests/checkpoint_file.gd', 'opening/reach_check.gd')
RUNNERS = ('check_physical_build.py', 'check_engine_environment.py', 'check_opening_session.py')
MAX_BYTES = 256 * 1024**2
PIN = '8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e'
VERSION = '4.7.2.stable.official.ed1daf0bf'
PRELOAD = re.compile(r'''(?:preload\s*\(\s*|extends\s*)["']res://([^"']+)["']''')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_inputs(project=PROJECT, files=FILES):
    """Check literal import closure of the ACTUAL minimal copied sources.

    This catches an omitted Model dependency before import; it does not replace
    Godot parsing or claim to resolve dynamic loads in unrelated consumers.
    """
    if len(files) != len(set(files)):
        raise ValueError('Duplicate source input')
    originals = {}
    for name in files:
        path = project / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Missing regular source input: ' + name)
        originals[name] = path.read_bytes()
    if sum(map(len, originals.values())) > 2 * 1024**2:
        raise ValueError('Source allowance exceeded')
    for name, content in originals.items():
        if name.endswith('.gd'):
            for dependency in PRELOAD.findall(content.decode('utf-8')):
                if dependency not in originals:
                    raise ValueError('Missing copied dependency: ' + dependency + ' (from ' + name + ')')
    return originals


def verify(report):
    if (report.get('status') != 'pass' or report.get('kind') != 'synthetic_actor_authority_controls_not_native_character_proof'
            or type(report.get('checks')) is not int or report['checks'] < 60 or report.get('failures') != []
            or type(report.get('pid')) is not int or report['pid'] < 1):
        raise ValueError('Missing actual successful authority controls')
    cases = report.get('cases', {})
    required = {'cache_and_independent_actors', 'equality', 'outside', 'three_dimensional_height',
                'reversed_drive_receipts', 'finite_production_and_retrieval', 'legacy_refusal',
                'actor_occupied_refusals', 'roster_boundaries', 'cached_accepted_historical'}
    if set(cases) != required:
        raise ValueError('Missing declared authority case')
    if (cases['equality'].get('accepted') is not True or cases['outside'].get('reason') != 'out_of_reach'
            or cases['legacy_refusal'] != {'accepted': False, 'reason': 'physical_state_required'}):
        raise ValueError('Boundary or explicit legacy refusal differs')
    for state in (value for value in cases.values() if 'stock' in value):
        stock, pockets = state['stock'], state['inventories']
        if (state['schema'] != 2 or state['options'] != {'opening': True, 'physical': True}
                or any(type(x) is not int or x < 0 for x in (*stock.values(), *pockets.values()))
                or sum(stock.values()) + sum(pockets.values()) != 16):
            raise ValueError('Typed finite custody/profile differs')


def worker(spec):
    directory = Path(spec['directory'])
    group = ActorGroup(directory)
    receipt = {'status': 'running', 'worker_pid': os.getpid(), 'worker_pgid': os.getpgrp()}
    stop = []
    handlers = {number: signal.signal(number, lambda number, _frame: stop.append(number))
                for number in (signal.SIGINT, signal.SIGTERM)}
    code = 0
    try:
        if os.getpid() != os.getpgrp():
            raise ValueError('Worker must own the helper process group')
        engine = group.launch('authority', spec['command'], spec['project'], dict(os.environ, **spec['environment']))
        group.actors['authority']['expected_exit'] = True
        deadline = time.monotonic() + 90
        while engine.poll() is None:
            group.pump()
            if stop:
                raise InterruptedError('Owned authority controls interrupted')
            if time.monotonic() >= deadline:
                raise TimeoutError('Authority controls deadline')
        if engine.returncode:
            raise ValueError('Actual authority engine failed')
        report = read_json(Path(spec['report']))
        if report.get('pid') != engine.pid:
            raise ValueError('Authority report belongs to a different process')
        verify(report)
        receipt['status'] = 'pass'
    except BaseException as error:
        receipt.update(status='fail', error=repr(error))
        code = 1
    finally:
        try:
            group.close()
        except BaseException as error:
            receipt.update(status='fail', error=repr(error))
            code = 1
        finally:
            for number, handler in handlers.items():
                signal.signal(number, handler)
            receipt.update(actors=group.evidence(), peak_live_engines=group.peak_live)
            publish(directory / 'lifetime.json', receipt)
    return code


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    args = parser.parse_args(argv)
    if (args.sha256 != PIN or not args.godot.is_absolute() or args.godot.resolve() != args.godot
            or not args.godot.is_file() or not os.access(args.godot, os.X_OK) or sha(args.godot) != PIN):
        parser.error('Use the existing supported absolute executable and exact verified SHA256')
    artifacts = args.artifacts
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error('Use an owned external artifact directory without symlinks')
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    ownership = subprocess.run(['git', '-C', str(artifacts), 'rev-parse', '--is-inside-work-tree', '--is-inside-git-dir'],
                               capture_output=True, text=True, timeout=5)
    if ownership.returncode == 0 and 'true' in ownership.stdout.splitlines():
        parser.error('Keep evidence outside Git')
    import shutil
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error('Require22GiB free and less than256MiB retained evidence')
    run = Path(tempfile.mkdtemp(prefix='authority-', dir=artifacts))
    project = run / 'project'
    project.mkdir()
    receipt = {'status': 'running', 'revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
               'binary_sha256': PIN, 'source_hashes': {}, 'runner_hashes': {}, 'stages': [],
               'scope': 'synthetic actor samples / actual Model+Store; no native character acceptance'}
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    deadline = time.monotonic() + 1800
    code = 0
    try:
        originals = source_inputs()
        for name, data in originals.items():
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            receipt['source_hashes'][name] = sha(target)
        runners = run / 'runners'
        runners.mkdir()
        for name in RUNNERS:
            target = runners / name
            target.write_bytes((ROOT / 'scripts' / name).read_bytes())
            receipt['runner_hashes'][name] = sha(target)
        environment = {}
        for key, name in (('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('TMPDIR', 'tmp')):
            target = run / name
            target.mkdir()
            environment[key] = str(target)

        def execute(name, command, cwd, timeout):
            result = bounds.execute_bounded(command, cwd=cwd, env=dict(os.environ, **environment), log=run / (name + '.log'), artifacts=artifacts,
                                            timeout=min(timeout, deadline - time.monotonic()))
            receipt['stages'].append({'name': name, 'command': command, 'exit': result.returncode})
            if result.returncode or 'ERROR:' in (run / (name + '.log')).read_text(errors='replace'):
                raise ValueError('Stage failed: ' + name)

        execute('version', [str(args.godot), '--version'], project, 15)
        if (run / 'version.log').read_text().strip() != VERSION:
            raise ValueError('Unsupported engine version')
        execute('import', [str(args.godot), '--headless', '--editor', '--path', str(project), '--import'], project, 120)
        spec = {'directory': str(run), 'project': str(project), 'environment': environment,
                'report': str(run / 'report.json'), 'command': [str(args.godot), '--headless', '--path', str(project),
                '--script', 'res://opening/reach_check.gd', '--', '--reach-report=' + str(run / 'report.json'), '--reach-directory=' + str(run)]}
        publish(run / 'spec.json', spec)
        execute('authority-controls', [sys.executable, '-B', str(runners / RUNNERS[0]), '--worker', str(run / 'spec.json')], ROOT, 95)
        life = read_json(run / 'lifetime.json')
        actor = life['actors']['authority']
        if (life['status'] != 'pass' or life['peak_live_engines'] != 1 or not actor['reaped'] or actor['exit'] != 0
                or actor['pgid_at_launch'] != life['worker_pgid']):
            raise ValueError('Actual engine lifetime differs')
        try:
            os.killpg(life['worker_pgid'], 0)
        except ProcessLookupError:
            receipt['group_gone'] = True
        else:
            raise ValueError('Owned native process group survived')
        for name, digest in receipt['source_hashes'].items():
            if sha(project / name) != digest:
                raise ValueError('Runtime source changed: ' + name)
        for name, digest in receipt['runner_hashes'].items():
            if sha(runners / name) != digest:
                raise ValueError('Captured runner changed: ' + name)
        if sha(args.godot) != PIN:
            raise ValueError('Pinned executable changed')
        report = read_json(run / 'report.json')
        verify(report)
        receipt.update(status='pass', report_sha256=sha(run / 'report.json'), checks=report['checks'], lifetime=life)
    except BaseException as error:
        receipt.update(status='fail', error=repr(error))
        code = 1
    finally:
        receipt['owned_bytes'] = bounds.owned_bytes(artifacts)
        publish(run / 'result.json', receipt)
        print('Physical authority controls ' + receipt['status'] + ': ' + str(run), flush=True)
    return code


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--worker':
        sys.exit(worker(read_json(Path(sys.argv[2]))))
    sys.exit(main())
