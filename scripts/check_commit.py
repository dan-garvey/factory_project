#!/usr/bin/env python3
"""One top-level admission for the exact staged commit. Do not wrap this script."""

import argparse
import re
import subprocess
import sys

import check
import run_local


def local_value(name):
    result = subprocess.run(["git", "-C", str(check.ROOT), "config", "--local", "--get", name],
                            text=True, capture_output=True)
    if result.returncode or not result.stdout.strip():
        raise ValueError(f"Staged GDScript needs repository-local {name}; see docs/engineering/native-builds.md")
    return result.stdout.strip()


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    try:
        tree = check.git("write-tree").strip()
        game = bool(check.staged_gdscript_changes(tree))
        command = [sys.executable, "-B", str(check.ROOT / "scripts/check.py"),
                   "--staged", "--expected-tree", tree.decode()]
        if game:
            binary = local_value("factory.godotExecutable")
            digest = local_value("factory.godotSHA256")
            artifacts = local_value("factory.godotArtifacts")
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError("factory.godotSHA256 must pin the verified executable with 64 lowercase hex digits")
            command += ["--parse-gdscript", "--godot", binary, "--godot-sha256", digest,
                        "--prototype-artifacts", artifacts]
        return run_local.run(check.ROOT, "heavy" if game else "check", command)
    except run_local.AdmissionError as error:
        print(f"COMMIT CHECK DEFERRED: {error}", file=sys.stderr)
        return 75
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"COMMIT CHECK FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
