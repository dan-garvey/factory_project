#!/usr/bin/env python3
"""Cooperative admission for checks, heavy work, and quiet measurements.

Usage: python3 -B scripts/run_local.py [options] MODE -- COMMAND [ARG ...]
Locks coordinate this Git repository's worktrees, not unrelated host processes.
"""

import argparse
from contextlib import contextmanager, ExitStack
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
GIB = 1024 ** 3
TEMPORARY_FAILURE = 75


class AdmissionError(RuntimeError):
    """The requested work cannot be admitted safely right now."""


def common_git_dir(root):
    # Hooks can export paths for their original repository/index. Discovery is
    # anchored to the checkout containing this script and never opens its index.
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    result = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "--path-format=absolute", "--git-common-dir"],
        env=env, text=True,
    )
    return Path(result.strip()).resolve(strict=True)


@contextmanager
def admission(common_dir, mode, wait=True):
    directory = common_dir / "factory-local-resources"
    directory.mkdir(mode=0o700, exist_ok=True)
    with ExitStack() as stack:
        handles = []

        def lock(name, operation):
            handle = stack.enter_context((directory / name).open("a+b"))
            try:
                fcntl.flock(handle, operation | (0 if wait else fcntl.LOCK_NB))
            except BlockingIOError as error:
                raise AdmissionError(f"{mode} is busy; another wrapped command holds {name}") from error
            handles.append(handle.fileno())

        # Waiting heavy commands do not hold shared activity while queued for
        # the single heavy lane. No mode acquires these locks in reverse order.
        if mode == "heavy":
            lock("heavy.lock", fcntl.LOCK_EX)
        lock("activity.lock", fcntl.LOCK_EX if mode == "benchmark" else fcntl.LOCK_SH)
        yield handles


def available_memory(path=Path("/proc/meminfo")):
    for line in path.read_text().splitlines():
        if line.startswith("MemAvailable:"):
            _, amount, unit = line.split()
            if unit != "kB":
                raise ValueError(f"Unexpected MemAvailable unit: {unit}")
            return int(amount) * 1024
    raise ValueError("MemAvailable is missing; refusing to guess memory capacity")


def check_capacity(root, disk_floor_gib, memory_reserve_gib):
    free = shutil.disk_usage(root).free
    if free < disk_floor_gib * GIB:
        raise AdmissionError(
            f"free disk {free / GIB:.1f} GiB is below the {disk_floor_gib} GiB floor"
        )
    memory = available_memory()
    if memory < memory_reserve_gib * GIB:
        raise AdmissionError(
            f"MemAvailable {memory / GIB:.1f} GiB is below the {memory_reserve_gib} GiB reserve"
        )


def run(root, mode, command, jobs=8, disk_floor_gib=20, memory_reserve_gib=8, wait=True):
    common_dir = common_git_dir(root)
    print(f"local resources: waiting for {mode} admission", file=sys.stderr, flush=True)
    with admission(common_dir, mode, wait=wait) as handles:
        if mode != "check":
            check_capacity(root, disk_floor_gib, memory_reserve_gib)
        env = dict(os.environ)
        for variable in ("CMAKE_BUILD_PARALLEL_LEVEL", "CARGO_BUILD_JOBS", "CTEST_PARALLEL_LEVEL"):
            env[variable] = str(jobs)
        print(f"local resources: admitted {mode}, jobs={jobs}", file=sys.stderr, flush=True)
        # The immediate child retains the admission even if this wrapper exits
        # unexpectedly. Commands must wait for their work, not detach daemons.
        result = subprocess.run(command, env=env, pass_fds=handles)
        return result.returncode if result.returncode >= 0 else 128 - result.returncode


def nonnegative(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("must be zero or greater")
    return number


def positive(value):
    number = nonnegative(value)
    if number == 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("check", "heavy", "benchmark"))
    parser.add_argument("--jobs", type=positive, default=8)
    parser.add_argument("--disk-floor-gib", type=nonnegative, default=20)
    parser.add_argument("--memory-reserve-gib", type=nonnegative, default=8)
    parser.add_argument("--no-wait", action="store_true", help="exit 75 instead of waiting for admission")
    arguments = list(sys.argv[1:] if argv is None else argv)
    separator = arguments.index("--") if "--" in arguments else len(arguments)
    args = parser.parse_args(arguments[:separator])
    command = arguments[separator + 1:]
    if not command:
        parser.error("provide -- followed by a command")
    try:
        return run(ROOT, args.mode, command, args.jobs, args.disk_floor_gib,
                   args.memory_reserve_gib, wait=not args.no_wait)
    except AdmissionError as error:
        print(f"LOCAL WORK DEFERRED: {error}", file=sys.stderr)
        return TEMPORARY_FAILURE
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"LOCAL WORK FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
