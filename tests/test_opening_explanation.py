"""Fail-closed boundary for actual explanation state consumed by the launcher."""
import copy
import unittest

from test_opening_startup import launcher


def fixture():
    # Independently declared finite opening ledger, no engine implementation call.
    def state(quantities, driven, remaining):
        return {"context": "opening-example-1", "initial_feed": 16, "recipe_input": 1,
                "stock": dict(zip(("source", "collector", "belt", "input", "held", "output", "player"), quantities)),
                "remaining": remaining, "powered": driven, "power_enabled": True, "options": {"opening": True},
                "inventories": {"EXAMPLE": 1} if quantities[-1] else {},
                "parts": {"collector": 0, "belt": 0, "processor": 0, "wheel": 0, "shaft": 0 if driven else 3},
                "entities": {"wheel-1": {"kind": "wheel", "cell": [-1, 0]},
                             "collector-1": {"kind": "collector", "cell": [0, 0]},
                             "belt-1": {"kind": "belt", "cell": [1, 0]},
                             "processor-1": {"kind": "processor", "cell": [2, 0]}},
                "links": [["collector-1", "belt-1"], ["belt-1", "processor-1"]],
                "drive_links": [["wheel-1", "collector-1"], ["collector-1", "belt-1"], ["belt-1", "processor-1"]] if driven else []}
    blocked = state([11, 1, 1, 1, 1, 1, 0], True, 0)
    return {"lessons": [state([16, 0, 0, 0, 0, 0, 0], False, 0),
                        state([16, 0, 0, 0, 0, 0, 0], True, 0),
                        state([12, 1, 1, 1, 1, 0, 0], True, 2), blocked],
            "step": state([15, 1, 0, 0, 0, 0, 0], True, 0),
            "blocked_retained": copy.deepcopy(blocked),
            "recovery": state([10, 1, 1, 1, 1, 1, 1], True, 2),
            "isolation": True, "live_clock": True}


class ExplanationOracleTests(unittest.TestCase):
    def test_missing_actual_state_or_isolation_evidence_fails(self):
        control = fixture()
        launcher.check_explanation_report(control)
        for field in ("lessons", "step", "blocked_retained", "recovery", "isolation", "live_clock"):
            altered = copy.deepcopy(control)
            del altered[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                launcher.check_explanation_report(altered)

    def test_plausible_conserved_but_wrong_locations_and_types_fail(self):
        control = fixture()
        for field, change in (("stock", {"collector": 0, "source": 12}),
                              ("stock", {"held": True}), ("parts", {"shaft": False}),
                              ("inventories", {"EXAMPLE": 0, "P": 1})):
            altered = copy.deepcopy(control)
            altered["recovery"][field].update(change)
            with self.subTest(field=field, change=change), self.assertRaises(ValueError):
                launcher.check_explanation_report(altered)
