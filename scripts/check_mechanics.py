#!/usr/bin/env python3
"""Bounded native-physics mechanics fixture; invoke through run_local.py heavy."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

import check_engine_environment as bounds


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "experiments/engine-environment/godot"
FILES = bounds.FILES + tuple("mechanics/" + name for name in (
    "authority.gd", "view.gd", "main.tscn", "check.gd"))
MAX_BYTES = 256 * 1024**2
EPSILON = 0.00001  # Fixture comparison tolerance; not a game or network target.


def verify(value):
    def require(condition, label):
        if not condition:
            raise ValueError("Mechanics oracle: " + label)

    def near(a, b):
        return abs(a - b) < EPSILON

    require(value["status"] == "pass" and value["checks"] >= 80 and not value["failures"], "actual assertion report")
    cases = value["cases"]
    require(set(cases) == {"clear", "negative", "ratio", "obstruction", "immediate_geometry"}, "all paired cases present")
    clear, negative, ratio, obstruction = (cases[name] for name in ("clear", "negative", "ratio", "obstruction"))
    require(near(clear["quarter"]["source_phase"], math.pi)
            and near(clear["quarter"]["phases"]["B"], math.pi / 2), "signed half-rate gearing")
    require(near(clear["quarter"]["positions"]["B"][0], 2)
            and clear["quarter"]["contact_entries"] == 1, "positive real encounter")
    require(near(clear["physical"]["bodies"]["B"][0], 2)
            and near(clear["physical"]["bodies"]["U"][2], 4), "independent native body transforms")
    require("B" in clear["physical"]["overlaps"]["at_endpoint"]
            and "B" not in clear["physical"]["overlaps"]["at_construction"], "collider follows operating frame")
    require(clear["cycle"]["committed"] == 32 and near(clear["cycle"]["phases"]["B"], math.tau)
            and near(clear["cycle"]["positions"]["B"][0], 0), "complete fixed cycle without phase reset")
    require(near(negative["phases"]["B"], -math.pi / 2)
            and near(negative["positions"]["B"][0], -2) and negative["contact_entries"] == 0, "reversed useful output")
    require(clear["two"]["contact_entries"] == 0 and ratio["two"]["contact_entries"] == 1
            and near(ratio["four"]["phases"]["B"], math.pi / 2), "ratio changes actual encounter timing")
    before, blocked = obstruction["approach"], obstruction["blocked"]
    require(blocked["last_collision"]["collider"] == "blocker"
            and "blocker" in obstruction["physical"]["overlaps"]["solid"], "native solid contact and independent solid query")
    require(blocked["phases"] == before["phases"] and blocked["positions"] == before["positions"]
            and blocked["source_phase"] == before["source_phase"] and blocked["committed"] == 2, "whole connected drivetrain retains phase")
    isolated = obstruction["isolated"]
    require(near(isolated["phases"]["B"], before["phases"]["B"])
            and isolated["phases"]["U"] > before["phases"]["U"], "isolated branch retained, clear branch advances")
    require(obstruction["isolated_physical"]["bodies"]["U"][0] > obstruction["physical"]["bodies"]["U"][0]
            and near(obstruction["isolated_physical"]["bodies"]["B"][0], before["positions"]["B"][0]), "isolation changes actual colliders")
    recovered = obstruction["recovered"]
    require(recovered["coupled"] and not recovered["blocked"]
            and near(recovered["phases"]["B"], 3 * math.pi / 16)
            and near(recovered["positions"]["B"][0], 2 * math.sin(3 * math.pi / 16)), "aligned re-engagement resumes retained phase")
    geometry = cases["immediate_geometry"]
    require(geometry["blocked"]["blocked"] and geometry["blocked"]["phases"] == geometry["before"]["phases"]
            and not geometry["cleared"]["blocked"] and near(geometry["cleared"]["phases"]["B"], 3 * math.pi / 16),
            "immediate add/remove native geometry governs the next intersecting sweep")
    require(len(value["boundaries"]) == 84, "all admitted steps have native-boundary observations")
    for boundary in value["boundaries"]:
        before, integrating, completed, published = (boundary[key] for key in ("before", "integrating", "completed", "published"))
        require(integrating["pending"] and not completed["pending"], "request retained until coherent native boundary")
        require(completed["attempts"] == before["attempts"] + 1
                and completed["committed"] == before["committed"] + int(boundary["accepted"]), "no duplicate operation")
        for branch in ("B", "U"):
            require(all(near(a, b) for a, b in zip(completed["bodies"][branch], published["positions"][branch])), "native pose matches earliest published outcome")
        delta = math.pi / 8 if boundary["accepted"] else 0
        require(near(published["source"] - before["source"], delta)
                and near(published["phases"]["U"] - before["phases"]["U"], delta / 2), "source/U advance exactly once")
        b_delta = delta * 20 / before["teeth"] * (1 if before["idler"] else -1) if before["coupled"] else 0
        require(near(published["phases"]["B"] - before["phases"]["B"], b_delta), "isolated B retains phase without duplicate advance")


def compare(a, b, path="cases"):
    if isinstance(a, bool) or isinstance(b, bool):
        equal = type(a) is type(b) and a == b
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)):
        equal = math.isfinite(a) and math.isfinite(b) and abs(a - b) < EPSILON
    elif isinstance(a, dict) and isinstance(b, dict) and a.keys() == b.keys():
        for key in a:
            compare(a[key], b[key], path + "." + key)
        return
    elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for index, (left, right) in enumerate(zip(a, b)):
            compare(left, right, path + f"[{index}]")
        return
    else:
        equal = a == b
    if not equal:
        raise ValueError("Headless/rendered divergence at " + path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    if not args.godot.is_absolute() or not args.godot.is_file() or not os.access(args.godot, os.X_OK):
        parser.error("Use the existing absolute verified Godot executable")
    artifacts = args.artifacts
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error("Keep artifacts outside the checkout at an absolute path without symlinks")
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"], capture_output=True, text=True)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        parser.error("Keep artifacts outside Git worktrees and administration directories")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error("Require 22 GiB free and less than 256 MiB retained task artifacts")
    run = Path(tempfile.mkdtemp(prefix="run-", dir=artifacts))
    project = run / "project"
    env = os.environ.copy()
    receipt = {"status": "running", "started": datetime.now(timezone.utc).isoformat(),
               "source_hashes": {}, "stages": [], "user_play": "not_assessed", "render": "not_run",
               "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "runner_hashes": {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (
                   ("check_mechanics.py", Path(__file__)), ("check_engine_environment.py", Path(bounds.__file__)))}}
    deadline = time.monotonic() + 1800
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    print(f"Mechanics evidence: {run}", flush=True)
    try:
        total = 0
        for name in FILES:
            path = PROJECT / name
            if path.is_symlink() or not path.is_file():
                raise ValueError("Missing or unsafe source: " + name)
            content = path.read_bytes()
            total += len(content)
            if total > 2 * 1024**2:
                raise ValueError("Mechanics source allowance exceeded")
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            receipt["source_hashes"][name] = hashlib.sha256(content).hexdigest()
        for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
            folder = run / name
            folder.mkdir()
            env[key] = str(folder)

        def execute(name, arguments, marker=None, timeout=30):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("Mechanics validation reached 30 minute allowance")
            log = run / (name + ".log")
            result = bounds.execute_bounded([str(args.godot), *arguments], cwd=project, env=env,
                                            log=log, artifacts=artifacts, timeout=min(remaining, timeout))
            output = log.read_text(errors="replace")
            receipt["stages"].append({"name": name, "exit": result.returncode})
            if result.returncode or "ERROR:" in output or (marker and marker not in output):
                raise ValueError(f"{name} failed; inspect {log}")
            return output

        version = execute("version", ["--version"]).strip()
        if not version.startswith("4.7.2.stable."):
            raise ValueError("This bounded fixture uses verified Godot 4.7.2 stable")
        execute("import", ["--headless", "--editor", "--path", str(project), "--import"], timeout=180)
        execute("neutral", ["--headless", "--path", str(project), "--script", "res://tests.gd"], "FACTORY_HEADLESS_PASS")
        execute("physics", ["--headless", "--path", str(project), "--script", "res://mechanics/check.gd", "--",
                            "--report=" + str(run / "physics.json")], "MECHANICS_PASS")
        physical = json.loads((run / "physics.json").read_text())
        verify(physical)
        if args.render:
            execute("view", ["--path", str(project), "--script", "res://mechanics/check.gd", "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--",
                             "--with-view", "--report=" + str(run / "view.json"), "--capture=" + str(run / "view.png")], "MECHANICS_PASS", timeout=180)
            viewed = json.loads((run / "view.json").read_text())
            verify(viewed)
            compare(physical["cases"], viewed["cases"])
            if not (run / "view.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
                raise ValueError("Missing real viewport capture")
            receipt["render"] = "pass"
        receipt["status"] = "pass"
    except Exception as error:
        receipt["status"] = "fail"
        receipt["error"] = str(error)
        raise
    finally:
        receipt["finished"] = datetime.now(timezone.utc).isoformat()
        receipt["owned_bytes"] = bounds.owned_bytes(artifacts)
        (run / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Mechanics passed; render={receipt['render']}; evidence={run}")


if __name__ == "__main__":
    main()
