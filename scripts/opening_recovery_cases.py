"""Stock-changing uncertainty through real opening input and existing delivery cuts.

Pure case driver for check_opening_session.py --ui --clock live --ui-driver.
No processes, files, transport, simulated commands or replacement quantity owner.
"""
from copy import deepcopy
import time


ROLES = ("P", "Q")
MACHINE_FIELDS = ("entities", "parts", "links", "drive_links", "remaining",
                  "power_enabled", "powered", "options", "initial_feed", "recipe_input", "context")


def require(value, message):
    if not value:
        raise AssertionError(message)


def ledger(snapshot):
    """Independent finite fixture oracle; boolean quantities must also refuse."""
    stock, inventories = snapshot["stock"], snapshot["inventories"]
    require(set(stock) == {"source", "collector", "belt", "input", "held", "output", "player"}, "Every stock location exposed")
    require(all(type(v) is int and v >= 0 for v in stock.values()), "Typed stock")
    require(set(inventories) <= set(ROLES) and all(type(v) is int and v >= 0 for v in inventories.values()), "Typed bound inventories")
    require(sum(stock.values()) == 16 and stock["player"] == sum(inventories.values()), "Finite16 and actor ownership")
    require(snapshot["initial_feed"] == 16 and snapshot["recipe_input"] == 1, "Actual opening fixture")
    parts, entities = snapshot["parts"], snapshot["entities"]
    require(set(parts) == {"collector", "belt", "processor", "wheel", "shaft"}, "All part kinds")
    require(all(type(v) is int and v >= 0 for v in parts.values()), "Typed parts")
    require(all(e["kind"] in parts and e["kind"] != "shaft" for e in entities.values()), "Actual machine kinds")
    for kind in ("collector", "belt", "processor", "wheel"):
        require(parts[kind] + sum(e["kind"] == kind for e in entities.values()) == 1, "Conserved part:" + kind)
    require(parts["shaft"] + len(snapshot["drive_links"]) == 3, "Conserved shafts")
    for field in ("links", "drive_links"):
        pairs = snapshot[field]
        require(all(len(p) == 2 and all(x in entities for x in p) for p in pairs), "Actual link endpoints")
        require(len({tuple(p) if field == "links" else frozenset(p) for p in pairs}) == len(pairs), "Unique links")


def retrieval_cut(before, after, owner):
    """A stopped cut changes one output into exactly one named actor's plate."""
    ledger(before)
    ledger(after)
    require(before["powered"] is False and after["powered"] is False, "Stopped machine boundary")
    require(before["stock"]["output"] == 1, "One actual output before retrieval")
    for field in MACHINE_FIELDS:
        require(after[field] == before[field], "Retained machine field:" + field)
    expected_stock = deepcopy(before["stock"])
    expected_stock.update(output=0, player=before["stock"]["player"] + 1)
    expected_inventories = deepcopy(before["inventories"])
    expected_inventories[owner] = expected_inventories.get(owner, 0) + 1
    require(after["stock"] == expected_stock and after["inventories"] == expected_inventories, "One plate at correct actor, all other locations retained")


def unchanged_checkpoint(before, after):
    """Transport/real-time ticks may change revision, never stopped work."""
    require(after == dict(before, revision=after["revision"]), "Stopped checkpoint changes only its tick revision")


def retrieval_disposition(server, request, actor):
    entries = request_entries(server, request)
    require(len(entries) == 1, "Exactly one cached retrieval disposition")
    entry = entries[0]
    intent, result = entry["intent"], entry["result"]
    require(intent == {"action": "retrieve", "amount": 1, "entity": "processor-1",
                       "context": server["context"], "client": actor, "request": request}, "Exact original retrieval intent")
    require(result["accepted"] is True and result["duplicate"] is False
            and result["reason"] == "retrieved" and result["entity"] == "processor-1"
            and result["context"] == server["context"] and result["client"] == actor
            and result["request"] == request, "Cached decision belongs to original actor and request")
    return entries


def request_entries(server, request):
    return [entry for entry in server["checkpoint"]["requests"].values()
            if entry["intent"].get("request") == request]


class RecoveryFailure(AssertionError):
    def __init__(self, message, report):
        super().__init__(message)
        self.report = report


def run_ui_cases(exchange, *, frozen_clock, wait_role_absent, observe_server, transport_boundary):
    report = {"status": "running", "case": "stock_retrieval_uncertainty", "operations": [],
              "server_observations": [], "boundaries": [], "cuts": [], "user_play": "not_assessed",
              "coverage": "additional inventory boundary; generic build/power uncertainty already accepted"}

    def send(roles, command):
        replies = exchange({r: deepcopy(command) for r in roles})
        report["operations"].append({"command": deepcopy(command), "responses": deepcopy(replies)})
        require(set(replies) == set(roles), "Exact responding roles")
        facts = {}
        for role, reply in replies.items():
            require(reply["status"] == "pass", "Actual input completed")
            f = reply["facts"]
            require(f["model_is_session"] and f["client_world_is_null"] and not f["auto_advance"], "Projection only client")
            require(f["state"] == f["projection"], "View uses actual projection")
            if f["ready"]:
                ledger(f["projection"])
                require(f["actor"] == role and f["namespace"] == f["session_namespace"] and f["sequence"] == f["session_sequence"], "Bound actor metadata")
            facts[role] = f
        return facts

    def key(role, value): return send((role,), {"action": "key", "key": value})[role]
    def cell(role, x): return send((role,), {"action": "cell", "x": x})[role]
    def button(role, name): return send((role,), {"action": "button", "button": name})[role]
    def barrier(roles, condition): return send(roles, {"action": "barrier", "condition": condition})

    def server(label):
        value = observe_server()
        report["server_observations"].append({"label": label, "evidence": deepcopy(value)})
        ledger(value["snapshot"])
        require(value["clock_frozen"] is False, "Real ordinary clock")
        require(value["model_instance"] == identity[0] and value["context"] == identity[1], "Same sole authority")
        return value

    def boundary(kind):
        value = transport_boundary(kind, roles=("P",))
        report["boundaries"].append({"kind": kind, "evidence": deepcopy(value)})
        return value

    def action(role, operation, accepted=True):
        before = send((role,), {"action": "observe"})[role]
        operation()
        f = barrier((role,), "settled")[role]
        result, receipt = f["last_outcome"], f["last_submission"]
        require(f["sequence"] == before["sequence"] + 1 and receipt["queued"] is True and receipt["accepted"] is False, "Exactly one queued ordinary command")
        require(result["accepted"] is accepted and result["duplicate"] is False and result["request"] == receipt["request"] and result["client"] == role, "Actual matching disposition")
        return f

    def convergence(expected):
        # Observe actual authority watermarks; never replay an input on timeout.
        deadline = time.monotonic() + 10
        for _ in range(64):
            views = send(ROLES, {"action": "observe"})
            if all(f["ready"] and f["projection"]["order"] >= expected["order"] for f in views.values()):
                for f in views.values():
                    for field in (*MACHINE_FIELDS, "stock", "inventories", "order"):
                        require(f["projection"][field] == expected[field], "Both current views:" + field)
                return views
            if time.monotonic() >= deadline:
                break
        raise AssertionError("Views never reached the authoritative stopped cut")

    try:
        require(not frozen_clock, "Recovery scenario requires the live authority clock")
        button("P", "reconnect_button")
        button("Q", "reconnect_button")
        barrier(ROLES, "ready")
        first = observe_server()
        identity = (first["model_instance"], first["context"])
        require(first["snapshot"]["stock"]["source"] == 16 and not first["snapshot"]["entities"], "Fresh disclosed finite fixture")
        for selector, x in (("1", 0), ("4", -1), ("2", 1), ("3", 2)):
            key("Q", selector)
            action("Q", lambda x=x: cell("Q", x))
        for selector, start, end in (("F", 0, 1), ("F", 1, 2), ("G", -1, 0), ("G", 0, 1), ("G", 1, 2)):
            key("Q", selector)
            cell("Q", start)
            action("Q", lambda end=end: cell("Q", end))
        for role in ROLES:
            key(role, "I")
            require(cell(role, 2)["selected"] == "processor-1", "Ordinary press selection")

        for admitted in (False, True):
            if admitted:
                action("Q", lambda: key("Q", "SPACE"))
            barrier(("Q",), "output")
            action("Q", lambda: key("Q", "SPACE"))
            before = server("stopped one-output baseline")
            require(not before["snapshot"]["powered"] and before["snapshot"]["stock"]["output"] == 1, "Actual power stopped after production")
            views = convergence(before["snapshot"])
            key("P", "I")
            cell("P", 2)
            old_namespace = views["P"]["namespace"]
            kind = "outcomes" if admitted else "admission"
            boundary("hold_" + kind)
            queued = key("P", "R")
            request = queued["last_submission"]["request"]
            require(queued["last_submission"]["queued"] is True and queued["last_submission"]["accepted"] is False, "Retrieval only queued")
            boundary("wait_outcomes" if admitted else "wait_received")
            cut = server("retrieval delivery cut")
            entries = request_entries(cut, request)
            if admitted:
                retrieval_disposition(cut, request, "P")
                retrieval_cut(before["snapshot"], cut["snapshot"], "P")
            else:
                require(not entries, "Unadmitted request has no cached disposition")
                unchanged_checkpoint(before["checkpoint"], cut["checkpoint"])
            pending = send(("P",), {"action": "observe"})["P"]
            require(request in pending["pending_actions"] and not pending["pending_actions"][request]["outcome"], "No outcome despite actual receive cut")
            button("P", "disconnect_button")
            barrier(("P",), "disconnected")
            wait_role_absent("P")
            lost = send(("P",), {"action": "observe"})["P"]
            require(not lost["pending_actions"] and any(e["request"] == request and e["disposition"] == "unknown" for e in lost["uncertain"]), "Actual client retains honest uncertainty")
            boundary("release_" + kind)
            # Even an empty-output refusal is a real explicit ordinary input,
            # rather than clicking the disabled retrieve button.
            q = action("Q", lambda: key("Q", "R"), accepted=not admitted)
            if admitted:
                require(q["last_outcome"]["reason"] == "unavailable_output", "Competing actor receives actual empty-output refusal")
            after = server("competing retrieval while P absent")
            retrieval_cut(before["snapshot"], after["snapshot"], "P" if admitted else "Q")
            require(len(after["checkpoint"]["requests"]) == len(before["checkpoint"]["requests"]) + 1 + int(admitted), "Only admitted requests enter cache")
            button("P", "reconnect_button")
            joined = barrier(("P",), "ready")["P"]
            require(joined["namespace"] != old_namespace and joined["sequence"] == 0 and not joined["selected"] and not joined["pending_link"], "Fresh rejoin without replay")
            final = server("same authority after fresh rejoin")
            unchanged_checkpoint(after["checkpoint"], final["checkpoint"])
            require(request_entries(final, request) == entries, "Original retrieval disposition retained or genuinely absent")
            current = convergence(final["snapshot"])
            require(current["P"]["sequence"] == 0 and not current["P"]["pending_actions"] and not current["P"]["last_outcome"], "No automatic uncertain retry or invented acknowledgement")
            require(any(e["request"] == request and e["disposition"] == "unknown" and not e["known_result"]
                        for e in current["P"]["uncertain"]), "Current stock does not invent an old request acknowledgement")
            report["cuts"].append({"admitted": admitted, "request": request, "before": before, "delivery": cut, "after": final,
                                   "pending": pending, "disconnected": lost, "competitor": q,
                                   "old_namespace": old_namespace, "new_namespace": joined["namespace"], "views": current})
            send(ROLES, {"action": "capture"})
        final = server("final stopped stock and phase")
        require(final["snapshot"]["inventories"] == {"P": 1, "Q": 1}, "Literal final actor credit P1/Q1")
        report.update(status="pass", final=final)
        return report
    except Exception as error:
        report.update(status="fail", error=str(error))
        raise RecoveryFailure(str(error), report) from error
