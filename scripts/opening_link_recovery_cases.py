"""Actual local-link choice recovery after a peer replaces its first endpoint.

The same pure input case records old obsolete-ID refusals before a final defect
assertion. Ordinary tool reselect is an explicit manual recovery control, not a
request retry. The supervisor owns every process, file and transport boundary.
"""
from copy import deepcopy


class LinkRecoveryFailure(AssertionError):
    def __init__(self, message, report):
        super().__init__(message)
        self.report = report


def run_ui_cases(exchange, *, frozen_clock, wait_role_absent, observe_server, transport_boundary):
    report = {"status": "running", "case": "removed_unsubmitted_link_endpoint", "operations": [],
              "server_cuts": [], "stale_choices": [], "obsolete_requests": [], "user_play": "not_assessed"}

    def need(value, label):
        if not value:
            raise AssertionError(label)

    def ledger(s):
        need(s["stock"] == {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0, "player": 0}
             and all(type(v) is int for v in s["stock"].values()) and not s["inventories"], "All finite material remains at actual source")
        need(set(s["parts"]) == {"collector", "belt", "wheel", "processor", "shaft"}
             and all(type(v) is int and v >= 0 for v in s["parts"].values()), "Typed actual parts")
        for kind in ("collector", "belt", "wheel", "processor"):
            need(s["parts"][kind] + sum(e["kind"] == kind for e in s["entities"].values()) == 1, "One original part:" + kind)
        need(s["parts"]["shaft"] + len(s["drive_links"]) == 3, "Three actual shafts conserved")
        need(s["remaining"] == 0 and s["powered"] is False, "No hidden factory work")

    def send(role, **command):
        reply = exchange({role: deepcopy(command)})[role]
        report["operations"].append({"role": role, "command": command, "response": deepcopy(reply)})
        f = reply["facts"]
        need(reply["status"] == "pass" and f["model_is_session"] and f["client_world_is_null"] and not f["auto_advance"], "Actual projection-only shared client")
        need(f["state"] == f["projection"], "View consumes actual current projection")
        if f["ready"]:
            ledger(f["projection"])
            need(f["actor"] == role and f["namespace"] == f["session_namespace"] and f["sequence"] == f["session_sequence"], "Bound actor/namespace sequence")
        return f

    def key(role, k): return send(role, action="key", key=k)
    def cell(role, x): return send(role, action="cell", x=x)
    def settled(role): return send(role, action="barrier", condition="settled")

    def server(label):
        v = observe_server()
        report["server_cuts"].append({"label": label, "evidence": deepcopy(v)})
        ledger(v["snapshot"])
        need(v["clock_frozen"] is True and v["tick_count"] == 0, "Frozen observation clock")
        need(v["model_instance"] == identity[0] and v["context"] == identity[1], "Same actual authority")
        need(len(v["checkpoint"]["requests"]) == v["snapshot"]["order"], "Each admitted unique request retained")
        return v

    def command(role, operation):
        before = send(role, action="observe")
        operation()
        f = settled(role)
        r, q = f["last_outcome"], f["last_submission"]
        need(f["sequence"] == before["sequence"] + 1 and q["queued"] is True and q["accepted"] is False,
             "Fresh ordinary action is queued, never speculative success")
        need(r["accepted"] is True and r["duplicate"] is False and r["request"] == q["request"] and r["client"] == role,
             "Real matching accepted disposition")
        return f

    def place(role, k, x):
        key(role, k)
        return command(role, lambda: cell(role, x))

    def remove(role, x):
        key(role, "I")
        cell(role, x)
        return command(role, lambda: send(role, action="button", button="remove_button"))

    def currentP(v):
        f = send("P", action="barrier", condition="revision", minimum=v["snapshot"]["revision"])
        need(f["projection"] == v["snapshot"], "P sees actual complete replacement snapshot")
        return f

    try:
        need(frozen_clock is True, "Link recovery case requires frozen observation")
        for role in ("P", "Q"):
            send(role, action="button", button="reconnect_button")
            send(role, action="barrier", condition="ready")
        first = observe_server()
        identity = (first["model_instance"], first["context"])
        place("Q", "1", 0)
        place("Q", "2", 1)
        key("P", "F")
        chosen = cell("P", 0)
        need(chosen["pending_link"] == "collector-1" and chosen["sequence"] == 0, "First material endpoint is local only")
        place("Q", "4", -1)
        unrelated = currentP(server("unrelated Q placement"))
        need(unrelated["pending_link"] == "collector-1" and unrelated["selected"] == "collector-1" and unrelated["sequence"] == 0,
             "Unrelated authoritative update preserves valid chosen endpoint")
        for tool, old_id, new_id, position, selector, target in (("F", "collector-1", "collector-2", 0, "1", 1),
                                                                  ("G", "wheel-1", "wheel-2", -1, "4", 0)):
            if tool == "G":
                key("P", tool)
                need(cell("P", position)["pending_link"] == old_id, "First drive endpoint is local only")
            before = send("P", action="observe")
            remove("Q", position)
            place("Q", selector, position)
            replaced = server("peer removed and rebuilt " + old_id)
            f = currentP(replaced)
            need(old_id not in f["projection"]["entities"] and new_id in f["projection"]["entities"] and f["sequence"] == before["sequence"],
                 "Removal/rebuild uses a new actual ID without a P command")
            report["stale_choices"].append({"tool": tool, "old_id": old_id, "new_id": new_id, "facts": deepcopy(f)})
            send("P", action="capture")
            cell("P", target)
            after = settled("P")
            after_server = server("actual next click after replacement")
            if after["sequence"] == before["sequence"] + 1:
                # Preserve the old defect's actual protocol consequence rather
                # than pretending a retained pointer was only a display issue.
                r = after["last_outcome"]
                need(r["accepted"] is False and r["reason"] == "missing_entity" and r["duplicate"] is False,
                     "Obsolete endpoint gets the real authoritative refusal")
                rows = [x for x in after_server["checkpoint"]["requests"].values() if x["intent"]["request"] == r["request"]]
                need(len(rows) == 1 and rows[0]["intent"]["from"] == old_id, "Actual obsolete-ID request retained")
                report["obsolete_requests"].append(deepcopy(rows[0]))
            else:
                need(after["sequence"] == before["sequence"] and after_server["checkpoint"] == replaced["checkpoint"],
                     "A new first local click creates no server command")
                target_id = "belt-1" if tool == "F" else "collector-2"
                need(after["pending_link"] == target_id and after["selected"] == target_id,
                     "Next click starts a fresh local endpoint without changing the chosen tool")
            send("P", action="capture")
            # Same explicit manual tool reselect on both revisions isolates the
            # stale-choice evidence while demonstrating stock-safe recovery.
            key("P", tool)
            need(cell("P", position)["pending_link"] == new_id, "Player explicitly chooses the new first endpoint")
            command("P", lambda target=target: cell("P", target))
        final = server("final same-worksite material and drive recovery")
        s = final["snapshot"]
        need(s["revision"] == 9 and s["order"] == 9 + len(report["obsolete_requests"]), "Exactly declared accepted work plus recorded obsolete refusals")
        need(s["entities"] == {"collector-2": {"kind": "collector", "cell": [0, 0]}, "belt-1": {"kind": "belt", "cell": [1, 0]}, "wheel-2": {"kind": "wheel", "cell": [-1, 0]}}, "Stable new identities chosen explicitly")
        need(s["links"] == [["collector-2", "belt-1"]] and s["drive_links"] == [["wheel-2", "collector-2"]]
             and s["parts"] == {"collector": 0, "belt": 0, "wheel": 0, "processor": 1, "shaft": 2}, "Only corrected current-ID links consume actual parts")
        need(final["checkpoint"]["next_ids"] == {"collector": 3, "belt": 2, "wheel": 3, "processor": 1}, "No identity reset or reuse")
        report.update(final=final)
        need(all(not x["facts"]["pending_link"] and not x["facts"]["selected"] for x in report["stale_choices"]),
             "Removed first endpoint remains selected after authoritative replacement")
        need(not report["obsolete_requests"], "Stale local endpoint sends an unnecessary obsolete-ID command")
        report["status"] = "pass"
        return report
    except Exception as error:
        report.update(status="fail", error=str(error))
        raise LinkRecoveryFailure(str(error), report) from error
