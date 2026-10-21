#!/usr/bin/env python3
"""Parse every script in an immutable staged prototype, under top-level heavy admission.

The local pinned runtime is supplied explicitly by check_commit.py. No setup,
game simulation or renderer is run. Owned diagnostics survive a parse refusal.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
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
VERSION = "4.7.2.stable.official.ed1daf0bf"
MAX_BYTES = 128 * 1024**2


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024**2):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--source-tree", required=True)
    args = parser.parse_args()
    binary, artifacts = args.godot, args.artifacts
    if (not binary.is_absolute() or binary.resolve() != binary or not binary.is_file()
            or not os.access(binary, os.X_OK)):
        parser.error("Use an absolute regular executable without symlinks; no engine is installed automatically")
    if not re.fullmatch(r"[0-9a-f]{64}", args.sha256) or sha256(binary) != args.sha256:
        parser.error("Installed Godot does not match the explicit verified SHA256 pin")
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", args.source_tree):
        parser.error("Use the immutable staged tree origin supplied by check_commit.py")
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(ROOT):
        parser.error("Use an external absolute artifact root without symlinks")
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"],
                               text=True, capture_output=True)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        parser.error("Keep compiler artifacts outside Git worktrees and administration directories")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error("Require 22 GiB free and less than 128 MiB retained compiler artifacts")
    session = Path(tempfile.mkdtemp(prefix="parse-", dir=artifacts))
    project = session / "project"
    environment = os.environ.copy()
    receipt = {"status": "running", "kind": "gdscript_parse_only", "source_tree": args.source_tree,
               "started": datetime.now(timezone.utc).isoformat(), "source_hashes": {}, "stages": [],
               "binary": str(binary), "binary_sha256": args.sha256,
               "runner_hashes": {name: sha256(path) for name, path in (
                   ("check_gdscript.py", Path(__file__)), ("check_engine_environment.py", Path(bounds.__file__)))}}
    print(f"Staged GDScript compiler diagnostics: {session}", flush=True)
    deadline = time.monotonic() + 300
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    try:
        if not (PROJECT / "project.godot").is_file():
            raise ValueError("Immutable staged candidate is missing its Godot project")
        total = 0
        for source in sorted(PROJECT.rglob("*")):
            relative = source.relative_to(PROJECT)
            if source.is_symlink() or ".godot" in relative.parts:
                raise ValueError("Refuse staged symlinks or generated engine cache: " + str(relative))
            if source.is_dir():
                continue
            if not source.is_file() or len(receipt["source_hashes"]) >= 512:
                raise ValueError("Invalid or excessive staged project inputs")
            if source.stat().st_size > 8 * 1024**2 - total:
                raise ValueError("Staged prototype sources exceed the explicit 8 MiB allowance")
            data = source.read_bytes()
            total += len(data)
            if total > 8 * 1024**2:
                raise ValueError("Staged prototype sources exceed the explicit 8 MiB allowance")
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            receipt["source_hashes"][str(relative)] = hashlib.sha256(data).hexdigest()
        scripts = sorted(name for name in receipt["source_hashes"] if name.endswith(".gd"))
        if not scripts or len(scripts) > 128:
            raise ValueError("Need 1..128 staged GDScript files in the supported project")
        for variable, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                               ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
            directory = session / name
            directory.mkdir()
            environment[variable] = str(directory)

        def execute(name, arguments, timeout):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("Staged compiler exceeded its 5 minute allowance")
            log = session / (name + ".log")
            result = bounds.execute_bounded([str(binary), *arguments], cwd=project, env=environment,
                                            log=log, artifacts=artifacts, timeout=min(timeout, remaining))
            output = log.read_text(errors="replace")
            receipt["stages"].append({"name": name, "exit": result.returncode, "arguments": arguments})
            if result.returncode or "ERROR:" in output:
                raise ValueError(f"Staged GDScript compilation failed at {name}; inspect {log}")
            return output

        if execute("version", ["--version"], 15).strip() != VERSION:
            raise ValueError("Pinned executable is not the separately verified supported Godot " + VERSION)
        execute("import", ["--headless", "--editor", "--path", str(project), "--import"], 180)
        receipt["post_import_project_sha256"] = sha256(project / "project.godot")
        for index, name in enumerate(scripts):
            execute(f"script-{index:03d}", ["--headless", "--path", str(project),
                                           "--check-only", "--script", "res://" + name], 30)
        for name, digest in receipt["source_hashes"].items():
            if name != "project.godot" and sha256(project / name) != digest:
                raise ValueError("Compiler changed copied staged input: " + name)
        receipt["runtime_project_sha256"] = sha256(project / "project.godot")
        if sha256(binary) != args.sha256:
            raise ValueError("Installed Godot changed during staged compilation")
        receipt["parsed_scripts"] = scripts
        receipt["status"] = "pass"
    except Exception as error:
        receipt["status"] = "fail"
        receipt["error"] = str(error)
        raise
    finally:
        receipt["finished"] = datetime.now(timezone.utc).isoformat()
        receipt["owned_bytes"] = bounds.owned_bytes(artifacts)
        (session / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Parsed {len(scripts)} immutable staged GDScripts; this is not runtime/gameplay evidence")


if __name__ == "__main__":
    main()
