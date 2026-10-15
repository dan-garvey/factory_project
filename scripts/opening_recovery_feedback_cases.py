"""Actual failed-reconnect feedback while an earlier command stays unknown.

Pure driver for the existing --ui --clock frozen --ui-driver consumer.
The same driver intentionally fails a baseline whose UI hides the actual cause.
"""
from copy import deepcopy


class FeedbackFailure(AssertionError):
    def __init__(self, message, report):
        super().__init__(message)
        self.report = report


def run_ui_cases(exchange, *, frozen_clock, wait_role_absent, observe_server, transport_boundary):
    report = {"status": "running", "case": "unknown_action_failed_reconnect_feedback",
              "operations": [], "boundaries": [], "user_play": "not_assessed"}

    def need(condition, message):
        if not condition:
            raise AssertionError(message)

    def send(roles, **command):
        replies = exchange({r: deepcopy(command) for r in roles})
        report["operations"].append({"command": command, "responses": deepcopy(replies)})
        need(set(replies) == set(roles), "All requested real clients responded")
        result = {}
        for role, reply in replies.items():
            f = reply["facts"]
            need(reply["status"] == "pass" and f["model_is_session"] and f["client_world_is_null"]
                 and not f["auto_advance"] and f["state"] == f["projection"], "Actual projection-only UI")
            if f["projection"]:
                need(f["projection"]["stock"] == {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0, "player": 0}
                     and not f["projection"]["inventories"], "No material change in feedback case")
            result[role] = f
        return result

    def cut(kind):
        result = transport_boundary(kind, roles=("P",))
        report["boundaries"].append({"kind": kind, "server": deepcopy(result)})
        return result

    try:
        need(frozen_clock, "Feedback case requires a frozen observation clock")
        send(("P", "Q"), action="button", button="reconnect_button")
        send(("P", "Q"), action="barrier", condition="ready")
        first = observe_server()
        need(first["clock_frozen"] is True and not first["checkpoint"]["requests"], "Fresh real authority")
        cut("hold_outcomes")
        send(("P",), action="key", key="4")
        queued = send(("P",), action="cell", x=-1)["P"]
        request = queued["last_submission"]["request"]
        need(queued["last_submission"]["queued"] is True and queued["last_submission"]["accepted"] is False, "Placement queued only")
        decided = cut("wait_outcomes")
        entries = [x for x in decided["checkpoint"]["requests"].values() if x["intent"]["request"] == request]
        need(len(entries) == 1 and entries[0]["result"]["accepted"] is True
             and entries[0]["intent"]["action"] == "place" and entries[0]["intent"]["kind"] == "wheel", "Actual retained decision before withheld acknowledgement")
        send(("P",), action="button", button="disconnect_button")
        lost = send(("P",), action="barrier", condition="disconnected")["P"]
        need(any(x["request"] == request and x["disposition"] == "unknown" and not x["known_result"] for x in lost["uncertain"]), "Real unknown action after loss")
        wait_role_absent("P")
        cut("release_outcomes")
        send(("P",), action="button", button="reconnect_button")
        joined = send(("P",), action="barrier", condition="ready")["P"]
        need(joined["namespace"] != queued["namespace"] and joined["sequence"] == 0 and not joined["last_outcome"], "Rejoin has fresh identity without old acknowledgement")
        stopped = cut("stop_server")
        need(stopped["checkpoint"] == decided["checkpoint"] and stopped["model_instance"] == first["model_instance"], "Lifecycle does not mutate or replace authority")
        send(("P", "Q"), action="barrier", condition="disconnected")
        send(("P",), action="button", button="reconnect_button")
        absent = send(("P",), action="barrier", condition="disconnected")["P"]
        reason = absent["transport_disconnect_reason"]
        report.update(request=request, original=first, stopped=stopped, absent=absent, actual_reason=reason)
        need(reason in ("connection_failed", "connection_timeout"), "Actual Session signal identifies failed reconnect")
        need(absent["projection"] == joined["projection"] and absent["sequence"] == 0
             and not absent["ready"] and not absent["connecting"] and not absent["pending_actions"], "Failed reconnect preserves read-only state and sends no replay")
        need(any(x["request"] == request and x["disposition"] == "unknown" and not x["known_result"] for x in absent["uncertain"]), "Failed reconnect does not invent disposition")
        send(("P",), action="capture")
        message = absent["message"].lower()
        # Public behavior: an unavailable service has a visible failure cause,
        # while historical action uncertainty remains honest and separate.
        visible_cause = "did not respond" if reason == "connection_timeout" else "could not connect"
        need(visible_cause in message, "Actual failed reconnect cause is hidden behind earlier uncertainty")
        need("unknown" in message and "retry" in message and "read-only" in message, "Cause, uncertainty and read-only state remain visible together")
        report.update(status="pass")
        return report
    except Exception as error:
        report.update(status="fail", error=str(error))
        raise FeedbackFailure(str(error), report) from error
