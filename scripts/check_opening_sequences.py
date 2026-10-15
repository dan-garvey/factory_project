#!/usr/bin/env python3
"""Bounded fixed-seed opening Model/Store probes; run through run_local.py heavy."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

import check_engine_environment as bounds

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "experiments/engine-environment/godot"
PROBE = "opening/seeded-tests/probe.gd"
FILES = bounds.FILES + ("save-tests/checkpoint_file.gd", PROBE)
SEEDS = [7, 29, 101, 2027]
CELLS = {"wheel": [-1, 0], "collector": [0, 0], "belt": [1, 0], "processor": [2, 0]}
MAX_BYTES = 128 * 1024**2


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024**2):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition, label):
    if not condition:
        raise ValueError("Seeded probe oracle: " + label)


def integer(value):
    return type(value) is int and value >= 0


def ledger(state):
    """Independent fixture invariants, not a command simulator/schema validator."""
    require(isinstance(state, dict), "actual state dictionary")
    stock, parts, entities = (state[name] for name in ("stock", "parts", "entities"))
    require(all(integer(stock.get(name)) for name in ("source", "collector", "belt", "input", "held", "output", "player")), "typed quantities")
    require(all(stock[name] <= 1 for name in ("collector", "belt", "input", "held", "output")), "one-item buffers")
    inventories = state["inventories"]
    require(all(client in ("P", "Q") and integer(n) for client, n in inventories.items()), "typed client inventory")
    require(stock["player"] == sum(inventories.values()), "one carried owner count")
    require(sum(stock[name] for name in ("source", "collector", "belt", "input", "held", "output", "player")) == 16,
            "sixteen conserved one-to-one items")
    require(type(state["initial_feed"]) is int and state["initial_feed"] == 16
            and type(state["recipe_input"]) is int and state["recipe_input"] == 1, "declared fixture")
    require(integer(state["remaining"]) and state["remaining"] <= 2 and (stock["held"] == 1 or state["remaining"] == 0), "retained phase")
    counts = dict.fromkeys(CELLS, 0)
    for identity, entity in entities.items():
        kind = entity["kind"]
        require(type(identity) is str and kind in CELLS and entity["cell"] == CELLS[kind], "actual fixture placements")
        counts[kind] += 1
    require(all(integer(parts.get(kind)) and parts[kind] + counts[kind] == 1 for kind in CELLS), "finite machine part ledgers")
    require(integer(parts.get("shaft")) and parts["shaft"] + len(state["drive_links"]) == 3, "finite shaft ledger")
    for drive, name in ((False, "links"), (True, "drive_links")):
        seen = set()
        for pair in state[name]:
            require(isinstance(pair, list) and len(pair) == 2 and all(type(x) is str and x in entities for x in pair)
                    and pair[0] != pair[1], "actual link identities")
            key = tuple(sorted(pair)) if drive else tuple(pair)
            require(key not in seen, "unique link")
            seen.add(key)
            a, b = (entities[x] for x in pair)
            if drive:
                require(sum(abs(x - y) for x, y in zip(a["cell"], b["cell"])) == 1, "neighbor drive")
            else:
                require((a["kind"], b["kind"]) in (("collector", "belt"), ("belt", "processor")), "material direction")
    for kind, locations in (("collector", ["collector"]), ("belt", ["belt"]), ("processor", ["input", "held", "output"])):
        require(not any(stock[name] for name in locations) or counts[kind] == 1, "live material owner")


def verify(report, evidence):
    require(report.get("schema") == 1 and type(report.get("schema")) is int and report.get("status") == "pass", "actual pass report")
    require(report.get("seeds") == SEEDS and report.get("random_steps") == 64, "declared seeds and limits")
    cases = report.get("cases")
    require(isinstance(cases, list) and [case.get("seed") for case in cases] == SEEDS, "all fixed seeds actually complete")
    for case in cases:
        events, stats, seed = case["events"], case["stats"], case["seed"]
        require(0 < len(events) <= 256 and case["random_steps"] == 64, "bounded actual event prefix")
        require([e["random_index"] for e in events if "random_index" in e] == list(range(64)), "every generated step observed")
        tallies = dict.fromkeys(("accepted", "refused", "duplicates", "collision", "foreign", "roundtrips", "ticks"), 0)
        for index, event in enumerate(events):
            require(type(event["index"]) is int and event["index"] == index, "ordered trace")
            state = event["state"]
            ledger(state)
            require(state["context"] == "opening-seed-" + str(seed), "trace world identity")
            operation = event["op"]
            if operation == "command":
                require(type(event["outcome"]["accepted"]) is bool, "typed actual disposition")
                tallies["accepted" if event["outcome"]["accepted"] else "refused"] += 1
            elif operation in ("duplicate", "collision", "foreign"):
                tallies["duplicates" if operation == "duplicate" else operation] += 1
            elif operation == "advance":
                require(integer(event["ticks"]), "bounded explicit clock")
                tallies["ticks"] += event["ticks"]
            elif operation == "store":
                require(event["write"]["accepted"] is True and event["read"]["accepted"] is True
                        and event["roundtrip_equal"] is True and event["continuation_equal"] is True
                        and event["continuation_ticks"] == 1, "actual same-model Store roundtrip/continuation")
                tallies["roundtrips"] += 1
                tallies["ticks"] += 1
            else:
                require(False, "known observed operation")
        require(all(integer(value) for value in stats.values()) and stats == tallies and stats["accepted"] >= 12 and stats["refused"] >= 4
                and stats["duplicates"] >= 2 and stats["collision"] >= 2 and stats["foreign"] >= 1
                and stats["roundtrips"] == 7, "directed control coverage and truthful totals")
        ledger(case["final"])
        require(case["final"]["stock"]["player"] == 16 and all(case["final"]["stock"][n] == 0
                for n in ("source", "collector", "belt", "input", "held", "output")), "actual complete drain")
        require(len(case["saves"]) == 7, "all immutable good save slots")
        for index, save in enumerate(case["saves"]):
            path = Path(save["path"])
            require(path == evidence / f"seed-{seed}-slot-{index}.factory" and path.is_file() and not path.is_symlink(), "owned real save path")
            data = path.read_bytes()
            require(0 < len(data) == save["bytes"] <= 1024**2 and hashlib.sha256(data).hexdigest() == save["sha256"]
                    and not Path(str(path) + ".pending").exists(), "original good save bytes preserved")
        paused, blocked = case["saves"][:2]
        require(paused["label"] == "paused-partial" and paused["stock"]["held"] == 1
                and paused["remaining"] == 2 and paused["power_enabled"] is False, "real paused partial-work save")
        require(blocked["label"] == "blocked" and blocked["stock"]["held"] == blocked["stock"]["output"] == 1
                and blocked["remaining"] == 0 and blocked["power_enabled"] is True, "real blocked-work save")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    args = parser.parse_args()
    if not args.godot.is_absolute() or args.godot.resolve() != args.godot or not args.godot.is_file() or not os.access(args.godot, os.X_OK):
        parser.error("Use the existing absolute verified executable without symlinks")
    if file_hash(args.godot) != args.sha256:
        parser.error("Existing runtime does not match the explicit verified binary pin")
    artifacts = args.artifacts
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error("Use an owned external absolute artifact root without symlinks")
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"], capture_output=True, text=True)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        parser.error("Keep seeded artifacts outside Git worktrees/administration")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error("Require 22 GiB free and less than 128 MiB retained artifacts")
    run = Path(tempfile.mkdtemp(prefix="run-", dir=artifacts))
    project, evidence = run / "project", run / "evidence"
    evidence.mkdir()
    environment = os.environ.copy()
    receipt = {"status": "running", "started": datetime.now(timezone.utc).isoformat(), "source_hashes": {}, "stages": [],
               "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "binary_sha256": args.sha256, "seeds": SEEDS, "random_steps": 64,
               "runner_hashes": {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (
                   ("check_opening_sequences.py", Path(__file__)), ("check_engine_environment.py", Path(bounds.__file__)))}}
    deadline = time.monotonic() + 600
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    print(f"Seeded opening evidence: {run}", flush=True)
    try:
        total = 0
        for name in FILES:
            source = PROJECT / name
            if source.is_symlink() or not source.is_file() or source.stat().st_size > 2 * 1024**2 - total:
                raise ValueError("Missing/unsafe/excessive probe input: " + name)
            data = source.read_bytes()
            total += len(data)
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            receipt["source_hashes"][name] = hashlib.sha256(data).hexdigest()
        for variable, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
            directory = run / name
            directory.mkdir()
            environment[variable] = str(directory)

        def execute(name, arguments, marker=None, timeout=30):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("Seeded proof reached its ten minute allowance")
            log = run / (name + ".log")
            result = bounds.execute_bounded([str(args.godot), *arguments], cwd=project, env=environment,
                                            log=log, artifacts=artifacts, timeout=min(timeout, remaining))
            output = log.read_text(errors="replace")
            receipt["stages"].append({"name": name, "exit": result.returncode, "arguments": arguments})
            if result.returncode or "ERROR:" in output or (marker and marker not in output):
                raise ValueError(f"{name} failed; inspect {log} and retained seed prefix")
            return output

        if execute("version", ["--version"]).strip() != "4.7.2.stable.official.ed1daf0bf":
            raise ValueError("Require the separately verified Godot4.7.2 official binary")
        execute("import", ["--headless", "--editor", "--path", str(project), "--import"], timeout=180)
        receipt["post_import_project_sha256"] = hashlib.sha256((project / "project.godot").read_bytes()).hexdigest()
        execute("sequences", ["--headless", "--path", str(project), "--script", "res://" + PROBE, "--",
                              "--evidence=" + str(evidence), "--report=" + str(run / "sequences.json")], "OPENING_SEQUENCES_PASS", 180)
        report = json.loads((run / "sequences.json").read_text())
        verify(report, evidence)
        receipt["status"] = "pass"
        receipt["summary"] = [{"seed": case["seed"], "events": len(case["events"]), "stats": case["stats"], "final_stock": case["final"]["stock"]} for case in report["cases"]]
    except Exception as error:
        receipt["status"] = "fail"
        receipt["error"] = str(error)
        raise
    finally:
        receipt["finished"] = datetime.now(timezone.utc).isoformat()
        receipt["owned_bytes"] = bounds.owned_bytes(artifacts)
        (run / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Seeded opening sequences PASS; this is bounded correctness/roundtrip coverage, not exhaustive or player evidence")


if __name__ == "__main__":
    main()
