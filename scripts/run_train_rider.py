#!/usr/bin/env python3
"""Bounded coupled-carriage passenger probe; invoke through run_local.py heavy."""
import math
from pathlib import Path

import run_rider as shared

require, near, vector = shared.require, shared.near, shared.vector
IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def relative(frame, body='deck'):
    return [a - b for a, b in zip(frame['player']['position'], frame[body]['position'])]


def distance(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def verify(report):
    require(report['status'] == 'pass' and not report['failures'] and report['checks'] > 500, 'actual coupled-carriage input report')
    cases = report['cases']
    require(set(cases) == {'initial', 'boarded', 'front_end', 'cross_before', 'cross_after', 'rear_end', 'home', 'air', 'landed', 'off', 'wall'},
            'all actual train-like passenger cases')
    requests = {(f['player']['id'], f['ticks']): f for f in report['provisional_frames']}
    frames = report['frames']
    completed = {(f['player']['id'], f['ticks']): f for f in frames}
    require(100 < len(frames) < 2000 and len(frames) == len(completed) == len(requests)
            == len(report['provisional_frames']) == report['observed_moves'] and requests.keys() == completed.keys(),
            'every actual input target has exactly one native completion')
    seeds = {'front_standing': relative(cases['boarded']), 'rear_standing': relative(cases['cross_after'], 'auxiliary')}
    identities = {name: (cases['boarded'][name]['id'], cases['boarded'][name]['rid']) for name in ('player', 'deck', 'auxiliary')}
    require(len({rid for _, rid in identities.values()}) == 3, 'genuinely separate player and two native carriage bodies')
    previous_tick = None
    pending = {}
    crossing_floors = []
    for frame in frames:
        state, deck, rear, player = frame['state'], frame['deck'], frame['auxiliary'], frame['player']
        request = requests[(player['id'], frame['ticks'])]
        require(frame['scene'] == 'res://train/main.tscn' and frame['requested_id'] == player['id']
                and frame['requested_tick'] == frame['observer_tick'] == frame['ticks']
                and frame['observed_engine_frame'] == frame['engine_frame'] + 1
                and vector(frame['requested_position'], request['player']['node_position'])
                and vector(player['position'], frame['requested_position']) and vector(player['position'], player['node_position'])
                and vector(player['position'], frame['player_mesh']), 'exact prior-input player/native epoch')
        require(previous_tick is None or frame['ticks'] == previous_tick + 1, 'no missing native carriage or player ticks')
        previous_tick = frame['ticks']
        require(frame['observer_state']['committed'] == state['committed'] and frame['observer_state']['phases'] == state['phases'],
                'fresh native result does not hide intervening phase advancement')
        for name in identities:
            require((frame[name]['id'], frame[name]['rid']) == identities[name], 'same three bodies throughout board/cross/ride/leave')
        require(player['shape_type'] == 4 and near(player['shape_data']['radius'], 0.3)
                and near(player['shape_data']['height'], 1.8) and player['layer'] == 16 and player['mask'] == 5
                and frame['follow_layers'] == 4, 'unchanged native player capsule and follow filter')
        count = state['committed']
        angle = count * math.pi / 16
        require(state['teeth'] == 40 and state['coupled'] and state['idler'] and near(state['source_phase'], count * math.pi / 8)
                and near(state['phases']['B'], angle) and near(state['phases']['U'], angle), 'one unchanged fixed positive 20:40 phase owner')
        for body, offset in ((deck, 0), (rear, 3)):
            require(body['shape_type'] == 3 and vector(body['shape_data'], [1.5, 0.175, 1.5])
                    and body['layer'] == 4 and body['mask'] == 1
                    and all(vector(a, b) for a, b in zip(body['basis'], IDENTITY))
                    and vector(body['position'], [offset + 2 * math.sin(angle), 0.75, 0])
                    and vector(body['position'], body['node_position']), 'both actual native boxes follow their literal straight path')
        require(vector([a - b for a, b in zip(rear['position'], deck['position'])], [3, 0, 0]),
                'native carriage spacing remains fixed throughout the cycle')
        if state['native_pending'] and count:
            pending.setdefault(count, []).append(frame['ticks'])
        if not state['native_pending']:
            require(state['completed']['committed'] == count and vector(state['completed']['positions']['B'], deck['position'])
                    and vector(state['completed']['positions']['U'], rear['position']), 'completed packet belongs to both actual native carriages')
        if frame['stage'] in seeds:
            body = deck if frame['stage'] == 'front_standing' else rear
            require(frame['on_floor'] and frame['floor_id'] == body['id'], 'standing support retains its genuine native carriage')
            error = distance(relative(frame, 'deck' if body is deck else 'auxiliary'), seeds[frame['stage']])
            bound = 0.015
            if state['native_pending']:
                bound += abs(2 * math.sin(angle) - 2 * math.sin(angle - math.pi / 16))
            require(error <= bound, 'standing local pose follows the declared completed/pending native boundary')
        if frame['stage'] == 'crossing':
            require(frame['on_floor'] and frame['floor_id'] in (deck['id'], rear['id'])
                    and any(c['id'] == frame['floor_id'] and c['normal'][1] > 0.9 for c in frame['collisions']),
                    'each crossing input has actual native support from one of the separate carriages')
            crossing_floors.append(frame['floor_id'])
    require(set(pending) == set(range(1, 33)), 'all thirty-two source goals expose their native completion handoff')
    for count, ticks in pending.items():
        require(len(ticks) == 1, 'one retained pending tick per discrete native goal')
        after = completed.get((cases['boarded']['player']['id'], ticks[0] + 1))
        require(after is not None and not after['state']['native_pending'] and after['state']['committed'] == count,
                'both native bodies complete that same goal on the next input epoch')
    for name, count, x in (('front_end', 8, 2), ('rear_end', 24, -2), ('home', 32, 0)):
        case = cases[name]
        require(case['state']['committed'] == count and near(case['deck']['position'][0], x)
                and near(case['auxiliary']['position'][0], x + 3), 'literal physical reversal/home ' + name)
    require(crossing_floors[0] == cases['boarded']['deck']['id'] and crossing_floors[-1] == cases['boarded']['auxiliary']['id'],
            'real floor identity changes from B to U across the moving joint')
    before, after = cases['cross_before'], cases['cross_after']
    for frame, body_name in ((before, 'deck'), (after, 'auxiliary')):
        body = frame[body_name]
        floor_contacts = {c['id'] for c in frame['collisions'] if c['normal'][1] > 0.9}
        require(floor_contacts == {body['id']} and frame['floor_id'] == body['id']
                and abs(relative(frame, body_name)[0]) < 1.5 - 0.3,
                'exclusive native support windows lie beyond the capsule radius from the ambiguous joint')
    own = 2 * (after['walking_seconds'] - before['walking_seconds'])
    actual = relative(after)[0] - relative(before)[0]
    require(before['state']['committed'] == 8 and 8 < after['state']['committed'] < 24 and own > 2.5
            and abs(actual - own) < 0.02 and after['floor_id'] == after['auxiliary']['id'],
            'actual walk input crosses while source Repeat moves both carriages, without extra carry impulse')
    require(len(report['advanced_events']) == 32, 'every actual source completion event is observed once')
    for event in report['advanced_events']:
        for body, branch, mesh in (('deck', 'B', 'deck_mesh'), ('auxiliary', 'U', 'trailing_mesh')):
            require(vector(event[body]['position'], event['state']['completed']['positions'][branch])
                    and vector(event[body]['position'], event[mesh]), 'both meshes consume the exact same completed native packet')
    require(20 < len(report['view_frames']) <= len(frames), 'actual view clock is separate from the complete physics trace')
    for view in report['view_frames']:
        require(vector(view['player']['position'], view['player_mesh']), 'actual player view matches its native collider')
        state = view['state']
        if state['completed']:
            require(vector(view['deck_mesh'], state['completed']['positions']['B'])
                    and vector(view['trailing_mesh'], state['completed']['positions']['U'])
                    and view['deck_visible'] and view['trailing_visible'], 'visible coupled carriages share one completed packet')
        support = {view['deck']['id']: 'carriage B', view['auxiliary']['id']: 'carriage U', view['ground_id']: 'ground'}.get(view['floor_id'], 'air')
        require('Feet: ' + support in view['view_status'] and ' · ' + str(state['completed'].get('committed', 0)) + ' completed steps' in view['view_status'],
                'actual support and completed goal count are presented truthfully')
    require(not cases['air']['on_floor'] and cases['air']['player']['position'][1] > 2.5
            and cases['landed']['floor_id'] == cases['boarded']['auxiliary']['id'], 'actual jump and landing on the same rear carriage')
    require(cases['off']['floor_id'] == cases['off']['ground_id'] and near(cases['wall']['player']['position'][0], 8.575, 0.015),
            'real step-off and native wall collision beyond the assembly envelope')


def main():
    files = shared.FILES + tuple('train/' + name for name in ('authority.gd', 'view.gd', 'main.tscn', 'check.gd', 'startup_observer.gd'))
    shared.main(scene_path='res://train/main.tscn', check_script='res://train/check.gd', observer_script='res://train/startup_observer.gd',
                files=files, oracle=verify, comparison_cases=('front_end', 'rear_end', 'home', 'landed', 'off', 'wall'), entry_source=Path(__file__))


if __name__ == '__main__':
    main()
