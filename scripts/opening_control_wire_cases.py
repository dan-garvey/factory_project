"""Actual malformed/stale movement RPCs through the existing physical client.

The test-only client hook emits ordinary Session RPCs, or calls the existing
jump/release API pair. It cannot set a server pose, capability or time step.
The shared supervisor owns processes, files, transport and admission. This is
transport evidence; ordinary keyboard teaching and the full character feature
have separate consumers. No intermediate native queued-jump sample is implied.
"""
from copy import deepcopy
import math
import time


class ControlWireFailure(AssertionError):
    def __init__(self, message, report):
        super().__init__(message)
        self.report = report


def material_state(checkpoint):
    """Only actor positions may change; roster/capabilities/material stay owned."""
    value = deepcopy(checkpoint)
    value['actors'] = {actor: {key: item for key, item in state.items() if key != 'position'}
                       for actor, state in value.get('actors', {}).items()}
    return value


def require_custody(checkpoint):
    values = list(checkpoint['stock'].values()) + list(checkpoint['inventories'].values())
    if (checkpoint.get('schema') != 2 or checkpoint.get('options') != {'opening': True, 'physical': True}
            or any(type(value) is not int or value < 0 for value in values) or sum(values) != 16):
        raise AssertionError('Actual physical profile must retain typed finite custody16')


def control_suffix(before, after, expected, peer):
    """Prove RPC admission/refusal. Native input application is checked separately."""
    old, current = before['control_trace'], after['control_trace']
    if (before.get('control_trace_dropped') != 0 or after.get('control_trace_dropped') != 0
            or current[:len(old)] != old or len(current) != len(old) + len(expected)):
        raise AssertionError('Actual control trace must extend by exactly the declared packet count')
    suffix = current[len(old):]
    for observed, wanted in zip(suffix, expected):
        if observed.get('peer') != peer or any(observed.get(key) != value for key, value in wanted.items()):
            raise AssertionError('Actual control disposition or bound peer differs: ' + repr((observed, wanted)))
    if material_state(before['checkpoint']) != material_state(after['checkpoint']):
        raise AssertionError('Movement control changed material, request history or entity identity')
    require_custody(after['checkpoint'])
    return suffix


def packet(namespace, sequence, *, direction=(0.0, 0.0), jump=False, release=False):
    return {'namespace': namespace, 'sequence': sequence, 'direction': list(direction), 'jump': jump, 'release': release}


def negative_packets(namespace, sequence):
    """Cases derive from the declared wire contract, not a model pose publisher."""
    cases = []

    def add(label, payload, reason, sequence_kind='int', nonfinite=None):
        descriptor = {'payload': payload, 'sequence_kind': sequence_kind}
        if nonfinite is not None:
            descriptor['nonfinite_direction'] = nonfinite
        cases.append({'label': label, 'descriptor': descriptor, 'reason': reason})

    base = packet(namespace, sequence)
    for key, value in (
            ('actor', 'Q'), ('position', [900.0, 1.0, 900.0]),
            ('capabilities', {'build_reach': 400.0}), ('delta_time', 3600.0),
            ('elapsed_time', 3600.0), ('camera_position', [900.0, 1.0, 900.0])):
        add('extra_' + key, dict(base, **{key: value}), 'invalid_control_binding')
    for key in base:
        missing = deepcopy(base)
        del missing[key]
        add('missing_' + key, missing, 'invalid_control_binding', 'preserve')
    for name, value in (('wrong_namespace', namespace + 'other'), ('numeric_namespace', 1)):
        add(name, dict(base, namespace=value), 'invalid_control_binding')
    for name, value, kind in (
            ('zero_sequence', 0, 'int'), ('negative_sequence', -1, 'int'),
            ('fractional_sequence', 1.5, 'preserve'), ('string_sequence', str(sequence), 'preserve'),
            ('boolean_sequence', True, 'preserve'), ('dictionary_sequence', {}, 'preserve'),
            ('null_sequence', None, 'preserve'), ('integer_valued_float_sequence', sequence, 'preserve')):
        add(name, dict(base, sequence=value), 'stale_control', kind)
    for name, value in (
            ('empty_direction', []), ('short_direction', [0.0]), ('long_direction', [0.0, 0.0, 0.0]),
            ('dictionary_direction', {}), ('null_direction', None), ('string_direction', '0,0'),
            ('oversized_direction', [2.0, 0.0]), ('negative_oversized_direction', [-1.1, 0.0]),
            ('boolean_coordinate', [True, 0.0]), ('string_coordinate', ['0', 0.0])):
        add(name, dict(base, direction=value), 'invalid_control')
    for name in ('nan', 'positive_infinity', 'negative_infinity'):
        add(name + '_direction', deepcopy(base), 'invalid_control', nonfinite=name)
    for name, changes in (
            ('numeric_jump', {'jump': 1}), ('string_jump', {'jump': 'true'}),
            ('numeric_release', {'release': 1}), ('string_release', {'release': 'false'})):
        add(name, dict(base, **changes), 'invalid_control')
    add('release_with_jump', dict(base, release=True, jump=True), 'invalid_control_release')
    add('release_with_direction', dict(base, release=True, direction=[1.0, 0.0]), 'invalid_control_release')
    return cases


def run_ui_cases(exchange, *, frozen_clock, wait_role_absent, observe_server, transport_boundary):
    report = {'status': 'running', 'case': 'actual_physical_movement_wire_negatives',
              'operations': [], 'server_cuts': [], 'negative_cases': [], 'user_play': 'not_assessed',
              'limits': ['Test-only client RPC injection is distinct from ordinary keyboard/UI evidence.',
                         'No intermediate native jump_queued=true sample is claimed.']}
    identity = None
    baseline_material = None

    def need(value, label):
        if not value:
            raise AssertionError(label)

    def send(role, **command):
        response = exchange({role: deepcopy(command)})[role]
        report['operations'].append({'role': role, 'command': deepcopy(command), 'response': deepcopy(response)})
        facts = response['facts']
        need(response['status'] == 'pass' and facts['model_is_session'] and facts['client_world_is_null']
             and not facts['auto_advance'], 'Actual projection-only client, no local authority or production clock')
        if facts['ready']:
            need(facts['actor'] == role and facts['physical_view']['has_presenter'], 'Actual bound physical consumer')
        return facts

    def observe(label=None):
        value = observe_server()
        require_custody(value['checkpoint'])
        need(value['clock_frozen'] is True and value['tick_count'] == 0 and value['physical_ready']
             and not value['actor_error'], 'Frozen production with ready physical actors')
        if identity is not None:
            need((value['model_instance'], value['context']) == identity, 'Same actual authority across rebind')
            need(material_state(value['checkpoint']) == baseline_material, 'No material/history mutation from controls')
        if label is not None:
            report['server_cuts'].append({'label': label, 'evidence': deepcopy(value)})
        return value

    def until(predicate, label):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            value = observe()
            if predicate(value):
                report['server_cuts'].append({'label': label, 'evidence': deepcopy(value)})
                return value
        report['server_cuts'].append({'label': label + ' deadline', 'evidence': deepcopy(value)})
        raise AssertionError('Actual server observation barrier not reached: ' + label)

    def samples(value):
        return value['native_actors']['samples']

    def peer_for(value, role):
        return value['roles'][role]

    def next_sequence(value, role):
        peer = peer_for(value, role)
        accepted = [row['sequence'] for row in value['control_trace'] if row.get('peer') == peer and row.get('accepted') and 'sequence' in row]
        return max(accepted, default=0) + 1

    def raw(role, descriptors):
        facts = send(role, action='wire_control', packets=deepcopy(descriptors))
        probe = facts['wire_control_probe']
        need(probe['kind'] == 'raw_rpc' and len(probe['packets']) == len(descriptors)
             and all(row['rpc_error'] == 0 for row in probe['packets']), 'Every declared packet actually sent through ordinary Session RPC')
        for descriptor, emitted in zip(descriptors, probe['packets']):
            expected = deepcopy(descriptor['payload'])
            actual = deepcopy(emitted['payload'])
            if descriptor.get('nonfinite_direction'):
                # JSON cannot retain NaN. The producer records the actual
                # Variant classification separately before serialization.
                expected['direction'][0] = actual['direction'][0] = None
            need(actual == expected, 'Emitted RPC preserves the declared keys and values')
            if descriptor['sequence_kind'] == 'int' and 'sequence' in descriptor['payload']:
                need(emitted['sequence_type'] == 'int', 'Valid sequence explicitly reified as a Variant integer')
            if descriptor.get('nonfinite_direction'):
                need(emitted['direction_nonfinite'][0] == descriptor['nonfinite_direction'], 'Actual nonfinite negative Variant retained by classification')
        return facts

    def wait_controls(before, amount, label):
        count = len(before['control_trace']) + amount
        return until(lambda value: len(value['control_trace']) >= count, label)

    try:
        need(frozen_clock is True, 'Wire cases require frozen production, never a frozen native body')
        initial_namespaces = {}
        for role in ('P', 'Q'):
            send(role, action='button', button='reconnect_button')
            send(role, action='barrier', condition='ready')
            initial_namespaces[role] = send(role, action='observe')['session_namespace']
        first = until(lambda value: set(value['roles']) == {'P', 'Q'}
                      and all(samples(value).get(role, {}).get('on_floor') for role in ('P', 'Q'))
                      and all(any(row.get('accepted') and row.get('namespace') == initial_namespaces[role]
                                  and row.get('sequence') == 1 for row in value['control_trace'])
                              for role in ('P', 'Q')),
                      'both bound actors at natural native floor contact')
        identity = (first['model_instance'], first['context'])
        baseline_material = material_state(first['checkpoint'])
        need(not first['checkpoint']['requests'] and not first['snapshot']['entities'], 'Empty fixture has no material command history')
        original_native = {role: {key: samples(first)[role][key] for key in ('body_id', 'rid', 'space')}
                           for role in ('P', 'Q')}

        # Existing Session APIs, not a replacement movement controller. The
        # actual server trace must place both calls in the same physics frame.
        before = observe('before existing jump/release API pair')
        namespace = send('P', action='observe')['session_namespace']
        ordinary_next = next_sequence(before, 'P')
        facts = send('P', action='wire_control', ordinary_jump_release=True)
        need(facts['wire_control_probe']['kind'] == 'ordinary_jump_release'
             and all(row.get('accepted') for row in facts['wire_control_probe']['results']), 'Both existing Session API sends succeeded')
        after = wait_controls(before, 2, 'actual jump then release RPC receipts')
        rows = control_suffix(before, after, [
            {'accepted': True, 'actor': 'P', 'namespace': namespace, 'sequence': ordinary_next,
             'direction': [0.0, 0.0], 'jump': True, 'release': False},
            {'accepted': True, 'actor': 'P', 'namespace': namespace, 'sequence': ordinary_next + 1,
             'direction': [0.0, 0.0], 'jump': False, 'release': True}], peer_for(before, 'P'))
        need(rows[0]['physics_frame'] == rows[1]['physics_frame'], 'Actual reliable RPC pair applied before the same next body step')
        released = until(lambda value: samples(value)['P']['physics_frame'] > rows[-1]['physics_frame'] + 1,
                         'natural native observation after jump/release pair')
        need(samples(released)['P']['on_floor'] and not samples(released)['P']['jump_queued']
             and samples(released)['P']['control'] == [0.0, 0.0]
             and samples(released)['P']['controls'] == samples(before)['P']['controls'] + 1
             and samples(released)['P']['releases'] == samples(before)['P']['releases'] + 1
             and abs(samples(released)['P']['position'][1] - samples(before)['P']['position'][1]) <= 0.00001,
             'Release clears horizontal input and accepted jump edge before a later natural observation')

        before = observe('before malformed packets')
        namespace = send('P', action='observe')['session_namespace']
        sequence = next_sequence(before, 'P')
        cases = negative_packets(namespace, sequence)
        raw('P', [case['descriptor'] for case in cases])
        after = wait_controls(before, len(cases), 'every malformed packet received and explicitly refused')
        control_suffix(before, after, [{'accepted': False, 'reason': case['reason']} for case in cases], peer_for(before, 'P'))
        need(all(samples(after)[role]['controls'] == samples(before)[role]['controls']
                 and samples(after)[role]['releases'] == samples(before)[role]['releases']
                 and samples(after)[role]['control'] == [0.0, 0.0]
                 and samples(after)[role]['position'][0] == samples(before)[role]['position'][0]
                 and samples(after)[role]['position'][2] == samples(before)[role]['position'][2]
                 and abs(samples(after)[role]['position'][1] - samples(before)[role]['position'][1]) <= 0.00001
                 for role in ('P', 'Q')), 'Malformed payloads never reach either actor input producer')
        report['negative_cases'] = cases

        # One valid packet with the SAME candidate sequence discriminates a
        # refusal from a silent receive-counter advance. A duplicate is stale.
        before = after
        raw('P', [{'payload': packet(namespace, sequence, release=True), 'sequence_kind': 'int'}])
        after = wait_controls(before, 1, 'fresh same sequence after malformed packets')
        control_suffix(before, after, [{'accepted': True, 'actor': 'P', 'namespace': namespace,
                                      'sequence': sequence, 'release': True}], peer_for(before, 'P'))
        before = after
        raw('P', [{'payload': packet(namespace, sequence, jump=True), 'sequence_kind': 'int'},
                  {'payload': packet(namespace, sequence - 1, direction=(1.0, 0.0)), 'sequence_kind': 'int'},
                  {'payload': packet(namespace, 1000, release=True), 'sequence_kind': 'int'}])
        after = wait_controls(before, 3, 'duplicate/lower sequences refused then higher valid sequence accepted')
        control_suffix(before, after, [{'accepted': False, 'reason': 'stale_control'},
                                      {'accepted': False, 'reason': 'stale_control'},
                                      {'accepted': True, 'actor': 'P', 'namespace': namespace, 'sequence': 1000, 'release': True}], peer_for(before, 'P'))
        old_peer, old_namespace = peer_for(after, 'P'), namespace
        send('P', action='button', button='disconnect_button')
        lost = wait_role_absent('P')
        report['server_cuts'].append({'label': 'actual old peer disconnected', 'evidence': deepcopy(lost)})
        need(any(row.get('reason') == 'disconnect_release' and row.get('peer') == old_peer
                 for row in lost['control_trace']), 'Actual peer loss releases its bound producer')
        send('P', action='button', button='reconnect_button')
        rebound = send('P', action='barrier', condition='ready')
        need(rebound['session_namespace'] != old_namespace, 'Actual rebind has a new namespace')
        namespace = rebound['session_namespace']
        after = until(lambda value: 'P' in value['roles'] and any(
            row.get('accepted') and row.get('namespace') == namespace and row.get('sequence') == 1
            for row in value['control_trace']), 'new binding accepts ordinary initial sequence1 below old1000')
        before = after
        sequence = next_sequence(before, 'P')
        raw('P', [{'payload': packet(old_namespace, 1001, direction=(1.0, 0.0)), 'sequence_kind': 'int'},
                  {'payload': packet(namespace, sequence - 1, jump=True), 'sequence_kind': 'int'},
                  {'payload': packet(namespace, sequence, release=True), 'sequence_kind': 'int'}])
        after = wait_controls(before, 3, 'old binding refused and new binding sequence remains usable')
        control_suffix(before, after, [{'accepted': False, 'reason': 'invalid_control_binding'},
                                      {'accepted': False, 'reason': 'stale_control'},
                                      {'accepted': True, 'actor': 'P', 'namespace': namespace, 'sequence': sequence, 'release': True}], peer_for(before, 'P'))

        # A positive Q control demonstrates actual sender binding and diagonal
        # normalization. It neither borrows P's body nor trusts a client pose.
        before = observe('before Q positive control')
        q_namespace = send('Q', action='observe')['session_namespace']
        q_sequence = next_sequence(before, 'Q')
        raw('Q', [{'payload': packet(q_namespace, q_sequence, direction=(1.0, 1.0)), 'sequence_kind': 'int'}])
        after = wait_controls(before, 1, 'actual Q accepted diagonal input')
        rows = control_suffix(before, after, [{'accepted': True, 'actor': 'Q', 'namespace': q_namespace,
                                             'sequence': q_sequence, 'jump': False, 'release': False}], peer_for(before, 'Q'))
        direction = rows[0]['direction']
        need(all(abs(value - 1 / math.sqrt(2)) <= 0.000001 for value in direction), 'Diagonal wire direction is bounded to unit magnitude')
        moving = until(lambda value: samples(value)['Q']['body_ticks'] > samples(before)['Q']['body_ticks'] + 3
                       and samples(value)['Q']['position'][0] > samples(before)['Q']['position'][0],
                       'Q native body advances through ordinary producer')
        need(samples(moving)['P']['position'][0] == samples(before)['P']['position'][0]
             and samples(moving)['P']['position'][2] == samples(before)['P']['position'][2]
             and samples(moving)['Q']['controls'] == samples(before)['Q']['controls'] + 1,
             'Actual Q producer consumes its input and cannot move P')
        before = moving
        raw('Q', [{'payload': packet(q_namespace, q_sequence + 1, release=True), 'sequence_kind': 'int'}])
        after = wait_controls(before, 1, 'Q release accepted')
        control_suffix(before, after, [{'accepted': True, 'actor': 'Q', 'namespace': q_namespace,
                                      'sequence': q_sequence + 1, 'release': True}], peer_for(before, 'Q'))
        final = until(lambda value: samples(value)['Q']['control'] == [0.0, 0.0]
                      and not samples(value)['Q']['jump_queued'], 'released Q natural native sample')
        for role in ('P', 'Q'):
            need({key: samples(final)[role][key] for key in ('body_id', 'rid', 'space')} == original_native[role]
                 and samples(final)[role]['registered'], 'Same registered native body across controls/rebind: ' + role)
        report.update(status='pass', final=final, negative_count=len(cases),
                      frozen_native=False, material_unchanged=material_state(final['checkpoint']) == baseline_material)
        return report
    except Exception as error:
        report.update(status='fail', error=str(error))
        raise ControlWireFailure(str(error), report) from error
