#!/usr/bin/env python3
"""Run a bounded real-server/two-client probe against an exact shared model commit.

Invoke through scripts/run_local.py heavy. No downloads, editor install, model
copy in source, or changes to another checkout. Artifacts are retained on failure.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import signal
import socket
import subprocess
import sys
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
PROJECT = Path("experiments/engine-environment/godot")
LIMIT = 256 * 1024 * 1024


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def safe_destination(path):
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("Use an absolute artifact path without parent traversal")
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError("Artifact path cannot traverse symlinks")
    listing = git("-c", "core.quotePath=false", "worktree", "list", "--porcelain").decode()
    for line in listing.splitlines():
        if line.startswith("worktree "):
            raw = line.removeprefix("worktree ")
            if raw.startswith('"'):
                raise ValueError("Quoted/control-character worktree paths are unsupported")
            worktree = Path(raw)
            if path.is_relative_to(worktree):
                raise ValueError("Artifacts must be outside all project worktrees")
    path.mkdir(mode=0o700)  # Refuse collisions; never clean up another run.


def copy_project(revision, target):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Supply the exact approved 40-character model commit")
    revision = git("rev-parse", "--verify", revision + "^{commit}").strip().decode()
    entries = git("ls-tree", "-rz", revision, "--", str(PROJECT)).split(b"\0")
    copied = {}
    copied_bytes = 0
    for entry in entries:
        if not entry:
            continue
        metadata, raw = entry.split(b"\t", 1)
        mode, kind, oid = metadata.split()
        relative = Path(os.fsdecode(raw)).relative_to(PROJECT)
        if mode not in (b"100644", b"100755") or kind != b"blob":
            raise ValueError("Dependency project contains unsupported entries")
        if ".godot" in relative.parts or relative.parts[0] == "stationary-tests":
            continue
        content = git("cat-file", "blob", oid.decode())
        copied_bytes += len(content)
        if copied_bytes > 32 * 1024 * 1024 or len(copied) >= 128:
            raise ValueError("Dependency sources exceed this small probe's copy allowance")
        output = target / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(content)
        copied[str(relative)] = oid.decode()
    for required in ("project.godot", "model.gd"):
        if required not in copied:
            raise ValueError("Exact dependency commit lacks " + required)
    own = target / "stationary-tests"
    own.mkdir()
    for name in ("peer.gd", "probe.gd"):
        content = (ROOT / PROJECT / "stationary-tests" / name).read_bytes()
        (own / name).write_bytes(content)
        copied["stationary-tests/" + name] = "sha256:" + hashlib.sha256(content).hexdigest()
    return revision, copied


def size(path):
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def run(args):
    godot = args.godot.resolve(strict=True)
    if not godot.is_file() or not os.access(godot, os.X_OK):
        raise ValueError("Godot must be an existing executable")
    safe_destination(args.artifacts)
    project = args.artifacts / "project"
    project.mkdir()
    model_revision, files = copy_project(args.model_revision, project)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    # A subsequent bind collision is a failure, never an automatic retry.
    events = queue.Queue()
    processes = {}
    readers = []
    commands = {}
    peak_live = 0
    started = time.monotonic()
    deadline = started + (150 if args.render else 90)

    def launch(name, role, actor="", rejoin=False):
        nonlocal peak_live
        if sum(process.poll() is None for process in processes.values()) >= 3:
            raise ValueError("Three-live-engine-process limit exceeded")
        profile = args.artifacts / name
        profile.mkdir()
        environment = dict(os.environ)
        environment.update({"XDG_DATA_HOME": str(profile / "data"),
                            "XDG_CONFIG_HOME": str(profile / "config"),
                            "XDG_CACHE_HOME": str(profile / "cache"),
                            "TMPDIR": str(profile / "tmp")})
        (profile / "tmp").mkdir()
        command = [str(godot)]
        if role == "server" or not args.render:
            command.append("--headless")
        command += ["--rendering-method", "gl_compatibility", "--path", str(project),
                    "--script", "res://stationary-tests/probe.gd", "--",
                    "--role=" + role, "--actor=" + actor, "--port=" + str(port),
                    "--artifacts=" + str(args.artifacts)]
        if rejoin:
            command.append("--rejoin")
        if args.opening:
            command.append("--opening")
        commands[name] = command
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, bufsize=1, env=environment, start_new_session=True)
        processes[name] = process
        peak_live = max(peak_live, sum(child.poll() is None for child in processes.values()))

        def read_output():
            used = 0
            with (args.artifacts / (name + ".log")).open("w") as log:
                for line in process.stdout:
                    used += len(line.encode())
                    if used > 8 * 1024 * 1024:
                        events.put((name, "OUTPUT_LIMIT"))
                        break
                    log.write(line)
                    log.flush()
                    events.put((name, line.strip()))
                    if line.startswith(("ERROR:", "SCRIPT ERROR:")):
                        events.put((name, "ENGINE_ERROR"))
            events.put((name, "EXIT"))

        reader = threading.Thread(target=read_output, daemon=True)
        reader.start()
        readers.append(reader)

    manifest = {"model_revision": model_revision, "files": files, "port": port,
                "fixture_parent_commit": git("rev-parse", "HEAD").strip().decode(),
                "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "render_clients": args.render,
                "fixture": {"feed": 16, "recipe_input": 1, "opening": args.opening},
                "max_live_engine_processes": 3, "disk_limit_bytes": LIMIT}
    result = None
    try:
        launch("server", "server")
        first_p_exited = False
        reconnect_ready = False
        rejoined = False
        success = False
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or size(args.artifacts) > LIMIT:
                raise ValueError("Probe exceeded its time or owned-disk limit")
            try:
                name, message = events.get(timeout=min(remaining, 1))
            except queue.Empty:
                # Resource/deadline watchdog only; it never releases a test phase.
                continue
            if message == "OUTPUT_LIMIT":
                raise ValueError("Probe log exceeded its limit")
            if message == "ENGINE_ERROR":
                raise ValueError(f"{name} logged an engine/script error; inspect retained log")
            if name == "server" and message == "STATIONARY_LISTENING":
                launch("Q", "client", "Q")
                launch("P", "client", "P")
            elif name == "server" and message == "STATIONARY_RECONNECT_READY":
                reconnect_ready = True
            elif name == "server" and message == "STATIONARY_AUTHORITY_PASS":
                success = True
            elif message == "EXIT":
                code = processes[name].wait(timeout=3)
                if code:
                    raise ValueError(f"{name} exited {code}; inspect retained log")
                if name == "P":
                    first_p_exited = True
                if name == "server":
                    if not success:
                        raise ValueError("Server exited without verified completion")
                    break
            if first_p_exited and reconnect_ready and not rejoined:
                launch("P-rejoined", "client", "P", rejoin=True)
                rejoined = True
        for process in processes.values():
            if process.wait(timeout=5):
                raise ValueError("Client failed after server completion")
        for reader in readers:
            reader.join(timeout=2)
        for log in args.artifacts.glob("*.log"):
            if re.search(r"(^|\n)(?:SCRIPT )?ERROR:", log.read_text()):
                raise ValueError("Engine error in retained log: " + log.name)
        report = json.loads((args.artifacts / "server.json").read_text())
        if not rejoined or report.get("status") != "pass" or report.get("checks", 0) < 20:
            raise ValueError("Missing actual reconnect or complete authoritative evidence")
        if report.get("opening", False) != args.opening:
            raise ValueError("Server did not exercise the requested fixture mode")
        if args.opening:
            for actor in ("P", "Q"):
                for phase in ("opening-paused", "opening-blocked", "opening-rebuilt"):
                    if actor + ":" + phase not in report.get("clients", {}):
                        raise ValueError("Missing actual opening client observation: " + actor + ":" + phase)
        for required in ("client-P-before-disconnect.json", "client-P-final.json", "client-Q-final.json"):
            if not (args.artifacts / required).is_file():
                raise ValueError("Missing actual client artifact: " + required)
        result = {"status": "pass", "checks": report["checks"], "processes": len(processes),
                  "elapsed_seconds": time.monotonic() - started}
        return result
    finally:
        for process in processes.values():
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        for process in processes.values():
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
        for reader in readers:
            reader.join(timeout=2)
        manifest.update(commands=commands, result=result, elapsed_seconds=time.monotonic() - started,
                        owned_bytes=size(args.artifacts), peak_live_engine_processes=peak_live,
                        process_ids={name: process.pid for name, process in processes.items()})
        (args.artifacts / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--model-revision", required=True)
    parser.add_argument("--artifacts", required=True, type=Path)
    parser.add_argument("--render", action="store_true", help="render both real client views")
    parser.add_argument("--opening", action="store_true", help="exercise shared wheel/power/edit rules with both clients")
    args = parser.parse_args()
    try:
        print(json.dumps(run(args)))
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("STATIONARY PROBE FAILED:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
