#!/usr/bin/env python3
"""Bounded native passenger probe; invoke through run_local.py heavy."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

import check_engine_environment as bounds

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'experiments/engine-environment/godot'
FILES = bounds.FILES + ('mechanics/authority.gd',) + tuple('rider/' + name for name in (
    'authority.gd', 'player.gd', 'view.gd', 'main.tscn', 'check.gd', 'startup_observer.gd'))
MAX_BYTES = 256 * 1024**2
VERSION = '4.7.2.stable.official.ed1daf0bf'


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024**2), b''):
            digest.update(chunk)
    return digest.hexdigest()


def require(ok, label):
    if not ok:
        raise ValueError('Rider oracle: ' + label)


def near(a, b, tolerance=0.00002):
    return abs(a - b) <= tolerance


def vector(a, b):
    return len(a) == len(b) and all(near(x, y) for x, y in zip(a, b))


def verify(report):
    require(report['status'] == 'pass' and not report['failures'] and report['checks'] >= 80,
            'actual input/native assertion report')
    cases = report['cases']
    require(set(cases) == {'initial', 'boarded', 'carried', 'walk', 'paused', 'air', 'landed', 'off', 'wall', 'follow_disabled'},
            'boarding/carry/walk/reversal/jump/leave/native-control coverage')
    require(100 < len(report['frames']) < 2000, 'bounded actual player physics-frame observations')
    requests = {(f['player']['id'], f['ticks']): f for f in report['provisional_frames']}
    completed = {(f['player']['id'], f['ticks']): f for f in report['frames']}
    require(len(requests) == len(completed) == report['observed_moves']
            == len(report['provisional_frames']) == len(report['frames'])
            and requests.keys() == completed.keys(), 'every provisional physics tick has exactly one natural completion; no loss/coalescence')
    pending_handoffs = {}
    for frame in report['frames']:
        deck, player, state = frame['deck'], frame['player'], frame['state']
        requested = requests[(player['id'], frame['ticks'])]
        require(frame['requested_tick'] == frame['ticks'] and frame['requested_id'] == player['id']
                and frame['observer_tick'] == frame['ticks']
                and frame['observed_engine_frame'] == frame['engine_frame'] + 1
                and vector(frame['requested_position'], requested['player']['node_position'])
                and vector(player['position'], frame['requested_position']),
                'next physics-frame native query belongs to the exact prior input target, identity and epoch')
        require(frame['state_cut'] == 'requested_player_move_before_its_natural_transform_flush'
                and frame['observer_state']['committed'] == state['committed']
                and frame['observer_state']['phases'] == state['phases'],
                'request state/contact epoch and actual observer state are explicit, with no intervening drive advance')
        require(deck['shape_type'] == 3 and vector(deck['shape_data'], [1.5, 0.175, 1.5])
                and deck['layer'] == 4 and deck['mask'] == 1, 'actual native deck shape/layers')
        capsule = player['shape_data']
        require(player['shape_type'] == 4 and player['layer'] == 16 and player['mask'] == 5,
                'actual native character capsule/layers')
        if isinstance(capsule, dict):
            require(near(capsule['radius'], 0.3) and near(capsule['height'], 1.8), 'raw native capsule parameters')
        else:
            require(vector(sorted(capsule), [0.3, 1.8]), 'raw native capsule parameter pair')
        require(vector(player['position'], player['node_position']) and vector(player['position'], frame['player_mesh']),
                'actual player collider, controller target and displayed mesh agree after natural flush')
        require(near(state['source_phase'], state['committed'] * math.pi / 8)
                and near(state['phases']['B'], state['committed'] * math.pi / 16)
                and near(state['phases']['U'], state['committed'] * math.pi / 16), 'unchanged inherited source law')
        if not state['native_pending']:
            require(vector(deck['position'], [2 * math.sin(state['phases']['B']), 0.75, 0])
                    and vector(state['completed']['positions']['B'], deck['position']),
                    'joined native completed cut verifies actual deck phase/publication in addition to player completion')
        elif state['committed'] > 0:
            key = (player['id'], state['committed'])
            pending_handoffs.setdefault(key, []).append(frame['ticks'])
    for (player_id, committed), ticks in pending_handoffs.items():
        require(len(ticks) == 1, 'native pending handoff occupies at most one observed physics tick per step')
        following = completed.get((player_id, ticks[0] + 1))
        require(following is not None and not following['state']['native_pending']
                and following['state']['committed'] == committed,
                'every pending handoff reaches its own joined completion on the immediately following tick')
    require(20 < len(report['view_frames']) <= report['observed_moves'], 'separate actual view-consumption clock')
    for view in report['view_frames']:
        key = (view['player']['id'], view['ticks'])
        require(key in requests and vector(view['player']['position'], requests[key]['player']['node_position'])
                and vector(view['player']['position'], view['player_mesh']),
                'actual view consumes the latest native player target without deleting physics epochs')
        if not view['state']['native_pending']:
            require(vector(view['deck']['position'], view['state']['completed']['positions']['B'])
                    and vector(view['deck']['position'], view['deck_mesh']),
                    'actual view deck is the completed native deck after its ordinary refresh')
    require(len(report['advanced_events']) == 11, 'all actual Drive-only advancement events observed')
    for event in report['advanced_events']:
        state = event['state']
        expected = [2 * math.sin(state['committed'] * math.pi / 16), 0.75, 0]
        require(event['cut'] == 'drive_only_advanced_before_player_callback'
                and near(state['phases']['B'], state['committed'] * math.pi / 16)
                and near(state['source_phase'], state['committed'] * math.pi / 8)
                and vector(event['deck']['position'], expected)
                and vector(state['completed']['positions']['B'], expected) and vector(event['deck_mesh'], expected),
                'exact Drive advanced event separately verifies phase/count/raw/completed/view deck, not passenger completion')
    boarded, carried = cases['boarded'], cases['carried']
    require(boarded['on_floor'] and boarded['floor_id'] == boarded['deck']['id']
            and cases['initial']['floor_id'] == cases['initial']['ground_id'], 'actual native ground-to-deck boarding')
    relative = boarded['player']['position'][0] - boarded['deck']['position'][0]
    for frame in report['frames']:
        if frame['stage'] == 'standing' and not frame['state']['native_pending']:
            require(frame['on_floor'] and frame['floor_id'] == frame['deck']['id']
                    and near(frame['player']['position'][0] - frame['deck']['position'][0], relative, 0.015),
                    'standing native rider retains deck-relative pose at every joined completed boundary')
            require(near(frame['player']['position'][1] - 0.9, 0.925, 0.015), 'standing feet remain on actual deck top')
    require(carried['state']['committed'] == 8 and near(carried['deck']['position'][0], 2)
            and near(carried['player']['position'][0] - boarded['player']['position'][0], 2, 0.015),
            'first eight half-rate steps physically carry a player two fixture units')
    require(any(f['stage'] == 'standing' and f['platform_velocity'][0] > 0.1 for f in report['frames']),
            'actual native moving-platform velocity was consumed')
    before, after = cases['walk']['before'], cases['walk']['after']
    walked = after['player']['position'][0] - after['deck']['position'][0] - before['player']['position'][0] + before['deck']['position'][0]
    require(after['deck']['position'][0] < before['deck']['position'][0] and walked > 0.2
            and near(walked, 2 * (after['walking_seconds'] - before['walking_seconds']), 0.02),
            'own walk displacement follows actual input duration while deck reverses')
    require(any(f['stage'] == 'walk_reversal' and f['platform_velocity'][0] < -0.1 for f in report['frames']),
            'native reversal velocity rather than a one-way parented ride')
    require(not cases['air']['on_floor'] and cases['air']['player']['position'][1] > 2.5
            and cases['landed']['floor_id'] == boarded['deck']['id'], 'real jump/gravity land on same deck')
    require(cases['off']['floor_id'] == cases['off']['ground_id']
            and near(cases['wall']['player']['position'][0], 4.575, 0.015), 'ordinary movement leaves onto ground and meets fixed wall')
    require(any(c['id'] == f['wall_id'] and c['normal'][0] < -0.99 and near(c['point'][0], 4.875)
                for f in report['frames'] if f['stage'] == 'wall' for c in f['collisions']),
            'actual native wall face/normal proves capsule obstruction')
    for name in ('carried', 'paused', 'air', 'landed', 'off', 'wall'):
        for body in ('player', 'deck'):
            require(cases[name][body]['id'] == boarded[body]['id']
                    and cases[name][body]['rid'] == boarded[body]['rid'], 'no identity reset during carry/leave')
    before, after = cases['follow_disabled']['before'], cases['follow_disabled']['after']
    require(before['follow_layers'] == after['follow_layers'] == 0
            and near(after['player']['position'][0], before['player']['position'][0], 0.015)
            and after['deck']['position'][0] - before['deck']['position'][0] > 0.7,
            'same native controller without platform following stays behind, no scripted carry')


def main(*, scene_path='res://rider/main.tscn', check_script='res://rider/check.gd',
         observer_script='res://rider/startup_observer.gd', files=FILES, oracle=verify,
         comparison_cases=('carried', 'paused', 'air', 'landed', 'off', 'wall'), entry_source=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--duration-seconds', type=int)
    args = parser.parse_args()
    if (args.render and not args.check) or (args.smoke and args.check):
        parser.error('--render requires --check; --smoke selects normal entry separately')
    if args.duration_seconds is not None and (args.check or args.smoke):
        parser.error('--duration-seconds selects normal play only')
    duration = 900 if args.duration_seconds is None else args.duration_seconds
    if not 1 <= duration <= 1700:
        parser.error('Use a bounded 1..1700 second normal session')
    binary, artifacts = args.godot, args.artifacts
    if (not binary.is_absolute() or binary.resolve() != binary or not binary.is_file()
            or not os.access(binary, os.X_OK) or not re.fullmatch('[0-9a-f]{64}', args.sha256)
            or sha(binary) != args.sha256):
        parser.error('Use the existing absolute executable and exact verified lowercase SHA256')
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error('Use an owned external absolute artifact root without symlinks')
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    ownership = subprocess.run(['git', '-C', str(artifacts), 'rev-parse', '--is-inside-work-tree', '--is-inside-git-dir'],
                               env=env, capture_output=True, text=True, timeout=5)
    if ownership.returncode == 0 and 'true' in ownership.stdout.splitlines():
        parser.error('Keep artifacts outside Git worktrees and administration')
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error('Require 22 GiB free and under 256 MiB retained rider evidence')
    run = Path(tempfile.mkdtemp(prefix='rider-', dir=artifacts))
    project = run / 'project'
    receipt = {'status': 'running', 'mode': 'check' if args.check else 'smoke' if args.smoke else 'normal',
               'scene': scene_path, 'check_script': check_script,
               'source_hashes': {}, 'stages': [], 'user_play': 'not_assessed',
               'started': datetime.now(timezone.utc).isoformat(), 'binary': str(binary), 'binary_sha256': args.sha256,
               'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
               'runner_hashes': {'run_rider.py': sha(Path(__file__)), 'check_engine_environment.py': sha(Path(bounds.__file__))}}
    if entry_source is not None:
        receipt['runner_hashes'][Path(entry_source).name] = sha(Path(entry_source))
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    deadline = time.monotonic() + 1800
    print('Rider evidence: ' + str(run), flush=True)
    try:
        total = 0
        for name in files:
            source = PROJECT / name
            require(source.is_file() and not source.is_symlink(), 'safe source ' + name)
            content = source.read_bytes()
            total += len(content)
            require(total <= 2 * 1024**2, 'bounded source copy')
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            receipt['source_hashes'][name] = hashlib.sha256(content).hexdigest()
        for key, name in [('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'), ('TMPDIR', 'tmp')]:
            folder = run / name
            folder.mkdir()
            env[key] = str(folder)

        def execute(name, arguments, marker=None, timeout=60):
            remaining = deadline - time.monotonic()
            require(remaining > 0, '30 minute total allowance')
            log = run / (name + '.log')
            result = bounds.execute_bounded([str(binary), *arguments], cwd=project, env=env, log=log,
                                            artifacts=artifacts, timeout=min(timeout, remaining))
            receipt['stages'].append({'name': name, 'exit': result.returncode, 'arguments': arguments})
            output = log.read_text(errors='replace')
            require(result.returncode == 0 and 'ERROR:' not in output and (not marker or marker in output), name + ' failed; inspect ' + str(log))
            return output

        require(execute('version', ['--version']).strip() == VERSION, 'separately checked supported version')
        execute('import', ['--headless', '--editor', '--path', str(project), '--import'], timeout=180)
        receipt['post_import_config_sha256'] = sha(project / 'project.godot')
        if args.check:
            execute('input', ['--headless', '--path', str(project), '--script', check_script, '--',
                              '--report=' + str(run / 'input.json')], 'RIDER_PASS', 240)
            physical = json.loads((run / 'input.json').read_text())
            oracle(physical)
            if args.render:
                execute('render', ['--path', str(project), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy',
                                   '--script', check_script, '--', '--report=' + str(run / 'render.json'),
                                   '--capture=' + str(run / 'rider.png')], 'RIDER_PASS', 240)
                rendered = json.loads((run / 'render.json').read_text())
                oracle(rendered)
                # Input duration is measured in each actual controller, not
                # assumed identical across headless/rendered process frames.
                for name in comparison_cases:
                    for field in ('phases', 'source_phase', 'committed'):
                        require(physical['cases'][name]['state'][field] == rendered['cases'][name]['state'][field],
                                'consumers agree on inherited drive state at ' + name)
                require((run / 'rider.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), 'actual standing-rider PNG')
        else:
            arguments = ['--path', str(project), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', scene_path]
            if args.smoke:
                config = project / 'project.godot'
                config.write_text(config.read_text() + '\n[autoload]\nRiderStartupObserver="*' + observer_script + '"\n')
                receipt['instrumentation'] = {'kind': 'read_only_startup_autoload', 'runtime_config_sha256': sha(config),
                                              'observer_sha256': receipt['source_hashes'][observer_script.removeprefix('res://')]}
                arguments += ['--', '--observer-report=' + str(run / 'startup.json'), '--observer-capture=' + str(run / 'startup.png')]
            try:
                execute('normal', arguments, 'RIDER_STARTUP_PASS' if args.smoke else None, 30 if args.smoke else duration)
                receipt['completion_reason'] = 'window_closed'
            except subprocess.TimeoutExpired:
                if args.smoke:
                    raise
                receipt['completion_reason'] = 'duration_limit'
            if args.smoke:
                observed = json.loads((run / 'startup.json').read_text())
                require(observed['status'] == 'pass' and observed['scene'] == scene_path
                        and observed['floor_id'] == observed['ground_id'], 'ordinary positional startup, actual grounded player')
        receipt['status'] = 'pass' if args.check or args.smoke else 'closed'
    except BaseException as error:
        receipt.update(status='fail', error=str(error))
        raise
    finally:
        receipt.update(finished=datetime.now(timezone.utc).isoformat(), owned_bytes=bounds.owned_bytes(artifacts))
        (run / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Rider finished: ' + str(run), flush=True)


if __name__ == '__main__':
    main()
