#!/usr/bin/env python3
"""Bounded geometric inspection fixture; run through run_local.py heavy."""

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
FILES = bounds.FILES + ("mechanics/authority.gd",) + tuple("scaling/" + name for name in (
    "authority.gd", "view.gd", "main.tscn", "check.gd"))
MAX_BYTES = 128 * 1024**2
CASES = {"gantry_base", "rotary_base", "gantry_grown", "rotary_grown", "duplicate",
         "overclock", "reversed_face", "low_mount", "far_mount", "shielded", "empty"}
EPSILON = 0.00002


def same(a, b):
    if isinstance(a, (float, int)) and isinstance(b, (float, int)):
        return abs(a - b) < EPSILON
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


def ray_box(start, end, center, size):
    """Independent segment/AABB slab oracle for these declared axis-aligned solids."""
    enter, leave, normal = 0.0, 1.0, [0, 0, 0]
    for axis in range(3):
        lower, upper = center[axis] - size[axis] / 2, center[axis] + size[axis] / 2
        delta = end[axis] - start[axis]
        if abs(delta) < 1e-9:
            if not lower <= start[axis] <= upper:
                return None
        else:
            first, last = (lower - start[axis]) / delta, (upper - start[axis]) / delta
            sign = -1 if delta > 0 else 1
            if first > last:
                first, last = last, first
            if first > enter:
                enter = first
                normal = [sign if k == axis else 0 for k in range(3)]
            leave = min(leave, last)
            if enter > leave:
                return None
    return enter, [start[k] + (end[k] - start[k]) * enter for k in range(3)], normal


def verify(report):
    def require(ok, label):
        if not ok:
            raise ValueError("Spatial oracle: " + label)

    require(report["status"] == "pass" and not report["failures"] and report["checks"] > 2000,
            "actual engine assertion report")
    require(set(report["cases"]) == CASES, "eleven declared controls")
    for name, case in report["cases"].items():
        grown = name not in {"gantry_base", "rotary_base"}
        layout = "gantry" if name.startswith("gantry") or name in {"reversed_face", "low_mount", "far_mount", "shielded", "empty"} else "rotary"
        count = 2 if grown and name != "overclock" else 1
        owners = 2 if name == "duplicate" else 1
        coupons = {} if name == "empty" else {f"Coupon_{row}_{side}": ([side * 2, 0, row * 3], [0.5, 0.2, 0.5])
                                                for row in range(2 if grown else 1) for side in (-1, 1)}
        shield = [0, 0.55 if name == "shielded" else 5, 1.5]
        solids = {**coupons, "AccessShield": (shield, [5, 0.1, 4])}
        visited, minimum, maximum, hits = set(), [math.inf] * 3, [-math.inf] * 3, []
        require(len(case["samples"]) == 33, name + " initial plus32 completed requests")
        for step, sample in enumerate(case["samples"]):
            state, native = sample["state"], sample["native"]
            phase = step * math.pi / 16 * (2 if name == "overclock" else 1)
            require(state["steps"] == step and not state["pending"], name + " coherent once-only completion")
            require(state["head_count"] == count and state["drive_count"] == owners, name + " real head/drive counts")
            require(same(native["shield"], shield), name + " independent shield transform")
            require(same({c["name"]: (c["position"], c["size"]) for c in native["coupons"]}, coupons),
                    name + " same physical work opportunities")
            require(all(c["layer"] == 16 for c in native["coupons"]) and native["shield_layer"] == 32, name + " native collider layers")
            require(all(same(h["size"], [0.4, 0.4, 0.4]) and h["layer"] == 0 and h["mask"] == 0 for h in native["head_shapes"]), name + " real head shapes and collision filters")
            for index, source in enumerate(native["sources"]):
                require(same(source["body"], [2 * math.sin(phase), 0.75, 25 + index * 8]), name + " native inherited slider")
                require(same(source["state"]["source_phase"], step * math.pi / 8)
                        and same(source["state"]["phases"]["B"], phase)
                        and source["state"]["committed"] == step, name + " unchanged phase owner/gear input")
            for index, at in enumerate(native["heads"]):
                radius = math.sqrt(13) if name == "rotary_grown" and index == 1 else 2
                expected = ([2 * math.sin(phase), 1.2, index * 3] if layout == "gantry"
                            else [radius * math.cos(phase), 1.2, radius * math.sin(phase) + (index * 3 if name == "duplicate" else 0)])
                if name == "low_mount":
                    expected[1] = -0.6
                elif name == "far_mount":
                    expected[1] = 2.4
                require(same(at, expected), name + " independent native path coordinates")
                require(same(at, state["completed"]["heads"][index]["position"]), name + " publication agrees with native")
                for axis in range(3):
                    minimum[axis] = min(minimum[axis], at[axis] - 0.2)
                    maximum[axis] = max(maximum[axis], at[axis] + 0.2)
                direction = [0, 1 if name == "reversed_face" else -1, 0]
                start = [at[k] + direction[k] * 0.2 for k in range(3)]
                end = [start[k] + direction[k] * 1.2 for k in range(3)]
                oracle_hits = [(result[0], label, result[1], result[2]) for label, (center, size) in solids.items()
                               if (result := ray_box(start, end, center, size)) is not None]
                expected_hit = min(oracle_hits) if oracle_hits else None
                observed = native["rays"][index]
                require(same(observed["from"], start) and same(observed["to"], end), name + " actual ray from native oriented face")
                require(observed["hit"] == (expected_hit[1] if expected_hit else ""), name + " first native contact vs slab oracle")
                eligible = bool(expected_hit and expected_hit[1] in coupons and direction[1] == -1 and expected_hit[3] == [0, 1, 0])
                if expected_hit:
                    require(same(observed["point"], expected_hit[2]) and same(observed["normal"], expected_hit[3]), name + " independent native point/normal")
                if step:
                    actual = state["completed"]["rays"][index]
                    require(same({k: actual[k] for k in observed}, observed) and actual["eligible"] == eligible,
                            name + " authority work result matches independent native ray")
                    if eligible:
                        visited.add(expected_hit[1])
                        hits.append((step, f"Head{index}", expected_hit[1]))
            require(state["completed"]["visited"] == sorted(visited), name + " native-derived unique contact set")
            require(same(state["completed"]["bounds"], {"min": minimum, "max": maximum}), name + " exact observed head envelope")
        final = case["final"]
        require(same(final, case["samples"][-1]["state"]), name + " final report is actual last completion")
        require([(e["step"], e["head"], e["coupon"]) for e in final["completed"]["encounters"]] == hits,
                name + " no unobserved useful encounter")
        expected_count = 0 if name in {"reversed_face", "low_mount", "far_mount", "shielded", "empty"} else 2 if name in {"gantry_base", "rotary_base", "overclock"} else 4
        require(len(visited) == expected_count, name + " known coverage outcome")
    groups = {name: [] for name in CASES}
    for boundary in report["parent_boundaries"]:
        groups[boundary["case"]].append(boundary)
        n = boundary["step_before"]
        state = boundary["state"]
        require(state["pending"] and state["steps"] == n and state["completed"]["steps"] == n,
                "parent completion retains pending and prior publication")
        # The source already advanced; the outer completion is still the old
        # native observation. Do not infer completion from the parent's signal.
        require(all(s["state"]["committed"] == n + 1 for s in boundary["native"]["sources"]),
                "parent-boundary source advanced exactly once")
        require(same(state["completed"], report["cases"][boundary["case"]]["samples"][n]["state"]["completed"]),
                "child-native window retains the exact prior published snapshot")
        require(same(boundary["requested"], report["cases"][boundary["case"]]["samples"][n + 1]["native"]["heads"]),
                "parent signal requests exactly the next native head pose")
    for name, boundaries in groups.items():
        expected = list(range(32))
        # Render capture deliberately repeats one fresh gantry fixture.
        require([b["step_before"] for b in boundaries] in (expected, expected + expected),
                name + " every parent completion has a bounded child-window witness")
    final = {name: value["final"] for name, value in report["cases"].items()}
    width = lambda n, axis: final[n]["completed"]["bounds"]["max"][axis] - final[n]["completed"]["bounds"]["min"][axis]
    require(same(width("gantry_base", 0), 4.4) and same(width("gantry_grown", 0), 4.4)
            and same(width("gantry_grown", 2), 3.4), "gantry added row retains physical stroke envelope")
    require(same(width("rotary_base", 0), 4.4) and same(width("rotary_base", 2), 4.4)
            and same(width("rotary_grown", 0), 2 * math.sqrt(13) + 0.4)
            and same(width("rotary_grown", 2), 2 * math.sqrt(13) + 0.4), "declared rotary growth expands both axes")
    require(same(width("duplicate", 0), 4.4) and same(width("duplicate", 2), 7.4), "duplicate is a real viable geometric control")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    if not args.godot.is_absolute() or not args.godot.is_file() or not os.access(args.godot, os.X_OK):
        parser.error("Use an existing absolute verified Godot executable")
    artifacts = args.artifacts
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error("Use an absolute external artifact directory without symlinks")
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"], capture_output=True, text=True, timeout=5)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        parser.error("Artifacts cannot be in Git worktrees or administration directories")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error("Require22GiB free and less than128MiB retained task artifacts")
    run = Path(tempfile.mkdtemp(prefix="run-", dir=artifacts))
    project = run / "project"
    env = os.environ.copy()
    receipt = {"status": "running", "started": datetime.now(timezone.utc).isoformat(), "source_hashes": {}, "stages": [],
               "user_play": "not_assessed", "render": "not_run", "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "runner_hashes": {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (("check_scaling.py", Path(__file__)), ("check_engine_environment.py", Path(bounds.__file__)))}}
    deadline = time.monotonic() + 1200
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    print(f"Spatial evidence: {run}", flush=True)
    try:
        total = 0
        for name in FILES:
            source = PROJECT / name
            if source.is_symlink() or not source.is_file():
                raise ValueError("Missing/unsafe source: " + name)
            content = source.read_bytes()
            total += len(content)
            if total > 2 * 1024**2:
                raise ValueError("Source allowance exceeded")
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            receipt["source_hashes"][name] = hashlib.sha256(content).hexdigest()
        for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
            folder = run / name
            folder.mkdir()
            env[key] = str(folder)

        def execute(name, arguments, marker=None, timeout=45):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("Spatial validation reached20minute allowance")
            log = run / (name + ".log")
            result = bounds.execute_bounded([str(args.godot), *arguments], cwd=project, env=env, log=log, artifacts=artifacts, timeout=min(timeout, remaining))
            output = log.read_text(errors="replace")
            receipt["stages"].append({"name": name, "exit": result.returncode})
            if result.returncode or "ERROR:" in output or (marker and marker not in output):
                raise ValueError(f"{name} failed; inspect {log}")
            return output

        if not execute("version", ["--version"]).strip().startswith("4.7.2.stable."):
            raise ValueError("This fixture uses verified Godot4.7.2stable")
        execute("import", ["--headless", "--editor", "--path", str(project), "--import"], timeout=120)
        for script in ("scaling/authority.gd", "scaling/view.gd", "scaling/check.gd"):
            execute("parse-" + Path(script).stem, ["--headless", "--path", str(project), "--check-only", "--script", "res://" + script])
        execute("neutral", ["--headless", "--path", str(project), "--script", "res://tests.gd"], "FACTORY_HEADLESS_PASS")
        execute("physics", ["--headless", "--path", str(project), "--script", "res://scaling/check.gd", "--", "--report=" + str(run / "physics.json")], "SPATIAL_SCALING_PASS", timeout=180)
        physics = json.loads((run / "physics.json").read_text())
        verify(physics)
        if args.render:
            execute("view", ["--path", str(project), "--script", "res://scaling/check.gd", "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--", "--with-view", "--report=" + str(run / "view.json"), "--capture=" + str(run / "view.png")], "SPATIAL_SCALING_PASS", timeout=180)
            rendered = json.loads((run / "view.json").read_text())
            verify(rendered)
            if not same(physics["cases"], rendered["cases"]):
                raise ValueError("Headless/rendered native outcomes differ")
            if not (run / "view.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
                raise ValueError("Missing actual viewport PNG")
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
    print(f"Spatial passed; render={receipt['render']}; evidence={run}")


if __name__ == "__main__":
    main()
