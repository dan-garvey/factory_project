# Native capture and startup

Build `//native/factory-launch:factory-project-capture` and
`//native/factory-launch:factory-opening-startup` through
[native builds](../../docs/engineering/native-builds.md).
Use the [native gameplay recipe](../factory-godot-world/README.md#build-and-consume)
for the extension descriptor/library and ordinary scene.

## Capture

```bash
/absolute/verified/factory-project-capture \
  --repo /absolute/checkout --tree FULL_COMMIT_OR_TREE_ID \
  --output /absolute/owned/fresh-capture
```

Run under ordinary admission. The repository/output parent must be canonical;
output must be new and outside source worktrees and Git administration.
The tool reads the tracked Godot project from raw Git blobs, excluding ignored
files, private tracker data and generated caches. It refuses symlinks/submodules.

A completed `capture.json` binds tree, modes, blob identities, hashes and totals.
An incomplete directory is retained diagnostic output, never a successful capture.
The tool performs no engine run or game-state interpretation.

## Startup and resume

Startup keeps pristine `project/` and a separate `runtime/project/` for imports.
It verifies engine and original source bytes around headless editor import and
ordinary `opening/opening.tscn` startup. Native resources require all six paired
descriptor/library path, SHA256 and relative-path options shown in the gameplay
recipe. Predeclare the native extension before import; do not substitute the
ABI-test library or a scripted fallback.

Use `factory-local heavy --inherit-permits` for startup's bounded child runner.
The later interactive engine launch is a separate admitted command without
inherited runner descriptors.

For continuation, add `--resume /absolute/previous.factory`. Startup copies the
opaque Store file into read-only `incoming.factory`; Store alone validates it.
The normal scene must save fresh `worksite.factory`. Invalid, empty, changed,
aliased or oversized input refuses rather than creating a fresh world.
For manual graphical entry, pass that captured incoming file with
`--resume-input` and a separate fresh `--save-slot`.

## Limits

Source capture allows 64 MiB, 512 files and 128 scripts. Resume input is 2 MiB;
native descriptor/library limits are 64 KiB/64 MiB. Startup retains a 256 MiB
session family and two 4 MiB logs with a 120-second engine-stage limit.
These are adapter budgets, not game requirements.

Original-source mutations and strict engine error lines fail even with exit zero.
Owned process groups are cleaned and failed evidence retained. Successful startup
establishes only the exercised entry, not readable graphics, saved production,
human input or multiplayer. Record exact outcomes in Beads.
