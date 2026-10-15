# Opening worksite consumer

The scene uses the shared `res://model.gd` authority. It owns camera, input,
meshes and UI; no recipe, material transfer or finite-part mutation lives here.
The model's opening fixture selects 16 initial blanks and a 1:1 blank/plate
recipe. A four-plate confirmation is a local session acknowledgement derived
from authoritative player inventory; it neither consumes items nor grants
technology/story/team credit. That acknowledgement is not a durable quest system.

From the repository root, launch with the separately verified existing runtime
and an external owned artifact root:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_opening.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --artifacts /absolute/owned/opening-sessions
```

This opens `res://opening/opening.tscn` from a fresh external project copy with
private cache/profile directories and one new session save slot. The neutral
project startup remains unchanged. The launcher downloads or installs nothing;
it records copied source hashes, logs and results and retains the session after
exit. It uses the shared bounded process supervisor with a 30 minute session,
8 MiB per log and 256 MiB artifact-root allowance. Time/size refusal preserves
diagnostics and is a failed run. Sessions share the repository's heavy lane and
resource floors. These are prototype operating limits, not game performance
targets. Close the game window to finish a normal session.
Add `--smoke` for an automated startup check of that same explicit scene; it
exits after 60 frames and requires a structured read-only observation of the
actual opening scene: 16 fresh blanks, the starter kit, no built machines and a
fresh save slot with Save enabled and Load disabled. A missing/invalid report,
wrong scene or wrong initial state fails even when the engine exits cleanly.
This is additional regression coverage, not an interactive-input or user-play
claim. Only smoke mode adds an observer autoload to the external project copy
after editor import. The receipt keeps original `source_hashes` separate from
`instrumentation`, which records the copied, post-import and altered project
hashes plus the observer hash. The tracked project and ordinary launch are
unchanged; `startup.json` retains the actual observation.

Controls: 1 collector, 2 belt, 3 press, 4 waterwheel; click a square to place.
Material ports face +x. F selects a material connection; G selects a drive
connection; click its two neighboring ends. I selects inspection, R retrieves
from the selected press, Space starts/stops the drive. Right-drag orbits, mouse
wheel zooms, WASD pans and Home recenters. H opens a read-only explanation;
construction controls are unavailable until it closes.
F5 or **Save worksite** stores this moment; F9 or **Load worksite** returns to
the latest successful save in this session. Saving again replaces only that
session's own slot. Save/load controls require the launcher's fresh destination;
opening the scene directly without it leaves those controls disabled.

Save/load uses the unchanged shared `save-tests/checkpoint_file.gd` adapter.
It retains paused work, occupied output, exact quantities, machine identities
and cached request outcomes. A successful load clears selected/half-connected
machines, refreshes geometry/items even when revision decreases, and assigns
fresh caller intent IDs. The four-plate session acknowledgement clears; actual
restored inventory determines whether the player can explicitly confirm again.
Failed load preserves current authority, selection, pending connection, caller
IDs and last good file. Failed saving retains the previous file and any blocking
`.pending` diagnostic; it never silently deletes one. No arbitrary file picker,
cross-session save browser, autosave or live network-world replacement is added.
The current slot is retained at the printed session path after exit. A new
launch creates its own slot and refuses to overwrite an existing user file.

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

For the complete single-process input/save/load check, use the launch command
above with `--check`; add `--render` to require real viewport captures. It runs
the unchanged neutral assertions, opening model and checkpoint checks, original
input consumer, and `opening/integration_check.gd`. The latter drives actual
save/load buttons and F5/F9, resumes paused and blocked work, retrieves after
load, restores lower revisions/rebuilt identities, recalculates the four-plate
goal and refuses pending-file collisions. Disposable truncated and contradictory
files exercise the same Load handler; these negative cases do not claim a file
picker interaction or alter the good slot. Logs and the good/bad/pending files
remain in the external session. Interactive launch success is process evidence;
it does not assess player understanding or enjoyment.
`consumer.json` records actual paused/blocked/final quantities and phase; the
Python runner independently checks 16 conserved blanks and four carried plates.

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
Retained outcome targets must match their command: explicit retrieval names the
same processor, drive connection names its destination, and power changes name
the wheel live at command time (empty before placement or after removal).
Material connection and both disconnection outcomes have no entity target.
Historical outcomes remain valid after the named machine is later removed.
A fresh view allocates a new opaque request namespace so its local counter
cannot collide with requests retained by a restored authority. This is intent
identity, not simulation randomness or a chosen production transport protocol.

Current validation includes the 22 unchanged neutral assertions, 60 opening-model
assertions, 384 checkpoint/metadata/target checks and the actual key/mouse/button consumer path in headless and real
Compatibility-rendered runs. Rendered captures were visually inspected. No
human play session, networked opening, save-file/crash durability, detailed
contact/injury, moving machinery, native-core portability or scale claim follows.
Final integration also needs the save and network owners' receipts against the
same integrated opening model. Single-placement placeholder geometry and a
fixed seven-by-seven construction site are intentional prototype limits.
