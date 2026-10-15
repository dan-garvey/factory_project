#!/usr/bin/env python3
"""Dependency-free checks for the current tooling, optionally on the Git index.

This is not a game build. Add the actual runtime's checks here when it exists.
The staged mode checks an immutable index snapshot without changing source files
or staging fixes. Git-local environment is removed before running fixture tests.
"""

import argparse
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PORTABLE_BEADS_FILES = {".gitignore", "README.md", "config.yaml", "issues.jsonl", "metadata.json"}


def git(*args, env=None):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], env=env)


def check_sources(root):
    for directory in ("scripts", "tests", ".githooks"):
        for path in sorted((root / directory).rglob("*")):
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            if path.suffix == ".py":
                ast.parse(path.read_bytes(), filename=str(path.relative_to(root)))
            elif path.suffix == ".sh" or directory == ".githooks":
                subprocess.run(["bash", "-n", str(path)], check=True)
    config = root / ".claude/settings.json"
    if config.exists():
        json.loads(config.read_text())
    seen = set()
    for number, line in enumerate((root / ".beads/issues.jsonl").read_text().splitlines(), 1):
        issue = json.loads(line)
        issue_id = issue.get("id")
        if not isinstance(issue_id, str) or not issue_id.startswith("factory-") or issue_id in seen:
            raise ValueError(f"Invalid or duplicate Beads ID on line {number}: {issue_id!r}")
        seen.add(issue_id)


def check_working_tree():
    check_sources(ROOT)
    if not (ROOT / "tests").is_dir():
        raise ValueError("Missing tooling tests; refusing an empty green check")
    suite = unittest.defaultTestLoader.discover(str(ROOT / "tests"))
    if suite.countTestCases() == 0:
        raise ValueError("No tooling tests found")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.skipped:
        print("CHECK FAILED: skipped tooling tests are missing acceptance evidence", file=sys.stderr)
        return 1
    return 0 if result.wasSuccessful() else 1


def check_staged():
    # write-tree fails on unresolved merges and respects a commit's temporary
    # GIT_INDEX_FILE. Read raw blobs: checkout-index would apply local smudge
    # filters, and git archive would honor export-ignore attributes.
    tree = git("write-tree").strip()
    git("diff", "--cached", "--check")
    files = []
    for entry in git("ls-tree", "-rz", tree.decode()).split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, _, object_id = metadata.split()
        path = os.fsdecode(raw_path)
        relative = Path(path)
        if relative.is_absolute() or any(part in ("..", ".git") for part in relative.parts):
            raise ValueError(f"Unsafe staged path: {path}")
        if mode not in (b"100644", b"100755"):
            raise ValueError(f"Staged symlinks/submodules are not supported by this starter gate: {path}")
        if path == ".beads" or (path.startswith(".beads/") and
                                path.removeprefix(".beads/") not in PORTABLE_BEADS_FILES):
            raise ValueError(f"Do not commit Beads runtime data or the shared symlink: {path}")
        files.append((mode, object_id, relative))
    with tempfile.TemporaryDirectory(prefix="factory-check-") as temporary:
        snapshot = Path(temporary) / "tree"
        snapshot.mkdir()
        for mode, object_id, relative in files:
            destination = snapshot / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(git("cat-file", "blob", object_id.decode()))
            destination.chmod(0o755 if mode == b"100755" else 0o644)
        checker = snapshot / "scripts/check.py"
        if not checker.is_file():
            raise ValueError("Staged candidate is missing scripts/check.py")
        clean_env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        clean_env["PYTHONDONTWRITEBYTECODE"] = "1"
        print(f"Checking staged tree {tree.decode()[:12]} (not unstaged files)", flush=True)
        result = subprocess.run([sys.executable, "-B", str(checker)], cwd=snapshot, env=clean_env)
    if git("write-tree").strip() != tree:
        raise ValueError("The Git index changed during checks; review staging and run again")
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="test the exact staged candidate")
    args = parser.parse_args()
    try:
        return check_staged() if args.staged else check_working_tree()
    except (OSError, ValueError, SyntaxError, subprocess.CalledProcessError) as error:
        print(f"CHECK FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
