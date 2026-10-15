#!/usr/bin/env python3
"""Bounded fresh-process continuation test using the shared checkpoint methods.

Use scripts/run_local.py heavy. No download, model edits or live user save access.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from check_stationary_authority import PROJECT, ROOT, copy_project, safe_destination, size


def run(args):
    godot = args.godot.resolve(strict=True)
    if not godot.is_file() or not os.access(godot, os.X_OK):
        raise ValueError("Supply the existing verified Godot executable")
    safe_destination(args.artifacts)
    project = args.artifacts / "project"
    project.mkdir()
    revision, sources = copy_project(args.model_revision, project)
    save_sources = project / "save-tests"
    save_sources.mkdir(exist_ok=True)
    for name in ("checkpoint_file.gd", "probe.gd"):
        content = (ROOT / PROJECT / "save-tests" / name).read_bytes()
        (save_sources / name).write_bytes(content)
        sources["save-tests/" + name] = "sha256:" + hashlib.sha256(content).hexdigest()
    manifest = {"model_revision": revision, "sources": sources,
                "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "commands": {}, "reports": {}, "max_live_engine_processes": 1}
    start = time.monotonic()
    try:
        for mode in ("produce", "consume"):
            profile = args.artifacts / mode
            profile.mkdir()
            (profile / "tmp").mkdir()
            environment = dict(os.environ)
            environment.update(XDG_DATA_HOME=str(profile / "data"),
                               XDG_CONFIG_HOME=str(profile / "config"),
                               XDG_CACHE_HOME=str(profile / "cache"), TMPDIR=str(profile / "tmp"))
            command = [str(godot), "--headless", "--path", str(project), "--script",
                       "res://save-tests/probe.gd", "--", "--mode=" + mode,
                       "--artifacts=" + str(args.artifacts)]
            manifest["commands"][mode] = command
            try:
                result = subprocess.run(command, capture_output=True, text=True,
                                        env=environment, timeout=60)
            except subprocess.TimeoutExpired as error:
                stdout = error.stdout or b""
                stderr = error.stderr or b""
                if isinstance(stdout, bytes):
                    stdout = stdout.decode(errors="replace")
                if isinstance(stderr, bytes):
                    stderr = stderr.decode(errors="replace")
                (args.artifacts / (mode + ".log")).write_text(stdout + stderr)
                raise ValueError(mode + " exceeded its 60-second deadline") from error
            log = result.stdout + result.stderr
            (args.artifacts / (mode + ".log")).write_text(log)
            if result.returncode or re.search(r"(^|\n)(?:SCRIPT )?ERROR:", log):
                raise ValueError(mode + " failed; inspect retained log")
            if "SAVE_CONTINUATION_PASS " + mode not in log:
                raise ValueError(mode + " did not produce a completion marker")
            report = json.loads((args.artifacts / (mode + ".json")).read_text())
            if report.get("status") != "pass" or report.get("checks", 0) < 20:
                raise ValueError(mode + " lacks complete assertion evidence")
            manifest["reports"][mode] = report
            if size(args.artifacts) > 256 * 1024 * 1024:
                raise ValueError("Owned artifact allowance exceeded")
        manifest["status"] = "pass"
        return {"status": "pass", "checks": {k: v["checks"] for k, v in manifest["reports"].items()},
                "model_revision": revision}
    finally:
        manifest.update(elapsed_seconds=time.monotonic() - start, owned_bytes=size(args.artifacts))
        (args.artifacts / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--model-revision", required=True)
    parser.add_argument("--artifacts", required=True, type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(run(args)))
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("SAVE PROBE FAILED:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
