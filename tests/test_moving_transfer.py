"""Discriminating transfer-oracle and entry guards; no engine in cheap checks."""
from contextlib import redirect_stderr
from copy import deepcopy
import io
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
with patch.object(sys, 'path', [str(ROOT / 'scripts'), *sys.path]):
    spec = importlib.util.spec_from_file_location('moving_transfer_runner', ROOT / 'scripts/run_moving_transfer.py')
    trial = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(trial)


def body(position, basis, half, layer, mask, identity):
    return dict(position=position, basis=basis, shape_data=half, shape_type=3,
                layer=layer, mask=mask, id=identity, rid=identity + 10,
                shape_rid=identity + 20, space=1)


def coincident(wrong=False):
    identity = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    receiver_basis = [[-1, 0, 0], [0, 1, 0], [0, 0, -1]] if wrong else identity
    return dict(carrier=body([0, .75, 0], identity, [1.5, .175, 1.5], 4, 1, -100),
                receiver=body([.85 if wrong else 1.95, 1.05, 0], receiver_basis, [.275, .05, .275], 1, 4, -200),
                outlet=[1.4, 1.05, 0], inlet=[1.4, 1.05, 0], outward=[1, 0, 0],
                inward=[1 if wrong else -1, 0, 0], distance=0, facing=-1 if wrong else 1,
                geometric=not wrong, same_world=True, initial_native=True, frame=10, angular_velocity=[0, 0, 0])


class TransferGuards(unittest.TestCase):
    def test_integral_ledger_rejects_equal_total_wrong_types_and_negative(self):
        trial.ledger({'carrier': 3, 'receiver': 0})
        for stock in ({'carrier': True, 'receiver': 2}, {'carrier': 1.5, 'receiver': 1.5},
                      {'carrier': -1, 'receiver': 4}, {'carrier': 3, 'receiver': 1}):
            with self.subTest(stock=stock), self.assertRaises(ValueError): trial.ledger(stock)

    def test_coincident_wrong_facing_cannot_hide_behind_distance(self):
        self.assertTrue(trial.geometry(coincident()))
        self.assertFalse(trial.geometry(coincident(True)))
        dishonest = coincident(True)
        dishonest['geometric'] = True
        with self.assertRaisesRegex(ValueError, 'distance AND facing'): trial.geometry(dishonest)

    def test_aligned_wrong_distance_and_stale_port_are_distinct(self):
        native = coincident()
        native['receiver']['position'][0] += .2
        native['inlet'][0] += .2
        native.update(distance=.2, geometric=False)
        self.assertFalse(trial.geometry(native))
        native['outlet'][0] = 1.3
        with self.assertRaisesRegex(ValueError, 'basis-to-port'): trial.geometry(native)

    def test_cut_gap_cannot_hide_a_leave_or_reentry(self):
        first = dict(cut=1, native=coincident(), registered=True, eligible=True,
                     window=dict(id=1, inside=True, entered=True, left=False, spent=False), previous={}, port_displacement=0)
        second = deepcopy(first)
        second.update(cut=2, previous=dict(cut=1, frame=10, outlet=[1.4, 1.05, 0]))
        second['native']['frame'] = 12
        second['window']['entered'] = False
        cuts = [dict(stock={'carrier': 3, 'receiver': 0}, observation=item) for item in (first, second)]
        with self.assertRaisesRegex(ValueError, 'consecutive natural physics'): trial.verify_cuts(cuts)
        second['native']['frame'] = 11
        trial.verify_cuts(cuts)

    def test_unready_native_cut_is_retained_with_actual_port_math(self):
        native = coincident()
        native['carrier']['position'] = [0, 0, 0]
        native.update(outlet=[1.4, .3, 0], distance=.75, geometric=False, initial_native=False)
        self.assertFalse(trial.geometry(native))
        first = dict(cut=1, native=native, registered=False, eligible=False,
                     window=dict(id=0, inside=False, entered=False, left=False, spent=False), previous={}, port_displacement=0)
        ready = dict(cut=2, native=coincident(), registered=True, eligible=True,
                     window=dict(id=1, inside=True, entered=True, left=False, spent=False),
                     previous=dict(cut=1, frame=10, outlet=[1.4, .3, 0]), port_displacement=.75)
        ready['native']['frame'] = 11
        cuts = [dict(stock={'carrier': 3, 'receiver': 0}, observation=value) for value in (first, ready)]
        trial.verify_cuts(cuts)
        native['outlet'] = [1.4, 1.05, 0]
        with self.assertRaisesRegex(ValueError, 'basis-to-port'): trial.verify_cuts(cuts)

    def test_finished_quantity_cannot_hide_running_or_pending_work(self):
        good = dict(running=False, pending=False, queued_transfers=0)
        trial.stopped(good)
        for field, value in (('running', True), ('pending', True), ('queued_transfers', 1)):
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'actually stopped'):
                trial.stopped(dict(good, **{field: value}))

    def test_check_duration_override_refuses_before_engine_or_artifacts(self):
        argv = ['run_moving_transfer.py', '--godot', '/missing/engine', '--sha256', '0' * 64,
                '--artifacts', '/missing/evidence', '--check', '--duration-seconds', '1']
        error = io.StringIO()
        with patch.object(sys, 'argv', argv), patch.object(trial.bounds, 'execute_bounded') as execute, redirect_stderr(error):
            with self.assertRaises(SystemExit) as result: trial.main()
        self.assertEqual(result.exception.code, 2)
        self.assertIn('interactive mode only', error.getvalue())
        execute.assert_not_called()


if __name__ == '__main__':
    unittest.main()
