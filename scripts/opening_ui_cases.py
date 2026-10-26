"""Actual rendered opening UI scenarios; the caller owns every process and file.

Platform supplies marker-first exchange, read-only server diagnostics and private
transport/lifecycle barriers. This module has no Model, transport, file copier,
resource wrapper or subprocess. A failed case carries its partial report.
"""

from copy import deepcopy
import time


ROLES = ("P", "Q")
KINDS = ("collector", "belt", "processor", "wheel")
LOCAL_FIELDS = (
    "actor", "namespace", "sequence", "session_namespace", "session_sequence",
    "selected", "pending_link", "pending_actions", "uncertain", "last_submission",
    "last_outcome", "last_local_result", "confirmed", "goal", "confirm_disabled", "save_slot", "save_ready", "save_owned",
    "save_result", "load_result", "auto_advance", "elapsed", "model_is_session",
    "client_world_is_null", "model_script", "scene_path", "session_path",
)


class UICaseFailure(AssertionError):
    def __init__(self, message, report):
        super().__init__(message)
        self.report = report


def run_ui_cases(exchange, *, frozen_clock, wait_role_absent, observe_server,
                 transport_boundary):
    """Run one fresh frozen/live cohort with two rendered, deferred UI clients.

    exchange maps roles to commands WITHOUT ids, returning full completed UI
    responses. The caller publishes the whole batch before waiting on matching
    stdout markers, reads each closed response exactly once, and owns teardown.
    observe_server returns actual unwrapped server_evidence, including checkpoint
    and snapshot. Private barriers affect delivery/lifecycle, never game time.
    """
    report = {"status": "running", "case": "ui_frozen" if frozen_clock else "ui_live",
              "operations": [], "server_observations": [], "transport_boundaries": [],
              "checks": 0, "captures": [], "requires_rendered_clients": True,
              "user_play": "not_assessed"}
    expected_order = 0
    expected_revision = 0

    def require(condition, label):
        report["checks"] += 1
        if not condition:
            raise AssertionError(label)

    def ledger(snapshot):
        require(isinstance(snapshot, dict) and snapshot.get("options", {}).get("opening") is True,
                "Actual opening projection")
        require(snapshot["initial_feed"] == 16 and snapshot["recipe_input"] == 1,
                "Declared finite16 and one-blank recipe")
        stock = snapshot["stock"]
        require(set(stock) == {"source", "collector", "belt", "input", "held", "output", "player"},
                "Every actual material owner is exposed")
        require(all(type(v) is int and v >= 0 for v in stock.values()), "Typed nonnegative stock")
        inventories = snapshot["inventories"]
        require(set(inventories).issubset(ROLES) and all(type(v) is int and v >= 0 for v in inventories.values()),
                "Only bound fixture actors own carried plates")
        require(stock["player"] == sum(inventories.values()), "Aggregate stock equals separate actor inventories")
        require(sum(stock[k] for k in ("source", "collector", "belt", "input", "held"))
                + stock["output"] + stock["player"] == 16, "Exact finite material conservation")
        entities, parts = snapshot["entities"], snapshot["parts"]
        require(set(parts) == set(KINDS) | {"shaft"}, "All declared carried part kinds")
        require(all(type(v) is int and v >= 0 for v in parts.values()), "Typed nonnegative parts")
        require(all(e["kind"] in KINDS for e in entities.values()), "Real supported entity kinds")
        for kind in KINDS:
            require(parts[kind] + sum(e["kind"] == kind for e in entities.values()) == 1,
                    "One actual starter part per kind: " + kind)
        drives, links = snapshot["drive_links"], snapshot["links"]
        require(parts["shaft"] + len(drives) == 3, "Three shafts accounted between kit and actual links")
        require(len({tuple(e) for e in links}) == len(links)
                and len({frozenset(e) for e in drives}) == len(drives), "No duplicate topology")
        require(all(len(e) == 2 and all(n in entities for n in e) for e in links + drives),
                "Every connection names current actual identities")

    def facts(reply, role):
        require(reply["status"] == "pass", "Input controller completed, not authority acceptance")
        f = reply["facts"]
        require(f["model_is_session"] and f["client_world_is_null"] and not f["auto_advance"],
                "Client has projection facade and no live rule owner or clock")
        require(f["scene_path"] == "/root/OpeningShared" and f["session_path"] == "/root/OpeningShared/Session",
                "Actual 3D scene and canonical RPC path")
        require(not f["save_slot"] and not f["save_ready"] and not f["save_owned"]
                and f["save_disabled"] and f["load_disabled"], "Network Store/rollback unavailable")
        require(f["sequence"] == f["session_sequence"] and f["namespace"] == f["session_namespace"],
                "View metadata mirrors the actual session identity")
        if f["ready"]:
            require(f["actor"] == role and bool(f["namespace"]), "Connection-bound actor and fresh namespace")
            ledger(f["projection"])
            require(f["state"] == f["projection"], "Actual view displays current session projection")
        return f

    def exchange_checked(commands, label):
        replies = exchange(deepcopy(commands))
        report["operations"].append({"label": label, "commands": deepcopy(commands), "responses": deepcopy(replies)})
        require(set(replies) == set(commands), "All and only requested actual UI processes responded")
        return {role: facts(reply, role) for role, reply in replies.items()}

    def send(roles, command, label):
        return exchange_checked({role: command for role in roles}, label)

    def key(roles, value):
        return send(roles, {"action": "key", "key": value}, "key:" + value)

    def cell(roles, x, z=0):
        return send(roles, {"action": "cell", "x": x, "z": z}, "cell:%d,%d" % (x, z))

    def button(roles, name):
        return send(roles, {"action": "button", "button": name}, "button:" + name)

    def settled(roles):
        return send(roles, {"action": "barrier", "condition": "settled"}, "actual verdict+projection settled")

    def boundary(kind, roles=()):
        value = transport_boundary(kind, roles=roles)
        report["transport_boundaries"].append({"kind": kind, "roles": list(roles), "evidence": deepcopy(value)})
        return value

    def server(label):
        value = observe_server()
        report["server_observations"].append({"label": label, "evidence": deepcopy(value)})
        require(value["clock_frozen"] is frozen_clock, "Actual declared server clock mode")
        ledger(value["snapshot"])
        require(value["snapshot"]["order"] == expected_order and value["checkpoint"]["order"] == expected_order,
                "Only declared ordinary UI commands entered authority")
        require(len(value["checkpoint"]["requests"]) == expected_order, "Each unique command retains one disposition")
        if frozen_clock:
            require(value["tick_count"] == 0 and value["snapshot"]["revision"] == expected_revision,
                    "Frozen observation does not invent authority ticks")
        return value

    def stable(snapshot):
        return {key: deepcopy(value) for key, value in snapshot.items() if key != "revision"}

    def converge(label):
        # This is an explicit read-only order/state barrier, not a retry of a
        # failed assertion/game action. Invariants fail immediately on any sample.
        deadline = time.monotonic() + 10
        for _ in range(64):
            value = send(ROLES, {"action": "observe"}, "convergence:" + label)
            if all(v["ready"] and v["projection"]["order"] >= expected_order for v in value.values()):
                if stable(value["P"]["projection"]) == stable(value["Q"]["projection"]):
                    return value
            if time.monotonic() >= deadline:
                break
        raise AssertionError("Authoritative views did not reach declared order/stable facts: " + label)

    def queue_receipt(f, label):
        receipt = f["last_submission"]
        require(receipt["queued"] is True and receipt["accepted"] is False and bool(receipt["request"]),
                label + ": queue is not authority acceptance")
        return receipt["request"]

    def decision(role, f, *, accepted=True):
        result = f["last_outcome"]
        require(not f["pending_actions"] and result["accepted"] is accepted and not result["duplicate"],
                "Actual unique server verdict, settled before dependent input")
        require(result["request"] == queue_receipt(f, role) and result["client"] == role
                and result["context"] == f["projection"]["context"], "Verdict belongs to this actual actor/request/context")
        return result

    def one_command(role, operation):
        nonlocal expected_order, expected_revision
        before = send((role,), {"action": "observe"}, "before actual command")[role]
        operation()
        expected_order += 1
        expected_revision += 1
        f = settled((role,))[role]
        require(f["sequence"] == before["sequence"] + 1, "One ordinary command allocates one new identity")
        decision(role, f)
        return f

    def place(role, selector, x):
        key((role,), selector)
        return one_command(role, lambda: cell((role,), x))

    def connect(role, selector, start, end):
        key((role,), selector)
        before = cell((role,), start)[role]
        require(before["pending_link"], "First actual endpoint creates local link selection")
        return one_command(role, lambda: cell((role,), end))

    def inspect_press(role):
        key((role,), "I")
        f = cell((role,), 2)[role]
        require(f["selected"] == "processor-1", "Actual native 3D click selects current press identity")
        return f

    def local(f):
        return {name: deepcopy(f[name]) for name in LOCAL_FIELDS}

    def capture(roles, label):
        replies = exchange_checked({role: {"action": "capture"} for role in roles}, "capture:" + label)
        last = report["operations"][-1]["responses"]
        report["captures"].extend({"role": role, "id": last[role]["id"], "file": "capture-%d.png" % last[role]["id"]}
                                  for role in roles)
        return replies

    def help_cycle(role, *, expect_live_work=False):
        before = send((role,), {"action": "observe"}, "before Help")[role]
        authority_before = server("before Help")
        key((role,), "H")
        opened = send((role,), {"action": "observe"}, "actual Help open")[role]
        require(opened["explanation_open"] and opened["help_title"] == "CURRENT TASK"
                and opened["goal"] in opened["help_body"], "Help shows the current shared objective")
        key((role,), "F5")
        key((role,), "F9")
        send((role,), {"action": "view_delta", "seconds": 120}, "presentation-only delta during Help")
        if expect_live_work:
            # P leaves the worksite through Help; Q and the actual server keep
            # working. No frozen-world assertion is made for this branch.
            one_command("Q", lambda: key(("Q",), "R"))
            send((role,), {"action": "barrier", "condition": "revision",
                           "minimum": authority_before["snapshot"]["revision"] + 2},
                 "real authority clock continues during Help")
            live = server("live Help with other participant")
            require(live["tick_count"] > authority_before["tick_count"], "Server alone advances real live time")
            require(live["snapshot"]["inventories"].get("Q", 0) == 1, "Other participant collects its own plate during Help")
        button((role,), "help_close_button")
        after = send((role,), {"action": "observe"}, "after Help")[role]
        require(not after["explanation_open"] and local(before) == local(after),
                "Help/navigation/save shortcuts preserve all exposed local player/request/save facts")
        authority_after = server("after Help")
        if frozen_clock:
            require(authority_after["checkpoint"] == authority_before["checkpoint"],
                    "Frozen Help preserves full actual server checkpoint, not just visible quantities")
            require(after["projection"] == before["projection"], "Frozen Help preserves complete player projection")
        else:
            require(after["projection"]["inventories"].get(role, 0) == before["projection"]["inventories"].get(role, 0),
                    "Live Help does not spend or credit the viewing actor")
        return before, after

    def local_goal(role, expected_inventory):
        before = send((role,), {"action": "observe"}, "before local goal confirmation")[role]
        authority_before = server("before local goal confirmation")
        require(before["projection"]["inventories"].get(role, 0) == expected_inventory,
                "Goal uses this actor's exact authoritative inventory")
        require(not before["confirmed"] and before["confirm_disabled"] is (expected_inventory < 4),
                "Goal availability is actor-specific, not aggregate stock")
        button((role,), "confirm_button")
        after = send((role,), {"action": "observe"}, "after local goal confirmation")[role]
        require(after["confirmed"] is (expected_inventory >= 4), "Only explicit qualified local acknowledgement")
        require(after["sequence"] == before["sequence"] and after["namespace"] == before["namespace"],
                "Goal confirmation emits no server command")
        authority_after = server("after local goal confirmation")
        require(authority_after["checkpoint"]["requests"] == authority_before["checkpoint"]["requests"]
                and authority_after["snapshot"]["inventories"] == authority_before["snapshot"]["inventories"],
                "Goal confirmation is non-consuming and does not create an authority request")

    try:
        initial = send(ROLES, {"action": "observe"}, "explicit deferred/not-ready boundary")
        report["initial"] = deepcopy(initial)
        for f in initial.values():
            require(not f["ready"] and not f["projection"] and not f["state"] and f["sequence"] == 0,
                    "Not-ready client invents no initial world")
        key(ROLES, "1")
        cell(ROLES, 0)
        key(ROLES, "R")
        key(ROLES, "SPACE")
        key(ROLES, "F5")
        key(ROLES, "F9")
        idle = send(ROLES, {"action": "observe"}, "not-ready mutation/save refusals")
        require(all(not f["ready"] and not f["projection"] and f["sequence"] == 0 for f in idle.values()),
                "Ordinary not-ready controls neither submit nor start a local world")
        button(ROLES, "reconnect_button")
        ready = send(ROLES, {"action": "barrier", "condition": "ready"}, "actual server welcome")
        require(ready["P"]["projection"]["context"] == ready["Q"]["projection"]["context"], "Both UI clients share one context")
        require(all(f["projection"]["stock"]["source"] == 16 and not f["projection"]["entities"]
                    and not f["projection"]["inventories"] for f in ready.values()), "Actual new finite empty worksite")
        original_server = server("initial actual authority")
        model_instance = original_server["model_instance"]
        context = original_server["context"]

        # Hold only admission, through the private server-local test seam. Both
        # real UI intents are queued against the same unmodified construction.
        key(ROLES, "1")
        baseline = send(ROLES, {"action": "observe"}, "before controlled contention")
        boundary("hold_admission", ROLES)
        queued = cell(ROLES, 0)
        requests = {role: queue_receipt(f, role) for role, f in queued.items()}
        boundary("wait_received", ROLES)
        for role, f in queued.items():
            require(f["pending_actions"] and f["sequence"] == baseline[role]["sequence"] + 1,
                    "Real UI shows queued command with owned pending state")
            require(stable(f["projection"]) == stable(baseline[role]["projection"]),
                    "Queue receipt cannot debit a part or create a machine")
        boundary("release_admission", ROLES)
        expected_order += 2
        expected_revision += 1
        conflict = settled(ROLES)
        decisions = {role: f["last_outcome"] for role, f in conflict.items()}
        require(sorted(r["accepted"] for r in decisions.values()) == [False, True],
                "Contested actual input has exactly one authority success")
        for role, f in conflict.items():
            require(f["last_outcome"]["request"] == requests[role], "Contested response keeps originating request identity")
            decision(role, f, accepted=f["last_outcome"]["accepted"])
        refusal = next(r for r in decisions.values() if not r["accepted"])
        require(refusal["reason"] == "occupied", "Real refusal is an occupied construction square")
        report["contested"] = deepcopy(decisions)
        views = converge("one conserved collector after controlled contention")
        require(all(len(f["projection"]["entities"]) == 1 and f["projection"]["parts"]["collector"] == 0
                    for f in views.values()), "One shared collector consumes exactly one starter part")

        place("P", "4", -1)
        place("Q", "2", 1)
        place("P", "3", 2)
        connect("P", "F", 0, 1)
        connect("Q", "F", 1, 2)
        connect("P", "G", -1, 0)
        connect("Q", "G", 0, 1)
        connect("P", "G", 1, 2)
        built = converge("ordinary actual 3D build/link controls")
        for f in built.values():
            snapshot = f["projection"]
            require(set(snapshot["entities"]) == {"collector-1", "wheel-1", "belt-1", "processor-1"},
                    "Stable identities arise from real placement")
            require({tuple(e) for e in snapshot["links"]} == {("collector-1", "belt-1"), ("belt-1", "processor-1")},
                    "Real directed material links")
            require(len(snapshot["drive_links"]) == 3 and all(v == 0 for v in snapshot["parts"].values())
                    and snapshot["powered"], "Actual complete drive consumes finite three shafts")
        server("after actual full build")
        inspect_press("P")
        inspect_press("Q")

        if frozen_clock:
            before = server("before explicit client-only delta")
            send(ROLES, {"action": "view_delta", "seconds": 120}, "client cannot advance the worksite")
            require(server("after client-only delta")["checkpoint"] == before["checkpoint"],
                    "No client clock or local factory mutation")
            # A nonempty selected/pending-link state must survive Help too.
            key(("P",), "F")
            cell(("P",), 0)
            help_cycle("P")
            local_goal("P", 0)
            local_goal("Q", 0)
        else:
            for amount in range(1, 5):
                send(("P",), {"action": "barrier", "condition": "output"}, "wait for real server-produced plate")
                one_command("P", lambda: key(("P",), "R"))
                seen = converge("actor-owned retrieval")
                require(all(f["projection"]["inventories"].get("P", 0) == amount
                            and f["projection"]["inventories"].get("Q", 0) == 0 for f in seen.values()),
                        "Only the requesting actor receives each real plate")
            local_goal("P", 4)
            local_goal("Q", 0)
            # Q is already inspecting the press; wait for a true next output,
            # then perform its real retrieval while P stays in isolated Help.
            send(("Q",), {"action": "barrier", "condition": "output"}, "live work before Help")
            help_cycle("P", expect_live_work=True)
            views = converge("live Help after other actor retrieval")
            require(views["P"]["confirmed"] and not views["Q"]["confirmed"], "Local goals never become shared campaign credit")
            require(all(f["projection"]["inventories"].get("P", 0) == 4
                        and f["projection"]["inventories"].get("Q", 0) == 1 for f in views.values()),
                    "P/Q inventories remain separately owned")

        # F5/F9 are actual global input paths, not only disabled GUI buttons.
        before = server("before shared save/load shortcuts")
        identities = send(ROLES, {"action": "observe"}, "before unavailable save/load")
        key(ROLES, "F5")
        key(ROLES, "F9")
        after = send(ROLES, {"action": "observe"}, "after unavailable save/load")
        for role, f in after.items():
            require(f["sequence"] == identities[role]["sequence"]
                    and f["save_result"] == {"accepted": False, "reason": "network_save_unavailable"}
                    and f["load_result"] == {"accepted": False, "reason": "network_load_unavailable"},
                    "F5/F9 explicitly unavailable and cannot send authority commands")
        require(server("after shared save/load shortcuts")["checkpoint"]["requests"] == before["checkpoint"]["requests"],
                "No client Store operation or server rollback request")
        capture(ROLES, "actual shared worksites")

        # Hold only the actual outcome delivery. The server applies a normal
        # power command and broadcasts state; the UI must still own the pending
        # request until it gets a disposition, even when it sees changed state.
        before_hold = send(("P",), {"action": "observe"}, "before held acknowledgement")["P"]
        old_namespace = before_hold["namespace"]
        boundary("hold_outcomes", ("P",))
        queued = key(("P",), "SPACE")["P"]
        held_request = queue_receipt(queued, "held power outcome")
        expected_order += 1
        expected_revision += 1
        boundary("wait_outcomes", ("P",))
        applied = server("applied command with withheld acknowledgement")
        stored = [entry for entry in applied["checkpoint"]["requests"].values()
                  if entry["intent"].get("client") == "P" and entry["intent"].get("request") == held_request]
        require(len(stored) == 1 and stored[0]["result"]["accepted"]
                and stored[0]["intent"]["action"] == "set_power", "Actual server retains the applied-but-unacknowledged disposition")
        pending = send(("P",), {"action": "observe"}, "actual UI still pending without outcome")["P"]
        require(held_request in pending["pending_actions"] and not pending["pending_actions"][held_request]["outcome"],
                "A fresh projection alone cannot acknowledge a queued action")
        button(("P",), "disconnect_button")
        send(("P",), {"action": "barrier", "condition": "disconnected"}, "actual participant disconnect")
        wait_role_absent("P")
        lost = send(("P",), {"action": "observe"}, "uncertain action after disconnect")["P"]
        require(not lost["ready"] and not lost["pending_actions"] and any(
            entry["request"] == held_request and entry["disposition"] == "unknown" for entry in lost["uncertain"]),
                "Client retains explicit uncertainty and performs no blind retry")
        boundary("release_outcomes", ("P",))
        # The accepted command stopped power. Q can still act while P is absent;
        # doing so restores ordinary production in the live branch.
        one_command("Q", lambda: key(("Q",), "SPACE"))
        offline_sequence = lost["sequence"]
        key(("P",), "1")
        cell(("P",), 3)
        key(("P",), "R")
        offline = send(("P",), {"action": "observe"}, "disconnected ordinary controls refused")["P"]
        require(not offline["ready"] and offline["sequence"] == offline_sequence,
                "Disconnected mutations cannot send work or instantiate a fallback")
        before_rejoin = server("server continues with one participant")
        require(before_rejoin["model_instance"] == model_instance and before_rejoin["context"] == context,
                "Disconnect does not replace the server Model or context")
        button(("P",), "reconnect_button")
        joined = send(("P",), {"action": "barrier", "condition": "ready"}, "actual rejoin welcome")["P"]
        require(joined["namespace"] != old_namespace and joined["sequence"] == 0 and not joined["selected"]
                and not joined["pending_link"] and not joined["confirmed"], "Rejoin refreshes namespace/selection/local acknowledgement")
        require(joined["projection"]["context"] == context, "Rejoin obtains the continuing authority, not a local new world")
        after_rejoin = server("retained server disposition after rejoin")
        retained = [entry for entry in after_rejoin["checkpoint"]["requests"].values()
                    if entry["intent"].get("client") == "P" and entry["intent"].get("request") == held_request]
        require(retained == stored, "Returning UI cannot erase or reapply the old accepted command")
        views = converge("fresh participant converges to continuing worksite")
        report["pending_loss"] = {"request": held_request, "old_namespace": old_namespace,
                                  "new_namespace": joined["namespace"], "server_disposition_retained": True,
                                  "uncertainty_explicit": True, "automatic_retry": False}
        if not frozen_clock:
            require(views["P"]["projection"]["inventories"].get("P", 0) == 4
                    and views["Q"]["projection"]["inventories"].get("Q", 0) == 1,
                    "Actor-owned inventory survives disconnect/rejoin")
            local_goal("P", 4)
            local_goal("Q", 1)
        capture(ROLES, "after actual rejoin")
        final_running = server("final continuing authority before stop")
        report["final_running"] = deepcopy(final_running)

        # Graceful lifecycle is supplied by the sole supervisor; this module
        # creates no process, writes no stop file and opens no socket.
        stopped = boundary("stop_server")
        require(stopped["checkpoint"] == final_running["checkpoint"] if frozen_clock else
                stopped["checkpoint"]["requests"] == final_running["checkpoint"]["requests"],
                "Lifecycle stop cannot introduce an extra game command")
        disconnected = send(ROLES, {"action": "barrier", "condition": "disconnected"}, "actual server loss")
        for f in disconnected.values():
            require(not f["ready"] and not f["pending_actions"], "Stopped authority never becomes a local live world")
        stopped_sequences = {role: f["sequence"] for role, f in disconnected.items()}
        key(ROLES, "R")
        key(ROLES, "SPACE")
        key(ROLES, "F5")
        key(ROLES, "F9")
        refused = send(ROLES, {"action": "observe"}, "stopped-server mutation/save refusal")
        require(all(not f["ready"] and f["sequence"] == stopped_sequences[role] for role, f in refused.items()),
                "Server loss cannot turn local input into accepted work")
        button(ROLES, "reconnect_button")
        send(ROLES, {"action": "barrier", "condition": "disconnected"},
             "missing-server connection reaches explicit terminal refusal")
        absent = send(ROLES, {"action": "observe"}, "explicit reconnect with no server")
        require(all(not f["ready"] and f["client_world_is_null"] for f in absent.values()),
                "Missing server refuses readiness and has no silent local fallback")
        report.update(status="pass", final=deepcopy(absent), final_server=deepcopy(stopped),
                      ordinary_commands=expected_order, accepted_commands=expected_revision,
                      old_namespace_retry="separate actual transport proof; not relabelled UI input")
        return report
    except Exception as error:
        report.update(status="fail", error=str(error), ordinary_commands=expected_order,
                      accepted_commands=expected_revision)
        raise UICaseFailure(str(error), report) from error
