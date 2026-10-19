"""Synthetic dictionaries test the external evidence oracle, not game behavior."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from opening_control_wire_cases import control_suffix, material_state, require_custody


def checkpoint():
    return {'schema': 2, 'options': {'opening': True, 'physical': True},
            'actors': {'P': {'position': [0.0, 0.9, 1.3], 'capabilities': {'build_reach': 4.0}},
                       'Q': {'position': [0.0, 0.9, 2.5], 'capabilities': {'build_reach': 4.0}}},
            'stock': {'source': 16, 'collector': 0, 'belt': 0, 'input': 0, 'held': 0, 'output': 0},
            'inventories': {}, 'parts': {'collector': 1}, 'entities': {}, 'requests': {},
            'next_ids': {'collector': 1}, 'order': 0, 'revision': 0}


class ControlWireOracleTests(unittest.TestCase):
    def setUp(self):
        self.before = {'checkpoint': checkpoint(), 'control_trace_dropped': 0, 'control_trace': []}
        self.after = deepcopy(self.before)
        self.after['control_trace'] = [{'peer': 73, 'accepted': False, 'reason': 'invalid_control_binding'}]
        self.expected = [{'accepted': False, 'reason': 'invalid_control_binding'}]

    def verify(self):
        return control_suffix(self.before, self.after, self.expected, 73)

    def test_explicit_refusal_has_actual_peer_event(self):
        self.assertEqual(self.verify(), self.after['control_trace'])

    def test_silence_is_not_a_refusal(self):
        self.after['control_trace'] = []
        with self.assertRaisesRegex(AssertionError, 'exactly'):
            self.verify()

    def test_wrong_actual_peer_cannot_supply_the_witness(self):
        self.after['control_trace'][0]['peer'] = 74
        with self.assertRaisesRegex(AssertionError, 'bound peer'):
            self.verify()

    def test_accepted_or_differently_refused_packet_is_not_the_expected_refusal(self):
        for changes in ({'accepted': True}, {'reason': 'stale_control'}):
            with self.subTest(changes=changes):
                row = self.after['control_trace'][0]
                original = deepcopy(row)
                row.update(changes)
                with self.assertRaisesRegex(AssertionError, 'disposition'):
                    self.verify()
                row.clear()
                row.update(original)

    def test_unrelated_control_cannot_be_silently_filtered(self):
        self.after['control_trace'].append({'peer': 74, 'accepted': True})
        with self.assertRaisesRegex(AssertionError, 'exactly'):
            self.verify()

    def test_dropped_or_rewritten_history_is_not_accepted(self):
        self.after['control_trace_dropped'] = 1
        with self.assertRaisesRegex(AssertionError, 'trace'):
            self.verify()
        self.after['control_trace_dropped'] = 0
        self.before['control_trace'] = [{'peer': 73, 'accepted': True, 'sequence': 1}]
        self.after['control_trace'].insert(0, {'peer': 73, 'accepted': True, 'sequence': 2})
        with self.assertRaisesRegex(AssertionError, 'trace'):
            self.verify()

    def test_real_movement_is_allowed_without_freezing_the_whole_projection(self):
        self.after['checkpoint']['actors']['P']['position'] = [1.0, 0.9, 1.3]
        self.verify()
        self.assertEqual(material_state(self.before['checkpoint']), material_state(self.after['checkpoint']))

    def test_roster_capability_and_material_identity_are_still_immutable(self):
        for change in ('roster', 'capability', 'quantity', 'generation', 'history'):
            with self.subTest(change=change):
                original = deepcopy(self.after['checkpoint'])
                state = self.after['checkpoint']
                if change == 'roster':
                    del state['actors']['Q']
                elif change == 'capability':
                    state['actors']['P']['capabilities']['build_reach'] = 400.0
                elif change == 'quantity':
                    state['stock']['source'] = 15
                elif change == 'generation':
                    state['next_ids']['collector'] = 2
                else:
                    state['requests']['unearned'] = {}
                with self.assertRaisesRegex(AssertionError, 'material'):
                    self.verify()
                self.after['checkpoint'] = original

    def test_finite_custody_rejects_boolean_fractional_and_refilled_quantities(self):
        for value in (True, 16.0, -1, 17):
            with self.subTest(value=value):
                state = checkpoint()
                state['stock']['source'] = value
                with self.assertRaisesRegex(AssertionError, 'typed finite custody'):
                    require_custody(state)


if __name__ == '__main__':
    unittest.main()
