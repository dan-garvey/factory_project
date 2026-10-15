#!/usr/bin/env python3
"""Bounded optional mechanical workshop; invoke through run_local.py heavy."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

import check_engine_environment as bounds

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "experiments/engine-environment/godot"
FILES = bounds.FILES + ("mechanics/authority.gd",) + tuple("workshop/" + name for name in (
    "authority.gd", "view.gd", "main.tscn", "check.gd", "startup_observer.gd"))
MAX_BYTES = 256 * 1024**2
VERSION = "4.7.2.stable.official.ed1daf0bf"
EPSILON = 0.00002


def require(ok, label):
    if not ok:
        raise ValueError("Workshop oracle: " + label)


def near(a, b):
    return abs(a - b) < EPSILON


def vector(a, b):
    return len(a) == len(b) and all(near(x, y) for x, y in zip(a, b))


def verify(report):
    require(report["status"] == "pass" and not report["failures"] and report["checks"] > 500,
            "actual input assertion report")
    cases = report["cases"]
    require(set(cases) == {"empty", "miss", "positive8", "positive32", "negative8", "negative32",
                          "ratio20two", "blocked", "isolated32", "recovered", "late_stop", "U3blocked", "U4clear"},
            "all placement/direction/ratio/clearance/recovery controls")
    for name, case in cases.items():
        if name == "empty":
            require(not case["state"]["layout"]["ready"] and case["state"]["layout"]["pieces"]["gear"] is None,
                    "empty/invalid board cannot invent a ready assembly")
            continue
        state, native = case["state"], case["native"]
        require("stock" not in state and "inventories" not in state, "non-consuming mechanism, not fabricated production")
        for item in case["steps"]:
            before, after, observed = item["before"], item["after"], item["native"]
            require(item["admission"]["state"]["pending"] and not after["pending"] and not after["native_pending"],
                    "real N admission remains owned until completed native state")
            require(after["attempts"] == before["attempts"] + 1
                    and after["committed"] == before["committed"] + int(item["accepted"]), "once-only native outcome")
            delta = math.pi / 8 if item["accepted"] else 0
            ratio = (1 if after["teeth"] == 20 else 0.5) * (1 if after["idler"] else -1)
            require(near(after["source_phase"] - before["source_phase"], delta)
                    and near(after["phases"]["U"] - before["phases"]["U"], delta / 2)
                    and near(after["phases"]["B"] - before["phases"]["B"], delta * ratio if after["coupled"] else 0),
                    "unchanged source/signed gearing/isolated phase law")
            for branch in ("B", "U"):
                mount = after["mounts"][branch]
                expected = [mount[0] + 2 * math.sin(after["phases"][branch]), 0.75, mount[1]]
                require(vector(observed["bodies"][branch], expected)
                        and vector(after["completed"]["positions"][branch], expected), "independent RID coordinate oracle")
                require(vector(observed["sizes"][branch], [0.55, 0.8, 0.8]), "actual declared slider shape")
            bx = observed["bodies"]["B"][0]
            overlap = bx + 0.275 > 1.3 and bx - 0.275 < 1.9
            require(after["target_occupied"] is overlap, "actual declared work-area overlap")
            entries = int(item["accepted"] and overlap and not before["target_occupied"])
            require(after["contact_entries"] == before["contact_entries"] + entries,
                    "non-consuming work entries follow geometry, never injected quantity")
            if not item["accepted"]:
                require(after["phases"] == before["phases"] and after["positions"] == before["positions"],
                        "native solid stalls every connected phase without partial movement")
                stop = after["layout"]["pieces"]["stop"]["cell"]
                require(near(after["last_collision"]["point"][0], stop[0] - 0.175)
                        and vector(after["last_collision"]["normal"], [-1, 0, 0]), "real native stop face/normal")
        require(native["ids"] == case["steps"][-1]["native"]["ids"], "published case uses real retained bodies")
    require(cases["miss"]["state"]["contact_entries"] == 0 and cases["miss"]["state"]["committed"] == 32,
            "player B mount -1 misses over complete cycle")
    require(near(cases["positive8"]["state"]["phases"]["B"], math.pi / 2)
            and cases["positive8"]["state"]["contact_entries"] == 1, "positive first8 working encounter")
    require(near(cases["negative8"]["state"]["phases"]["B"], -math.pi / 2)
            and cases["negative8"]["state"]["contact_entries"] == 0
            and cases["negative32"]["state"]["contact_entries"] > 0, "early reversal contrast versus later full-cycle reach")
    require(cases["positive8"]["steps"][1]["after"]["contact_entries"] == 0
            and cases["ratio20two"]["state"]["contact_entries"] == 1, "player output gear changes native contact timing")
    require(cases["blocked"]["state"]["committed"] == 1 and cases["blocked"]["state"]["contact_entries"] == 0
            and cases["late_stop"]["state"]["committed"] == 4 and cases["late_stop"]["state"]["contact_entries"] == 1,
            "player stop x1 versus x2 changes work before actual obstruction")
    blocked, isolated, recovered = (cases[k] for k in ("blocked", "isolated32", "recovered"))
    require(near(isolated["state"]["phases"]["B"], math.pi / 16)
            and near(isolated["state"]["phases"]["U"], 33 * math.pi / 16)
            and near(recovered["state"]["phases"]["B"], 3 * math.pi / 16), "retained phase through isolated cycle/recovery")
    require(blocked["native"]["ids"] == isolated["native"]["ids"] == recovered["native"]["ids"]
            and blocked["native"]["stop_id"] == recovered["native"]["stop_id"], "native identity survives entire recovery")
    require(cases["U3blocked"]["state"]["blocked"] and cases["U3blocked"]["state"]["last_collision"]["branch"] == "U"
            and not cases["U4clear"]["state"]["blocked"] and cases["U4clear"]["state"]["committed"] == 8,
            "U mount clearance matters even when only B is isolated")


def equivalent(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(equivalent(a[k], b[k]) for k in a if k not in {"ids", "stop_id"})
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(equivalent(x, y) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return near(a, b)
    return a == b


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--duration-seconds", type=int, default=900)
    args = parser.parse_args()
    if (args.render and not args.check) or (args.smoke and args.check):
        parser.error("--render requires --check; --smoke selects normal entry and cannot combine with --check")
    if not 1 <= args.duration_seconds <= 1700:
        parser.error("Use a bounded 1..1700 second normal session")
    binary, artifacts = args.godot, args.artifacts
    if (not binary.is_absolute() or binary.resolve() != binary or not binary.is_file()
            or not os.access(binary, os.X_OK) or not re.fullmatch(r"[0-9a-f]{64}", args.sha256)
            or hashlib.sha256(binary.read_bytes()).hexdigest() != args.sha256):
        parser.error("Use the existing absolute verified executable and exact lowercase SHA256 pin")
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error("Use an owned external artifact root without symlinks")
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"], capture_output=True, text=True, env=env, timeout=5)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        parser.error("Keep artifacts outside Git worktrees and administration")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error("Require 22 GiB free and under 256 MiB retained workshop evidence")
    run = Path(tempfile.mkdtemp(prefix="workshop-", dir=artifacts))
    project = run / "project"
    receipt = {"status": "running", "mode": "check" if args.check else "smoke" if args.smoke else "normal",
               "source_hashes": {}, "stages": [], "user_play": "not_assessed", "started": datetime.now(timezone.utc).isoformat(),
               "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "binary": str(binary), "binary_sha256": args.sha256,
               "runner_hashes": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__), Path(bounds.__file__)]}}
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    deadline = time.monotonic() + 1800
    print("Workshop evidence: " + str(run), flush=True)
    try:
        total = 0
        for name in FILES:
            source = PROJECT / name
            if source.is_symlink() or not source.is_file():
                raise ValueError("Missing or unsafe source: " + name)
            content = source.read_bytes()
            total += len(content)
            if total > 2 * 1024**2:
                raise ValueError("Workshop source allowance exceeded")
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            receipt["source_hashes"][name] = hashlib.sha256(content).hexdigest()
        for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
            folder = run / name
            folder.mkdir()
            env[key] = str(folder)

        def execute(name, arguments, marker=None, timeout=60):
            left = deadline - time.monotonic()
            if left <= 0:
                raise ValueError("Workshop reached 30 minute allowance")
            log = run / (name + ".log")
            result = bounds.execute_bounded([str(binary), *arguments], cwd=project, env=env, log=log,
                                            artifacts=artifacts, timeout=min(timeout, left))
            output = log.read_text(errors="replace")
            receipt["stages"].append({"name": name, "exit": result.returncode, "arguments": arguments})
            if result.returncode or "ERROR:" in output or (marker and marker not in output):
                raise ValueError(name + " failed; inspect " + str(log))
            return output

        require(execute("version", ["--version"]).strip() == VERSION, "separately verified supported version")
        execute("import", ["--headless", "--editor", "--path", str(project), "--import"], timeout=180)
        receipt["post_import_config_sha256"] = hashlib.sha256((project / "project.godot").read_bytes()).hexdigest()
        if args.check:
            execute("input", ["--headless", "--path", str(project), "--script", "res://workshop/check.gd", "--", "--report=" + str(run / "input.json")], "WORKSHOP_PASS", 240)
            physical = json.loads((run / "input.json").read_text())
            verify(physical)
            if args.render:
                execute("render", ["--path", str(project), "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--script", "res://workshop/check.gd", "--", "--report=" + str(run / "render.json"), "--capture=" + str(run / "workshop.png")], "WORKSHOP_PASS", 240)
                rendered = json.loads((run / "render.json").read_text())
                verify(rendered)
                require(equivalent(physical["cases"], rendered["cases"]), "headless/rendered mechanism and input outcomes agree")
        else:
            arguments = ["--path", str(project), "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "res://workshop/main.tscn"]
            if args.smoke:
                config = project / "project.godot"
                config.write_text(config.read_text() + '\n[autoload]\nWorkshopStartupObserver="*res://workshop/startup_observer.gd"\n')
                receipt["instrumentation"] = {"kind": "read_only_startup_autoload", "runtime_config_sha256": hashlib.sha256(config.read_bytes()).hexdigest(), "observer_sha256": receipt["source_hashes"]["workshop/startup_observer.gd"]}
                arguments += ["--", "--observer-report=" + str(run / "startup.json"), "--observer-capture=" + str(run / "startup.png")]
            try:
                execute("normal", arguments, "WORKSHOP_STARTUP_PASS" if args.smoke else None, 30 if args.smoke else args.duration_seconds)
                if not args.smoke:
                    receipt["completion_reason"] = "window_closed"
            except subprocess.TimeoutExpired:
                if args.smoke:
                    raise
                receipt["completion_reason"] = "duration_limit"
            if args.smoke:
                observed = json.loads((run / "startup.json").read_text())
                require(observed["status"] == "pass" and observed["scene"] == "res://workshop/main.tscn"
                        and not observed["B_visible"] and not observed["U_visible"], "actual normal empty workshop startup")
                require(observed["state"]["layout"]["pieces"] == dict.fromkeys(("B", "U", "gear", "idler", "stop")), "normal entry invents no construction")
        receipt["status"] = "pass" if args.check or args.smoke else "closed"
    except BaseException as error:
        receipt.update(status="fail", error=str(error))
        raise
    finally:
        receipt.update(finished=datetime.now(timezone.utc).isoformat(), owned_bytes=bounds.owned_bytes(artifacts))
        (run / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("Workshop finished: " + str(run), flush=True)


if __name__ == "__main__":
    main()
