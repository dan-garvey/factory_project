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
GODOT_PROJECT = Path("experiments/engine-environment/godot")


def git(*args, env=None):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], env=env)


def staged_gdscript_changes(tree):
    head = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--verify", "--quiet", "HEAD"],
                          capture_output=True)
    if head.returncode == 0:
        names = git("diff-tree", "--no-commit-id", "--name-only", "--no-renames", "-r", "-z",
                    head.stdout.strip().decode(), tree.decode()).split(b"\0")
    else:
        names = git("ls-tree", "-rz", "--name-only", tree.decode()).split(b"\0")
    paths = [Path(os.fsdecode(name)) for name in names if name and Path(os.fsdecode(name)).suffix == ".gd"]
    if any(not path.is_relative_to(GODOT_PROJECT) for path in paths):
        raise ValueError("Staged GDScript outside the supported prototype project needs an explicit parser contract")
    return paths


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


def check_working_tree(godot=None, prototype_artifacts=None, prototype_render=False,
                       parse_gdscript=False, godot_sha256=None, source_tree=None):
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
    if not result.wasSuccessful():
        return 1
    if godot:
        if parse_gdscript:
            command = [sys.executable, "-B", str(ROOT / "scripts/check_gdscript.py"),
                       "--godot", str(godot), "--sha256", godot_sha256,
                       "--artifacts", str(prototype_artifacts), "--source-tree", source_tree]
            return subprocess.run(command, cwd=ROOT).returncode
        command = [sys.executable, "-B", str(ROOT / "scripts/check_engine_environment.py"),
                   "--godot", str(godot), "--artifacts", str(prototype_artifacts)]
        if prototype_render:
            command.append("--render")
        return subprocess.run(command, cwd=ROOT).returncode
    return 0


def check_staged(godot=None, prototype_artifacts=None, prototype_render=False,
                 parse_gdscript=False, godot_sha256=None, expected_tree=None):
    # write-tree fails on unresolved merges and respects a commit's temporary
    # GIT_INDEX_FILE. Read raw blobs: checkout-index would apply local smudge
    # filters, and git archive would honor export-ignore attributes.
    tree = git("write-tree").strip()
    if expected_tree is not None and tree.decode() != expected_tree:
        raise ValueError("The Git index changed before admission; review staging and run again")
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
        if path == ".beads" or path.startswith(".beads/"):
            raise ValueError(f"Do not commit private Beads runtime data, exports or configuration: {path}")
        files.append((mode, object_id, relative))
    if staged_gdscript_changes(tree) and not parse_gdscript:
        raise ValueError("Staged GDScript requires python3 -B scripts/check_commit.py (one top-level heavy admission)")
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
        command = [sys.executable, "-B", str(checker)]
        if godot:
            command += ["--godot", str(godot), "--prototype-artifacts", str(prototype_artifacts)]
            if prototype_render:
                command.append("--prototype-render")
            if parse_gdscript:
                command += ["--parse-gdscript", "--godot-sha256", godot_sha256,
                            "--source-tree", tree.decode()]
        result = subprocess.run(command, cwd=snapshot, env=clean_env)
    if git("write-tree").strip() != tree:
        raise ValueError("The Git index changed during checks; review staging and run again")
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="test the exact staged candidate")
    parser.add_argument("--godot", type=Path, help="explicit installed engine: also require prototype checks")
    parser.add_argument("--prototype-artifacts", type=Path, help="external owned output/cache directory")
    parser.add_argument("--prototype-render", action="store_true", help="also require the actual 3D renderer")
    parser.add_argument("--parse-gdscript", action="store_true", help="compiler-only path used by check_commit.py")
    parser.add_argument("--godot-sha256", help="explicit local verified executable pin for compiler-only checks")
    parser.add_argument("--expected-tree", help="refuse an index changed while waiting for top-level admission")
    parser.add_argument("--source-tree", help="immutable staged origin passed only to the snapshot compiler")
    args = parser.parse_args()
    if bool(args.godot) != bool(args.prototype_artifacts) or (args.prototype_render and not args.godot):
        parser.error("--godot and --prototype-artifacts are required together; rendering also requires them")
    if args.parse_gdscript and (not args.godot or not args.godot_sha256 or args.prototype_render):
        parser.error("GDScript parsing requires --godot, --godot-sha256 and --prototype-artifacts, without rendering")
    if (args.godot_sha256 or args.source_tree) and not args.parse_gdscript:
        parser.error("Compiler pins/origins require --parse-gdscript")
    if args.expected_tree and not args.staged:
        parser.error("--expected-tree requires --staged")
    if args.parse_gdscript and not args.staged and not args.source_tree:
        parser.error("Compiler-only checks require an explicit immutable staged origin")
    try:
        options = (args.godot, args.prototype_artifacts, args.prototype_render, args.parse_gdscript, args.godot_sha256)
        return (check_staged(*options, args.expected_tree) if args.staged
                else check_working_tree(*options, args.source_tree))
    except (OSError, ValueError, SyntaxError, subprocess.CalledProcessError) as error:
        print(f"CHECK FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
