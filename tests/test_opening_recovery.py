"""Discriminating pure record oracles, never a simulated game or transport."""
from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("opening_recovery", ROOT / "scripts/opening_recovery_cases.py")
recovery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(recovery)


def stopped_snapshot():
    return {"stock": {"source": 11, "collector": 1, "belt": 1, "input": 1, "held": 1, "output": 1, "player": 0},
            "inventories": {}, "initial_feed": 16, "recipe_input": 1, "context": "record-context", "revision": 20, "order": 9,
            "entities": {"collector-1": {"kind": "collector", "cell": [0, 0]},
                         "wheel-1": {"kind": "wheel", "cell": [-1, 0]},
                         "belt-1": {"kind": "belt", "cell": [1, 0]},
                         "processor-1": {"kind": "processor", "cell": [2, 0]}},
            "parts": {"collector": 0, "wheel": 0, "belt": 0, "processor": 0, "shaft": 0},
            "links": [["collector-1", "belt-1"], ["belt-1", "processor-1"]],
            "drive_links": [["wheel-1", "collector-1"], ["collector-1", "belt-1"], ["belt-1", "processor-1"]],
            "remaining": 2, "power_enabled": False, "powered": False, "options": {"opening": True}}


def credited_snapshot(owner):
    value = stopped_snapshot()
    value["stock"].update(output=0, player=1)
    value["inventories"] = {owner: 1}
    value.update(revision=25, order=10)
    return value


def cached_retrieval():
    return {"context": "record-context", "checkpoint": {"requests": {"opaque-cache-key": {
        "intent": {"action": "retrieve", "amount": 1, "entity": "processor-1", "context": "record-context", "client": "P", "request": "old-1"},
        "result": {"accepted": True, "duplicate": False, "reason": "retrieved", "entity": "processor-1",
                   "context": "record-context", "client": "P", "request": "old-1", "revision": 21, "order": 10}}}}}


class RecoveryOracleTests(unittest.TestCase):
    def test_literal_stopped_record_allows_either_actual_owner_but_only_the_declared_one(self):
        for owner in ("P", "Q"):
            recovery.retrieval_cut(stopped_snapshot(), credited_snapshot(owner), owner)
        with self.assertRaisesRegex(AssertionError, "correct actor"):
            recovery.retrieval_cut(stopped_snapshot(), credited_snapshot("Q"), "P")

    def test_balanced_wrong_location_or_credit_cannot_hide_behind_finite_total(self):
        bad = credited_snapshot("P")
        bad["stock"].update(player=0, output=1)
        bad["inventories"] = {}
        recovery.ledger(bad)  # Conservation alone cannot establish a transfer.
        with self.assertRaisesRegex(AssertionError, "correct actor"):
            recovery.retrieval_cut(stopped_snapshot(), bad, "P")
        duplicate = credited_snapshot("P")
        duplicate["stock"].update(source=10, player=2)
        duplicate["inventories"]["P"] = 2
        recovery.ledger(duplicate)
        with self.assertRaisesRegex(AssertionError, "correct actor"):
            recovery.retrieval_cut(stopped_snapshot(), duplicate, "P")

    def test_phase_identity_or_topology_change_is_not_recovery(self):
        variants = []
        for field, value in (("remaining", 0), ("context", "fresh-world"), ("power_enabled", True)):
            bad = credited_snapshot("P")
            bad[field] = value
            variants.append(bad)
        identity = credited_snapshot("P")
        identity["entities"]["collector-1"]["cell"] = [0, 1]
        variants.append(identity)
        topology = credited_snapshot("P")
        topology["links"].pop()
        variants.append(topology)
        for bad in variants:
            with self.subTest(bad=bad), self.assertRaisesRegex(AssertionError, "Retained machine"):
                recovery.retrieval_cut(stopped_snapshot(), bad, "P")

    def test_boolean_negative_or_unbound_quantities_refuse(self):
        for field, key, value in (("stock", "output", True), ("stock", "source", -1),
                                  ("parts", "shaft", False), ("inventories", "stranger", 0)):
            bad = stopped_snapshot()
            bad[field][key] = value
            with self.subTest(field=field, value=value), self.assertRaises(AssertionError):
                recovery.ledger(bad)

    def test_unadmitted_or_rejoined_checkpoint_changes_only_real_tick_revision(self):
        before = {"revision": 4, "order": 2, "requests": {}, "remaining": 1,
                  "inventories": {}, "next_ids": {"collector": 2}}
        after = dict(deepcopy(before), revision=100)
        recovery.unchanged_checkpoint(before, after)
        for field, value in (("order", 3), ("remaining", 0), ("requests", {"replay": {}}),
                             ("inventories", {"P": 1}), ("next_ids", {"collector": 3})):
            changed = dict(after, **{field: value})
            with self.subTest(field=field), self.assertRaisesRegex(AssertionError, "checkpoint"):
                recovery.unchanged_checkpoint(before, changed)

    def test_cached_disposition_needs_exact_original_retrieval_identity(self):
        server = cached_retrieval()
        recovery.retrieval_disposition(server, "old-1", "P")
        for part, key, value in (("intent", "amount", 2), ("intent", "client", "Q"),
                                  ("intent", "action", "set_power"), ("intent", "context", "other"),
                                  ("result", "client", "Q"), ("result", "request", "fresh-1"),
                                  ("result", "duplicate", True), ("result", "accepted", False)):
            bad = deepcopy(server)
            bad["checkpoint"]["requests"]["opaque-cache-key"][part][key] = value
            with self.subTest(part=part, key=key), self.assertRaises(AssertionError):
                recovery.retrieval_disposition(bad, "old-1", "P")
        bad = deepcopy(server)
        bad["checkpoint"]["requests"]["another-key"] = deepcopy(bad["checkpoint"]["requests"]["opaque-cache-key"])
        with self.assertRaisesRegex(AssertionError, "Exactly one"):
            recovery.retrieval_disposition(bad, "old-1", "P")

    def test_first_failure_retains_partial_report_without_any_callback_retry(self):
        calls = []
        def forbidden(*args, **kwargs):
            calls.append((args, kwargs))
            raise AssertionError("should not reach an engine callback")
        with self.assertRaises(recovery.RecoveryFailure) as failure:
            recovery.run_ui_cases(forbidden, frozen_clock=True, wait_role_absent=forbidden,
                                  observe_server=forbidden, transport_boundary=forbidden)
        self.assertEqual(calls, [])
        self.assertEqual(failure.exception.report["status"], "fail")
        self.assertIn("live authority", failure.exception.report["error"])
        self.assertEqual(failure.exception.report["cuts"], [])


if __name__ == "__main__":
    unittest.main()
