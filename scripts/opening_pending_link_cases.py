"""A local first endpoint and an unrelated issued power intent can coexist.

Pure existing-consumer case. The same inputs retain an old obsolete-ID refusal
before the final defect assertion; no fake outcome or local command cancellation.
"""
from copy import deepcopy


class PendingLinkFailure(AssertionError):
    def __init__(self, message, report):
        super().__init__(message)
        self.report = report


def run_ui_cases(exchange, *, frozen_clock, wait_role_absent, observe_server, transport_boundary):
    report = {"status": "running", "case": "local_endpoint_during_unrelated_pending_intent", "operations": [], "cuts": [], "user_play": "not_assessed"}
    def need(value, label):
        if not value: raise AssertionError(label)
    def send(role, **command):
        reply = exchange({role: deepcopy(command)})[role]
        report["operations"].append({"role": role, "command": command, "response": deepcopy(reply)})
        f = reply["facts"]
        need(reply["status"] == "pass" and f["model_is_session"] and f["client_world_is_null"] and not f["auto_advance"] and f["state"] == f["projection"], "Real projection-only consumer")
        if f["projection"]:
            need(f["projection"]["stock"] == {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0, "player": 0}
                 and all(type(v) is int for v in f["projection"]["stock"].values()) and not f["projection"]["inventories"], "All material remains at source")
        return f
    def key(role, k): return send(role, action="key", key=k)
    def cell(role, x): return send(role, action="cell", x=x)
    def settled(role): return send(role, action="barrier", condition="settled")
    def actual(role, operation):
        before = send(role, action="observe"); operation(); f = settled(role)
        need(f["sequence"] == before["sequence"] + 1 and f["last_submission"]["queued"] is True and f["last_submission"]["accepted"] is False, "One fresh queued action")
        need(f["last_outcome"]["accepted"] is True and f["last_outcome"]["duplicate"] is False and f["last_outcome"]["request"] == f["last_submission"]["request"], "Actual matching accepted disposition")
        return f
    def place(k, x):
        key("Q", k); return actual("Q", lambda: cell("Q", x))
    def server(label):
        v = observe_server(); report["cuts"].append({"label": label, "evidence": deepcopy(v)})
        need(v["clock_frozen"] is True and v["tick_count"] == 0 and v["model_instance"] == owner and v["context"] == context, "Same frozen actual authority")
        need(len(v["checkpoint"]["requests"]) == v["snapshot"]["order"], "Every actual unique disposition retained")
        return v
    def boundary(kind): return transport_boundary(kind, roles=("P",))
    try:
        need(frozen_clock, "Pending coexistence requires frozen observation")
        for role in ("P", "Q"):
            send(role, action="button", button="reconnect_button"); send(role, action="barrier", condition="ready")
        first = observe_server(); owner, context = first["model_instance"], first["context"]
        place("1", 0); place("2", 1); place("4", -1)
        built = server("initial Q construction before P first choice")
        send("P", action="barrier", condition="revision", minimum=built["snapshot"]["revision"])
        key("P", "F"); f = cell("P", 0)
        need(f["pending_link"] == "collector-1" and f["sequence"] == 0, "First local choice sends no game command")
        boundary("hold_outcomes")
        queued = key("P", "SPACE"); request = queued["last_submission"]["request"]
        need(queued["last_submission"]["queued"] is True and queued["last_submission"]["accepted"] is False, "Unrelated power intent only queued locally")
        boundary("wait_outcomes"); decided = server("power decided but acknowledgement held")
        need(decided["snapshot"]["order"] == 4 and decided["snapshot"]["power_enabled"] is False, "Actual power decision before replacement")
        key("Q", "I"); cell("Q", 0)
        actual("Q", lambda: send("Q", action="button", button="remove_button")); place("1", 0)
        replaced = server("confirmed collector replacement during pending power")
        f = send("P", action="barrier", condition="revision", minimum=replaced["snapshot"]["revision"])
        need(f["projection"] == replaced["snapshot"] and "collector-1" not in f["projection"]["entities"] and "collector-2" in f["projection"]["entities"], "P has current actual replacement")
        need(list(f["pending_actions"]) == [request] and not f["pending_actions"][request]["outcome"] and f["sequence"] == 1,
             "Issued power intent remains pending and unmodified")
        need(f["pending_actions"][request]["action"] == {"action": "set_power", "active": False}
             and "awaiting the server" in f["inspector"].lower() and "waiting" in f["message"].lower() and "removed" not in f["message"].lower(), "Pending intent and its message retain priority")
        report.update(request=request, while_pending=deepcopy(f), replaced=replaced)
        send("P", action="capture")
        boundary("release_outcomes"); after_ack = settled("P")
        need(not after_ack["pending_actions"] and after_ack["last_outcome"]["request"] == request and after_ack["last_outcome"]["accepted"] is True
             and after_ack["last_outcome"]["reason"] == "power_changed" and after_ack["message"] == "Drive updated.", "Original power disposition settles without cancellation or overwritten success")
        need(after_ack["projection"] == replaced["snapshot"] and "collector-1" in after_ack["last_outcome"]["snapshot"]["entities"]
             and "collector-2" not in after_ack["last_outcome"]["snapshot"]["entities"], "Historical power acknowledgement never rolls current geometry back")
        report["after_ack"] = deepcopy(after_ack)
        cell("P", 1); next_click = settled("P"); clicked = server("next ordinary local click after old power acknowledgement")
        obsolete = next_click["sequence"] == 2
        if obsolete:
            need(next_click["last_outcome"]["accepted"] is False and next_click["last_outcome"]["reason"] == "missing_entity", "Old stale endpoint has real server refusal")
        else:
            need(next_click["sequence"] == 1 and next_click["pending_link"] == "belt-1" and clicked["checkpoint"] == replaced["checkpoint"], "New first local click sends no command")
        send("P", action="capture")
        key("P", "F"); need(cell("P", 0)["pending_link"] == "collector-2", "Explicit new first choice")
        actual("P", lambda: cell("P", 1)); final = server("actual same-worksite fresh connection")
        need(final["snapshot"]["order"] == (8 if obsolete else 7) and final["snapshot"]["revision"] == 7
             and final["snapshot"]["links"] == [["collector-2", "belt-1"]] and not final["snapshot"]["drive_links"]
             and final["snapshot"]["parts"] == {"collector": 0, "belt": 0, "wheel": 0, "processor": 1, "shaft": 3}, "Only intended power and fresh link alter authority; no stock loss")
        report.update(next_click=next_click, obsolete=obsolete, final=final)
        need(not f["pending_link"] and not f["selected"], "Unsubmitted endpoint survives removal while another action awaits its outcome")
        need(not after_ack["pending_link"] and not obsolete, "Released historical outcome leaves an obsolete local endpoint")
        report["status"] = "pass"; return report
    except Exception as error:
        report.update(status="fail", error=str(error)); raise PendingLinkFailure(str(error), report) from error
