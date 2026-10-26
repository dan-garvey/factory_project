"""Shared opening source roster and bounded external Store input helpers."""

import os
from pathlib import Path
import stat
import subprocess

import check_engine_environment as bounds


FILES = bounds.FILES + tuple("opening/" + name for name in (
    "opening.gd", "opening.tscn", "actor_body.gd", "actor_world.gd",
    "character_presenter.gd")) + ("save-tests/checkpoint_file.gd",)
RESUME_LIMIT = 2 * 1024**2


def capture_resume(path):
    """Read a bounded regular local input without ever opening it for writing."""
    if (not path.is_absolute() or ".." in path.parts or path.resolve() != path
            or any(part.casefold() in (".git", ".beads") for part in path.parts)):
        raise ValueError("Resume requires an absolute local save outside Git/tracker paths, without symlinks")
    for parent in path.parents:
        if (parent / ".git").exists() or (parent / ".git").is_symlink():
            raise ValueError("Resume input cannot be inside a Git checkout")
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    ownership = subprocess.run(["git", "-C", str(path.parent), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"],
                               capture_output=True, text=True, timeout=5, env=environment)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        raise ValueError("Resume input cannot be inside Git administration or a checkout")
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    if not stat.S_ISREG(os.fstat(descriptor).st_mode):
        os.close(descriptor)
        raise ValueError("Resume input must be a regular local file")
    with os.fdopen(descriptor, "rb") as source:
        content = source.read(RESUME_LIMIT + 1)
    if len(content) > RESUME_LIMIT:
        raise ValueError("Resume input exceeds the bounded local input allowance")
    return content


def _same_value(actual, expected):
    # JSON bools/floats must not masquerade as integer item quantities.
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(_same_value(actual[k], v) for k, v in expected.items())
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(_same_value(a, b) for a, b in zip(actual, expected))
    return actual == expected
