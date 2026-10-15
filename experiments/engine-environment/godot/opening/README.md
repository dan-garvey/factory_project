# Opening worksite consumer

The scene uses the shared `res://model.gd` authority. It owns camera, input,
meshes and UI; no recipe, material transfer or finite-part mutation lives here.
The model's opening fixture selects 16 initial blanks and a 1:1 blank/plate
recipe. A four-plate confirmation is a local session acknowledgement derived
from authoritative player inventory; it neither consumes items nor grants
technology/story/team credit. That acknowledgement is not a durable quest system.

Open the existing Godot sandbox project with scene
`res://opening/opening.tscn`. The host must have the separately verified sandbox
runtime; this consumer downloads or installs nothing. Use the repository's
`scripts/run_local.py heavy --` wrapper for engine runs. Keep caches and evidence
in a task-owned external copy of the project, following the sandbox runner's
pattern. The project and rule owner must come from the same recorded candidate.

Controls: 1 collector, 2 belt, 3 press, 4 waterwheel; click a square to place.
Material ports face +x. F selects a material connection; G selects a drive
connection; click its two neighboring ends. I selects inspection, R retrieves
from the selected press, Space starts/stops the drive. Right-drag orbits, mouse
wheel zooms, WASD pans and Home recenters. H opens a read-only explanation;
construction controls are unavailable until it closes.

One compact arrangement places wheel/collector/belt/press at x=-1/0/1/2 with
z=0. Connect collector→belt→press for material, then wheel→collector→belt→press
for drive. It is a convenient fixture arrangement, not a permanent blueprint.
Backpressure should be visible at the press outlet. Retrieve its plate to make
room. Stopping power retains partial work; dismantling an occupied component
must refuse rather than erase stock. Empty stopped parts can return to the kit.

Run `--script res://opening/opening_check.gd` for the actual input/scene consumer
checks, with `--headless` for automated assertions. A rendered run accepts
`-- --capture=/absolute/owned/path/opening.png`. It drives real key/mouse/button
events, inspects the actual model, tests backpressure/power pause, refuses losing
held work, retrieves four plates, confirms without consumption and rebuilds a
refunded wheel. A screenshot is visual evidence; the headless assertions establish
only the listed supported behavior. Both are separate from actual user play.

The scoped Python runner copies the shared model/project and opening sources,
records their hashes, and retains logs/results outside Git. Example from the
repository root, substituting the existing verified runtime and owned paths:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B \
  experiments/engine-environment/godot/opening/validate.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --artifacts /absolute/owned/opening-evidence --render
```

It requires the unchanged neutral baseline assertions, opening model invariants
and real scene input path to pass. `--import-only` checks project import alone
and makes no operating/visual claim. No runtime is downloaded. Rejected restore
checks preserve an existing valid world and its request dispositions. Rendered
mode requires a real PNG, not a dummy renderer's successful exit.

The opening requires the model's agreed wheel/shaft/power/stopped-edit/capacity
extension. It cannot truthfully demonstrate those features against the earlier
always-powered neutral model. Evidence must name the actual model revision.
Network clients and save/restore integration remain `.6.10` acceptance, using
Core/Platform's shared consumers rather than a second network/rules implementation.

The opening model option is the optional fourth constructor argument
`{"opening": true}`. The existing three-argument neutral fixture and its 22
assertions remain supported. Opening placement anchors the collector to the
marked seam column and the wheel to its stream bank. Drive links consume three
finite shafts; the whole fixture runs only when all three working components
are reachable from the enabled wheel. This is a simple opening power rule,
not a load/torque model or proof of branch isolation.

`checkpoint()` returns a deep-copied pure-value schema-1 dictionary;
`restore_checkpoint(snapshot)` returns `{accepted, reason}`. Restoration validates
the complete candidate before replacing the live state. It retains options,
power/drive topology, next entity identities, quantities, phase and request
outcomes; a rebuilt machine never inherits an old command's identity. This
prototype uses atomic command admission/application, so it does not claim an
observable accepted-but-pending command stage. Process-held work is represented.
Command metadata and checkpoint contents must be acyclic plain values: scalar
null/bool/int/finite float/string, arrays, and dictionaries with string keys.
Unsupported objects are refused before request retention rather than silently
dropped. The prototype traversal limits are 32 nested levels and 100,000 values;
these are input-format bounds, not game performance targets. Restore requires
an explicit positive validation result, typed correlators and consistent retained
revision, generation, entity, connection, power and retrieval histories.
A fresh view allocates a new opaque request namespace so its local counter
cannot collide with requests retained by a restored authority. This is intent
identity, not simulation randomness or a chosen production transport protocol.

Current validation includes the 22 unchanged neutral assertions, 60 opening-model
assertions, 124 malformed-checkpoint/metadata regressions and the actual key/mouse/button consumer path in headless and real
Compatibility-rendered runs. Rendered captures were visually inspected. No
human play session, networked opening, save-file/crash durability, detailed
contact/injury, moving machinery, native-core portability or scale claim follows.
The save and network owners still need to replay their consumers against the
same integrated opening model. Single-placement placeholder geometry and a
fixed seven-by-seven construction site are intentional prototype limits.
