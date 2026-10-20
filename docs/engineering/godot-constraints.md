# Godot and prototype constraint register

First source/API audit: 2026-10-15 UTC, accepted source
`ecd80b486066fe78d7e8e3ed6483981c3599f438`. Physical-adapter addendum:
2026-10-19 UTC, source candidate `18bef7dfa013e0ead8c7c4c74f89d8802bb845d0`.
Shared-runtime addendum: 2026-10-19 UTC, tested candidate
`df8446387088da522221cc7972f0aab91a646c45`.
Normal P/Q save/reopen addendum: 2026-10-19 UTC, tested candidate
`250941dc0ecce70ef1eab5055cc4f46ef49c5f59`.
Godot use is approved for current development. This register prevents the
modeling framework from silently defining the game. The bounded first audit is
owned by `factory-yau.3.10`; this maintained register is not a claim that every
engine subsystem or production requirement is proven.

[DESIGN](../../DESIGN.md) owns intended behavior. Classify each discovery as:

- **Engine/API:** a documented or reproduced requirement of a named engine/build/backend.
- **Adapter:** a limitation or dependency of our implementation, not proof the engine requires it.
- **Fixture:** a deliberately narrow test/default, not a game rule or engine ceiling.
- **Unknown:** a risk not yet established; neither an impossibility nor a solved requirement.

For new entries record exact version/source or reproducer, affected game promise,
mitigation/exit path, owner and follow-up. A workaround that changes gameplay
requires an explicit design decision. Preserve the original failure and limits.
Current runtime provenance is in the [environment record](engine-environment.md);
the pinned 4.7.2 build is a test dependency, not a permanent game requirement.
The official `stable` documentation linked below was checked on 2026-10-15; it
can advance independently of our pin and is not exact-build executable evidence.
Version-specific XML links below come from the upstream `4.7.2-stable` tag;
reading its API contract is distinct from exercising our installed binary.

## Audited evidence and confidence

Source inspection uses `ecd80b486066fe78d7e8e3ed6483981c3599f438` for the
shared opening, mechanics, rider and tooling. The verified executable reports
`4.7.2.stable.official.ed1daf0bf`, SHA-256
`8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`.
Its [original trial](engine-environment.md) records installation provenance;
that page's first-trial coverage is historical. Subsequent proofs are scoped below.
No new engine invocation, backend switch, runtime download or precision build was used
for this document audit.
The physical addenda read `18bef7d`, including the `ed2b6cf` actor/view join,
the corrected `df84463` worksite layout, and the separate `250941d` normal
save/reopen consumer. The independent `6.37` review
accepts its declared frozen/live shared consumers; whole implementation acceptance
and incorporation into main remain separate under `factory-yau.5.21`, `.6.36`
and `.6.37`. The tested source and this register must land together; the addendum
does not assert that current main already contains the physical join.

| Evidence anchor | What it supports | What it does not establish |
| --- | --- | --- |
| `a7d4cce` rotary rider, [authority](../../experiments/engine-environment/godot/rotary/authority.gd) and [fixture](../../experiments/engine-environment/godot/rotary/README.md) | Real native operating poses and an unparented local passenger, with explicit request/completion clocks | Arbitrary angular clearance, networked passengers or a complete physical factory |
| `e967cbc` [train probe](../../experiments/engine-environment/godot/train/README.md) | Coupled kinematic carriages and a real local passenger | Freely simulated train dynamics, moving-save or multiplayer movement |
| `d1e32f0` [retrieval continuation](opening-recovery.md) and `e7eb73e` [shared opening](../../experiments/engine-environment/godot/opening/shared_opening.md) | One bounded stationary authority, interrupted retrieval custody, inspection/reconnect feedback | Adversarial movement admission, internet reliability, crash durability or user play |
| `ecd80b4` [moving-port probe](../../experiments/engine-environment/godot/moving-transfer/README.md) | Native sampled port geometry and finite transfer ownership | Continuous contact, real item bodies, campaign logistics or a production network join |
| `2e8665f` [exact-count bench](../../experiments/engine-environment/godot/precision/README.md) | Exact material quantities, retained work and recovery | Floating-point spatial precision: its directory name is not a coordinate-precision benchmark |
| `18bef7d` physical candidate, [opening limits](../../experiments/engine-environment/godot/opening/README.md) and [contract](physical-construction-contract.md) | Actor/reach/save interfaces and explicitly scoped offline/shared fixtures | Complete ordinary two-player behavior, live replacement, cross-roster migration or user play |
| `18bef7d` [control-wire cases](../../scripts/opening_control_wire_cases.py) | Forty malformed real-client control packets, sequence/rebind handling and selected native input/release sentinels, with unchanged finite custody | Ordinary keyboard play, live production, nonempty material-cache continuation, fresh-process physical reopening or a complete movement-security model |
| `ed2b6cf` [offline character check](../../experiments/engine-environment/godot/opening/character_check.gd) | P-only fresh-process floor/wall save reopen and deep-overlap refusal | Shared P/Q host-file reopening, accepted small-positive saved overlap, live replacement or momentum continuation |
| `df84463` [shared physical consumer](../../experiments/engine-environment/godot/opening/shared_check.gd), independent `6.37` review | Actual movement/native admission cuts, camera-independent reach, fixed collision, finite live P4/Q1 plate custody, selected/pending controls and reconnect | Human play, physical P/Q host-file reopening, OS-focus transitions, other resolutions, internet behavior or game-scale acceptance |
| `250941d` [normal P/Q save/reopen consumer](../../scripts/check_physical_shared_resume.py), independent retained-evidence reviews | First normal host's actual binary save, a fresh host's exact Store load and native P/Q restoration, with historical accepted/refused requests retained | Disk continuation of the earlier live P4/Q1 production: this witness has one collector, two old requests, 16 unprocessed blanks and empty pockets; no momentum, crash or human-play proof |

**Observed** below means a named code path or retained bounded consumer witness.
**Documented** means an upstream API contract, with no broader runtime result.
**Unknown** means the current evidence cannot decide it. These confidence labels
qualify the claim, not a score for the engine. Full local receipts and independent
review pins remain in the owning Beads; the linked tracked consumers are reusable.


## GDC-01: engine-coupled rules are not an independent core

**Adapter, observed.** [model.gd](../../experiments/engine-environment/godot/model.gd)
uses GDScript, `RefCounted` and Godot value/container APIs. Running it headlessly
removes graphics, not its runtime dependency. Scene physics has additional coupling.

The native offline increment now uses one
[C++ World bridge](../../native/factory-godot-world/README.md), with GDScript
forwarding commands and actual ActorWorld observations. Store keeps the binary
file boundary while native code validates the complete typed checkpoint. The
shared server's explicit `--native-world` profile uses that same owner with
Session's existing authenticated actor binding. Historical scripted profiles
remain separate. The bridge and its site profile still depend
on the pinned Godot API; this is not whole-game portability or a second authority.

**Boundary/exit:** retain explicit commands, quantities, identifiers and state
ownership; record migration costs when an interface changes. A future native or
different-engine core needs adaptation and parity tests. Do not claim portability
or build a speculative universal engine wrapper now. Owner: Platform.

## GDC-02: requested, visual and native physics poses are different observations

**Engine/API plus observed adapter boundary.**
Godot's [AnimatableBody3D API](https://docs.godotengine.org/en/stable/classes/class_animatablebody3d.html)
describes physics-frame synchronization and estimated motion.
The [rotary](../../experiments/engine-environment/godot/rotary/README.md) and
[moving-transfer](../../experiments/engine-environment/godot/moving-transfer/README.md)
witnesses retain readiness and actual native operating poses separately from goals.

**Boundary/exit:** use declared natural physics boundaries for native contact
evidence; neither a mesh nor a requested endpoint proves physical arrival.
The fixture's 24 updates, 20:40 ratio and dimensions are not required machine
rules or production timing. Backend/version changes require consumer revalidation.
Owners: Platform and Ops.

**Exact contract and local evidence:** the pinned
[AnimatableBody3D XML](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/AnimatableBody3D.xml)
describes estimated velocity and `sync_to_physics`;
[SceneTree XML](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/SceneTree.xml)
places `physics_frame` before node physics callbacks. Our
[mechanics authority](../../experiments/engine-environment/godot/mechanics/authority.gd)
retains pending geometry/native completion; rotary adds a finite operating path.
The proven next-frame observation belongs to these consumers and settings,
rather than a universal rule that every command must wait exactly one frame.
Published completed poses, current native queries and rendered samples must keep
separate revision/clock labels. A source pause can leave already requested motion
to drain; it does not imply an immediate native freeze.

The physical adapter retains at most 2,048 read-only native observations globally
across actors and refreshes. Its shared review captures each admitted epoch with
the actual body/world/pose, rather than substituting a later sample. The corrected
frozen/live cases reconstructed 22 and 17 admissions respectively; five corrupt
evidence controls were rejected. Missing or evicted native evidence is a failed
observation, not permission to use the latest pose. This history bound is probe
policy, not a game history or actor-count limit.

## GDC-03: a character API is not the game's movement design

**Engine/API plus fixture.**
[CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)
provides scripted collision/movement APIs with floor, slope and platform settings.
Our [rider controller](../../experiments/engine-environment/godot/rider/player.gd)
chooses a capsule, gravity, walk/jump values and collision masks for a local probe.
The physical opening now has its own
[ActorBody](../../experiments/engine-environment/godot/opening/actor_body.gd),
with the same single producer used offline or on the dedicated shared host;
shared clients render confirmed proxies. Its actual movement and construction
join has bounded consumer evidence at `df84463`, independently of the rider.

**Boundary/exit:** these choices do not fix the game's body dimensions, speed,
jumping, camera or injury model. A physical controlled character and limited
construction proximity are user requirements, not Godot defaults. The physical
candidate supplies a controller/authority/reach join with its own fixtures;
a rider success does not validate that join. Owners: Chapter and Platform;
`3.11`, `5.21`, `6.36`, `6.37`
under `factory-yau`.

**Exact contract and consequence:** the pinned
[CharacterBody3D XML](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/CharacterBody3D.xml)
specifies scripted motion, physics-step `move_and_slide`, post-move floor/contact
facts and platform velocity contribution. It does not supply our construction
permission or automatically validate a remote actor. The rider controller is
observed local integration, not an input-to-authoritative-actor construction join.
That join must identify the actual admitted pose and operation target in 3D;
changing camera distance must not increase building reach. Capsule dimensions,
mask bits, snap distance and the `.015` rider-test tolerance remain fixture values.

**Physical adapter impact/exit:** [ActorWorld](../../experiments/engine-environment/godot/opening/actor_world.gd)
publishes current native body origins to Model; camera picking identifies only
the requested target. Its [documented masks](../../experiments/engine-environment/godot/opening/README.md)
put actors on collision bit16 with mask1|2, excluding actor-actor collision. Actor-actor
saved-overlap rejection is also unsupported. The separate `actor_occupied`
placement rule checks a new machine against ready actors; it does not supply
actor-actor contact. Add and validate those contact/restore policies when needed,
rather than making these adapter omissions game requirements. Owners: Chapter
and Platform, with Recovery/Playability consumer review.

**Chosen motor/input defaults:** [site geometry](../../experiments/engine-environment/godot/opening/site_geometry.gd)
sets capsule radius 0.3/height 1.8, walk speed 3, gravity 14, jump speed 6, floor snap 0.1
and safe margin 0.001. These are reversible adapter values, not final movement
design. Bounded direction/jump/release input reaches the trusted actor binding;
the producer owns physics delta and clamps horizontal magnitude. Release clears
horizontal motion and queued jump while gravity continues. Freezing Model
production does not freeze this body. The construction rule separately checks
the latest native origin against the declared 3D work anchors, including height;
camera orbit supplies no extra range. See the [physical contract](physical-construction-contract.md).

## GDC-04: limited contact probes are not a universal collision policy

**Adapter/fixture, observed.**
The rotary authority's limited obstruction query and the transfer experiment's
discrete port samples do not establish angular swept clearance, item rigid-body
dynamics, docking forces or independent-machine pushing. The transfer distance,
facing threshold and one-unit-per-visit latch were chosen for that witness.

**Boundary/exit:** do not conclude that Godot cannot support an untested interaction,
or make those thresholds mandatory game rules. Preserve the intended connected
drivetrain stall/isolation behavior and deferred detailed collision choices.
Refine the relevant native query/body/authority contract when needed. Owners:
Platform and Ops; [declared transfer limits](../../experiments/engine-environment/godot/moving-transfer/README.md).

**Documented query boundary:** the pinned
[direct-space API](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsDirectSpaceState3D.xml)
explicitly says `intersect_shape` ignores query motion. `cast_motion` tests a
linear motion and ignores shapes already overlapping; it is not proof of a
rotating volume's swept clearance. Our mechanics `test_move` sweep covers its
declared linear sliders; rotary and moving ports retain narrower samples.
Result limits, collision layers, body/area flags, shape-local transforms and world
space are query inputs to audit, not engine-selected game eligibility rules.
Use initial-overlap handling and a separately validated angular/contact strategy
when the intended mechanic requires them. No claim that Godot cannot provide it.

**Physical saved-contact limit:** ActorWorld's initial query covers its upright
capsule against a floor plane and uniform axis-aligned machine boxes. Its
analytical overlap measure and chosen 0.001 contact allowance are not a general
native penetration-depth result. The accepted offline floor/wall reopens had
empty contact-query results; they do not exercise the small-positive-overlap
acceptance branch. Deep-overlap refusal is separate negative evidence. A broader
contact/restore policy needs its own discriminating consumer; fixed-box collision
and `actor_occupied` do not establish actor contact, pushing or injury rules.

**Chosen native transmission adapter:** the
[native Host](../../native/factory-godot-world/README.md#oriented-transmission-api)
uses integer quarter-pitch centers, explicit X/Y/Z axes, equal carried gears and
finite shaft spans. Those dimensions, kit and bounded construction heights are
revisable modeling choices, not Godot restrictions. The C++ geometric solver
derives engagement and signed rational rates; it does not simulate tooth contact,
torque or angular phase. Current material stepping accepts either rotating
direction as power and does not scale throughput with angular rate.

The ordinary view's gear/shaft bodies are pick-only geometry on layer 4. They
do not add actor collision shapes or make a rendered contact authoritative.
Static direction arrows and engagement markers use confirmed native facts;
the translucent placement cursor is only a requested grid point. ActorWorld
continues to supply real body origins for the exact 3D reach decision. Precise
part collision, pushing, authoritative dynamic phase and rate-dependent production remain
separate implementation work, not limitations inferred from these fixtures.

**Chosen motion presentation:** the wheel, cog and shaft-keyway illustrations
integrate cosmetic angles from confirmed native signed rates. The source rate's
visual reference is 0.8 radians per second, not a selected physical RPM or
processing rate. Long frame gaps are capped at 0.1 seconds for this illustration.
Local angles survive a mesh refresh for the same context/part generation, reset
on replacement or a new world, and are not checkpoint fields or contact data.
Unknown/stalled parts and unavailable/Help/unready/shared-disconnected views do
not invent continued operation. The unchanged axisymmetric pick cylinders stay
pick-only; spinning their visuals adds no actor collision or moving mechanism.
The collector's existing cutter meshes consume the same angle cache. The press
only eases toward a confirmed held/empty tool pose, including retained blocked
READY work; that pose never advances remaining ticks or releases material. These
render transforms and their disposable pose cache are not checkpoint state,
moving collision or evidence of a synchronized mechanical stroke.
**Opening engineering fixture:** the [upstream-drive prototype](../../native/opening-engineering/include/factory/opening_engineering.hpp)
uses ideal pitch/coax geometry, including a cog at the collector's hub anchor.
The native cog Host at `e4f1b31` permits that mount; it does not test interference
with a machine housing or floor. Its C++ comparison supplies actor observations and makes
no engine/body calls. This is an adapter/fixture shortcut, not a Godot limit or a
selected physical mounting rule. Ordinary presentation and housing clearance
remain outside that evidence under `factory-yau.6.51`; Workhorse owns the prototype.

The ordinary composition uses starter row 1 and upstream wheel cell `[-1, 0]`.
These are reversible content coordinates, not engine rules or a placement ban.
The native inspector supplies per-actor eligibility and the extension publishes
it as a derived view for the existing offline/shared adapter. The scene adds no
clock, inventory, saved progression flag or second authority. Its geometric
diagnostics remain presentation, not permission to place a part.

## GDC-05: coordinate precision needs a scale strategy, not an invented world cap

**Engine/API risk; factory-scale result unknown.**
Godot documents [floating-point precision and large-world alternatives](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html).
Its ordinary vector precision differs from GDScript scalar precision; larger
coordinates can lose spatial accuracy. Double-precision builds and origin
shifting have different costs and integration consequences.

**Boundary/exit:** near-origin fixtures do not establish world size, smallest
clearance, vertical reach accuracy or factory capacity. Audit the actual build
and choose measured coordinate/representation boundaries when scale requires it;
no double build, world cap or origin-shifting architecture is adopted here.
Keep integral material accounting distinct from approximate geometry. Owners:
Platform and Ops; build/backend/precision characterization remains a future
measured follow-up when the intended scale requires it.

**Confidence and impact:** documented risk, with no far-origin runtime witness.
The linked stable guide distinguishes default 32-bit vectors from GDScript's
64-bit scalar floats; double builds require different editor/export builds and
compatible extension/network precision. Our retained version and renderer logs
do not directly measure `real_t` precision, safe world dimensions or smallest
workable gap. Those remain unknown for the intended game. A global integer
construction coordinate and local approximate native pose can be separated without
adopting origin shifting now; the authority must define conversions explicitly.
Do not trade away 3D building, exact material custody or nearby construction to
make a small near-origin fixture easier.

## GDC-06: scene mutation and data parallelism are separate problems

**Engine/API, documented; project-scale capacity unknown.**
The [thread-safety guide](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)
restricts active scene-tree access and qualifies server/resource threading by API
and settings.

**Boundary/exit:** do not mutate scene nodes arbitrarily from factory workers,
but do not infer that all simulation must be single-threaded. Keep authoritative
data and scene application boundaries explicit; evaluate batching, server APIs or
native processing against measured needs. No thread model or benchmark result
is selected by this register. Owners: Platform and Ops.

**Evidence/confidence:** documented API restrictions, no concurrent-factory
benchmark. The shared Session currently advances the Model from `_process`;
that is observed adapter scheduling. A mutex or deferred scene update by itself
does not choose command order, make shared mutable containers safe or prove a
parallel data model. Native/server batching is a possible exit path to measure,
not a requirement to rewrite the current stationary opening.

## GDC-07: transport and runtime identities are not a complete multiplayer model

**Adapter coverage limit, observed.**
The [shared-session fixture](../../experiments/engine-environment/godot/opening-session/README.md)
proves a bounded trusted same-host authority/request/snapshot path and orderly
checkpoint continuation. It does not establish a complete adversarial movement model,
internet deployment, prediction/rollback, deterministic cross-platform physics
or durable cross-version saves.

**Boundary/exit:** keep game identifiers and persistence contracts separate from
diagnostic instance/RID values. Confirmed actor state must govern construction
reach, not a camera or an unvalidated client position. Reuse one authority for
single-player/server play; test correction and continuation through actual
consumers before broadening claims. Owners: Platform and Recovery; `5.21`.

**Documented identity/lifetime:** pinned
[RID XML](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/RID.xml)
and [Object XML](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Object.xml)
qualify RID/instance IDs as current-session handles. Model context, entity
counter, request namespace and checkpoint identity are separate adapter data;
restoration must recreate/remap native handles. A diagnostic native ID staying
stable during one run does not prove a persistent identity.

**Ordering and authority:** pinned
[MultiplayerAPI XML](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/MultiplayerAPI.xml)
says polling executes RPCs in the polling context, and sender identity is only
available inside the active RPC. The
[Session](../../experiments/engine-environment/godot/opening-session/session.gd)
captures its peer binding before deferring admission, then the one Model owns
accepted order and cached dispositions. Reliable RPC alone does not give a
cross-client gameplay order or application-level exactly-once effects. The two
trusted loopback roles, `.45` clock and 10-second connect bound are fixture policy.
Prediction, rollback, WAN behavior and cross-platform native determinism remain
unknown; none is inferred from stationary snapshot convergence.

**Physical input admission versus application, observed adapter/probe limit:**
the Session's `control_trace.accepted` records RPC schema, binding and sequence
admission. That bit does not record the return from the native producer's
`set_control`, or prove that a later body step applied the input. The
[control-wire fixture](../../scripts/opening_control_wire_cases.py) separately
checks producer control/release counters and later native poses for its positive
sentinels. Its paired jump/release calls use existing Session APIs in one test
callback; the actual same-frame RPC trace and later floor sample do not include
an intermediate native `jump_queued=true` observation or an airborne peak.

**Affected promise / exit:** keep admission, producer application and native
observation distinct when validating controlled movement. Use the declared
native cuts in GDC-02; add an explicit application result if a future consumer
needs one. This is a diagnostic/adapter boundary, not a selected player input
rule or networking architecture. Owners: Platform, Chapter and Recovery.

## GDC-08: a planar construction fixture does not make this a flat game

**Adapter/fixture, observed.**
The opening's [model](../../experiments/engine-environment/godot/model.gd) accepts
a small two-coordinate placement grid; its [view](../../experiments/engine-environment/godot/opening/opening.gd)
picks a worksite plane. The first audit's unrestricted builder lacked a physical
character and proximity admission. At `df84463`, the actual shared controlled
body and proximity join have bounded native evidence, including an airborne
refusal and fresh grounded acceptance at the same horizontal position. That
adapter retains the planar placement fixture; it does not yet
implement stacked construction. Neither fixture defines a Godot or game-world limit.

**Boundary/exit:** preserve the intended global 3D construction alignment and
meaningful vertical factory design. Prioritize physical-character/3D-reach
construction for the stationary opening, without adopting that fixture's bounds
as world limits. An elevated or distant camera must not extend permission.
Owners: Chapter and Platform; `factory-yau.3.11` and its consumer tasks.

## GDC-09: renderer, harness and local resource limits are not game limits

**Fixture/tooling, observed.**
[project.godot](../../experiments/engine-environment/godot/project.godot) selects
Compatibility rendering and a 1280×800 window. The [environment record](engine-environment.md)
describes the observed Linux/WSLg renderer; [resource admission](local-resources.md)
and the staged compiler impose deliberate test/source/log budgets.

**Render-attribute readback, observed in an isolated asset fixture.** The pinned
4.7.2 runtime returned finite unit tangents with normal-dot error up to
`0.00012452` after `SurfaceTool` committed an `ArrayMesh`. Its matching
[rendering-server source](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/rendering_server.cpp#L562-L602)
packs normals and tangents into 16-bit octahedral attributes even without
compressed vertex positions. The initial `0.00001` asset assertion failed and
is retained under `production-worksite-finishes-20261020`; the successor uses
`0.0002` for decoded tangent orthogonality, with missing/non-finite/misoriented
negative controls. This is a render-attribute observation allowance only. It
changes no mesh envelope, physical pose, construction reach or game rule, and
does not establish rendered material quality.

**Headless instance readback, observed and source-qualified.** The pinned dummy
renderer ignores individual `MultiMesh` transform writes and returns identity
from the corresponding getter. Its
[bulk-buffer implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/dummy/storage/mesh_storage.cpp#L89-L101)
retains submitted data. The environment fixture therefore inspects the actual
bulk buffer for foliage placement, without claiming a GPU draw or rendered
position. Its first per-instance readback failure is retained under
`production-worksite-environment-20261020`. This harness boundary changes no
physical collision, construction range or game rule.

The native bridge's initial engine call inherited a 2 GiB compiler address-space
limit and aborted during initialization. Its separate engine-only ABI check passed
with an explicit 8 GiB address-space envelope. A later first full-project import
also aborted without a unique cause in its log; a traced copy exited normally.
The corrected offline scene passed its own import, ordinary startup and physical
save/reopen consumer. These scoped results do not diagnose the earlier abort or
establish an engine memory target. Keep compiler and engine envelopes distinct;
the normal helper's 22 GiB free-disk requirement is a separate quantity.

The import abort recurred in the shared candidate. Debugger captures stopped at
a native segmentation fault before game startup. A fresh import with the exact
extension declared in generated `.godot/extension_list.cfg` before launch passed;
the original ABI fixture also used an explicit early catalogue. The native P/Q
consumer reused that imported runtime. Keep this controlled configuration and
the first failures distinct from acceptance of the launcher correction; the
stripped engine backtrace does not establish a unique symbolic engine cause.

**Boundary/exit:** no fixed game resolution, target OS/GPU, session duration,
factory object count or performance target follows. A parser pass is not a
runtime/physics/network test; a bounded probe pass is not a scale certification.
Change operational limits only through their reviewed contract, not as an
undocumented engine workaround. Owners: Ops and PM.

## GDC-10: the physics backend is a qualified dependency

**Unknown runtime selection; documented interface.** The project does not set
`physics/3d/physics_engine`. Retained renderer/version logs identify the binary
and graphics path, not the selected 3D physics server. Upstream source registering
a default is insufficient to identify this runtime's backend/settings. This first
audit makes no Godot Physics-versus-Jolt comparison or claim of identical behavior.

For example, the pinned
[WorldBoundaryShape3D XML](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/WorldBoundaryShape3D.xml)
documents a finite, origin-centered boundary under Jolt, controlled by
`physics/jolt_physics_3d/limits/world_boundary_shape_size`. A plane-shaped floor
in a small fixture therefore does not certify collision support at arbitrary
coordinates. The character consumer must capture its actual backend and relevant
setting when testing its declared site; extending that site needs an explicit
floor/coordinate strategy. This documents an engine dependency, not a game-world
size limit or a reason to run another engine just for this audit.

The pinned [PhysicsServer3D API](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsServer3D.xml)
exposes native bodies, areas, transformed shapes and queries independently of scene
nodes. This supports observing the actual world; it does not replace testing the
selected backend or create a shared-engine-independent authority.

**Affected promise / exit:** character support, contact eligibility and tiny
clearances must survive any backend/build/settings change. When such a change is
proposed, capture the actual backend and relevant physics settings in that
bounded consumer's ordinary report, then rerun its discriminating cases. Do not
launch an extra engine merely to fill this documentation gap. Owners: Platform
and Ops; new consumer follow-up before a backend change, existing character/reach
work `3.11`/`5.21`/`6.36`/`6.37` proceeds against its declared interface.

## GDC-11: save and UI evidence have explicit coverage boundaries

**Adapter/fixture, observed; broader support unknown.**
The Model/Store checkpoint serializes explicit game state, with supported orderly
continuation. It does not serialize an arbitrary live scene, every native body,
remote player motion or an unrestricted engine resource graph. Quantity-safe
stationary restore is useful evidence without proving crash/power-loss durability,
concurrent writers, cross-version migration or moving-world reconstruction.
Owners: Recovery and Platform; refine the save contract when these become scope.

**Physical profile impact/exit:** the [physical contract](physical-construction-contract.md#persistence-and-the-unrestricted-baseline)
persists actor positions/capabilities, then rebuilds fresh native bodies with
released controls and zero restored velocity. Continuous saved momentum or jump
phase is unsupported. Offline physical live Load refuses `load_requires_restart`; use
a fresh-process reopen. Cross-roster migration also refuses explicitly rather
than inventing or dropping actors. These are adapter limits, not Godot limits.
Later live replacement needs native geometry preflight and atomic Model/adapter
replacement; migration and momentum need explicit continuation policies and
consumer evidence. Owners: Platform, Chapter and Recovery; `.6.37` retains the
independent combined-consumer scope. See the [opening limits](../../experiments/engine-environment/godot/opening/README.md).

The `ed2b6cf` new-process physical save/reopen evidence is P-only offline,
including floor/wall reopening and deep-overlap refusal. The shared `6.37` disconnect/rejoin
keeps the host/native world alive; it is not host-file restoration in a new
process. The separate `250941d` / `factory-yau.5.23` consumer passed two normal
P/Q launcher runs: actual ordinary refusal/placement and walking produced the
first host's binary save, then a fresh host Store-loaded that exact preserved
input. Fresh native bodies were registered and stepped from the saved poses;
their final released floor poses matched exactly in this witness. Actor
capabilities, parts, generated IDs, context and the accepted/refused cache were
unchanged; only the new live clock advanced revision. Reopened clients issued
no material commands. This is one collector, two historical requests and 16
unprocessed blanks with empty pockets, not a disk reopen of the earlier live
P4/Q1 production. It does not establish velocity/jump continuity, crash recovery
or human play. Offline P and a shared P or P/Q roster are declared
profiles; schema-1 physical reopen and cross-roster migration refuse explicitly.

The first shared physical `18bef7d` run failed with settled selected-press controls
at707 crossing the status area at694. That original failure remains retained;
no failed-state screenshot is claimed. The `df84463` correction passed the same
frozen driver, followed by a distinct live-production consumer. All 490 retained
closed raw responses satisfied `worksite_bottom <= 644 < 694`, where 694 is the
status area's top. The live case includes selected press
and two-line pending-connection observations at Q33/34/35, plus P4/Q1 individual
plate custody; these are actual declared cuts, not a whole-window layout theorem.
The independent retained-evidence audit reports 4,129 checks with five corrupt
evidence controls rejected. It is agent event injection in Compatibility/WSLg
at 1280×800 with two loopback peers, not actual user play or enjoyment evidence.
There is no current certification of other resolutions, input devices, rendering
backends, packaging or accessibility. Keep picking/camera and authority separate;
validate the actual character-building consumer as its UI changes. Owners: Chapter,
Playability and Ops; `6.36`/`6.37` and actual-user feedback `6.11`.

At component `5aa680c`, the [shared UI consumer](../../experiments/engine-environment/godot/opening/shared_check.gd)
waits for `RenderingServer.frame_post_draw` before reporting readiness and sampling
button geometry. It sends one ordinary mouse press and release and records the actual
`Button.pressed` notification, bounds, enabled state, input point and sampled focus
state. The first declared live case recorded one press for each of two reconnects
and two dismantle clicks. The unchanged stock-recovery oracle also completed all
16 plates and returned the empty collector and two shafts on the same worksite.
The separate fresh-worksite case with the material clock frozen recorded two
enabled reconnects and seven disabled clicks across the two peers. Each disabled
click emitted no pressed signal and left the namespace, stock, parts and material
request cache unchanged. This covers the tested controls in that fixture without
adding live-production evidence. Cancelled clicks still lack native coverage.
Sampled focus state does not establish a real operating-system focus transition,
and these passes do not identify the earlier reconnect failure's cause or
eliminate intermittent failures. Keep these adapter observations separate from construction permission,
transport admission, native material application and human-play claims. Owners:
Playability and Ops; `6.39` retains the bounded consumer evidence.

Help/disconnect release has bounded actual consumer evidence. The focus-release
fixture injects `Window.focus_exited`; a real operating-system focus transition
remains untested. Near-origin floor/contact and two-client success do not resolve
the backend-identification, far-origin or factory-scale unknowns in GDC-05/06/10.

**Window resizing is an adapter responsibility.** The actual user report in
`6.40` showed the inspector and footer left inside an enlarged viewport. Their
original fixed pixel positions explain that layout; the report does not prove a
button-hit, state-loss or DPI defect. The opening now uses right/bottom anchors
and offsets for those panels and central anchors for Help. The pinned
[Control API](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Control.xml)
defines parent/viewport anchors; the
[Window API](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Window.xml)
separates native window size from content scaling. The opening's 1280×800 minimum
is a revisable adapter policy, while larger windows remain resizable. The private
[layout observer](../../experiments/engine-environment/godot/opening/layout_observer.gd)
records actual viewport bounds, edge margins, rendered text, button signals and
ordinary input across size changes and maximize/restore. Its pending-view fixture
temporarily pauses only client multiplayer polling around an ordinary request;
the server and its authority remain live. Treat that pause as a disclosed fixture
shortcut, not natural network-delay evidence. Runtime verdicts and supported
display/backend limits belong to the exact retained `6.40` cases; source or parser
success alone does not certify resizing, DPI, accessibility or actual user play.

## GDC-12: JSON control files do not preserve RPC Variant types

**Engine/API, documented for 4.7.2; fixture conversions observed.** The pinned
[JSON XML](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/JSON.xml),
checked 2026-10-19, documents floating-point number parsing. A control-file JSON
number therefore does not attest a native integer Variant in a later RPC.
The normal Session constructs its own integer control sequence; the private
[test controller](../../experiments/engine-environment/godot/opening/shared_check.gd)
uses explicit `int` or `preserve` descriptors to construct the intended valid or
malformed Variant before sending the existing RPC. This is test setup, not
receiver-side coercion or a game rule about acceptable player values.

The same API documents different nonfinite serialization: NaN becomes JSON
null, while signed infinities use overflowing numeric tokens. The private probe
constructs named nonfinite direction Variants and retains actual field types
and nonfinite classifications before RPC submission and JSON observation.
Treat those fields as controlled-test diagnostics, never client authority.
Reading the serialized numeric value alone can lose the distinction the test
was meant to exercise. The retained first control-wire execution has three
nonfinite negative variants and explicit server refusals. Constructing these
malformed values is confined to the private test controller.

**Affected promise / exit:** retain actual payload types and original raw
evidence when checking a typed transport contract. Reify only the test values
explicitly selected by its descriptor, and preserve malformed types in negative
cases. A different codec or engine version needs its own consumer checks;
these conversions select no production wire/save format or material policy.
The bounded wire case has frozen production and an empty material request
cache; use the separate continuation and ordinary physical consumers for their
declared behavior. Owners: Recovery and Platform; Ops reviews retained evidence.

## GDC-13: a dictionary key is not a lexical tool-name oracle

**Engine/API, documented for 4.7.2; observer limitation found by source review.**
The pinned [named setter](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/variant/variant_setget.cpp#L222-L245)
passes a `StringName` key into a dictionary. The default
[`StringName` comparison](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/string/string_name.h#L91-L145)
orders interned pointers; its separate alphabetical comparator orders characters.
The [Variant less-than registration](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/variant/variant_op.cpp#L662-L668)
also distinguishes String and StringName comparisons. Sorting raw keys therefore
does not establish lexical order of displayed names.

The original `0deb66c` layout observer used that assumption when checking All
tools. Its first shared attempt retained one enabled-button pressed signal and
then failed the visibility assertion, but omitted the disputed post-click values.
That is failed coverage, not proof of a product visibility defect or of the sole
runtime cause. The original failed packet remains intact in `factory-yau.6.40`.

**Affected promise / exit:** compare explicit String names when the oracle means
names, and retain actual flags, key types, visibility and a settled image before
the assertion. This changes only the test observer and leaves game dictionaries,
ordinary input and authoritative state unchanged. Source review is not a passing
native result; the successor requires its own reviewed gates and bounded case.
Owner: Playability, with Chapter source review and Ops operational reconciliation.

## Required follow-through

This first source/API/evidence audit leaves actual backend identification,
far-origin precision, concurrent factory scale, predictive movement and moving-save
behavior explicitly unknown. Owners must add a scoped measured follow-up when
one becomes necessary; unknown is not a claim of impossibility. No exhaustive
runtime characterization was performed for this register. New engine/backend
versions, authority/controller changes and newly discovered restrictions must
update this register with their actual impact and evidence during ordinary
integration and review. Do not postpone stationary chapter work for an exhaustive engine
comparison, and do not mark this maintained register permanently finished after
its initial audit.
