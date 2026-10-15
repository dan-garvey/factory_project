"""Actual first-placement refusals and correction through the shared view.

Pure scenarios only: the existing supervisor owns process, transport and files.
The same scenario intentionally fails an old view that exposes bare reason codes.
"""
from copy import deepcopy


def run_ui_cases(exchange, *, frozen_clock, wait_role_absent, observe_server, transport_boundary):
    report = {'status': 'running', 'case': 'shared_placement_guidance', 'operations': [],
              'observations': {}, 'checks': 0, 'user_play': 'not_assessed'}

    def need(value, label):
        report['checks'] += 1
        if not value:
            raise AssertionError(label)

    def send(role, action, **fields):
        command = dict(action=action, **fields)
        f = exchange({role: command})[role]['facts']
        report['operations'].append({'role': role, 'command': command, 'facts': deepcopy(f)})
        need(f['model_is_session'] and f['client_world_is_null'] and f['auto_advance'] is False,
             'Only real server owns the worksite')
        need(f['save_disabled'] and f['load_disabled'], 'Shared client cannot roll back the server')
        if f['ready']:
            need(f['state'] == f['projection'] and f['actor'] == role, 'Actual actor-bound confirmed projection')
            stock = f['projection']['stock']
            need(all(type(v) is int for v in stock.values()) and stock == dict(source=16, collector=0,
                 belt=0, input=0, held=0, output=0, player=0), 'No material created or consumed')
        return f

    def settled(role):
        return send(role, 'barrier', condition='settled')

    def boundary(kind):
        return transport_boundary(kind, roles=('P',))

    try:
        need(frozen_clock is True, 'Frozen observation clock isolates placement decisions')
        for role in ('P', 'Q'):
            send(role, 'button', button='reconnect_button')
            send(role, 'barrier', condition='ready')
        boundary('hold_admission')
        send('P', 'key', key='1')
        queued = send('P', 'cell', x=1, z=0)
        held = boundary('wait_received')
        need(queued['last_submission']['queued'] is True and queued['last_submission']['accepted'] is False
             and not queued['last_outcome'] and not held['checkpoint']['requests'],
             'Pending placement has no invented refusal or acceptance before authority')
        boundary('release_admission')
        collector = settled('P')
        need(collector['last_outcome']['accepted'] is False and collector['last_outcome']['reason'] == 'not_at_seam',
             'Actual collector location refusal remains in diagnostics')
        report['observations']['collector_refused'] = deepcopy(collector)
        send('P', 'capture')
        send('Q', 'key', key='4')
        send('Q', 'cell', x=0, z=1)
        wheel = settled('Q')
        need(wheel['last_outcome']['accepted'] is False and wheel['last_outcome']['reason'] == 'not_at_stream',
             'Actual wheel location refusal remains in diagnostics')
        report['observations']['wheel_refused'] = deepcopy(wheel)
        send('Q', 'capture')
        refused = observe_server()['checkpoint']
        need(not refused['entities'] and refused['parts'] == dict(collector=1, belt=1, processor=1, wheel=1, shaft=3)
             and refused['order'] == 2 and refused['revision'] == 0 and len(refused['requests']) == 2,
             'Both refused placements preserve actual parts, identities and quantities')
        # Correct the two locations in the same authoritative world, using
        # fresh ordinary actions rather than retrying a request with new intent.
        send('P', 'cell', x=0, z=0)
        corrected_collector = settled('P')
        send('Q', 'cell', x=-1, z=0)
        corrected_wheel = settled('Q')
        need(corrected_collector['last_outcome']['accepted'] is True
             and corrected_wheel['last_outcome']['accepted'] is True, 'Correct locations succeed on the same worksite')
        final = observe_server()['checkpoint']
        need(final['entities'] == {'collector-1': {'kind': 'collector', 'cell': [0, 0]},
                                  'wheel-1': {'kind': 'wheel', 'cell': [-1, 0]}}
             and final['parts'] == dict(collector=0, belt=1, processor=1, wheel=0, shaft=3)
             and final['order'] == 4 and final['revision'] == 2 and len(final['requests']) == 4,
             'Refusal creates no identity or hidden debit; correction spends exactly the original parts')
        report.update(queued=queued, refused=refused, final=final)
        # Assert the public usability gap after retaining BOTH failures and
        # successful recovery, so an old baseline is complete and attributable.
        need('seam strip' in collector['message'].lower(), 'Collector refusal lacks actionable seam location')
        need('stream bank' in wheel['message'].lower(), 'Wheel refusal lacks actionable stream location')
        report['status'] = 'pass'
        return report
    except BaseException as error:
        report.update(status='fail', error=str(error))
        error.report = report
        raise
