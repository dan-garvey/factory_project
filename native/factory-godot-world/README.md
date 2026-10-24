# Native World in the Godot opening

`FactoryNativeWorld` is a scene-level `RefCounted` extension that owns one C++
World. The normal offline scene uses `opening/native_model.gd` to forward
commands, natural ticks, ActorWorld observations and checkpoint values. The
bridge has no file, network connection, clock or second quantity map. Store
retains the existing binary envelope, verified write and atomic publication.
Missing native resources fail startup; only an explicit `--legacy-fixture`
selects the historical scripted fixture. The existing shared server can explicitly
select this same native owner with `--native-world`; clients remain read-only
Session facades and never instantiate a native World.

`initialize_arrival(context, actors)` is an experimental native site seed for
the redesigned opening. It creates one settled landing pod and nine ordinary
foundations and one distinct fabrication hub on the common quarter-tile grid,
puts both actors on the deck, and
leaves fifteen of the original twenty-four foundation parts with P. Its
projection includes `landing_pod`, `fabrication_hub` and the usual foundation records; the normal
checkpoint retains both. The ordinary offline scene selects this profile through
the NativeModel arrival argument; existing mechanics fixtures and shared startup
still use `initialize`. This
slice has native actor component cargo and an actor-reachable `craft_component`
command at the east deck bench. The command spends the actor's own raw stock,
reports the typed component and survives retry and restore. `place_component`
and `reclaim_component` move that stock between actor cargo and persistent
quarter-grid world parts with one native material ledger. The Host projects
their identities, positions and types and reserves component-specific occupied
bounds against actors, terrain obstacles, belts and complete machines. A placed
wooden workbench costs four harvested timbers, occupies a supported aligned tile,
and offers the same local component and stationary-part crafting commands as the
pod workshop. The original issued workshop can be stowed by a nearby actor and
redeployed at a clear site; its holder and the placed bench identities survive
checkpoint restore. Both benches spend only the crafting actor's carried stock.
The Host also derives `supplied_hardware_boxes` for the fixed deployed pod and
installed issued workshop. Their anchors use the foundation floor and common
height unit, without the transmission spindle offset. Native construction and
checkpoint checks share these coarse boxes with ActorWorld's existing component
body cache; stow and relocation change the emitted geometry rather than a second
scene authority. Actor seeds inside supplied hardware are invalid. The focused
`arrival_geometry_test` and `native_adapter_check.gd` mode `supplied-hardware`
cover native refusals, conservation, real capsule collision, clear access,
relocation and registration. The reveal remains cosmetic, not falling-pod physics.
A placed cutting edge at one of the profile's trusted ore faces may contact only the
tagged source outcrop; other components and other obstacles still block it.
Checkpoint import rechecks that same source fit against the receiving site.
Grounded frame legs and the current collector components have fitted bounds;
future component art still needs its own fit review. A placed collector can
now be turned manually; press assembly remains unfinished. The offline view
offers exact-target ore harvesting and native stock feedback. Scene controls
for placing, selecting, stowing and redeploying the portable workbench still
need integration. The experimental
arrival begins without inherited complete-machine or transmission kits; the
historical initializer retains those mechanics fixtures. The new offline start
is partial implementation toward the chapter contract, not chapter completion.
The pod also starts with one identified detachable hand crank. A nearby
physical actor can take it from the pod tray or return it through Host
commands. Its single holder is projected and preserved through retries and
checkpoints. It is not yet physically attached to a shaft or driving continuous motion.
The arrival projection derives `collector_assemblies` from those placed
components at the two west-facing ore workcells and their supported grid
heights. Each entry reports missing, ready or ambiguous geometry; a ready
entry names the five exact installed identities, cutting height and shaft
material. The trusted profile carries those same ore faces into World and its
checkpoint fingerprint. A nearby actor holding the unique pod crank can send
`turn_hand_crank` for an installed shaft in a ready layout. One accepted turn
moves one finite ore blank into canonical loose-item custody at its receiver
center. Native World ticks can move that item onto a correctly positioned,
outward-running belt endpoint, while stopped, reversed and full inlets retain
it. The arrival workshop now offers provisional finite recipes for a waterwheel
(two timber and one softmetal), a full-tile shaft (one timber), and a belt span
(two timber and one softmetal). A route with three shafts, one span and one wheel
embodies seven timber and two ore. These kits stay in the single World inventory,
with their spent material and installation custody checked against accepted
history on restore. The ordinary workshop offers the recipes and points out the
receiver mouth, rotation direction and occupied inlet; a short passive chute
appears only where a ready receiver meets a placed belt endpoint. The scene
consumer builds the route from harvested stock through a physical actor and
checks a transferred blank and a fresh-process Store continuation. Full output
and missing parts, wrong holder and remote poses refuse without a debit. The
hand crank cuts a blank at its fitted shaft; the waterwheel powers the belt.
The read-only `press_assemblies` projection inspects each placed wooden frame
against the same canonical component records. A ready entry names the separate
anvil, ram face, guide, mount, shaft and cog, the work and drive centers,
material types and clear lower feed/exit routes. Missing or ambiguous entries
stay visible for diagnosis. An actor-bound `feed_press` request selects a clear
entry and moves one carried blank into the existing loose-material record at
that press's work center. An actor holding the identified pod crank can turn
the press's installed drive shaft and select a clear lower exit. The native
work clock creates a WorkLot, advances it on later turns and releases one
formed product into the canonical loose-material ledger. A full or terrain
blocked exit retains custody, and pickup recovers a blank, partial work or
product after dismantling. The Host checks physical actor reach and exit site
clearance; ordinary scene press controls and autonomous drive remain open.
The separate read-only `guided_press_assemblies` projection inspects each
placed anvil for the five-part, frame-free press. Ready entries identify the
anvil, ram, guide, shaft and cog, their work and drive centers, and the four
open feed routes. The same actor-bound feed and hand-crank requests accept its
anvil identity; the ordinary scene still consumes the framed projection.
The arrival profile additionally exposes `hand_sources`: three named
eight-piece timber sites and one 4,096-unit ore deposit. `harvest_source`
accepts a target identity only after the bound physical actor is ready and
within reach. It credits timber or raw ore in the same native actor cargo,
with the ore debit shared by the collector. Source balances and carried timber
survive the normal checkpoint. Current site coordinates are provisional; the
live scene has no matching harvestable tree art, depletion feedback or crafting
consumer yet. The focused Host test uses synthetic poses; the ordinary view
consumes the same exact source identities through its multitool interaction.

The current opening adapter is a revisable profile: a finite 4,096-unit ore
deposit, a 32-blank collector buffer, one-unit downstream buffers, a two-tick
press, four-world-unit reach and the existing site/capsule geometry. Batch raw
recovery lets the larger reserve fit the prototype's request and save budgets.
The view receives `source_deposit.cells`, initial stock, buffer capacity and
maximum depth from this native owner; it holds no source ledger. The initial
node covers cells `[0, 0]` and `[0, 1]`, with one carried collector.
The native `motion` projection includes complete placed collector and press
drive parts under their issued IDs. Overloaded parts expose the effective
`capacity`, `impact`, `limiting_part` and `remedy`; an empty limiting part means
the wheel source capacity is insufficient. A placed wooden shaft or cog can
stall a connected line while another branch remains in motion. This is native
load feedback, not a scene usability or human play result.

The collector may operate above the mineral surface by at most eight common
height steps (3.3 m), allowing a leveling foundation over sloped ore. Construction
support, actor occupancy and proximity still apply independently. Placement and
checkpoint import use the same mineral footprint and depth rule. Rebuilding a
collector, changing foundations or reopening cannot refill the deposit. No old
sixteen-unit checkpoint migration is provided.

At ground level, either admitted deposit cell adds a short, source-facing pickup
volume to the collector body. The trusted site adapter identifies the fixed
outcrop obstacle so only that pickup may meet its rock; other scenery, actors,
foundations and constructed parts still block the occupied volume. The scene
renders a housing and trough from the pickup toward the stock bed and registers
the same conservative box for physical contact and picking. At four or eight
height steps, a separate pickup touches the same rock face and an exterior
open lift runs beside the foundation to an upper head. Its guides and flights
are occupied native volumes with matching scene collision and picking; a solid
carrier box would incorrectly obstruct the working cog route. The headless
native and normal-scene checks establish this physical fit, while matched
passive views still leave the lower route concealed from the outlet side.
This fixed interface is a prototype asset fit, not simulated cutter teeth or a
general rule for arbitrary ore nodes.

The adapter preserves the original wire intent in World's history. Exact retry
lookup precedes current target translation, so removal, rebuilding and a fresh
process cannot retarget an old receipt. Checkpoint import validates the original
action and typed payload against that historical translation without using
present poses or generations. Malformed adapter refusals retain their exact wire.

Player-built foundations are native World state and finite construction custody,
not mechanical hubs or prebuilt scenery. The current kit carries twenty-four
1.65 m blocks. The world origin and quarter-pitch integer height unit are shared
with machinery and transmission. `place_foundation` takes an integer `cell` and
absolute `level`; machine placement uses the same level and requires a multiple
of four so its axle aligns with the one-tile transmission grid. Foundations may
still use intermediate levels for their half-height steps. Waterwheel axle
levels also use multiples of four, so some wet sites need another size or site.
Ordinary `remove`
reclaims a foundation only after its dependents are removed. Exact retries use
the existing request history and never consume another block.

At startup the trusted adapter binds the actual emitted terrain vertices and
conservative rock/tree bounds once through `configure_terrain`. This interface is
not a Session command. Native machine placement clips both terrain triangles
throughout the complete footprint, refusing burial, unsupported bases and occupied
scenery. Foundations can intersect natural ground/scenery and need no lower block
or gravity support; constructed parts and actors still block their placement.
The ordinary site also supplies wet grid cells and water levels. Native waterflow
uses those same terrain triangles to derive bed depth, bank-clear downstream
neighbors and local current; the waterwheel samples that result at its actual
center. The direct fixed-current input remains available for synthetic Host
fixtures. No water state is submitted through Session commands.
Clear flat ground can support machines throughout the represented site. There is no privileged construction rectangle,
including for cogwheels. The current changed profile deliberately provides no old
save migration. Store still owns persistence and atomic file publication.

The native Host constructs a mechanical belt by connecting two confirmed,
parallel shaft tiles. The span consumes one carried belt and uses its actual
path and shaft motion for power and material travel. The older single-cell belt
machine is refused by the Host and World, including retained accepted history
and geometry. Stationary construction also rejects that machine and its old
material links; a carried belt item is used to build a shaft span. The standalone
material library still has a legacy single-slot fixture. Session and Store
continue to use the same native World.

The `line_belt_raw` projection totals raw blanks and unfinished work on all
confirmed belt spans for the opening's line counter. It excludes finished plates
and is derived from the same slots, so it is not an additional material owner.

Drive connections consume independent finite shaft parts and derive motion from
their actual geometry. The projection includes those parts, rational motion,
engagements, typed cargo and per-actor kits. It is a detached view, never authority.
The ordinary offline and native shared views mount thin individual-cog controls
and a confirmed transmission presenter; see the [opening controls](../../experiments/engine-environment/godot/opening/README.md).
ActorWorld represents shafts, cog discs and cog axles with conservative boxes,
alongside machine and foundation bodies and the shared terrain. The shapes do
not model individual teeth and remain prototype contact geometry.

Collector and press placement accepts an integer `rotation` from zero through
three, in horizontal quarter turns. Zero faces +X; successive turns face +Z,
−X and −Z. The default is zero. The confirmed projection and logical checkpoint
retain it, independently of the explicit drive `axis`. The ordinary Rotate
control turns both the body and a horizontal drive axis. A collector feeds only
its output side; a press receives only through its opposite input side. A belt
against a closed side keeps its cargo instead of dropping it inside a machine.

Mechanical belt spans can also run vertically, sideways or at 45 degrees.
The Host uses the same path for construction, subsequent obstruction and save
validation. Its inclined clearance covers the rotated contact body with short
conservative sections, including the end overhang; this may refuse an object
very close to the body even when the exact rotated boxes do not overlap.
Vertical and sideways spans transmit rotation without carrying cargo or actors.

The physical checkpoint has schema 3 and format `factory-native-physical`. Its
logical World checkpoint has schema 14, including timed manual cuts, workshop custody and placement,
the first freight beacon and its finite first and repeat orders, building facings, the trusted interaction offset and
identified belt spans, modular press output witnesses and belt-fed work claims.
Manual press receipts carry the prior work item, and productive tick records
bind automatic progress to its work identity, revision and press work point
during restore. These mutable records check save consistency; they do not
authenticate an arbitrarily rewritten save.
The arrival material ledger inside it has schema 12 and retains shipped plate,
copper offcut and sheet custody. Earlier logical formats are refused without
migration. The physical envelope remains schema 3. Its arrival material payload
has schema 12, including typed loose material and timber/ore embodied in
fabricated stationary kits. The
nonresource material payload remains schema 6. Earlier payloads are refused
rather than migrated.
It retains typed material, kits, topology, issued identities, original history and
actor seed positions. Native readiness, epochs, object identifiers and velocity
are process-local and are not saved. Restore requires a fresh unobserved Host;
there is no old scripted-save migration or safe-spawn fallback.

## Build and consume

After the pinned build, prepare an immutable captured runtime with the actual
absolute launcher/library outputs and the already verified engine hash. The
installed admission tool is in the canonical Git directory:

```sh
native_admission="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources"
"$native_admission/factory-local" --root "$PWD" heavy --inherit-permits -- \
  /absolute/factory-opening-startup \
  --repo "$PWD" --tree "$(git rev-parse 'HEAD^{tree}')" \
  --output /absolute/owned/fresh-native-opening \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --engine-sha256 verified-lowercase-executable-sha256 \
  --admission "$native_admission" \
  --native-descriptor "$PWD/native/factory-godot-world/native-world.gdextension" \
  --native-descriptor-sha256 "$(sha256sum native/factory-godot-world/native-world.gdextension | cut -d ' ' -f1)" \
  --native-descriptor-relative native-world.gdextension \
  --native-library /absolute/factory-native-world.so \
  --native-library-sha256 "$(sha256sum /absolute/factory-native-world.so | cut -d ' ' -f1)" \
  --native-library-relative factory-native-world.so
```

This checks a headless import and ordinary scene startup. A human with a graphical
display can then open the captured runtime directly, using a fresh save path
whose parent already exists:

```sh
"$native_admission/factory-local" --root "$PWD" heavy -- timeout 1800 \
  /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --path /absolute/owned/fresh-native-opening/runtime/project \
  res://opening/opening.tscn -- --save-slot=/absolute/owned/player.factory
```

For a saved worksite, prepare another fresh output using `--resume` and the
original Store file. Add `--resume-input` pointing at that new output's
`incoming.factory` when manually opening its runtime. Use a separate fresh
`--save-slot`; do not reuse the launcher's existing `worksite.factory`.
The automated headless consumer is not a rendered or human-play result.

The focused `opening/native_material_attachment_check.gd` consumer uses ordinary
construction callbacks and actual native walking to test an atomic unreachable
endpoint refusal, a fresh connected belt, removal and reconstruction. It retains
typed facts and tests the existing confirmed-link guidance. Its fresh-process
mode checks the original Store binary and history before new material input.
This is headless adapter coverage, not desktop input or human play. The first
Store continuation and the later axis-bearing current-main construction keep
their own source revisions rather than being reported as one unchanged case.

The separate `opening-session/native_shared_cog_check.gd` consumer exercises the
ordinary shared view through menu, key, button and projected click callbacks in
independent P and Q processes. Clients retain their raw initial projections
before validation and use separate passed markers before releasing material
input. `native_shared_cog_server_check.gd` inherits the ordinary server without
changing its commands, clock, body producer or Store lifecycle; it retains the
original ready/final dictionaries and native observations in typed binary files.
The selected continuation loads the original host save before fresh client input,
then inspects, removes and reconstructs a real cog with confirmed actor-specific
custody. These scripts are bounded automated consumers, not desktop control,
human usability, tooth-contact physics or rate-scaled production evidence.

`opening-session/native_shared_rejoin_check.gd` targets a different boundary:
live reconnection while Q carries raw material, a product and a partially
processed workpiece. It starts from the original shared-work producer save,
keeps the drive stopped, and uses the ordinary Disconnect, Reconnect and material
menu callbacks. It checks fresh request identity, foreign-custody refusal while
Q is absent, and exact work reinsertion and recovery. It adds no authority,
production clock or automatic retry. Its results must be attributed separately
from the original producer and fresh-host continuation.

Bazel targets are `//native/factory-godot-world:factory-native-world.so`,
`//native/factory-godot-world:host_test` and
`//native/factory-godot-world:gear_host_test`. The separate
`factory-native-world-abi-test.so` runs invented ABI controls at extension
initialization and must never be supplied as the gameplay library. Use the
existing [native build profile](../../docs/engineering/native-builds.md).

Supply the production library and `native-world.gdextension` as the six paired
resource options to [factory-opening-startup](../factory-launch/README.md).
Their project-relative paths are `factory-native-world.so` and
`native-world.gdextension`. The launcher captures the immutable Git project,
copies both pinned resources, imports and starts the ordinary offline scene.
It does not download a library or select a script fallback. The older Python
fixed-roster launchers do not deliver this extension.

`opening/native_adapter_check.gd` is a bounded headless scene consumer. It loads
the ordinary opening, uses actual registered ActorWorld observations and natural
scene ticks, then exercises recovery, running removal/rebuilding and exact retry.
Its fresh-process mode verifies the original typed Store load and native seeds
before a new material command. It retains binary observations before reporting
failure. This is automated integration evidence, not desktop input, usability,
human play, shared-world adoption or a performance result.

The independent API converter's supported engine and limits are documented in
[factory-godot-values](../factory-godot-values/README.md). Calls run synchronously
on the engine-owning thread. Engine exceptions fail delivery; the thin facade
stops the session rather than interpreting uncertainty as a material refusal.

The extension implements Variant calls and marks its method metadata `VARARG` so
the VM cannot select an absent typed callback. The callback still enforces exact
argument counts and scalar types. `native_dispatch_check.gd` guards that metadata
before compiling and invoking a typed native receiver. The old library is rejected
before that previously unsafe path; this is distinct from physical-body coverage.

The opening's trusted tick reader uses `advance_delta` after it has a complete
view. A delivery contains either `full` or top-level `changes` and `removed`
keys. The bridge merges those fields before any scene reader sees the result.
Authority mutations, including refused commands and actor samples, invalidate
the native comparison base, so the next delta delivers a complete view. Public
`advance` and `projection` still deliver full snapshots.

With a complete comparison base, `Host::advance_tick_fields` ticks the same
World and projects its revision, belt slots and raw count, dropped material,
stock, remaining work and manual source quantities. The extension merges them
with the unchanged topology and actor facts. It recomputes the derived opening
engineering view only when belt contents or loose drops change; actor inventory
and topology changes invalidate the full base. Any new field changed by
`World::tick` must join this field builder and its exact full-view fixtures.

## Shared native profile

The server's explicit `--native-world` option uses the same fixed native profile
with P/Q actors. Session keeps its peer, actor, context and request-namespace
checks and passes the authenticated actor to the native command call. The Host
also requires the original wire client to match. Local startup rejects a missing
library or a legacy/native combination; it does not select the scripted owner.
The historical shared profile remains separate when this option is absent.

Use the complete captured runtime for the existing `opening-session/server.gd`
entry with `--native-world`, and connect the ordinary `shared_opening.tscn` clients
with their existing port/role arguments. All tracked adapter scripts and the
exact descriptor/library must be present. The legacy fixed-roster Python shared
launcher does not prepare this native profile.

The original headless shared consumer ran that real server and ordinary P/Q client scenes
in distinct processes. It tests natural collection into a buffer, authenticated
Q recovery, an actual native host save, and fresh-host P/Q restoration before
either client submits material input. Q then reinserts its original raw unit and
P recovers it once. Six old requests, per-actor custody and the sixteen-unit total
survive. This is a raw-unit recovery witness, not press/product continuation,
walking, desktop input, actor contact, crash recovery or human play.

The current `opening-session/native_shared_check.gd` consumer extends the existing
shared-cog client's typed records, initial barriers and RPC assertions. It uses
the same `--cog-phase`, `--cog-directory` and `--cog-previous` arguments. Its separate
production case collects a real product into Q, pauses and recovers a positively
progressed workpiece into Q's Cargo, and rejects P's attempt to insert that lot.
A fresh server must load the original host save before either client submits a
material request. Q then reinserts the same lot and P collects three more products.
The original controlled-clock case passed both cohorts with all sixteen units
accounted for, the twelve cached outcomes preserved, and final products P3/Q1.
Its server used `--time-scale 0.25`; clients kept normal time. The original
default-speed failure remains distinct: Stop arrived after the observed lot
finished.

The corrected default-speed case also passed both cohorts at engine scale 1 and
the existing 0.45-second Session cadence. Shared clients prepare their unchanged
cached mechanical audio before connecting, so first playback does not synthesize
the four waveforms during live snapshot reception. The consumer reacts once to a
fresh confirmed partial-work transition and requires Stop's original receipt to
preserve remaining 1 with exactly one new revision. Q's validated product barrier,
native reach, exact custody, original save and twelve-outcome history prefix remain
required. Fresh P/Q clients finish with products P3/Q1 and all sixteen units
accounted for. These are bounded headless shared-custody and Store witnesses,
not an arbitrary-latency guarantee, performance measurement, desktop interaction
or human usability result.

The original consumer explicitly predeclared the runtime extension catalogue
before import. Two first cold imports without it failed; debugger captures show
a native importer fault. A fresh early-catalogue control passed. Keep that
instrumentation boundary and the original failures separate from acceptance of
the launcher correction. No unique symbolic engine cause is asserted.

## Oriented transmission API

Commands retain the same context, client and request identity. They enter the
existing World planner, finite kit and reach checks.

| Command | Additional fields | Meaning |
| --- | --- | --- |
| `place_gear` | `center: [int, int, int]`, `axis: "x"`, `"y"` or `"z"`, `teeth: int` | Place one carried gear at an exact grid center. |
| `place_shaft` | `center: [int, int, int]`, `axis: "x"`, `"y"` or `"z"`, `half_span: 2` | Place one carried, one-tile shaft at a grid center. Segments transmit when their geometry engages. |
| `place_belt_span` | `from: string`, `to: string` | Consume one belt to connect two aligned shaft tiles; actor reach and the complete path are checked. |
| `remove_belt_span` | `entity: string` | Remove an identified span and return one belt to the actor's kit. |
| `place` | Existing `kind` and `cell`, optional `axis` string | Orient a machine while retaining the existing cell wire. An omitted axis defaults to X; belt spans use their endpoint shaft axes. |
| `remove` | Existing `entity` identifier | Remove a selected individual shaft, gear or machine, preserving custody rules. |
| `pickup_material` | `center: [int, int, int]`, `expected: cargo` | Collect the matching loose material at a reach-checked grid point into the bound actor's cargo. |

One grid unit is `pitch / 4`, currently 0.4125 world units. Map a center to
`center * pitch / 4 + [0, anchor_height, 0]`. The axis is the rotation axis,
normal to the gear plane. Shaft and cog centers must be multiples of four on
all axes, so each part occupies one common 1.65 m tile. Endpoint-based shaft
construction is refused. Placement checks conservative disc and axle boxes
against registered actor capsules; individual tooth contact is not modeled.

The read-only `part_specifications` projection maps each actor to entries with
`kind`, `teeth`, `half_span` and remaining `count`. P starts with eight two-tooth
gears, two four-tooth gears, and eight shafts of half-span two; Q has
no parts. Uncarried specifications refuse without changing that kit. Gears and
shafts appear in `transmission_parts`, with integer `axis` values 0, 1 and 2 for
X, Y and Z. Use `engagements` and exact signed `motion` for transmission facts.
`belt_spans` maps each span identity to its generation and endpoint identities.
The historical `drive_links` shortcut describes machine-to-machine shafts only.

A synthetic channel fixture places a Z-axis wheel at cell `[-1, 1]`, a Z-axis
collector at `[0, 1]`, and Z-axis gears at `[-4, 0, 8]` and `[0, 0, 8]`. Each
machine joins its gear by a real Z-axis shaft; equal gears mesh and reverse
rotation. The fixture supplies explicit water velocity and a collector foundation.
Its unit tests cover running removal and rebuilding, the finite kit, historical
retries and typed checkpoint restore. The site and actor observations are
synthetic inputs, not physical gameplay evidence.

Negative Z-axis rotation or positive X-axis rotation moves blanks toward the
press on the corresponding +X or +Z route. The opposite rotation moves them to
a loose stack at the opposite end; a stopped belt holds its blank.
Loose stacks persist in the material owner and can be picked up after removing
the belt. They are represented at a fixed grid point, without gravity or a
general dropped-item physics simulation. Belt throughput remains a fixture
step, not a continuous speed model. Cell commands retain their default
orientation, and original receipts replay before present geometry or pose checks.

`opening/native_cog_check.gd` adds a headless integration consumer of the ordinary
scene's command boundary, using real ActorWorld cuts and a fresh Store reopen.
It retains exact typed observations on failure and independently checks scalar
three-dimensional reach. Its scope is native-body cog admission, geometry and
custody. It does not operate desktop controls or establish the separate cog UI's
discoverability, shared construction, human play or direction-sensitive throughput.
