# Retained Godot fixtures

The ordinary native game entry is documented in [README](../../README.md).
This directory also retains earlier scripted experiments and focused native
adapters. Their fixture defaults are not current game requirements.

Use the pinned Godot 4.7.2 executable, import resources first, and use an owned
external artifact directory with [resource admission](../../docs/engineering/local-resources.md).
For a focused script use the
[native fixture runner](../../native/godot-fixture/README.md); supply the exact
PASS line for the selected source revision and reject engine error lines.

| Location under `godot/` | Scope |
| --- | --- |
| `opening/` | Ordinary scene, native adapters, UI/presentation checks |
| `opening-session/` | Shared server/client and continuation consumers |
| `rotary/`, `rider/`, `train/`, `moving-transfer/` | Bounded motion, passenger and port experiments |
| `mechanics/`, `precision/`, `workshop/`, `scaling/` | Rule/arrangement and quantity fixtures |
| `stationary-tests/`, `save-tests/` | Scripted authority and Store fixtures |
| `model.gd`, `tests.gd`, `scenario.gd` | Earlier engine-coupled finite production baseline |

Each script defines its required arguments, markers and invented setup.
The shared server selects native authority explicitly with `--native-world`;
legacy fixed-roster Python launchers do not prepare its compiled resources.
Source/runtime identity, actual outcomes and unresolved coverage belong in Beads.

The historical sandbox command remains available for changes to that fixture:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check_engine_environment.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --artifacts /absolute/owned/fresh-sandbox --render
```

It imports, runs bounded headless checks and optionally renders, retaining
source hashes and first failures. Its scripted production owner is not the
native opening. Rendered fixtures are not human play; live scene code should
not assume their fixed stock, dimensions, roster or controls.
