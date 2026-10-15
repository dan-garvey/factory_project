#!/usr/bin/env python3
"""Check the actual opening scene in an external owned project copy; no setup."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


PROJECT = Path(__file__).resolve().parent.parent
BASE = ("project.godot", "main.tscn", "model.gd", "scenario.gd", "tests.gd", "view.gd")
OPENING = ("opening.gd", "opening.tscn", "opening_check.gd", "model_check.gd", "checkpoint_check.gd")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--import-only", action="store_true")
    args = parser.parse_args()
    binary, artifacts = args.godot, args.artifacts
    if not binary.is_absolute() or not binary.is_file() or not os.access(binary, os.X_OK):
        parser.error("Use the absolute existing verified Godot executable")
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts:
        parser.error("Use an absolute artifact root without symlinks")
    if artifacts.is_relative_to(PROJECT):
        parser.error("Keep caches and evidence outside the source project")
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"],
                               capture_output=True, text=True)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        parser.error("Keep evidence outside Git worktrees and administration directories")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3:
        parser.error("Require 22 GiB free before the run")
    existing = sum(p.stat().st_size for p in artifacts.rglob("*") if p.is_file())
    if existing >= 256 * 1024**2:
        parser.error("Opening artifact allowance reached; preserve and replan")
    run = Path(tempfile.mkdtemp(prefix="run-", dir=artifacts))
    project = run / "project"
    (project / "opening").mkdir(parents=True)
    hashes = {}
    source_bytes = 0
    for name in (*BASE, *("opening/" + name for name in OPENING), "save-tests/checkpoint_file.gd"):
        source = PROJECT / name
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"Missing or unsafe shared project source: {source}")
        content = source.read_bytes()
        source_bytes += len(content)
        if source_bytes > 2 * 1024**2:
            raise ValueError("Opening source allowance exceeded")
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        hashes[name] = hashlib.sha256(content).hexdigest()
    environment = os.environ.copy()
    for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                      ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
        directory = run / name
        directory.mkdir()
        environment[key] = str(directory)
    receipt = {"status": "running", "started": datetime.now(timezone.utc).isoformat(),
               "mode": "import_only" if args.import_only else "rendered" if args.render else "headless",
               "source_hashes": hashes, "stages": [], "render": "not_run"}
    print(f"Opening evidence: {run}", flush=True)

    def execute(label, arguments, marker=None, timeout=30):
        log = run / (label + ".log")
        with log.open("x") as stream:
            result = subprocess.run([str(binary), *arguments], cwd=project, env=environment,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        output = log.read_text(errors="replace")
        receipt["stages"].append({"name": label, "exit": result.returncode})
        if result.returncode or "SCRIPT ERROR:" in output or "ERROR:" in output or (marker and marker not in output):
            raise ValueError(f"{label} failed; inspect {log}")
        if sum(p.stat().st_size for p in artifacts.rglob("*") if p.is_file()) > 256 * 1024**2:
            raise ValueError("Opening artifact allowance exceeded; preserve and replan")
        return output

    try:
        version = execute("version", ["--version"]).strip()
        if not version.startswith("4.7.2.stable."):
            raise ValueError("This bounded experiment requires verified Godot 4.7.2 stable")
        execute("import", ["--headless", "--editor", "--path", str(project), "--import"], timeout=180)
        if not args.import_only:
            execute("baseline", ["--headless", "--path", str(project), "--script", "res://tests.gd"], "FACTORY_HEADLESS_PASS")
            execute("opening-model", ["--headless", "--path", str(project), "--script", "res://opening/model_check.gd"], "OPENING_MODEL_PASS")
            execute("checkpoint-regression", ["--headless", "--path", str(project), "--script", "res://opening/checkpoint_check.gd"], "CHECKPOINT_REGRESSION_PASS")
            arguments = ["--path", str(project), "--script", "res://opening/opening_check.gd"]
            if args.render:
                arguments += ["--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
                              "--", "--capture=" + str(run / "opening.png")]
            else:
                arguments.insert(0, "--headless")
            execute("opening", arguments, "OPENING_INPUT_PASS", 180 if args.render else 30)
            if args.render and not (run / "opening.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
                raise ValueError("Actual rendered viewport capture is missing or invalid")
            receipt["render"] = "pass" if args.render else "not_run"
        receipt["owned_bytes"] = sum(p.stat().st_size for p in artifacts.rglob("*") if p.is_file())
        if receipt["owned_bytes"] > 256 * 1024**2:
            raise ValueError("Opening artifact allowance exceeded; preserve and replan")
        receipt["status"] = "pass"
    except Exception as error:
        receipt["status"] = "fail"
        receipt["error"] = str(error)
        raise
    finally:
        (run / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Opening check passed; render={receipt['render']}; evidence={run}")


if __name__ == "__main__":
    main()
