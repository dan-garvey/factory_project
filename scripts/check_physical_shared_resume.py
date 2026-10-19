#!/usr/bin/env python3
"""Two real P/Q normal-launcher sessions: create a physical save, then reopen it.

The unchanged public launcher owns admission children, imports, logs, capture,
ActorGroup and host shutdown. This controller calls its ordinary main twice;
it adds no nested wrapper, helper, game model or process supervisor.
"""
import argparse
from contextlib import contextmanager
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import socket
import subprocess
import tempfile

import run_shared_opening as normal

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'experiments/engine-environment/godot'
OBSERVER = PROJECT / 'opening-session/physical_resume_observer.gd'
PHASE_ENV = 'FACTORY_PHYSICAL_RESUME_PHASE'
RUNNERS = ('check_physical_shared_resume.py', 'run_shared_opening.py',
           'check_opening_session.py', 'check_engine_environment.py', 'run_opening.py')
ROLES = ('P', 'Q')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return normal.read_json(Path(path))


def write(path, value):
    normal.publish(Path(path), value)


def validate_checkpoint(value):
    """Literal probe oracle, not a substitute for Core/Store validation."""
    require(type(value.get('schema')) is int and value['schema'] == 2
            and value.get('options') == {'opening': True, 'physical': True},
            'Require actual physical schema2 checkpoint')
    require(set(value.get('actors', {})) == set(ROLES), 'Require exactly the declared P/Q roster')
    for actor in value['actors'].values():
        require(set(actor) == {'position', 'capabilities'} and actor['capabilities'] == {'build_reach': 4.0},
                'Persist only declared pose/capability, never runtime readiness or input')
        position = actor['position']
        require(type(position) is list and len(position) == 3
                and all(type(n) in (int, float) and math.isfinite(n) for n in position), 'Finite saved pose')
    quantities = list(value['stock'].values()) + list(value['inventories'].values())
    require(all(type(n) is int and n >= 0 for n in quantities) and sum(quantities) == 16,
            'Typed finite custody16')
    require(type(value.get('initial_feed')) is int and value['initial_feed'] == 16
            and type(value.get('recipe_input')) is int and value['recipe_input'] == 1,
            'Original typed fixture quantities')
    require(value['stock'] == {'source': 16, 'collector': 0, 'belt': 0, 'input': 0, 'held': 0, 'output': 0}
            and value['inventories'] == {} and value['remaining'] == 0, 'No hidden processing or inventory credit')
    require(value['entities'] == {'collector-1': {'kind': 'collector', 'cell': [0, 0]}}
            and value['links'] == value['drive_links'] == [], 'Actual ordinary placement retained')
    require(all(type(n) is int and n >= 0 for n in (*value['parts'].values(), *value['next_ids'].values()))
            and value['parts'] == {'collector': 0, 'belt': 1, 'processor': 1, 'wheel': 1, 'shaft': 3}
            and value['next_ids'] == {'collector': 2, 'belt': 1, 'processor': 1, 'wheel': 1},
            'Actual parts and generation counters retained')
    require(type(value['order']) is int and value['order'] == 2 and len(value['requests']) == 2,
            'Both original actual request outcomes retained')
    by_actor = {record['intent']['client']: record for record in value['requests'].values()}
    require(set(by_actor) == set(ROLES), 'One original request from each real participant')
    for actor, accepted, reason in (('P', True, 'placed'), ('Q', False, 'out_of_reach')):
        record = by_actor[actor]
        require(record['intent']['action'] == 'place' and record['intent']['kind'] == 'collector'
                and record['intent']['cell'] == [0, 0] and record['result']['accepted'] is accepted
                and record['result']['reason'] == reason, 'Actual nearby/far history: ' + actor)


def compare_continuation(saved, loaded, final):
    validate_checkpoint(saved)
    validate_checkpoint(loaded)
    validate_checkpoint(final)
    require(loaded == saved, 'Actual Store-loaded checkpoint must equal the original host capture')
    before, after = deepcopy(saved), deepcopy(final)
    # The live material clock and ordinary floor settling are not frozen.
    before.pop('revision'); after.pop('revision')
    for actor in ROLES:
        before['actors'][actor].pop('position')
        after['actors'][actor].pop('position')
    require(before == after, 'Read-only reopen changed history, identity, parts, capability or material')


def validate_native(server, saved=None):
    checkpoint = server['checkpoint']
    preflight = server['persistence']['native_preflight']
    require(server['physical_ready'] is True and not server['actor_error']
            and preflight.get('accepted') is True, 'Actual native save preflight accepted')
    samples = server['native_actors']['samples']
    require(set(samples) == set(ROLES), 'Actual native P/Q bodies reported')
    for role in ROLES:
        sample = samples[role]
        require(sample['registered'] is True and sample['ready'] is True
                and sample['space'] == sample['expected_space'] and sample['body_ticks'] > 0,
                'Registered stepped native body: ' + role)
        require(sample['position'] == checkpoint['actors'][role]['position']
                and sample['control'] == [0., 0.] and sample['jump_queued'] is False
                and sample['on_floor'] is True, 'Released actual floor pose at save: ' + role)
        if saved is not None:
            require(sample['seed'] == saved['actors'][role]['position'], 'Fresh producer seeded from real saved pose: ' + role)
            require(all(abs(a - b) <= .001 for a, b in zip(sample['position'], sample['seed'])),
                    'Read-only native floor settling stays within declared contact allowance')
    require(samples['P']['body_id'] != samples['Q']['body_id'] and samples['P']['rid'] != samples['Q']['rid'],
            'Two distinct bodies within this server lifetime')


@contextmanager
def observer_phase(value):
    previous = os.environ.get(PHASE_ENV)
    os.environ[PHASE_ENV] = value
    try:
        yield
    finally:
        if previous is None:
            os.environ.pop(PHASE_ENV, None)
        else:
            os.environ[PHASE_ENV] = previous


def source_capture(directory):
    revision = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    require(not subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain']), 'Freeze a clean committed candidate first')
    sources = {PROJECT / name: 'experiments/engine-environment/godot/' + name for name in normal.FILES}
    sources.update({ROOT / 'scripts' / name: 'scripts/' + name for name in RUNNERS})
    sources[OBSERVER] = str(OBSERVER.relative_to(ROOT))
    pins = {}
    for path, relative in sources.items():
        data = normal.regular_bytes(path, 2 * 1024**2)
        raw = subprocess.check_output(['git', '-C', str(ROOT), 'show', revision + ':' + relative])
        require(raw == data, 'Raw Git/source agreement: ' + relative)
        target = directory / 'sources' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        pins[relative] = hashlib.sha256(data).hexdigest()
    return {'revision': revision, 'pins': pins}


def unchanged(capture):
    require(subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip() == capture['revision'],
            'Source revision changed during the two normal sessions')
    for relative, digest in capture['pins'].items():
        require(normal.sha(ROOT / relative) == digest, 'Source changed during actual consumer: ' + relative)


def run_phase(directory, capture, phase, args, observer, resume=None):
    unchanged(capture)
    previous = set(directory.glob('shared-*'))
    argv = ['--godot', str(args.godot), '--sha256', args.sha256, '--artifacts', str(directory),
            '--clients', '2', '--smoke', '--observer', str(observer), '--save-on-close', '--duration-seconds', '60']
    if resume is not None:
        argv += ['--resume', str(resume)]
    write(directory / (phase + '-precommand.json'), {'public_launcher': 'scripts/run_shared_opening.py',
          'arguments': argv, 'observer_environment_override': {PHASE_ENV: phase}, 'source': capture})
    with observer_phase(phase):
        code = normal.main(argv)
    created = set(directory.glob('shared-*')) - previous
    require(len(created) == 1, 'One actual normal-launcher family per declared phase')
    run = created.pop()
    receipt = read(run / 'result.json')
    write(directory / (phase + '-command-result.json'), {'exit': code, 'run': str(run), 'result_sha256': normal.sha(run / 'result.json')})
    require(code == 0 and receipt['status'] == 'pass', 'FIRST actual normal phase failed: ' + phase)
    server = read(run / 'server-report.json')
    require(receipt['physical_profile'] is True and receipt['roles'] == list(ROLES)
            and receipt['observer']['default'] is False, 'Declared instrumented normal physical consumer')
    require(receipt['observer']['sha256'] == normal.sha(observer), 'Actual captured observer bytes')
    require(all(item['exit'] == 0 for item in receipt['stages']), 'Every actual normal-launcher stage passed')
    cohort = receipt['cohort']
    require(cohort['status'] == 'pass' and cohort['peak_live_engines'] == 3, 'Actual server plus two normal windows')
    require(all(item['exit'] == 0 and item['reaped'] and item['pgid_at_launch'] == cohort['worker_pgid']
                for item in cohort['actors'].values()), 'Original normal ActorGroup owns/reaps every process')
    require(cohort['worker_pid'] == cohort['worker_pgid'], 'Existing worker owns its process group')
    pids = [cohort['worker_pid'], *(item['pid'] for item in cohort['actors'].values())]
    require(all(not Path('/proc', str(pid)).exists() for pid in pids), 'Original normal processes are absent before continuation')
    for proc in Path('/proc').glob('[0-9]*'):
        try:
            require(os.getpgid(int(proc.name)) != cohort['worker_pgid'], 'Original normal worker group must be gone')
        except ProcessLookupError:
            pass
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as released:
        released.bind(('127.0.0.1', receipt['port']))
    for role in ROLES:
        observation = cohort['observations'][role]
        require(observation['phase'] == phase, 'Actual observer phase recorded')
        if phase == 'produce':
            movement = observation['movement']
            require(movement['stable_observations'] == 3 and movement['held_keys'] == [], 'Released ordinary movement observed')
            distance = sum((movement['after'][i] - movement['before'][i]) ** 2 for i in (0, 2))
            require(distance >= .04, 'Actual server-confirmed body moved: ' + role)
        else:
            require(observation['movement'] == observation['placement'] == {}
                    and observation['view']['sequence'] == 0, 'Fresh reopened observers are read-only')
    require(server['clock_frozen'] is False and server['tick_count'] > 0, 'Normal live server, no replacement material clock')
    validate_checkpoint(server['checkpoint'])
    validate_native(server)
    if phase == 'produce':
        require(all(server['native_actors']['samples'][role]['controls'] >= 2 for role in ROLES),
                'Both actual native producers received movement and zero-direction input')
    saved = Path(receipt['saved_checkpoint']['file'])
    require(saved == run / 'worksite.factory' and normal.sha(saved) == receipt['saved_checkpoint']['sha256']
            and not Path(str(saved) + '.pending').exists(), 'Actual original Store publication')
    unchanged(capture)
    return {'phase': phase, 'run': str(run), 'result_sha256': normal.sha(run / 'result.json'),
            'server_report_sha256': normal.sha(run / 'server-report.json'), 'checkpoint_file': str(saved),
            'checkpoint_sha256': normal.sha(saved), 'old_pids_absent': pids, 'old_group_absent': True,
            'listener_released': True}, receipt, server


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    args = parser.parse_args(argv)
    if not args.artifacts.is_absolute() or args.artifacts.resolve() != args.artifacts or not args.artifacts.is_dir():
        parser.error('Use an existing owned absolute artifact directory without symlinks')
    check = subprocess.run(['git', '-C', str(args.artifacts), 'rev-parse', '--is-inside-work-tree', '--is-inside-git-dir'],
                           capture_output=True, text=True)
    if check.returncode == 0 and 'true' in check.stdout.splitlines():
        parser.error('Keep artifacts outside Git worktrees/administration')
    directory = Path(tempfile.mkdtemp(prefix='pq-resume-', dir=args.artifacts))
    report = {'status': 'running', 'started': datetime.now(timezone.utc).isoformat(), 'phases': [],
              'user_play': 'not_assessed', 'scope': 'actual normal P/Q physical host save and fresh process reopen',
              'envelopes': {'sequential_public_launches': 2, 'peak_engines': 3,
                            'existing_public_launcher_seconds_each': 1800, 'whole_family_bytes': normal.MAX_BYTES},
              'limits': ['Captured injected ordinary input is instrumentation, not human play.',
                         'No native velocity/jump continuity or cross-process numeric RID inequality claim.',
                         'No new supervisor/helper/ActorGroup, and no direct game pose/capability mutation.']}
    code = 1
    try:
        report['source'] = source_capture(directory)
        observer = directory / 'sources' / OBSERVER.relative_to(ROOT)
        first, first_receipt, first_server = run_phase(directory, report['source'], 'produce', args, observer)
        report['phases'].append(first)
        original = Path(first['checkpoint_file'])
        original_data = normal.capture_resume(original)
        second, second_receipt, second_server = run_phase(directory, report['source'], 'resume', args, observer, original)
        report['phases'].append(second)
        require(normal.capture_resume(original) == original_data, 'Original actual save input unchanged')
        loaded = second_receipt['cohort']['ready']['persistence']['loaded_checkpoint']
        compare_continuation(first_server['checkpoint'], loaded, second_server['checkpoint'])
        validate_native(second_server, first_server['checkpoint'])
        require(second_server['checkpoint']['revision'] == loaded['revision'] + second_server['tick_count'],
                'Only the actual new live material ticks advance the resumed revision')
        require(first_server['pid'] != second_server['pid'], 'Observed distinct actual host process lifetimes')
        for role in ROLES:
            old = first_receipt['cohort']['observations'][role]
            new = second_receipt['cohort']['observations'][role]
            require(old['pid'] != new['pid'] and old['view']['namespace'] != new['view']['namespace'], 'Fresh actual client/namespace lifetime')
        report.update(status='pass', original_checkpoint_sha256=hashlib.sha256(original_data).hexdigest(),
                      original_input_preserved=True, loaded_checkpoint_matches=True,
                      body_seeds={role: second_server['native_actors']['samples'][role]['seed'] for role in ROLES})
        code = 0
    except BaseException as error:
        report.update(status='interrupted' if isinstance(error, KeyboardInterrupt) else 'fail', error=str(error))
        code = 130 if isinstance(error, KeyboardInterrupt) else 1
    finally:
        report.update(finished=datetime.now(timezone.utc).isoformat(), owned_bytes=normal.bounds.owned_bytes(directory))
        write(directory / 'result.json', report)
        print(json.dumps({'status': report['status'], 'run': str(directory), 'error': report.get('error')}), flush=True)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
