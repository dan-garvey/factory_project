# Opening worksite consumer

The normal offline and shared opening select the **physical** profile. Offline
now uses the native World through `native_model.gd`; the shared server can select
the same owner explicitly with `--native-world`. Historical shared launch retains
its separate scripted profile. Native drives
consume independent finite shafts, and native checkpoints retain typed custody,
original history and physical seeds. See the [native bridge](../../../../native/factory-godot-world/README.md).
WASD walks a native capsule, Space jumps, and the orbit camera follows your
confirmed character. Right-drag changes the view; the mouse wheel zooms and
Home restores follow distance. Clicked targets never stand in for your body.
Build, dismantle, retrieve and both ends of a connection must be within the
authority's provisional four-world-unit sphere. Move closer after a refusal
and deliberately retry. P (or the drive button) operates the wheel from nearby;
it does not promise a global stop from the press. Read-only inspection, Help,
saving and the non-consuming four-plate confirmation remain available at distance.

The native physical view has eight quick-select slots and a short next-step
prompt. **Build [B]** opens the catalog: choose a destination slot and a carried
part to assign or replace it. Right-click a slot to edit it; an empty slot also
opens the catalog. **1–8** select the displayed assignments. The default order is
Collector, Foundation, Belt, Press, Waterwheel, Cogwheel, Shaft and one empty slot.
Counts and unavailable states follow the active actor's actual kit. Movement keys
are inactive while the catalog is open. Slot assignments are local interface state
and reset on a fresh launch; they are not inventory,
technology unlocks or saved progression. F, G and I retain material, shaft and
inspection selection. Reopening derives goal advice from the actual worksite.

**Foundation** builds a level surface from the carried kit. Its height controls
and Page Up / Page Down select whole-tile factory floors, initially at 1.65 m.
Enable **Access steps** for quarter-height walking steps; turn it off to snap the
selected height back to a factory floor without moving anything already built. Every
foundation and machine uses the same quarter-pitch height unit, currently
0.4125 m on 1.65 m horizontal tiles. Machines require a whole-tile height: a
foundation top at level 0, 4, 8 and so on can support a machine and align its
axle with tile-snapped transmission. Intermediate foundation heights remain
available for steps, but do not show a machine preview or support a powered machine. A 0.825 m foundation stacks two
height units above another foundation. The 1.65 m machines remain two foundation
depths tall. At gravity 14 and jump speed 6, the ideal jump rise is about 1.29 m,
leaving about 0.46 m of clearance above one foundation. Foundations may float
or intersect terrain, rocks and vegetation; no ground contact or gravity support
is required. Enable
**Area (two corners)** to select opposite corners of a rectangular patch at the
chosen height. The translucent preview shows the full footprint. The second
click requests the entire patch atomically from carried parts; insufficient
parts or an occupied tile refuses the whole patch. Escape, changing tools or
changing height cancels the first corner. Area placement temporarily ignores
construction distance; single-block and machine placement retain character reach.
Clear flat ground also supports ordinary
construction throughout the represented site. Uneven ground needs a foundation;
there is no special building rectangle. Constructed machines, overlapping blocks
and characters still block foundation placement. Inspect and Remove reclaim a
block after its machinery has been removed; floating blocks above may remain. The
twenty-four carried blocks and dimensions are experimental defaults. Old saves
are not migrated to this changed feature profile.

In the native profile, place the waterwheel in the stream with its lower rim
immersed and clear of the bed. The wheel tool adjusts its diameter in whole grid
squares, starting at a three-square diameter, and its level on the shared height grid. Choose a horizontal axle across
the current; the sampled flow controls the wheel's signed rotation, and a larger
wheel turns more slowly in the same current. A wheel can be wet yet stationary
when the flow is parallel to its axle. The displayed river has a narrow starter
reach, a deeper and broader reach for a larger wheel, and a downstream rapid
that narrows again. Native current is derived from the emitted terrain bed and
the staged water surface at each wet cell: downhill direction, depth and wetted
width determine local speed. A bank interrupts the route, and a basin without a
lower outlet stays still. The staged surface and speed rule are experimental
site choices, not a volume-conserving fluid simulation. The animated ripple
normal follows the river's downstream direction but does not display a
per-cell speed measurement. Cached seamless two-dimensional ripples replace
straight repeating wave bands. The visible water ends at the terrain-clipped
shoreline with a thin opacity transition; it has no decorative extruded sides.
This is surface presentation, not additional water depth or flow simulation.

In the native profile, G selects an individual **finite shaft tile**. Click the
highlighted tile to place it. Selecting a Cogwheel or Shaft hotbar slot exposes
**Cogwheels and shafts…** for placement settings and transmission removal. The
catalog can assign either tool at any time. The menu chooses X/Y/Z rotation axis
and placement height in full-tile steps. Shafts and cogs occupy one 1.65 m tile
and snap to the common world grid in all three dimensions. That axis also applies to subsequent
machine placement, except for the belt. Select the belt and press **T** to turn
its material direction between +X and +Z; its drive spindle runs across that
direction. The placement preview shows the selected direction, and connecting
machines face along the belt. A translucent cursor marks
the requested gear plane, not permission to build there. Real character
proximity remains authoritative. Adjacent aligned cog, shaft and machine axle
ends connect directly; fill a longer gap with individual shaft tiles.

The inspector can select a cogwheel or shaft and return it to the carried kit.
Static arrows show the confirmed signed rate, and contact marks use confirmed
engagements. Cosmetic wheel, cog and shaft motion illustrates those rates at a
revisable visual reference speed; it does not supply a physics or processing
clock. Angles are local presentation only, retained across ordinary refreshes
but not saved or synchronized as tooth-contact phase. Unknown/stalled parts,
Help, unready actors and disconnected shared views stop the illustration.
The belt carries blanks toward the press only when its top surface moves in that
direction. Reversing the drive carries them off the other end. A loose stack is
shown at that end; stand nearby and use **Pick up loose blanks…** to collect it,
then insert the blanks at a machine. Loose stacks survive saving and belt removal.
This prototype represents their fixed grid locations without gravity. Belt
throughput remains a fixture step. The press's work per tick scales with its
confirmed angular rate and works in either turning direction. Cog and shaft
quantities and dimensions are revisable fixture choices.

After confirming four plates, the native opening marks an upstream waterwheel
site at `[-2, 0]` and asks for eight carried plates in total. The wheel must be
immersed and aligned with the flow. Reconnect the drive after moving it; recover
machine contents before moving a stocked machine. The target and per-actor
eligibility come from the same native definition in offline and shared sessions.
The current ideal hub mounts do not establish housing or floor clearance, and
the geared route does not earn an invented processing-speed bonus.

Selecting the suggested Belt or Press also outlines the empty square at the
confirmed upstream machine's outlet. This cue is a layout suggestion, not a
construction permission or reach indicator. It hides in Help, the catalog and
pending/disconnected views, and when the next square is occupied or ambiguous.

**Details** shows global stock/drive counters and the original save controls;
it does not change their eligibility. Machine inspection, retrieval, dismantling,
connection status, refusal messages and Help remain accessible without it. Help
retains the same separate read-only example. Pending and disconnected shared
views replace the next-action prompt with their current waiting/reconnect state.
The full original interface remains available in the historical legacy fixture.
These view changes need actual rendered and ordinary-input review; source checks
alone do not establish that a new player understands the opening.

The current native offline launch and manual human-entry commands are in the
[native guide](../../../../native/factory-godot-world/README.md#build-and-consume).
The Python launcher description and physical consumer results below belong to
the earlier scripted source revisions. That fixed roster does not deliver the
new bridge, so it is not the current offline entry.

Historically, the scripted physical worksite used the separately
verified existing runtime and an external owned artifact root:

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

The command uses the physical profile by default. With `--check`, it drives actual
ordinary walking/build/interaction input, checks current native cuts, saves,
then reopens that save in another engine process. `--render` additionally retains
the actual view. `--smoke` observes fresh physical startup only. These consumers
are technical evidence, not a human play session. `character.json` and
`character-reopen.json` retain the initial native registration, immediate
admission samples, finite custody, contact/save results and process IDs.
The same batch retains `wall.factory` before later saves, reopens that contact
in another fresh process, then checks a separately generated schema-valid deep
overlap fixture. The latter is explicit malformed persistence data, never a
live pose setter or positive native evidence. Its actual startup must refuse
before readiness or output writing; the raw failed native query is retained.
The check controls production ticks for most assertions; its Help interval uses
the real production clock while movement always uses natural native physics.
The Window focus-release case injects its signal and is labelled accordingly;
it does not claim an actual operating-system focus transition.

F5 saves the current worksite after native pose/geometry/contact preflight.
F9 explains how to reopen it: close the session, then launch with
`--resume /absolute/path/to/session/worksite.factory`. This first physical
adapter refuses live Load as `load_requires_restart` before changing anything.
The selected source remains read only; the new process writes its own slot only
after realizing the saved body. Unsupported saved overlap aborts that new launch
without a spawn fallback. The earlier scripted schema-2 checkpoint saves position/capability;
input, native RIDs, readiness and velocity are not restored as live state.
Offline declares P; shared declares its planned P or P/Q roster. Cross-roster
reopen and old schema-1 saves refuse explicitly; migration is not supplied.

These reversible demo values are recorded in `site_geometry.gd`: pitch 1.65,
work-anchor height 0.5, reach 4, capsule radius 0.3 and height 1.8, speed 3,
gravity 14, jump speed 6, floor snap 0.1 and native motor safe margin 0.001. New P starts
at [-1.65, 1, 3.3] and Q at [-1.65, 1, 4.95], then gravity settles them naturally.
Follow distance 14 and zoom range 8–24 are presentation choices. Native seed
matching uses a 1e-5 observation tolerance. Contact classification allows the
declared 0.001 numerical motor margin. Neither increases the exact scalar reach sphere.

ActorWorld alone supplies native floor layer 1 and uniform machine-box layer 2;
view picking uses layer 4. Actor bodies use layer 16 and mask 1 | 2. **Actor-actor
collision and actor-actor saved-overlap rejection are not implemented.** The
chosen Model placement rule still refuses a new machine intersecting any ready
actor (`actor_occupied`) before parts/IDs change; it does not push or snap them.
Machine boxes are 1.45 × 1.65 × 1.45, with centre height 0.8; they are not precise
art collision. The displayed grid [-2, 4] and terrain extent 256 are fixture
presentation extents, not controller clamps or a selected game-world cap. WorldBoundary floor extent is
backend-specific; diagnostics retain the actual backend setting and size.
Read-only native history holds 2048 observations **globally across all actors
and refreshes**. Consumers capture each admission sample immediately; missing or
evicted evidence never falls back to a newer pose. Shared views render confirmed
proxies only; the dedicated server runs the same single native producer.
Help/focus loss/disconnect releases held movement and queued jump, while gravity
and authoritative production continue. Build acknowledgement waits do not halt
movement. Final movement tuning, camera perspective and game collision policy
remain open. See the [physical contract](../../../../docs/engineering/physical-construction-contract.md).

## Historical unrestricted fixture

The following retained baseline description and old counts apply only to the
explicit `--legacy-fixture` profile. Its free camera, Space power key, live Load
and schema 1 are not evidence of physical-character construction. Use
`scripts/run_opening.py --legacy-fixture --check` for that regression suite.
The older `opening/validate.py` entry point also names this fixture explicitly.

The scene uses the shared `res://model.gd` authority. It owns camera, input,
meshes and UI; no recipe, material transfer or finite-part mutation lives here.
The model's opening fixture selects 16 initial blanks and a 1:1 blank/plate
recipe. A four-plate confirmation is a local session acknowledgement derived
from authoritative player inventory; it neither consumes items nor grants
technology/story/team credit. That acknowledgement is not a durable quest system.

Add `--legacy-fixture` to the launcher above to select this profile. Together
with that flag, `--smoke` checks startup of the historical explicit scene; it
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
construction controls are unavailable until it closes. Help shows a populated
3D example in its own physics world, with a separate instance of the same rules
and its own finite 16 blanks and starter parts. It supplies nothing to your
worksite. Your worksite clock continues while Help is open.

The selected-machine inspector explains the next local step: a missing material
inlet/outlet names the pair to link with F, an unconnected drive calls for G, and
a switched-off drive calls for Space. A full press outlet calls for R to make
room; unfinished work stays in the press. These hints describe confirmed state
and do not grant permission to edit. In shared play, a pending action shows that
the server decision is still awaited, and a disconnected view remains read only.

For a native-authority projection, missing material-link advice does not require
stopping the drive: the stationary native rules allow linking while it runs.
The explicit historical scripted profiles retain their stopped-edit advice.
These are profile-specific hints, not permission or a replacement for the
authority's reach, identity, topology and material checks.

Use Previous/Next (or left/right arrows) to inspect placement, drive, a blank
held in the press, and a blocked outlet. Each lesson resets the example, as its
heading states. **Advance example one tick** moves that example through real
rule transitions; **Collect example plate → resume** removes its blockage and
continues retained work. Right-drag, wheel, WASD and Home control its camera;
click a machine to inspect it. H, Escape or Return closes Help. Player build,
retrieve, power and save/load shortcuts remain unavailable inside the example.
These are reversible presentation choices, not a permanent tutorial policy.
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
The current slot is retained at the printed session path after exit. Add
`--resume /absolute/path/to/previous/session/worksite.factory` to reopen a
compatible worksite in a new process. Its original file is read only; new F5
writes go to the newly printed session slot. The selected input must be a
bounded regular local file outside Git/checkouts/administration/private tracker
paths, without symlinks. Corrupt or unsupported inputs refuse explicitly; they
never silently become a fresh world. The retained `incoming.factory` is a
diagnostic capture, separate from a successfully validated output save.
No implicit latest-file selection, browser, format migration or offline catch-up
is provided. A new launch without `--resume` still begins a fresh worksite.

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
input consumer, `opening/integration_check.gd` and `opening/explanation_check.gd`.
The integration consumer drives actual
save/load buttons and F5/F9, resumes paused and blocked work, retrieves after
load, restores lower revisions/rebuilt identities, recalculates the four-plate
goal and refuses pending-file collisions. Disposable truncated and contradictory
files exercise the same Load handler; these negative cases do not claim a file
picker interaction or alter the good slot. Logs and the good/bad/pending files
remain in the external session. Interactive launch success is process evidence;
it does not assess player understanding or enjoyment.
`consumer.json` records actual paused/blocked/final quantities and phase; the
Python runner independently checks 16 conserved blanks and four carried plates.

`explanation.json` records actual four-lesson states and blocked/recovery
transitions from an initially empty player factory. The explanation check drives
H/Next/Previous/Return, actual example inspection/orbit/zoom/pan, and blocked
player shortcuts. With its declared observation clock frozen, it compares the
full player checkpoint, requests, selection, goal, save facts and camera before
and after; a separate check verifies the normal live clock still runs. The
Python launcher checks an independent finite ledger; rendered mode retains
working, blocked and recovered viewport images. This is technical consumer
evidence, not evidence of player understanding.

`--smoke --resume PATH` checks the actual resumed scene against that saved
checkpoint, with separately recorded observer/configuration instrumentation;
fresh-start smoke keeps its existing oracle. `--check --resume PATH` instead
runs a focused input consumer for a paused or blocked connected opening, resumes
its retained work, retrieves one product and saves the new owned slot. Add
`--render` for its viewport capture. The usual `--check` fixture suite remains
the default when no resume source is selected.

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
