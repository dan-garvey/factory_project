#!/usr/bin/env python3
"""Native rotary passenger probe; invoke through run_local.py heavy."""
import math
from pathlib import Path

import run_rider as shared

require, near, vector = shared.require, shared.near, shared.vector
ANGLE = math.pi / 16
SUBDIVISIONS = 24


def basis(angle):
    c, s = math.cos(angle), math.sin(angle)
    return [[c, 0, -s], [0, 1, 0], [s, 0, c]]


def matrix(a, b):
    return len(a) == len(b) == 3 and all(vector(x, y) for x, y in zip(a, b))


def local(frame):
    relative = [x - y for x, y in zip(frame['player']['position'], frame['deck']['position'])]
    return [sum(x * y for x, y in zip(column, relative)) for column in frame['deck']['basis']]


def distance(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def verify(report):
    require(report['status'] == 'pass' and not report['failures'] and report['checks'] > 500, 'actual rotary input report')
    cases = report['cases']
    require(set(cases) == {'initial', 'boarded', 'positive8', 'positive32', 'walk', 'air', 'landed', 'off', 'wall',
                          'negative_seed', 'negative8', 'disabled_before', 'disabled_after'}, 'all rotary cases')
    requests = {(f['player']['id'], f['ticks']): f for f in report['provisional_frames']}
    frames = report['frames']
    completed = {(f['player']['id'], f['ticks']): f for f in frames}
    require(len(requests) == len(completed) == len(frames) == report['observed_moves']
            == len(report['provisional_frames']) and requests.keys() == completed.keys()
            and 100 < len(frames) < 2000, 'every actual physics target has exactly one native completion')
    seeds = {cases[name]['player']['id']: local(cases[name]) for name in ('boarded', 'negative_seed')}
    for seed in seeds.values():
        require(0.3 <= math.hypot(seed[0], seed[2]) <= 0.5, 'real nonzero off-axis standing witness')
    previous = {}
    pending = {}
    for frame in frames:
        state, deck, player = frame['state'], frame['deck'], frame['player']
        key = (player['id'], frame['ticks'])
        request = requests[key]
        require(frame['scene'] == 'res://rotary/main.tscn' and frame['requested_id'] == player['id']
                and frame['requested_tick'] == frame['observer_tick'] == frame['ticks']
                and frame['observed_engine_frame'] == frame['engine_frame'] + 1
                and vector(frame['requested_position'], request['player']['node_position'])
                and vector(player['position'], frame['requested_position'])
                and vector(player['position'], player['node_position']) and vector(player['position'], frame['player_mesh']),
                'actual native player/target/mesh belongs to the precise prior input epoch')
        require(frame['observer_state']['committed'] == state['committed']
                and frame['observer_state']['phases'] == state['phases'], 'no intervening source phase hidden by observer')
        require(deck['shape_type'] == 3 and vector(deck['shape_data'], [1.5, 0.175, 1.5])
                and deck['layer'] == 4 and deck['mask'] == 1 and vector(deck['position'], [0, 0.75, 0]), 'actual fixed-centre native box')
        require(all(near(sum(component ** 2 for component in column), 1, 0.000001) for column in deck['basis']),
                'declared unit-size deck does not accumulate native basis scale drift')
        require(player['shape_type'] == 4 and player['layer'] == 16 and player['mask'] == 5
                and near(player['shape_data']['radius'], 0.3) and near(player['shape_data']['height'], 1.8), 'unchanged native player capsule')
        count = state['committed']
        sign = 1 if state['idler'] else -1
        goal = sign * count * ANGLE
        require(near(state['source_phase'], count * math.pi / 8) and near(state['phases']['B'], goal)
                and near(state['phases']['U'], count * ANGLE) and state['teeth'] == 40, 'unchanged signed goal phase owner')
        motion = state['motion']
        start = sign * (count - 1) * ANGLE if count else 0
        expected = start + (goal - start) * motion['ticks'] / SUBDIVISIONS
        require(motion['subdivisions'] == SUBDIVISIONS and 0 <= motion['ticks'] <= SUBDIVISIONS
                and near(motion['from'], start) and near(motion['goal'], goal)
                and near(motion['requested_angle'], expected) and matrix(deck['basis'], basis(expected)),
                'every native substep follows the declared operating trajectory, separate from its goal')
        measured = math.atan2(-deck['basis'][0][2], deck['basis'][0][0])
        if player['id'] in previous:
            prior, prior_angle, unwrapped = previous[player['id']]
            delta = math.atan2(math.sin(measured - prior_angle), math.cos(measured - prior_angle))
            require(abs(delta) <= ANGLE / SUBDIVISIONS + 0.00002 and frame['ticks'] == prior['ticks'] + 1,
                    'no missing angle/target tick or angular teleport')
            unwrapped += delta
        else:
            unwrapped = measured
        require(near(unwrapped, expected), 'signed unwrapped native winding reconstructed from every actual basis')
        previous[player['id']] = (frame, measured, unwrapped)
        if state['native_pending'] and count:
            pending.setdefault((player['id'], count), []).append(frame['ticks'])
        if not state['native_pending']:
            require(matrix(deck['basis'], basis(goal)) and matrix(state['completed']['basis'], deck['basis']), 'completed native goal really reached')
        if frame['stage'] in ('standing_positive', 'standing_negative'):
            require(frame['on_floor'] and frame['floor_id'] == deck['id']
                    and distance(local(frame), seeds[player['id']]) <= 0.015,
                    'actual local standing pose and native floor support hold THROUGH every substep, including pending')
    for (player_id, count), ticks in pending.items():
        require(len(ticks) <= 25 and ticks == list(range(ticks[0], ticks[-1] + 1)), 'bounded contiguous native operating handoff')
        after = completed.get((player_id, ticks[-1] + 1))
        require(after is not None and not after['state']['native_pending'] and after['state']['committed'] == count,
                'operating goal reaches its own following native completion')
    for name, count, angle in [('positive8', 8, math.pi / 2), ('positive32', 32, 2 * math.pi), ('negative8', 8, -math.pi / 2)]:
        case = cases[name]
        require(case['state']['committed'] == count and near(case['state']['phases']['B'], angle)
                and matrix(case['deck']['basis'], basis(angle)), 'quarter/full/reversed actual turn ' + name)
    require(any(f['stage'] == 'standing_positive' and f['platform_angular_velocity'][1] > 0.1 for f in frames)
            and any(f['stage'] == 'standing_negative' and f['platform_angular_velocity'][1] < -0.1 for f in frames),
            'native angular floor velocity actually consumed in both directions')
    require(len(report['advanced_events']) == 43, 'all manual and overlapping real source advancement events observed')
    for event in report['advanced_events']:
        goal = event['state']['phases']['B']
        require(matrix(event['deck']['basis'], basis(goal)) and matrix(event['state']['completed']['basis'], basis(goal))
                and matrix(event['deck_mesh_basis'], basis(goal)), 'exact Drive event native/published/displayed goal basis')
    require(20 < len(report['view_frames']) <= len(frames), 'separate view clock')
    for view in report['view_frames']:
        require(vector(view['player']['position'], view['player_mesh']), 'actual player view and collider agree')
        if view['deck_visible']:
            require(vector(view['deck']['position'], view['deck_mesh']) and matrix(view['deck']['basis'], view['deck_mesh_basis']),
                    'live actual native operating deck is displayed during pending turns')
        require(' · ' + str(view['state']['completed'].get('committed', 0)) + ' completed steps' in view['view_status'],
                'queued goal is never labelled finished')
    before, after = cases['walk']['before'], cases['walk']['after']
    require(after['floor_id'] == after['deck']['id'] and after['walking_seconds'] > before['walking_seconds'] + 0.3,
            'actual walk input remains independent during native turning')
    require(distance(local(after), local(before)) > 0.3, 'walk input changes actual position relative to the moving deck')
    own = [0.0, 0.0]
    carried = [0.0, 0.0]
    for tick in range(before['ticks'] + 1, after['ticks'] + 1):
        frame = completed[(before['player']['id'], tick)]
        require(frame['floor_id'] == frame['deck']['id'], 'every walking input retains native deck support')
        for axis, index in [(0, 0), (1, 2)]:
            own[axis] += frame['input'][axis] * 2 * frame['delta']
            carried[axis] += frame['platform_velocity'][index] * frame['delta']
    actual = [after['player']['position'][i] - before['player']['position'][i] for i in (0, 2)]
    require(distance(actual, [x + y for x, y in zip(own, carried)]) <= 0.02,
            'world walk displacement follows actual input duration plus measured native platform motion')
    require(not cases['air']['on_floor'] and cases['air']['player']['position'][1] > 2.5
            and cases['landed']['floor_id'] == cases['boarded']['deck']['id'], 'actual jump and native landing on same rotating deck')
    require(cases['off']['floor_id'] == cases['off']['ground_id'] and near(cases['wall']['player']['position'][0], 4.575, 0.015),
            'real leave and fixed boundary collision remain supported')
    for name in ('positive8', 'positive32', 'air', 'landed', 'off', 'wall'):
        for body in ('player', 'deck'):
            require(cases[name][body]['id'] == cases['boarded'][body]['id']
                    and cases[name][body]['rid'] == cases['boarded'][body]['rid'], 'no body reset to fabricate carry')
    a, b = cases['disabled_before'], cases['disabled_after']
    require(a['follow_layers'] == b['follow_layers'] == 0 and distance(a['player']['position'], b['player']['position']) <= 0.015
            and matrix(b['deck']['basis'], basis(ANGLE)), 'native follow-filter contrast, not parenting or manual compensation')


def main():
    files = shared.FILES + tuple('rotary/' + name for name in ('authority.gd', 'view.gd', 'main.tscn', 'check.gd', 'startup_observer.gd'))
    shared.main(scene_path='res://rotary/main.tscn', check_script='res://rotary/check.gd',
                observer_script='res://rotary/startup_observer.gd', files=files, oracle=verify,
                comparison_cases=('positive8', 'positive32', 'negative8', 'landed', 'off', 'wall', 'disabled_after'),
                entry_source=Path(__file__))


if __name__ == '__main__':
    main()
