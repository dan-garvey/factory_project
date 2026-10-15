#!/usr/bin/env python3
"""Run the actual Godot prototype checks; never fetch an engine or skip failures.

Call through run_local.py heavy. Source-only tooling checks need no Godot install.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "experiments/engine-environment/godot"
FILES = ("project.godot", "main.tscn", "model.gd", "scenario.gd", "tests.gd", "view.gd")


def run(binary, artifacts, render=False):
    binary, artifacts = Path(binary), Path(artifacts)
    if not binary.is_absolute() or not binary.is_file() or not os.access(binary, os.X_OK):
        raise ValueError("Requested Godot executable is missing or not an absolute executable file")
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        raise ValueError("Use an absolute artifact directory outside this source checkout, without symlinks")
    artifacts.mkdir(parents=True, exist_ok=True)
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"],
                               capture_output=True, text=True)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        raise ValueError("Keep prototype artifacts outside Git worktrees and administration directories")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3:
        raise ValueError("Prototype run requires 22 GiB free to preserve the recorded floor/headroom")
    directory = Path(tempfile.mkdtemp(prefix="run-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-"), dir=artifacts))
    project = directory / "project"
    project.mkdir()
    source_hashes = {}
    for name in FILES:
        source = PROJECT / name
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"Missing/unsafe prototype source: {name}")
        shutil.copyfile(source, project / name)
        source_hashes[name] = hashlib.sha256((project / name).read_bytes()).hexdigest()
    environment = os.environ.copy()
    for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                      ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
        target = directory / name
        target.mkdir()
        environment[key] = str(target)
    results = []

    def execute(name, args, marker=None, report=None, timeout=30):
        started = time.monotonic()
        log = directory / f"{name}.log"
        with log.open("x") as output:
            result = subprocess.run([str(binary), *args], cwd=project, env=environment,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        text = log.read_text(errors="replace")
        results.append({"stage": name, "exit": result.returncode, "elapsed_seconds": time.monotonic() - started})
        if result.returncode or "SCRIPT ERROR:" in text or "ERROR:" in text or (marker and marker not in text):
            raise ValueError(f"{name} failed; inspect retained {log}")
        if report:
            value = json.loads(report.read_text())
            if value.get("status") != "pass" or value.get("checks", 0) < 1:
                raise ValueError(f"{name} did not report verified passing checks")
            return value
        return text

    try:
        version = execute("version", ["--version"]).strip()
        if not version.startswith("4.7.2.stable."):
            raise ValueError("This experiment pins Godot 4.7.2 stable; revise the scope before substituting")
        execute("editor-import", ["--headless", "--editor", "--path", str(project), "--import"], timeout=180)
        headless = execute("headless", ["--headless", "--path", str(project), "--script", "res://tests.gd",
                                       "--", "--report=" + str(directory / "headless.json")],
                           "FACTORY_HEADLESS_PASS", directory / "headless.json")
        if render:
            scene = execute("scene", ["--path", str(project), "--rendering-method", "gl_compatibility",
                                      "--audio-driver", "Dummy", "--", "--smoke",
                                      "--capture=" + str(directory / "scene.png"),
                                      "--report=" + str(directory / "scene.json")],
                            "FACTORY_SCENE_PASS", directory / "scene.json", timeout=180)
            for key in ("first", "blocked", "final"):
                if scene[key] != headless[key]:
                    raise ValueError(f"Headless and real scene disagree at {key}")
            if not (directory / "scene.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
                raise ValueError("Real rendered scene capture is missing/invalid")
        total = sum(path.stat().st_size for path in directory.rglob("*") if path.is_file())
        if total > 384 * 1024**2:
            raise ValueError("Run artifact/cache allowance exceeded; preserve evidence and stop")
        receipt = {"status": "pass", "godot": version, "render": "pass" if render else "not_run",
                   "headless_checks": headless["checks"], "stages": results, "owned_bytes": total,
                   "source_hashes": source_hashes,
                   "verified_at": datetime.now(timezone.utc).isoformat()}
        (directory / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(f"Engine prototype passed; render={receipt['render']}; evidence={directory}")
        return directory
    except Exception:
        (directory / "result.json").write_text(json.dumps({"status": "fail", "stages": results}, indent=2) + "\n")
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--artifacts", required=True, type=Path)
    parser.add_argument("--render", action="store_true", help="require actual Compatibility renderer and PNG capture")
    args = parser.parse_args()
    try:
        run(args.godot, args.artifacts, args.render)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"PROTOTYPE FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
