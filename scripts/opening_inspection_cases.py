"""Selected-inspector witnesses using the existing real shared-input supervisor.

No files, processes, transport or simulation state live here. The supervisor
owns lifecycle and private delivery barriers. Observation never repeats an action.
"""
from copy import deepcopy
import time


def run_ui_cases(exchange, *, frozen_clock, wait_role_absent, observe_server,
                 transport_boundary):
    report = {'status': 'running', 'case': 'selected_inspector', 'checks': 0,
              'observations': {}, 'operations': [], 'user_play': 'not_assessed'}

    def require(value, message):
        report['checks'] += 1
        if not value:
            raise AssertionError(message)

    def send(role, action, **fields):
        command = dict(action=action, **fields)
        reply = exchange({role: command})[role]
        f = reply['facts']
        report['operations'].append({'role': role, 'command': command, 'facts': deepcopy(f)})
        require(reply['status'] == 'pass', 'Actual input controller completed')
        require(f['model_is_session'] and f['client_world_is_null'] and f['auto_advance'] is False,
                'Shared client owns no live rule state or clock')
        require(f['save_disabled'] and f['load_disabled'] and not f['save_ready'],
                'Shared Save/Load remain unavailable')
        require(f['worksite_bottom'] < 694, 'Inspector and shared controls fit above bottom status')
        if f['ready']:
            s = f['projection']
            require(f['actor'] == role and f['state'] == s, 'Actor-specific confirmed view')
            stock = s['stock']
            require(all(type(v) is int and v >= 0 for v in stock.values()), 'Typed nonnegative stock')
            require(sum(stock[k] for k in ('source', 'collector', 'belt', 'input', 'held', 'output', 'player')) == 16,
                    'Finite16 material conserved')
            require(stock['player'] == sum(s['inventories'].values()), 'Actor inventory has one authority')
            require(s['parts']['shaft'] + len(s['drive_links']) == 3, 'Finite three shafts conserved')
            for kind in ('wheel', 'collector', 'belt', 'processor'):
                require(s['parts'][kind] + sum(e['kind'] == kind for e in s['entities'].values()) == 1,
                        'One construction part per kind: ' + kind)
        return f

    def key(role, value):
        return send(role, 'key', key=value)

    def cell(role, x):
        return send(role, 'cell', x=x, z=0)

    def settled(role):
        return send(role, 'barrier', condition='settled')

    def inspect(role, x, label):
        before = observe_server()['checkpoint']
        key(role, 'I')
        f = cell(role, x)
        after = observe_server()['checkpoint']
        # Server clock continues; inspection must not add commands, consume or
        # change identities. Exact paused equality is checked at a stopped cut.
        require(after['order'] == before['order'] and after['requests'] == before['requests'],
                'Inspect submits no game command')
        if not before['power_enabled']:
            require(after['stock'] == before['stock'] and after['remaining'] == before['remaining'],
                    'Paused inspection preserves retained work exactly')
        report['observations'][label] = deepcopy(f)
        return f

    def connect(tool, a, b):
        key('P', tool)
        cell('P', a)
        cell('P', b)
        f = settled('P')
        require(f['last_outcome']['accepted'] is True, 'Ordinary connection accepted by server')
        return f

    try:
        require(frozen_clock is False, 'Live shared clock required for actual blocked/recovery input')
        for role in ('P', 'Q'):
            send(role, 'button', button='reconnect_button')
            send(role, 'barrier', condition='ready')
        # Normal keys and projected cell clicks debit the sole server kit.
        for tool, x in [('4', -1), ('1', 0), ('2', 1), ('3', 2)]:
            key('P', tool)
            cell('P', x)
            f = settled('P')
            require(f['last_outcome']['accepted'] is True, 'Ordinary placement accepted')
        f = inspect('Q', 2, 'Q_missing_material')
        require('No material inlet linked.' in f['inspector'] and '[F] link Belt → Press.' in f['inspector'],
                'Q sees causal missing material diagnosis')
        send('Q', 'capture')
        connect('F', 0, 1)
        connect('F', 1, 2)
        f = inspect('Q', 2, 'Q_missing_drive')
        require('[G]' in f['inspector'] and '[Space]' not in f['inspector']
                and f['power_label'] == 'DRIVE NEEDS CONNECTIONS', 'Q distinguishes missing drive from its switch')
        send('Q', 'capture')
        key('P', 'SPACE')
        settled('P')
        f = inspect('Q', 2, 'Q_switched_off')
        require('Drive switched off.' in f['inspector'] and f['power_label'] == 'DRIVE SWITCHED OFF',
                'Q sees stopped drive distinctly')
        for pair in [(-1, 0), (0, 1), (1, 2)]:
            connect('G', *pair)
        key('P', 'SPACE')
        settled('P')
        send('Q', 'barrier', condition='output')
        # Wait only for an observed finite held/output cut, never repeat input.
        deadline = time.monotonic() + 10
        while True:
            server = observe_server()
            s = server['snapshot']
            if s['stock']['output'] == 1 and s['stock']['held'] == 1 and s['remaining'] == 0:
                break
            require(time.monotonic() < deadline, 'Actual server reaches retained blocked phase')
        f = inspect('Q', 2, 'Q_blocked')
        require('[R] collect to make room.' in f['inspector'], 'Q sees outlet recovery action')
        send('Q', 'capture')
        # Hold the actual server admission boundary, without altering game time.
        transport_boundary('hold_admission', roles=('Q',))
        key('Q', 'R')
        transport_boundary('wait_received', roles=('Q',))
        f = send('Q', 'observe')
        report['observations']['Q_queued'] = deepcopy(f)
        require(f['pending_actions'] and 'Action awaiting the server.' in f['inspector']
                and '[R]' not in f['inspector'], 'Queued input shows waiting, never successful retrieval')
        require(f['last_submission']['queued'] is True and f['last_submission']['accepted'] is False,
                'Queued intake remains distinct from final acceptance')
        require(f['projection']['inventories'].get('Q', 0) == 0, 'No speculative inventory credit')
        send('Q', 'capture')
        transport_boundary('release_admission', roles=('Q',))
        f = settled('Q')
        require(f['last_outcome']['accepted'] is True, 'Release obtains actual retrieval decision')
        send('Q', 'barrier', condition='inventory', minimum=1)
        server = observe_server()
        require(server['snapshot']['inventories'].get('Q', 0) == 1
                and server['snapshot']['inventories'].get('P', 0) == 0, 'Only Q carries the retrieved real plate')
        # Stop and compare the whole server checkpoint around Help and F5/F9.
        key('P', 'SPACE')
        settled('P')
        before = observe_server()['checkpoint']
        key('Q', 'H')
        send('Q', 'observe')
        key('Q', 'H')
        after = observe_server()['checkpoint']
        require(before['stock'] == after['stock'] and before['remaining'] == after['remaining']
                and before['requests'] == after['requests'] and before['order'] == after['order'],
                'Help remains isolated from stopped live work')
        for value in ('F5', 'F9'):
            key('Q', value)
        f = send('Q', 'observe')
        require(f['save_result']['reason'] == 'network_save_unavailable'
                and f['load_result']['reason'] == 'network_load_unavailable', 'Client cannot roll back shared world')
        # Restore a selected confirmed press before ordinary disconnect.
        inspect('Q', 2, 'Q_before_disconnect')
        send('Q', 'button', button='disconnect_button')
        wait_role_absent('Q')
        f = send('Q', 'observe')
        report['observations']['Q_disconnected'] = deepcopy(f)
        require(not f['ready'] and 'Last confirmed state only.' in f['inspector']
                and '[R]' not in f['inspector'] and '[Space]' not in f['inspector'],
                'Disconnected inspector never advertises stale mutations')
        send('Q', 'capture')
        send('Q', 'button', button='reconnect_button')
        send('Q', 'barrier', condition='ready')
        f = inspect('Q', 2, 'Q_rejoined')
        require(f['projection']['inventories'].get('Q', 0) == 1 and not f['pending_actions'],
                'Fresh rejoin retains authoritative Q inventory without replay')
        report.update(status='pass', final=observe_server()['snapshot'])
        return report
    except BaseException as error:
        report.update(status='fail', error=str(error))
        error.report = report
        raise
