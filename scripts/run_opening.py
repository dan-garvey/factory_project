#!/usr/bin/env python3
"""Launch/check the opening in a fresh external session; use run_local.py heavy."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time

import check_engine_environment as bounds


PROJECT = Path(__file__).resolve().parents[1] / "experiments/engine-environment/godot"
FILES = bounds.FILES + tuple("opening/" + name for name in (
    "opening.gd", "opening.tscn", "opening_check.gd", "model_check.gd",
    "checkpoint_check.gd", "integration_check.gd", "example_presenter.gd",
    "example_world.gd", "explanation_check.gd")) + ("save-tests/checkpoint_file.gd",)
MAX_BYTES = 256 * 1024**2
SMOKE_OBSERVER = "opening/startup_observer.gd"
SMOKE_SCENE = "res://opening/opening.tscn"
RESUME_LIMIT = 2 * 1024**2  # Local input allowance; Store owns format/1 MiB validation.
RESUME_SCRIPTS = ("opening/resume_prepare.gd", "opening/resume_observer.gd", "opening/resume_check.gd")


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


def read_resume_report(path, expected, save_slot):
    if path.stat().st_size > 8 * 1024**2:
        raise ValueError("Resume observer report exceeds its allowance")
    report = json.loads(path.read_text())
    if (not isinstance(report, dict) or not _same_value(report.get("schema"), 1)
            or report.get("scene") != SMOKE_SCENE or report.get("script") != "res://opening/opening.gd"
            or not _same_value(report.get("loaded"), expected["checkpoint"])
            or report.get("continued_from_source") is not True or report.get("slot_matches_loaded") is not True):
        raise ValueError("Resume did not observe the actual restored opening state")
    state = report.get("state", {})
    view = report.get("view", {})
    if not isinstance(state, dict) or any(not _same_value(state.get(key), value)
            for key, value in expected["state"].items() if key not in ("revision", "stock", "remaining")):
        raise ValueError("Resumed observer topology, ownership or inventory changed before input")
    stock = state.get("stock", {})
    if (not isinstance(stock, dict) or any(type(stock.get(key)) is not int or stock[key] < 0
            for key in ("source", "collector", "belt", "input", "held", "output", "player"))
            or sum(stock[key] for key in ("source", "collector", "belt", "input", "held"))
            + state["recipe_input"] * (stock["output"] + stock["player"]) != state["initial_feed"]
            or type(state.get("revision")) is not int or state["revision"] < expected["state"]["revision"]):
        raise ValueError("Resumed observer material accounting or version differs")
    if (not isinstance(state, dict) or not isinstance(view, dict)
            or not _same_value(view.get("save_slot"), str(save_slot))
            or any(view.get(key) is not value for key, value in (
                ("save_ready", True), ("save_owned", True), ("save_disabled", False),
                ("load_disabled", False), ("confirmed", False), ("namespace_nonempty", True)))
            or not _same_value(view.get("request_sequence"), 0)
            or view.get("selected") != "" or view.get("pending") != ""
            or not isinstance(view.get("entity_ids"), list) or any(not isinstance(key, str) for key in view["entity_ids"])
            or not _same_value(sorted(view.get("entity_ids", [])), sorted(expected["state"]["entities"]))
            or view.get("confirm_disabled") is not (expected["state"]["inventories"].get("P", 0) < 4)
            or not save_slot.is_file() or Path(str(save_slot) + ".pending").exists()):
        raise ValueError("Resume view, goal or new-slot ownership differs from restored state")
    return report


def instrument_smoke(project, copied_config_hash):
    """Attach only to the owned copy; keep original and altered hashes distinct."""
    config = project / "project.godot"
    original = config.read_bytes()
    if b"[autoload]" in original:
        raise ValueError("Smoke instrumentation needs explicit support for existing autoloads")
    config.write_bytes(original + b'\n[autoload]\nFactorySmokeObserver="*res://opening/startup_observer.gd"\n')
    return {"kind": "read_only_startup_autoload",
            "modified_files": {"project.godot": {
                "copied_sha256": copied_config_hash,
                "post_import_sha256": hashlib.sha256(original).hexdigest(),
                "runtime_sha256": hashlib.sha256(config.read_bytes()).hexdigest()}},
            "observer": {"path": SMOKE_OBSERVER,
                         "sha256": hashlib.sha256((project / SMOKE_OBSERVER).read_bytes()).hexdigest()}}


def _same_value(actual, expected):
    # JSON bools/floats must not masquerade as integer item quantities.
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(_same_value(actual[k], v) for k, v in expected.items())
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(_same_value(a, b) for a, b in zip(actual, expected))
    return actual == expected


def read_smoke_report(path, save_slot):
    try:
        if path.stat().st_size > 64 * 1024:
            raise ValueError("Startup observer report exceeds its small allowance")
        report = json.loads(path.read_text())
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError("Smoke needs a readable, valid startup observer report") from error
    if (not isinstance(report, dict) or not _same_value(report.get("schema"), 1)
            or report.get("scene") != SMOKE_SCENE
            or report.get("script") != "res://opening/opening.gd"):
        raise ValueError("Smoke did not observe the actual opening scene")
    expected = {
        "context": "opening-local-1", "initial_feed": 16, "recipe_input": 1,
        "order": 0, "entities": {}, "links": [], "drive_links": [], "inventories": {},
        "stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0, "player": 0},
        "parts": {"collector": 1, "belt": 1, "processor": 1, "wheel": 1, "shaft": 3},
        "remaining": 0, "powered": False, "power_enabled": True, "options": {"opening": True}}
    state = report.get("state")
    if (not isinstance(state, dict) or any(not _same_value(state.get(k), v) for k, v in expected.items())
            or type(state.get("revision")) is not int or state["revision"] < 0):
        raise ValueError("Smoke startup quantities, identities, parts or power differ from the fresh fixture")
    view = {"save_slot": str(save_slot), "save_ready": True, "save_owned": False,
            "save_disabled": False, "load_disabled": True, "confirmed": False,
            "request_sequence": 0, "namespace_nonempty": True, "machines": 0, "items": 16}
    if not _same_value(report.get("view"), view):
        raise ValueError("Smoke startup view or save/load ownership differs from the fresh session")
    if any(path.exists() or path.is_symlink() for path in (save_slot, Path(str(save_slot) + ".pending"))):
        raise ValueError("Smoke startup unexpectedly wrote its save slot")
    return report


def check_explanation_report(report):
    # Independent finite ledger: source, collector, belt, input, held, output, player.
    ledgers = ([16, 0, 0, 0, 0, 0, 0], [16, 0, 0, 0, 0, 0, 0],
               [12, 1, 1, 1, 1, 0, 0], [11, 1, 1, 1, 1, 1, 0])
    stages = report.get("lessons")
    if not isinstance(stages, list) or len(stages) != 4:
        raise ValueError("Explanation needs all four actually observed lesson states")
    checks = list(zip(stages, ledgers, (False, True, True, True), (0, 0, 2, 0)))
    checks += [(report.get("step"), [15, 1, 0, 0, 0, 0, 0], True, 0),
               (report.get("blocked_retained"), ledgers[3], True, 0),
               (report.get("recovery"), [10, 1, 1, 1, 1, 1, 1], True, 2)]
    for state, ledger, powered, remaining in checks:
        if not isinstance(state, dict):
            raise ValueError("Explanation state missing")
        stock = dict(zip(("source", "collector", "belt", "input", "held", "output", "player"), ledger))
        expected = {"context": "opening-example-1", "initial_feed": 16, "recipe_input": 1,
                    "stock": stock, "remaining": remaining, "powered": powered,
                    "power_enabled": True, "options": {"opening": True},
                    "inventories": {"EXAMPLE": 1} if ledger[-1] else {},
                    "parts": {"collector": 0, "belt": 0, "processor": 0, "wheel": 0,
                              "shaft": 0 if powered else 3},
                    "entities": {kind + "-1": {"kind": kind, "cell": [cell, 0]}
                                 for kind, cell in (("wheel", -1), ("collector", 0), ("belt", 1), ("processor", 2))},
                    "links": [["collector-1", "belt-1"], ["belt-1", "processor-1"]],
                    "drive_links": [["wheel-1", "collector-1"], ["collector-1", "belt-1"],
                                    ["belt-1", "processor-1"]] if powered else []}
        if any(not _same_value(state.get(k), v) for k, v in expected.items()):
            raise ValueError("Actual explanation differs from independent finite ownership/phase oracle")
    if report.get("isolation") is not True or report.get("live_clock") is not True:
        raise ValueError("Explanation needs isolation and normal live-time evidence")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--check", action="store_true", help="run actual model and input consumers, then exit")
    parser.add_argument("--render", action="store_true", help="capture the real rendered check viewport")
    parser.add_argument("--smoke", action="store_true", help="observe fresh opening scene/state and exit after 60 frames")
    parser.add_argument("--resume", type=Path, help="reopen an explicitly selected compatible save in a new session")
    args = parser.parse_args()
    if args.render and not args.check:
        parser.error("--render selects the rendered automated check; normal launch already opens a window")
    if args.smoke and args.check:
        parser.error("Choose --smoke for scene startup or --check for the input consumers")
    if not args.godot.is_absolute() or not args.godot.is_file() or not os.access(args.godot, os.X_OK):
        parser.error("Use the existing absolute verified Godot executable; no setup is performed")
    artifacts = args.artifacts
    if not artifacts.is_absolute() or artifacts.resolve() != artifacts or artifacts.is_relative_to(PROJECT):
        parser.error("Use an external absolute artifact root without symlinks")
    artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
    ownership = subprocess.run(["git", "-C", str(artifacts), "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir"],
                               capture_output=True, text=True)
    if ownership.returncode == 0 and "true" in ownership.stdout.splitlines():
        parser.error("Keep sessions outside Git worktrees and administration directories")
    if shutil.disk_usage(artifacts).free < 22 * 1024**3 or bounds.owned_bytes(artifacts) >= MAX_BYTES:
        parser.error("Require 22 GiB free and less than 256 MiB retained in this artifact root")
    session = Path(tempfile.mkdtemp(prefix="session-", dir=artifacts))
    project = session / "project"
    save_slot = session / "worksite.factory"
    environment = os.environ.copy()
    receipt = {"status": "running", "mode": "check" if args.check else "startup_smoke" if args.smoke else "interactive",
               "started": datetime.now(timezone.utc).isoformat(), "source_hashes": {}, "stages": [],
               "runner_hashes": {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in (
                   ("run_opening.py", Path(__file__)), ("check_engine_environment.py", Path(bounds.__file__)))},
               "save_slot": str(save_slot), "user_play": "not_assessed"}
    deadline = time.monotonic() + 1800
    bounds.MAX_ARTIFACT_BYTES = MAX_BYTES
    print(f"Opening session: {session}\nSave/Load: F5 / F9. Close the window to finish.", flush=True)
    try:
        if args.resume is not None:
            incoming = capture_resume(args.resume)
            incoming_path = session / "incoming.factory"
            incoming_path.write_bytes(incoming)
            incoming_path.chmod(0o400)
            receipt["resume"] = {"source": str(args.resume), "source_sha256": hashlib.sha256(incoming).hexdigest(),
                                 "incoming": str(incoming_path), "bytes": len(incoming)}
        copied = 0
        for name in (*FILES, *((SMOKE_OBSERVER,) if args.smoke and args.resume is None else ()),
                     *(RESUME_SCRIPTS if args.resume is not None else ())):
            source = PROJECT / name
            if source.is_symlink() or not source.is_file():
                raise ValueError(f"Missing or unsafe opening source: {name}")
            content = source.read_bytes()
            copied += len(content)
            if copied > 2 * 1024**2:
                raise ValueError("Opening source allowance exceeded")
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            receipt["source_hashes"][name] = hashlib.sha256(content).hexdigest()
        for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                          ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
            directory = session / name
            directory.mkdir()
            environment[key] = str(directory)

        def execute(name, arguments, marker=None, timeout=30):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("Opening session reached its 30 minute allowance")
            log = session / (name + ".log")
            result = bounds.execute_bounded([str(args.godot), *arguments], cwd=project, env=environment,
                                            log=log, artifacts=artifacts, timeout=min(timeout, remaining))
            output = log.read_text(errors="replace")
            receipt["stages"].append({"name": name, "exit": result.returncode})
            if result.returncode or "ERROR:" in output or (marker and marker not in output):
                raise ValueError(f"{name} failed; inspect {log}")
            return output

        version = execute("version", ["--version"]).strip()
        if not version.startswith("4.7.2.stable."):
            raise ValueError("This experiment uses the separately verified Godot 4.7.2 stable")
        execute("import", ["--headless", "--editor", "--path", str(project), "--import"], timeout=180)
        resume_arguments = []
        if args.resume is not None:
            expected_path = session / "resume-expected.json"
            resume_arguments = ["--resume-input=" + str(incoming_path)]
            execute("resume-prepare", ["--headless", "--path", str(project), "--script", "res://opening/resume_prepare.gd",
                                      "--", *resume_arguments, "--resume-report=" + str(expected_path)], "OPENING_RESUME_VALID")
            expected_resume = json.loads(expected_path.read_text())
            if expected_resume.get("accepted") is not True:
                raise ValueError("Selected save was refused by the actual Model/Store")
        if args.check:
            checks = (("resume-input", "opening/resume_check.gd", "OPENING_RESUME_INPUT_PASS"),) if args.resume is not None else (
                    ("neutral", "tests.gd", "FACTORY_HEADLESS_PASS"),
                    ("opening-model", "opening/model_check.gd", "OPENING_MODEL_PASS"),
                    ("checkpoint", "opening/checkpoint_check.gd", "CHECKPOINT_REGRESSION_PASS"),
                    ("opening-input", "opening/opening_check.gd", "OPENING_INPUT_PASS"),
                    ("save-load-input", "opening/integration_check.gd", "OPENING_SAVE_LOAD_PASS"),
                    ("explanation-input", "opening/explanation_check.gd", "OPENING_EXPLANATION_PASS"))
            for name, script, marker in checks:
                arguments = ["--path", str(project), "--script", "res://" + script]
                stage_slot = session / "example-unwritten.factory" if name == "explanation-input" else save_slot
                if args.render and name in ("opening-input", "save-load-input", "explanation-input", "resume-input"):
                    capture = session / (name + ".png")
                    arguments += ["--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
                                  "--", "--capture=" + str(capture), "--save-slot=" + str(stage_slot), *resume_arguments]
                else:
                    arguments = ["--headless", *arguments, "--", "--save-slot=" + str(stage_slot), *resume_arguments]
                output = execute(name, arguments, marker,
                                 timeout=180 if args.render and name in ("opening-input", "save-load-input", "explanation-input", "resume-input") else 30)
                if name == "resume-input":
                    prefix = "OPENING_RESUME_STATE "
                    report = json.loads(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))
                    final = report["final"]
                    inventories = dict(expected_resume["state"]["inventories"])
                    inventories["P"] = inventories.get("P", 0) + 1
                    stock = final["stock"]
                    if (not _same_value(report.get("loaded"), expected_resume["checkpoint"])
                            or report.get("failures") != [] or report.get("checks", 0) < 10
                            or not _same_value(final["inventories"], inventories)
                            or any(not _same_value(final[k], expected_resume["state"][k])
                                   for k in ("initial_feed", "recipe_input", "entities", "links", "drive_links", "parts"))
                            or sum(stock[k] for k in ("source", "collector", "belt", "input", "held"))
                            + final["recipe_input"] * (stock["output"] + sum(inventories.values())) != final["initial_feed"]):
                        raise ValueError("Actual resumed input differs from saved state and independent material/identity oracle")
                    receipt["resume_consumer"] = report
                if name == "save-load-input":
                    prefix = "OPENING_SAVE_LOAD_STATE "
                    report = json.loads(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))
                    final = report["final"]
                    stock = final["stock"]
                    raw = sum(stock[key] for key in ("source", "collector", "belt", "input", "held"))
                    if (final["initial_feed"] != 16 or final["inventories"] != {"P": 4}
                            or raw + stock["output"] + sum(final["inventories"].values()) != 16
                            or not report["confirmed"] or report["paused"]["remaining"] != 2
                            or report["paused"]["restored_remaining"] != report["paused"]["remaining"]
                            or report["paused"]["power_enabled"] or report["paused"]["stock"]["held"] != 1
                            or report["blocked"]["stock"]["output"] != 1 or report["blocked"]["stock"]["held"] != 1):
                        raise ValueError("Actual consumer quantities/phase/goal differ from the independent fixture oracle")
                    (session / "consumer.json").write_text(json.dumps(report, indent=2) + "\n")
                if name == "explanation-input":
                    prefix = "OPENING_EXPLANATION_STATE "
                    report = json.loads(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix)))
                    check_explanation_report(report)
                    (session / "explanation.json").write_text(json.dumps(report, indent=2) + "\n")
                if args.render and name in ("opening-input", "save-load-input", "explanation-input", "resume-input"):
                    if not capture.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
                        raise ValueError("Missing actual rendered viewport capture")
        else:
            arguments = ["--path", str(project), SMOKE_SCENE,
                         "--rendering-method", "gl_compatibility"]
            user_arguments = ["--save-slot=" + str(save_slot), *resume_arguments]
            if args.smoke:
                if args.resume is None:
                    receipt["instrumentation"] = instrument_smoke(project, receipt["source_hashes"]["project.godot"])
                else:
                    config = project / "project.godot"
                    original = config.read_bytes()
                    if b"[autoload]" in original:
                        raise ValueError("Resume smoke needs explicit support for existing autoloads")
                    config.write_bytes(original + b'\n[autoload]\nFactoryResumeObserver="*res://opening/resume_observer.gd"\n')
                    receipt["instrumentation"] = {"kind": "read_only_resume_observer",
                        "modified_files": {"project.godot": {"copied_sha256": receipt["source_hashes"]["project.godot"],
                            "post_import_sha256": hashlib.sha256(original).hexdigest(),
                            "runtime_sha256": hashlib.sha256(config.read_bytes()).hexdigest()}},
                        "observer": {"path": "opening/resume_observer.gd", "sha256": receipt["source_hashes"]["opening/resume_observer.gd"]}}
                startup_report = session / "startup.json"
                user_arguments.append("--startup-report=" + str(startup_report))
                arguments += ["--quit-after", "60"]
            execute("interactive", [*arguments, "--", *user_arguments],
                    timeout=30 if args.smoke else 1800)
            if args.smoke:
                receipt["startup"] = (read_smoke_report(startup_report, save_slot) if args.resume is None
                                      else read_resume_report(startup_report, expected_resume, save_slot))
        receipt["status"] = "pass"
    except Exception as error:
        receipt["status"] = "fail"
        receipt["error"] = str(error)
        raise
    finally:
        if "resume" in receipt:
            try:
                unchanged = hashlib.sha256(capture_resume(args.resume)).hexdigest() == receipt["resume"]["source_sha256"]
            except (OSError, ValueError, subprocess.SubprocessError):
                unchanged = False
            receipt["resume"]["source_unchanged"] = unchanged
            if not unchanged:
                receipt["status"] = "fail"
                receipt["error"] = "The selected source changed during this session; inspect retained evidence"
        receipt["owned_bytes"] = bounds.owned_bytes(artifacts)
        receipt["finished"] = datetime.now(timezone.utc).isoformat()
        (session / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if receipt["status"] != "pass":
        raise ValueError(receipt.get("error", "Opening failed"))
    print(f"Opening {receipt['mode']} finished; evidence and save retained at {session}")


if __name__ == "__main__":
    main()
