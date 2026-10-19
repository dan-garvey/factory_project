"""Synthetic dictionaries challenge the evidence oracle, never game behavior."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from check_physical_shared_resume import compare_continuation, validate_checkpoint, validate_native


def checkpoint():
    return {'schema': 2, 'options': {'opening': True, 'physical': True}, 'context': 'oracle-only',
            'initial_feed': 16, 'recipe_input': 1, 'revision': 30, 'remaining': 0,
            'actors': {role: {'position': [float(i), .88, 3.3], 'capabilities': {'build_reach': 4.0}}
                       for i, role in enumerate(('P', 'Q'))},
            'stock': {'source': 16, 'collector': 0, 'belt': 0, 'input': 0, 'held': 0, 'output': 0},
            'inventories': {}, 'parts': {'collector': 0, 'belt': 1, 'processor': 1, 'wheel': 1, 'shaft': 3},
            'next_ids': {'collector': 2, 'belt': 1, 'processor': 1, 'wheel': 1},
            'entities': {'collector-1': {'kind': 'collector', 'cell': [0, 0]}},
            'links': [], 'drive_links': [], 'order': 2,
            'requests': {role: {'intent': {'client': role, 'action': 'place', 'kind': 'collector', 'cell': [0, 0]},
                                'result': {'accepted': role == 'P', 'reason': 'placed' if role == 'P' else 'out_of_reach'}}
                         for role in ('P', 'Q')}}


def native_evidence(capture):
    return {'checkpoint': deepcopy(capture), 'physical_ready': True, 'actor_error': '',
            'persistence': {'native_preflight': {'accepted': True}},
            'native_actors': {'samples': {role: {
                'body_id': index + 1, 'rid': index + 101, 'space': 91, 'expected_space': 91,
                'body_ticks': 3, 'registered': True, 'ready': True, 'control': [0., 0.],
                'jump_queued': False, 'on_floor': True,
                'position': list(capture['actors'][role]['position']),
                'seed': list(capture['actors'][role]['position'])}
                for index, role in enumerate(('P', 'Q'))}}}


class PhysicalSharedResumeOracleTests(unittest.TestCase):
    def test_same_loaded_state_allows_live_revision_and_floor_settling(self):
        original = checkpoint(); final = deepcopy(original)
        final['revision'] += 3
        final['actors']['P']['position'][1] += .0001
        compare_continuation(original, deepcopy(original), final)
        evidence = native_evidence(final)
        for role in ('P', 'Q'):
            evidence['native_actors']['samples'][role]['seed'] = original['actors'][role]['position']
        validate_native(evidence, original)

    def test_legacy_or_float_schema_cannot_supply_a_physical_witness(self):
        for schema in (1, 2.0, True):
            value = checkpoint(); value['schema'] = schema
            with self.assertRaisesRegex(ValueError, 'schema2'):
                validate_checkpoint(value)

    def test_missing_q_or_persisted_runtime_state_is_rejected(self):
        value = checkpoint(); del value['actors']['Q']
        with self.assertRaisesRegex(ValueError, 'roster'):
            validate_checkpoint(value)
        value = checkpoint(); value['actors']['P']['ready'] = True
        with self.assertRaisesRegex(ValueError, 'runtime'):
            validate_checkpoint(value)

    def test_fractional_boolean_or_refilled_custody_is_rejected(self):
        for count in (16., True, 17):
            value = checkpoint(); value['stock']['source'] = count
            with self.assertRaisesRegex(ValueError, 'custody16'):
                validate_checkpoint(value)

    def test_loaded_cache_and_generation_cannot_be_silently_replaced(self):
        original = checkpoint(); loaded = deepcopy(original)
        loaded['requests']['P']['intent']['request'] = 'invented-new-request'
        with self.assertRaisesRegex(ValueError, 'Store-loaded'):
            compare_continuation(original, loaded, deepcopy(original))
        final = deepcopy(original); final['next_ids']['collector'] = 1
        with self.assertRaisesRegex(ValueError, 'generation'):
            compare_continuation(original, deepcopy(original), final)

    def test_declared_pose_is_not_a_native_seed_or_native_registration(self):
        original = checkpoint(); evidence = native_evidence(original)
        evidence['native_actors']['samples']['Q']['seed'][0] += 1.
        with self.assertRaisesRegex(ValueError, 'seeded'):
            validate_native(evidence, original)
        evidence = native_evidence(original)
        evidence['native_actors']['samples']['Q']['registered'] = False
        with self.assertRaisesRegex(ValueError, 'Registered'):
            validate_native(evidence, original)

    def test_arbitrary_teleport_is_not_ordinary_floor_settling(self):
        original = checkpoint(); final = deepcopy(original)
        final['actors']['Q']['position'][0] += 40.
        compare_continuation(original, deepcopy(original), final)
        evidence = native_evidence(final)
        evidence['native_actors']['samples']['Q']['seed'] = original['actors']['Q']['position']
        with self.assertRaisesRegex(ValueError, 'settling'):
            validate_native(evidence, original)


if __name__ == '__main__':
    unittest.main()
