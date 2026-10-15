#!/usr/bin/env python3
"""Launch/check the opening in a fresh external session; use run_local.py heavy."""

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


PROJECT = Path(__file__).resolve().parents[1] / "experiments/engine-environment/godot"
FILES = bounds.FILES + tuple("opening/" + name for name in (
    "opening.gd", "opening.tscn", "opening_check.gd", "model_check.gd",
    "checkpoint_check.gd", "integration_check.gd")) + ("save-tests/checkpoint_file.gd",)
MAX_BYTES = 256 * 1024**2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--check", action="store_true", help="run actual model and input consumers, then exit")
    parser.add_argument("--render", action="store_true", help="capture the real rendered check viewport")
    parser.add_argument("--smoke", action="store_true", help="launch the actual opening scene and exit after 60 frames")
    args = parser.parse_args()
    if args.render and not args.check:
        parser.error("--render selects the rendered automated check; normal launch already opens a window")
    if args.smoke and args.check:
        parser.error("Choose --smoke for scene startup or --check for the input consumers")
    if not args.godot.is_absolute() or not args.godot.is_file() or not os.access(args.godot, os.X_OK):
        parser.error("Use the existing absolute verified Godot executable; no setup is performed")
    artifacts = args.artifacts
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(PROJECT):
        parser.error("Use an external absolute artifact root without symlinks")
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"],
                               capture_output=True, text=True)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        parser.error("Keep sessions outside Git worktrees and administration directories")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error("Require 22 GiB free and less than 256 MiB retained in this artifact root")
    session = Path(tempfile.mkdtemp(prefix="session-", dir=artifacts))
    project = session / "project"
    save_slot = session / "worksite.factory"
    environment = os.environ.copy()
    receipt = {"status": "running", "mode": "check" if args.check else "startup_smoke" if args.smoke else "interactive",
               "started": datetime.now(timezone.utc).isoformat(), "source_hashes": {}, "stages": [],
               "runner_hashes": {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (
                   ("run_opening.py", Path(__file__)), ("check_engine_environment.py", Path(bounds.__file__)))},
               "save_slot": str(save_slot), "user_play": "not_assessed"}
    deadline = time.monotonic() + 1800
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    print(f"Opening session: {session}\nSave/Load: F5 / F9. Close the window to finish.", flush=True)
    try:
        copied = 0
        for name in FILES:
            source = PROJECT / name
            if source.is_symlink() or not source.is_file():
                raise ValueError(f"Missing or unsafe opening source: {name}")
            content = source.read_bytes()
            copied += len(content)
            if copied > 2 * 1024**2:
                raise ValueError("Opening source allowance exceeded")
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            receipt["source_hashes"][name] = hashlib.sha256(content).hexdigest()
        for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                          ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
            directory = session / name
            directory.mkdir()
            environment[key] = str(directory)

        def execute(name, arguments, marker=None, timeout=30):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("Opening session reached its 30 minute allowance")
            log = session / (name + ".log")
            result = bounds.execute_bounded([str(args.godot), *arguments], cwd=project, env=environment,
                                            log=log, artifacts=artifacts, timeout=min(timeout, remaining))
            output = log.read_text(errors="replace")
            receipt["stages"].append({"name": name, "exit": result.returncode})
            if result.returncode or "ERROR:" in output or (marker and marker not in output):
                raise ValueError(f"{name} failed; inspect {log}")
            return output

        version = execute("version", ["--version"]).strip()
        if not version.startswith("4.7.2.stable."):
            raise ValueError("This experiment uses the separately verified Godot 4.7.2 stable")
        execute("import", ["--headless", "--editor", "--path", str(project), "--import"], timeout=180)
        if args.check:
            for name, script, marker in (
                    ("neutral", "tests.gd", "FACTORY_HEADLESS_PASS"),
                    ("opening-model", "opening/model_check.gd", "OPENING_MODEL_PASS"),
                    ("checkpoint", "opening/checkpoint_check.gd", "CHECKPOINT_REGRESSION_PASS"),
                    ("opening-input", "opening/opening_check.gd", "OPENING_INPUT_PASS"),
                    ("save-load-input", "opening/integration_check.gd", "OPENING_SAVE_LOAD_PASS")):
                arguments = ["--path", str(project), "--script", "res://" + script]
                if args.render and name in ("opening-input", "save-load-input"):
                    capture = session / (name + ".png")
                    arguments += ["--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
                                  "--", "--capture=" + str(capture), "--save-slot=" + str(save_slot)]
                else:
                    arguments = ["--headless", *arguments, "--", "--save-slot=" + str(save_slot)]
                output = execute(name, arguments, marker,
                                 timeout=180 if args.render and name in ("opening-input", "save-load-input") else 30)
                if name == "save-load-input":
                    prefix = "OPENING_SAVE_LOAD_STATE "
                    report = json.loads(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))
                    final = report["final"]
                    stock = final["stock"]
                    raw = sum(stock[key] for key in ("source", "collector", "belt", "input", "held"))
                    if (final["initial_feed"] != 16 or final["inventories"] != {"P": 4}
                            or raw + stock["output"] + sum(final["inventories"].values()) != 16
                            or not report["confirmed"] or report["paused"]["remaining"] != 2
                            or report["paused"]["restored_remaining"] != report["paused"]["remaining"]
                            or report["paused"]["power_enabled"] or report["paused"]["stock"]["held"] != 1
                            or report["blocked"]["stock"]["output"] != 1 or report["blocked"]["stock"]["held"] != 1):
                        raise ValueError("Actual consumer quantities/phase/goal differ from the independent fixture oracle")
                    (session / "consumer.json").write_text(json.dumps(report, indent=2) + "\n")
                if args.render and name in ("opening-input", "save-load-input"):
                    if not capture.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
                        raise ValueError("Missing actual rendered viewport capture")
        else:
            arguments = ["--path", str(project), "res://opening/opening.tscn",
                         "--rendering-method", "gl_compatibility"]
            if args.smoke:
                arguments += ["--quit-after", "60"]
            execute("interactive", [*arguments, "--", "--save-slot=" + str(save_slot)],
                    timeout=30 if args.smoke else 1800)
        receipt["status"] = "pass"
    except Exception as error:
        receipt["status"] = "fail"
        receipt["error"] = str(error)
        raise
    finally:
        receipt["owned_bytes"] = bounds.owned_bytes(artifacts)
        receipt["finished"] = datetime.now(timezone.utc).isoformat()
        (session / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Opening {receipt['mode']} finished; evidence and save retained at {session}")


if __name__ == "__main__":
    main()
