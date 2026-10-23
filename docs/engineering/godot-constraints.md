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

The current [adult worker presentation](../../experiments/engine-environment/godot/opening/assets/worker/README.md)
uses a skinned asset whose imported skeleton has a rotated parent. Its chosen
adapter includes that parent when fitting the visible standing height to the
existing capsule and when converting cosmetic bone rotations. The pinned
[Skeleton3D implementation](https://github.com/godotengine/godot/blob/ed1daf0bf/scene/3d/skeleton_3d.cpp)
invalidates global-pose caches on pose changes only inside the scene tree, so
preparation composes the current local poses explicitly. Each actor owns its pose;
the mesh, materials and textures are shared. These source and headless skinning
checks do not establish human appearance quality, physical limb contact or a
different movement/collision model.

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

**Physical saved-contact limit:** The original fixtures cover an upright capsule
against a floor plane and uniform axis-aligned machine boxes. Complete current
captures also share the displayed terrain triangles and rigid site-box descriptors
between `site_surface.gd`, the renderer and ActorWorld. Historical fixed-roster
captures retain their original flat presentation and plane; the native profile
refuses a missing shared helper. The finite displayed site is adapter data, not a
game-world boundary. Scenery nodes remain free of controllers and colliders.
The native unbuilt site now uses a nonuniform lattice with quarter-metre local
samples around the clearing and river banks. Rendering, height queries and
collision use the same emitted float32 coordinates and triangle diagonal; callers
must use the actual cell endpoints rather than assume uniform spacing. The old
tile, slab and canal-box catalogues are empty in this profile, while visible rock
obstacles retain shared rigid descriptors. Local refinement and the natural bank
profile are revisable adapter choices, not build-grid rules or measured frame-cost
targets. Scenery rocks reuse the detailed sourced boulder mesh, normalized to
their existing visible dimensions. The pinned engine's
[mesh simplifier](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/resources/mesh.cpp)
prepares one convex hull; a uniform expansion encloses the original asset vertices
without retaining the simplifier's inward cuts. Each scaled instance retains its
original hull cooking input separately from the cooked reference vertices and
facets. Its plant-clearance envelope encloses the actual expanded hull; that box
does not become a collider. The convex body approximates detailed concavities.
The raw dense hull and a directional support-plane candidate missed some native
character-body sweeps despite direct shape casts detecting contact. The fitted
simplified hull passes the focused five-direction capsule queries for all sixty-five
site rocks, with the existing contact tolerance and zero shape margin. This is
bounded native query evidence, not a guarantee for every approach or backend. The pinned
[convex-shape API](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/ConvexPolygonShape3D.xml)
accepts the points of a solid hull. ActorWorld verifies the native shape type and
point set, with an explicit zero shape margin, against the shared descriptor.
The source points remain exact in the shape resource. The pinned GodotPhysics3D
[hull conversion](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/convex_hull.cpp)
truncates coordinates on a per-AABB integer grid of 10,216 intervals, and its
[shape-data getter](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/godot_physics_3d/godot_shape_3d.cpp)
returns those cooked vertices. Registration therefore requires a one-to-one point
match within one native grid interval per axis plus the existing observation
epsilon. It does not enlarge contact or construction-reach margins. The analytical
contact guard uses the actual cooked vertices after matching, rather than the
nominal render facets. This adapter projection is specific to the pinned backend;
an unsupported conversion fails closed rather than silently accepting another hull.
The mineable source uses a sourced detailed mesh and its full convex envelope.
Its descriptor retains the original 201-point cooking input separately from the
200 cooked reference vertices and faces. Feeding the cooked debug vertices back
as new input removed further points in the pinned engine, so bodies always use
the original input and registration matches the resulting reference. The fitted
longer hull is checked against actual native registration and capsule contact;
it does not reproduce the mesh's concavities. Visible placement,
native construction obstruction and the actor body share one transform and
envelope. Cached native `TriangleMesh.intersect_ray` queries drape stock-derived
veins over the detailed surface only; they supply neither build height nor
collision authority. The fixed rock remains when its finite ore veins disappear.
ActorWorld may reuse an already validated site-point correspondence only while
the native shape identity, actual cooked data and expected reference are exactly
unchanged. Shape type, space, rigid pose, original resource points and zero margin
are still checked on every registration read. Changed correspondence inputs rerun
the full bounded match; the cache does not relax its tolerance or admit an
unvalidated shape.
ActorWorld registers the terrain faces, backface flag and rigid site transforms
before admitting saved bodies. Concave terrain is a hollow surface: an explicitly
labelled analytical burial guard also refuses a saved capsule wholly below it,
without inventing a native query hit or resetting the pose. Box contact uses the
actual rigid transform. Rock contact measures capsule distance to the shared
convex facets and explicitly detects the solid interior. These are analytical
adapter measures rather than a general native penetration-depth API. All native query hits remain
visible, and reaching the bounded query-result limit fails closed. The adapter's
analytical overlap measure and chosen 0.001 contact allowance are not a general
native penetration-depth result. The accepted offline floor/wall reopens had
empty contact-query results; they do not exercise the small-positive-overlap
acceptance branch. Deep-overlap refusal is separate negative evidence. A broader
contact/restore policy needs its own discriminating consumer; fixed-box collision
and `actor_occupied` do not establish actor contact, pushing or injury rules.

The shared-site witness retains the original hill counterexample, exact emitted
triangle relation and rotated-solid controls. An actual walk/jump/save prefix is
retained separately from its later harness-path assertion; the corrected shared
reopen stage loads that preserved binary through the ordinary Session producer.
An explicit buried-pose negative retains the declared source pose and refuses
readiness. These bounded headless records do not establish fresh-process client
play, positive-overlap policy, backend identity, far-origin support, frame cost,
human usability or rendered quality.

**Chosen native transmission adapter:** the
[native Host](../../native/factory-godot-world/README.md#oriented-transmission-api)
uses quarter-pitch integer coordinates to represent the common world grid, with
shaft and cog centers at multiples of four, explicit X/Y/Z axes, two finite cog
sizes and individual one-tile shafts. Those dimensions and the kit are revisable
modeling choices, not Godot restrictions. The C++ geometric solver
derives engagement and signed rational rates; it does not simulate tooth contact,
torque or angular phase. Belt material moves according to the signed spindle
direction; reverse-end blanks become recoverable loose material. Processor work
and span-belt throughput scale with the derived rate. A 45-degree span uses the
fixed-point factor 2896/4096 to approximate the extra length per diagonal tile;
actor carry uses the same horizontal progress. The active native World uses
shaft spans; the single-cell belt remains only in standalone material fixtures.

The ordinary view's layer-4 gear/shaft picking geometry does not make a rendered
contact authoritative. ActorWorld separately registers transmission collision
shapes derived from confirmed native geometry.
Static direction arrows and engagement markers use confirmed native facts;
the translucent placement cursor is only a requested grid point. ActorWorld
continues to supply real body origins for the exact 3D reach decision. Pushing,
authoritative dynamic phase and full physical tooth contact remain separate work.

**Chosen motion presentation:** the wheel, cog and shaft-keyway illustrations
integrate cosmetic angles from confirmed native signed rates. The source rate's
visual reference is one horizontal tile per 0.45-second native tick at unit rate,
using the illustrated pulley radius; it is not a selected physical RPM. Long
frame gaps are capped at 0.1 seconds for this illustration.
Local angles survive a mesh refresh for the same context/part generation, reset
on replacement or a new world, and are not checkpoint fields or contact data.
Unknown/stalled parts and unavailable/Help/unready/shared-disconnected views do
not invent continued operation. The axisymmetric pick cylinders stay pick-only;
spinning their visuals does not rotate ActorWorld's collision shapes.
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

**Mesh tangent input, observed in a source-derived wheel fixture.** The same
pinned renderer rejected a resized mesh whose tangent array was present but
empty: it required four tangent values per vertex. The wheel adapter instead
transforms the source tangents with the changed geometry and orthogonalizes
them against the transformed normals before rebuilding the indexed surface.
This concerns Godot's mesh-array contract and the local art preparation path;
it is not a wheel collision, power or material-quality rule.

**Headless instance readback, observed and source-qualified.** The pinned dummy
renderer ignores individual `MultiMesh` transform writes and returns identity
from the corresponding getter. Its
[bulk-buffer implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/dummy/storage/mesh_storage.cpp#L89-L101)
retains submitted data. The environment fixture therefore inspects the actual
bulk buffer for foliage placement, without claiming a GPU draw or rendered
position. Its first per-instance readback failure is retained under
`production-worksite-environment-20261020`. This harness boundary changes no
physical collision, construction range or game rule.

The continuous-meadow zero-instance case found that the dummy bulk getter can
retain its previous array after the active instance count becomes zero. The
clearance fixture checks that active count and its records, including counts
restored after construction removal. Its first real-renderer probes passed the
geometry assertions but emitted two texture-leak errors during teardown. Waiting
for a completed frame while each view exists and another after freeing the views
produced a clean completion. These original observations remain under
`continuous-meadow-20261021`; the fixture adds no gameplay or collision rule.

**Machine mesh batching, adapter and fixture.** The native opening keeps one
confirmed pick body and source part hierarchy per machine while repeated
opaque render surfaces use shared `MultiMesh` instances. Source parts with
separate surface finishes receive one cached visual mesh with those finishes
bound to its surfaces before batching. Each wheel's rotor surfaces become one
cached mesh with one independently updated transform per wheel. Conveyor loops
use a shared shader and per-instance texture phase while their hidden source
materials retain the original offset. Wheel joinery with an original visibility
range remains an individual source part so its distance culling still applies;
the shared rotor holds the silhouette and other permanent surfaces. Isolated
12-machine collector and press captures matched their direct renders byte for
byte. The conveyor close view changed 90 pixels by at most one 8-bit channel
step, and a flat wheel silhouette
matched exactly; shaded wheels differed slightly. This fixture repeats
visual assemblies in a regular layout and does not exercise native placement,
the complete opening or human play. The threshold and batch sizes are adapter
choices, not limits on constructable machines. Owner: Performance.

The same isolated graphical process measured first unprepared preview
construction at 0.86 s for a collector, 2.37 s for a conveyor, 2.45 s for a
press and 4.82 s for a wheel. Priming all four visual assemblies once cost
about 8.3 s in this fixture, after which first selection took 1 to 5 ms.
Priming moves asset preparation into opening setup; it does not eliminate the
one-time work. A complete native opening launch and input timing remain to be
measured before treating its startup cost as accepted. Owner: Performance.

On Godot 4.7.2's graphical Compatibility path, decoding available authored
JPEG/WebP/PNG bytes with `Image.load_*_from_buffer` avoids the measured cost
of calling `get_image()` on imported textures. The imported `Texture2D`
path remains the fallback when source bytes are absent, as may happen in an
export. In separate isolated first-build runs, collector/conveyor/press/wheel
assembly measured 870/1687/1784/4110 ms through imported texture readback
and 595/946/1001/2334 ms through source-buffer decode. The actual four-kind
preview priming fixture then measured 4772 ms, with first wheel selection
at 2.0 ms; its earlier imported-texture runs were about 8.3 s and 1 to 5 ms.
The 100-machine rendered frame was pixel-identical before and after this
decode change. Relevant asset, transmission and preview checks passed, but an
export without source bytes and full native startup have not been exercised.
These are single-process measurements, not a loading-time guarantee. Owner:
Performance.

**Repeated static machine composites.** The native opening now combines the
eligible static opaque surfaces of identical collector, conveyor and press
assemblies into one cached mesh per exact source/finish/pose signature. Moving
parts, translucent parts, range-culled detail, conveyor loops and pick bodies
retain their existing paths. Waterwheels keep their separate rotor composite;
an additional support composite did not improve their 100-wheel tail time.
In an exclusive 1280×800 Godot 4.7.2 Compatibility rendered fixture on
WSL2/D3D12 RTX 3090, with the same static opening scenery, synthetic machines,
camera rule, 30 warmup and 120 measured frames per case, the production batch
path changed as follows (old grouping → static composites): 100 mixed
collector/conveyor/press assemblies, 20.887 → 19.531 ms median and
28.475 → 25.255 ms p95, with 264 → 221 median draw calls; 400 assemblies,
16.971 → 15.232 ms median and 18.366 → 16.942 ms p95, with 191 → 117
draw calls. These are single runs. The camera moves back as the array grows,
so the 400 case shows smaller machines and cannot be read as constant-view
scaling. First batch construction grew from 135.945 to 333.748 ms for 100 and
343.025 to 598.913 ms for 400, leaving placement latency unresolved.
The repository's `machine_visual_test.gd --mixed-scale --production-batch`
repeated the final render with pixel-identical captures and 221/117 median
draw calls; its separate 100/400 runs measured 19.133/14.761 ms median and
26.350/15.645 ms p95, showing run-to-run frame-time variation.
The 100-machine direct and composited frames differed at 4,442 of 1,024,000
pixels; the previous batching path differed from direct at six pixels. The
changed pixels cluster on small machine edges and highlights in the captured
view. The source hierarchy and pick bodies remain, and the baked meshes use
the original finishes. All-angle
fidelity, native player placement, motion under a full authored worksite and
human play remain unverified. Fixture scripts, logs and captures are retained
locally under `cog-performance-20261022`. Owner: Performance.

**Motion update cost, measured but not fully resolved.** The presenter retains
only unbatched animated anchors when topology changes; the opening retains
machine motion anchors and resolves each conveyor loop once. It also uses the
wheel rotor's fixed parent pose for batch updates. In paired isolated headless
runs, 200 conveyors' body update fell from 0.730 to 0.416 ms median. In an
exclusive complete-opening fixture with 400 synthetic confirmed cogs, the
presenter change lowered process time from 2.491 to 1.919 ms median and frame
time from 18.831 to 18.312 ms median; p95 frame time rose from 20.423 to
22.681 ms in those single runs. The fixture does not exercise native placement
or a human-built inventory, and this is not a steady 60 FPS result.
With both motion caches present after the later terrain and opening join, a
0/400-cog fixture pair measured 13.017/17.143 ms median and
17.171/18.999 ms p95 on the same machine.

**Native transmission refresh cost.** The normal opening calls its
transmission refresh from the per-frame UI refresh. The earlier paused scale
fixture omitted that call and understated the cost of hundreds of cogs. An
exclusive 1280×800 Godot 4.7.2 Compatibility probe on WSL2/D3D12 RTX 3090
added the same refresh call on every frame of a synthetic opening. With 400
supported mixed cogs, 30 warmup frames and 120 measured frames, its unchanged
projection took 5.789 ms median to refresh and 23.003 ms median /
27.858 ms p95 per frame with stopped cogs. Rotating cogs measured 5.834 ms
refresh and 23.884 / 29.763 ms per frame. Those are source measurements
before the change below, not earlier paused-fixture FPS results.

The presenter now compares an owned deep snapshot instead of serializing
every part to text. It skips the deep walk between revisions only when the
host has the native Model, whose changed World snapshots increment revision.
Synthetic hosts retain exact value comparison, including motion edits without
a revision. Unchanged batched cog angles also avoid transform updates. In
separate single runs using the same scene and sample rule, the final
synthetic native-revision path measured 0.573 ms refresh and
16.984 / 18.802 ms frames for stopped cogs, and 0.534 ms refresh and
18.433 / 19.526 ms frames for rotating cogs. An earlier candidate run
measured 16.647 / 17.598 and 18.041 / 19.374 ms frames respectively,
showing run-to-run variation. A trusted-revision fixture advances its synthetic revision
on append and tests the resulting rebuild; it does not boot the native World.
Those synthetic runs did not boot the native World, and the rotating frames
still exceed a steady 60 FPS budget. The fixture's
verify-only whole-opening mode emits two GL texture leak errors at exit even
without the trusted revision path; its isolated graphical pose, pick and
revision checks complete without those errors. Owner: Performance.

**Complete native opening baseline.** On the exact published `46dfd8b`
source with a freshly built native extension, the ordinary opening at 1280×800
on Godot 4.7.2 Compatibility, X11/WSL2/D3D12 RTX 3090, took 16.801 s to
reach the first actor-ready observer frame. With no placed cogs or machines,
30 warmup and 120 measured frames gave 75.923 ms median, 83.656 ms p95 and
131 median draw calls. A blank same-project render measured 7.333 ms median,
so the high floor is in the opening. Passive ablations attributed substantial
cost to ProductionScenery and sun shadows, but hiding them visibly changed
the scene and was not shipped. In a stripped three-draw opening, disconnecting
only the ActorWorld physics-frame callback changed 31.263 to 13.946 ms median;
the production physical character must keep that callback. The earlier
synthetic cog fixture therefore cannot establish complete native opening
frame rate. The passive screenshot confirms the worksite view and FPS display,
not human playability. The source-matched probe, report and image are retained
locally under `cog-performance-20261022/native-runtime`. Owner: Performance.

An explicit distant wheel mesh experiment reduced the batched rotor from
14,094 to 2,306 triangles per instance. Exclusive isolated 200/400-wheel
medians improved from 22.905/34.773 to 20.302/32.077 ms, but the 200-wheel
tail did not improve and a flat rendered comparison changed 2,154 pixels.
That mesh substitution is not used in the opening. Generated mesh LOD alone
gave no measured improvement in the same fixture; the cause was not isolated.

**Asset import, observed for one source representation.** During the
[scanned steel surface preparation](../../experiments/engine-environment/godot/opening/assets/steel/CREDITS.md),
the pinned runtime's TinyEXR loader rejected the provider's normal EXR with an
unknown compression type. The same provider's OpenGL normal PNG decoded and
prepared successfully without a green-channel flip. The original EXR and first
failure remain in `scanned-steel-materials-20261020`. This is a specific format
adapter limitation, not a ban on EXR, a texture-quality ceiling or a game rule.

**Project images use imported resources.** The pinned 4.7.2 runtime warns when
`Image.load_from_file()` reads project bitmap paths because an exported package
can retain imported data without its original image file. Runtime material
loaders use `ResourceLoader.exists()` and an imported `Texture2D.get_image()`
copy; external preparation inputs still use filesystem decoding. This follows
the [image-resource API](https://docs.godotengine.org/en/4.7/classes/class_imagetexture.html).
The worker opacity map disables import-time alpha-border processing to preserve
the original pixels. The focused controls compare every loaded channel, including
HDR data and character mipmaps, and exercise imported remaps in a package without
raw bitmap files. This is an image-loading contract, not a complete standalone
game-export or human appearance verdict. Evidence: `imported-material-images-20261021`.
For the derived wheel-center color, a source-render trial before editor import
could not resolve the new `Texture2D` and showed the procedural fallback even
though the general passive image runner returned success. Importing the image
made the source mount available; the focused material check must verify that
mount rather than treating an arbitrary rendered wheel image as source proof.
The original failed trial remains in `waterwheel-timber-20261021`.
The current sourced roster requires that graded atlas; a missing or unimported
map is incomplete and refuses the sourced mount.

**Data-map alpha is not surface opacity.** The
[paddle timber source](../../experiments/engine-environment/godot/opening/assets/wheel-paddles/CREDITS.md)
contains slightly nonopaque alpha in its normal and roughness PNGs. An initial
preparation guard rejected that unused channel. The pinned asset preparation now
checks every loaded RGB value against independent raw PNG decoding and preserves
all data components while dropping alpha before resizing. The
[material API](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html#class-basematerial3d-property-normal-texture)
uses red and green for normals and ignores their blue/alpha channels; this
roughness adapter explicitly selects red. Its material remains opaque. The
original refusal and corrected pixel evidence remain under
`timber-waterwheel-paddles-20261021`. This is a data-channel boundary, not a game
transparency rule or a rendered-quality result.

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

The pinned native-opening capture in `grass-daylight-color-20261022` requested
X11, fell back to Wayland and exited zero after rendering the changed grass
material, while reporting two ObjectDB instances at shutdown. A focused verbose
rendered diagnostic also fell back to Wayland and identifies them as
`DisplayServer` and `NativeMenu`; the corresponding headless diagnostic reports
no ObjectDB leak. The original warnings, object names, completions and source
binding remain with that result. The underlying cause, X11 behavior and
longer-session leak behavior remain unknown; this is a bounded Wayland display
shutdown observation.

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
[original layout observer](https://github.com/dan-garvey/factory_project/blob/d83716d7bc786201b48895154c8b7b91e8287111/experiments/engine-environment/godot/opening/layout_observer.gd)
records actual viewport bounds, edge margins, rendered text, button signals and
ordinary input across size changes and maximize/restore. Its pending-view fixture
temporarily pauses only client multiplayer polling around an ordinary request;
the server and its authority remain live. Treat that pause as a disclosed fixture
shortcut, not natural network-delay evidence. That old text-menu driver is now
superseded by the hotbar's detached widget and layout controls in
`opening/parts_view_check.gd`; its original packets retain their verdicts. Runtime verdicts and supported
display/backend limits belong to the exact retained `6.40` cases; source or parser
success alone does not certify resizing, DPI, accessibility or actual user play.

**Collector pickups are a fixed site adapter.** The two admitted seam cells
have separate occupied pickup boxes that intersect the actual outcrop
triangles. At four or eight height steps, an open exterior lift reaches from
the low pickup to a head above the founded machine; its guides and flights
have separate occupied volumes. Native placement and restore allow the
trusted, identified source obstacle at the pickup only. Other scenery,
actors and built parts remain blockers. ActorWorld and the ordinary pick body
register the same boxes. This does not model moving tooth contact or arbitrary
mineral sources. Native and headless scene checks establish physical fit;
passive outlet-side images still conceal the lower route, and human usability
and final rendered quality remain unassessed.

**Runtime scenery import is presentation only.** The sourced grass uses a
self-contained GLB buffer through
[GLTFDocument](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html)
and its mesh resources, without instantiating an asset scene or relying on editor
import files. The first isolated 4.7.2 check retained geometry and textures but
found missing mipmaps. The adapter now generates them once and renormalizes normal
mip levels before caching. The separate focused correction passed; the original
failure remains in the sourced-foliage evidence. Tuft selection, image dimensions,
cutout threshold, density and distance culling are reversible art/resource choices.
The meadow follows existing terrain and avoids existing solids; it adds no
collision or gameplay authority. The [sourced daylight](../../experiments/engine-environment/godot/opening/assets/sky/CREDITS.md)
keeps its original HDR bytes, decodes once to floating RGB with mipmaps and aligns
the ordinary key light to the measured bright source texel using pinned panorama
coordinates. Source radiance and node binding do not establish rendered lighting
balance or photometric calibration. Resource/geometry checks establish neither
rendered quality nor GPU cost. See the [foliage asset record](../../experiments/engine-environment/godot/opening/assets/foliage/CREDITS.md).

**River transmission is an adapter art approximation.** The ordinary natural
river blends two mipmapped normal layers through the standard material's separate
texture-coordinate channels. Cached seamless two-dimensional noise gradients
replace coherent analytic wave bands, with wrapped derivatives and normalized
mips. The mesh ends at the terrain-clipped water surface; decorative submerged
side faces are removed. Shore vertex opacity softens that edge. The alpha surface
can reveal the opaque bed and uses the existing sky reflection path, without
changing terrain, actual water elevations, actor contact, power or simulation
time. This is ordinary alpha blending, not depth-dependent
absorption or refraction; transparent-object sorting, underwater viewing and final
rendered balance remain unassessed. Resource and frame-consumer checks do not
establish pixel quality or GPU cost. The historical flat fixture stays opaque.

**Terrain-guided water is a bounded stationary model.** The ordinary scene sends
wet grid cells and staged water levels through the trusted Godot adapter. Native
code samples the exact emitted terrain triangles for bed depth, looks for a
connected lower wet neighbor across a clear path, and derives a local current
from slope and wetted width. A solid bank blocks that connection; level or
rising water without an outlet remains still. The renderer clips its water edge
against the same terrain and varies ripple texture density from a presentation
estimate of the same slope, depth and width. The texture is not current
authority. The staged surface is authored for the demo and does not solve mass
conservation, rainfall, water pressure, erosion, dynamic flooding or lateral
transport around obstacles. These are native model and adapter limits, not
intended-game restrictions. Isolated checks cover the synthetic bank and basin,
three real riverbed widths/speeds and the source geometry; rendered quality and
human usability remain unassessed.

The current [grass surface](../../experiments/engine-environment/godot/opening/assets/ground/CREDITS.md)
uses provider-declared 1.4-metre mapping and preserves the source albedo's decoded
RGB8 values through lossless packing. The pinned loader resamples separate JPEG
OpenGL normal, occlusion and roughness maps; red-channel ambient occlusion and
green-channel roughness are packed as an explicit adapter choice. These are
shading/data boundaries, not terrain
displacement, collision or biome requirements. Stable triangular patch blending
replaces the two fixed texture frames, whose common period was 6.5 metres.
Each patch rotates all sampled channels together and returns the decoded normal
to the original plane basis. The small variance correction does not implement
full histogram-preserving synthesis. The isolated render control distinguishes
that old period from a nearby translation and checks stationary-frame stability;
it is not a universal texture-quality or GPU-performance metric. Resource checks
establish neither rendered balance nor the overall graphical-quality target.

The [fern asset](../../experiments/engine-environment/godot/opening/assets/ferns/CREDITS.md)
uses the same resource-only foliage import. Its first export attempt failed exact
geometry/image preservation checks; the shipped preparation copies the selected
source ranges and prepared PNG bytes through a fixed native writer instead.
This is a preparation boundary, not a demonstrated renderer ceiling or gameplay
restriction. Low plants do not add collision or authority.

The [full-size fir resource](../../experiments/engine-environment/godot/opening/assets/fir/CREDITS.md)
retains its qualified complete base and locally generated distance
levels use pinned `ImporterMesh`; its nominal LOD size is a simplifier error
scaled to source metres, not a rendered-error bound. Only bound methods are
script API: the first preparation failed on native-only `has_mesh()`, while
constructing a fresh importer through `add_surface()` corrected that path.
The original API failure and bounded timeout remain retained. Source material
transforms and scalar normal-incidence dielectric reflectance are preserved;
the descriptor supplies no occlusion binding. Three current bank instances use
the same prepared woody triangles in rendering and the existing native floor
shape. Their roots follow actual terrain triangles, while the eight-metre
working ring and river/rock clearances remain open. Needles add no collision.
The analytical contact measure is triangle distance, not native contact depth.
The floor's native and node transforms must both remain identity; matching a
shifted body to a shifted node is insufficient for the shared fixture.
Retained scene and isolated physical controls cover mounting, real capsule
contacts and changed-shape/pose refusal. They do not establish ordinary player
traversal, a save/reopen consumer, detail switching, visual quality or frame
cost. This is a chosen static site fixture, with no new harvesting, growth,
inventory, reach or mechanical rule.

The optional [young pine component](../../experiments/engine-environment/godot/opening/assets/pine/CREDITS.md)
preserves all selected source triangles through the importer's compressed GPU
attributes and a self-contained native `ArrayMesh`. Imported positions and UVs
are quantized, not original float bits; native arrays and embedded prepared pixels
round-trip exactly. Cached material copies map the source IOR and gray specular
color to the pinned Compatibility shader's normal-incidence reflectance, while
preserving imported material references and textures. This is a bounded opaque
dielectric adaptation, not a complete glTF scattering conversion. At most six small,
noncolliding plants are rooted in terrain and omitted beneath confirmed machines;
no vegetation state or second controller is introduced. Resource/placement checks
do not establish rendered quality, cost or collision rules for mature trees.

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

## GDC-14: short segment tests can miss small finite mesh faces

**Engine/API source verified for 4.7.2; bounded fixture failure observed.** The
pinned [segment/triangle implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/math/geometry_3d.h)
tests the unnormalized segment/triangle determinant with
[`is_zero_approx`](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/math/math_funcs.h).
Its [absolute epsilon](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/math/math_defs.h)
is independent of face area and segment length. A short segment crossing a small
face can therefore be rejected by the parallel test before intersection bounds
are considered. This does not establish a minimum game feature size.

The first compact-conveyor-hub asset case retained sixteen failed short joint
probes while its other clearance checks completed. The changed fixture uses
longer probes, records their actual hit heights and requires overlapping solid
intervals for the housing and its support at the intended joint. Deliberately
lowered supports must fail that same predicate. The original failed result is
preserved; changing this fixture does not change mesh geometry, native collision,
construction reach or mechanical authority.

**Affected promise / exit:** qualify a mesh predicate at its actual geometric
scale and retain measured intersections before asserting contact. Do not turn a
test-helper miss into a permanent gameplay tolerance or a physics-backend verdict.
These are technical asset observations, not physical force, rendered-quality or
human-play evidence. Owner: Platform, under `factory-yau.6.45.23.15`.

## GDC-15: convenience mesh faces are not the original render vertices

Godot 4.7.2 commit `ed1daf0bf001b61586d9930840f2f1394092c079` implements
`Mesh.get_faces()` through its cached triangle mesh. That cache snaps each input
vertex to a 0.0001-unit grid before returning faces. The pinned
[mesh implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/resources/mesh.cpp)
and [triangle-mesh implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/math/triangle_mesh.cpp)
establish this source behavior; it is not a restriction on build precision.

The first focused cog-bore fixture used that convenience list and failed its
original outer-radius assertion. A changed diagnostic fixture retained the
values: the 0.14025-metre hub reported a maximum cached radius of approximately
0.140300 metres. Its passage still cleared the shaft, but the cached triangles
were unsuitable for the exact render-dimension assertion. The first fixture
also assumed a name for an unnamed pick-shape child; that reader failure and its
exit diagnostics remain separate from product geometry.

Fine presentation checks now reconstruct triangles directly from each surface's
vertex and index arrays, retaining the cached observations for comparison. The
shaft envelope uses the same original arrays. This changes neither geometry nor
the acceptance tolerance. It does not establish collision-backend precision,
mechanical contact, native reach, force behavior or a general minimum feature
size. Previous coarse face-list results retain their actual scope and revision.

## GDC-16: appending mixed mesh indexing can omit whole components

**Engine/API and adapter, source-confirmed.** In the pinned Godot 4.7.2
[SurfaceTool implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/resources/surface_tool.cpp#L1021),
`append_from()` appends vertices and any supplied indices; it does not generate
indices for an unindexed input when another input is indexed. A combined indexed
surface therefore leaves the unindexed component's vertices unreferenced. Its
bounds can still include those vertices, and checking only the referenced closed
components does not prove that every intended component is present.

The shared press/service hardware helper combined unindexed authored washers
with indexed primitive bolt heads. The first rear-service consumer retained zero
matched washer-foot area. The helper now indexes the washers before appending
either input. The focused fixture requires the complete input triangle count and
all four actual washer-foot areas, and reproduces the previous mixed-index
omission as a negative control. The affected press tooling is checked separately
from unchanged native gameplay. This is render-resource assembly, not a physics,
mechanical-contact, construction or material rule. Owner: Platform, under
`factory-yau.6.45.23.25`. Other future compound meshes must preserve each input's
topology rather than infer completeness from bounds or a nonempty surface.

## GDC-17: construction pointers request a datum, not terrain permission

**Retained engine observation and adapter choice.** In the pinned 4.7.2
foundation view fixture, an oblique 400 m physics ray returned no terrain hit
while a vertical ray through the same requested point hit the emitted surface.
The concave shape was registered in the correct space with back faces enabled.
The cause and generality are unestablished; this is not a claim that terrain
contact or every terrain ray fails. The original failures and diagnostic source
are retained in `native-grid-foundations-20261021/view-new-v1-sources`,
`view-new-v2.log`, `view-new-v3.log` and `view-new-v3-sources` under the local
prototype evidence root. Owner: Playability, `factory-yau.6.53`.

The view selects a confirmed constructable surface or the chosen absolute grid
height plane. It needs no duplicate terrain collider on a shared client. This
requests coordinates only. Machine placement still checks emitted triangles,
support, occupied space and the real character's reach. Following human feedback,
foundations deliberately ignore terrain, scenery and gravity support; constructed
objects and actors still block them. Rectangular foundation requests temporarily
omit the distance restriction, while single blocks retain it. These are explicit
prototype construction choices, not limitations imposed by Godot. A selected plane
never grants construction permission. The foundation and machine height denominator
is a user requirement, independent of this observed query behavior.

## GDC-18: confirmed actor pose cadence can differ from render cadence

**Presentation adapter observation, isolated fixture.** At a 60 Hz render rate,
repeating a confirmed walking position for two frames and advancing it on the
third made the adult gait alternate between a near-idle pose and a false fast
step. The native `native_epoch` is an ordinal, not a timestamp. The presenter
now measures elapsed presentation time between fresh confirmed positions and
briefly holds the last confirmed gait during repeated samples. A stale pose
settles instead of predicting more actor travel. This keeps actor roots exact;
it does not smooth their positional hitch or establish real network cadence,
whole-scene quality or human playability. The focused dense/sparse check and
passive image comparison belong to `factory-yau.6.45.22.14`.

## GDC-19: runtime cutout mip generation does not preserve blade coverage

**Measured pinned-engine adapter behavior.** The runtime GLB grass import uses
`Image.generate_mipmaps()`, outside the editor texture importer. Its source atlas
has 16.03% cutout coverage, falling to 8.33% at 24 pixels and 4.17% at 12 pixels
with ordinary averaging. The adapter now dilates transparent color borders and
rescales each color mip's alpha to the nearest achievable source coverage at the
existing 0.5 cutout. A subpixel mip can remain empty instead of making a solid
card. Geometry, base opacity, normal/scalar maps and population are unchanged.
The shared cutout import also serves the small fern clump.

The installed `4.7.2.stable.official.ed1daf0bf` exposes only the one-argument
`generate_mipmaps` call. The latest online Image documentation describes extra
coverage arguments absent from this binary; the rejected three-argument probe
is retained in `grass-distance-material-20261021/coverage-after.log`. It exited
zero despite script errors and zero checks, so it is not a passing observation.
The corrected adapter's focused mip checks and passive pixels belong to
`factory-yau.6.45.21.25`. Coverage fidelity does not establish healthy vegetation
color or complete scene quality.

## GDC-20: transmission stands are a derived opening adapter

**Experimental adapter and fixture rule.** The native Host derives fixed frames
for shafts, cogs and relay cases from their confirmed geometry and the current
terrain, ground-connected site solids, foundations, machinery, belts and lower
frames. Bearings remain coaxial. A horizontal bearing may use either axle face;
a limited lateral post offset and short arm keep an upper post clear of lower
axles. A rock below a clear axle can seat the post on its supplied site box top.
No route may intersect an obstacle or foundation, leave another frame invalid,
or exceed nine metres. Construction also refuses new or changed frame volumes
occupied by a ready character.

The projection supplies foot and bearing points plus four conservative support
boxes. ActorWorld adds these boxes to the part's existing physical body and
validates their native dimensions and local transforms. Capsule admission uses
each actual shape transform, including a post offset from its part's centre.
The presenter draws the stationary frame from the same foot and bearing.
Removal deletes its collision shapes with the part. The frame remains included
in the carried transmission part, with no separate stock, clock or saved state.

The native support and detached physics fixtures cover stacked axle clearance,
seating, actor occupancy, shape registration, removal and restore. Their
synthetic poses and projected boxes do not establish human usability or exact
mesh contact. This limited frame routing is an opening adapter, not a general
structural-load or strength simulation. An explicit buildable support system
would need its own native quantities, edit and save rules.

## GDC-21: the arrival pod is a projected native site seed

**Pinned engine and adapter observation.** The Godot 4.7.2 GDExtension method
`FactoryNativeWorld.initialize_arrival` accepted a two-actor roster in an
isolated headless script. Its projection reported one settled pod, nine deck
foundations and fifteen carried foundation parts. The focused native World and
Host tests also cover exact retry and checkpoint restore. The deck is seeded
through the normal foundation records and common grid; the `landing_pod`
descriptor is a presentation hint, not a second construction ledger.

That original extension probe supplied no rendered pod or human-play evidence.
The current ordinary offline and shared arrival paths use the native arrival
profile, with visible pod, workshop, multitool and component controls. The pod
center at grid `{4, 0, 16}` remains a revisable site choice. Host anchors include
the common spindle offset; floor-authored pod and bench meshes subtract that
offset once so their feet meet the ordinary foundation top plane.

The experimental arrival Host also projects three finite timber sites and the
existing ore reserve as `hand_sources`. Native `harvest_source` uses the bound
actor observation and the same reach authority as construction. In an isolated
pinned 4.7.2 extension probe, the actual emitted site accepted a synthetic
deck actor cutting one tree and a synthetic ore-side actor mining one unit;
checkpoint restore retained both balances. This establishes the site adapter
and bridge path, not input, movement, rendering or human play. The later scene
presenter binds its harvestable trees and depletion to those projected sites;
the original synthetic probe alone does not establish that presentation.
The experimental material schema also records typed crafted components with
their original timber or ore weights. A rebuilt 4.7.2 extension restored the
same two-source checkpoint after this schema change.
The experimental Host now also seeds a distinct bench on the east pod deck
tile. Native World/Host tests admit component crafting only at that bound
actor's reach, retain its source debit and typed output through retry and
checkpoint, and refuse removal of its supporting foundation. A rebuilt pinned
4.7.2 extension on the emitted site let synthetic P cut a tree and shape a
wooden shaft, refused Q's remote bench attempt, then let Q cut ore and shape a
metal edge after moving its supplied pose to the deck; a fresh Host restored
both components and source balances. This is an authority and extension
boundary, not evidence of ordinary player crafting. Current component and
workshop controls still send exact identities to that native authority.

The fresh opening's 2.8-second descent and unfolding sequence is local cosmetic
presentation of an already deployed native site, not simulated falling-pod
physics. It releases character controls while active. The canopy closes in
flight and hinges back after touchdown; the rigid bench swings onto its native
anchor. Restored and shared deployed views construct the open endpoint directly.
The existing view fixture checks actual mesh intersections, fixed bench scale,
native facts and cache identity at three common-grid heights in offline/shared
classes. Natural-clock app frames are separate rendered evidence, not human play.

The native Host now derives coarse occupied boxes for the deployed pod hull,
folded canopy and installed issued workshop from the existing World state.
ActorWorld mounts those boxes through its component-body path, including its
registration and contact checks. Native construction and checkpoint admission
use the same geometry; stowing removes the workshop boxes and redeployment moves
them to the new common-grid anchor. A saved actor inside this hardware is refused
rather than migrated. Thin decorative pieces and the fixed crank tray remain
presentation, without separate solid geometry.

The physical bodies use the deployed endpoint during the cosmetic reveal, while
character control is suppressed. This does not simulate falling-pod dynamics.
The bounded native-scene fixture uses real capsule queries and trusted motor
directions to check the wall, clear aisle, relocation and collider registration;
it supplies no actor pose, desktop input, harvesting or production replay. These
checks are separate from rendered quality and human play.

## GDC-22: first native tool presentation has separate cold costs

The current arrival profile does not call the older `_prime_machine_visuals()`:
its native projection has `hand_sources`. In a synthetic direct-function probe
of the ordinary X11 Compatibility opening at 1280×800 on WSL2/D3D12, the
first detached procedural collector, belt, press and wheel assemblies took
567, 943, 1017 and 2297 ms. The first collector display frame took 615 ms;
later instances shared their mesh resources and drew in roughly 50–60 ms.
This is preview presentation work, not native command latency.

The arrival now loads four bundled default amber preview scenes, renders and
retains their nodes in the main viewport, and prepares one reusable foundation
form. A focused headless fixture checks the baked local mesh geometry against
procedural assembly, neutral material, lack of colliders or callbacks, pooled
default selection and foundation area scaling. At that revision, nondefault
orientations and wheel sizes still used procedural assembly. Belt selection in the current native
profile opens a shaft-span tool, so its baked machine form does not represent
that tool's placement ghost.

An exclusive graphical direct-selection probe then separated the interface
from the ghost by hiding only the warmed ghost for one frame. With invented
carried parts and target cells, first collector and wheel interface frames
were each about 117 ms; revealing their ghosts later took 55 and 45 ms, near
neighboring frames. Warming those actual tool panels under the preparation
cover reduced first interface frames to 57 and 50 ms, with selection calls
about 4–5 ms. The foundation's first selection changed from 8.5 ms CPU and
83 ms first frame to 4.2 ms CPU and 42 ms first frame after retaining its
form. The same probe found no comparable first-use frame spike for native belt,
cog, shaft or gearbox menus. These are single-run, direct-function results on
an older locally compiled native extension; they do not establish mouse-driven
or human use. Actor-ready preparation took about 15.5–16.0 seconds in those
captures. The current source and evidence scripts, JSON and inspected collector
screenshot are retained under `cog-performance-20261022/native-runtime`.
An opaque-versus-0.99-alpha cover comparison did not improve the first-frame
spike, so the translucent-cover trial was not kept. This WSL renderer still has
a high frame-time floor, and static visual stress plus a zero-machine native
Windows run do not prove hundreds of active machines in the playable opening.

## GDC-23: a carried tool is actor presentation, not another physical actor

The opening's qualified worker exposes `Bip01 R Hand`. A `BoneAttachment3D`
carries the original multitool scene there; its fit compensates for the worker's
uniform presentation scale while retaining the authored tool dimensions. Only
the right-hand finger grip changes. Native capsule, pose, stock, harvesting and
construction admission remain outside this presentation.

The local eye-level view reuses the same tool mesh and a cached hand extracted
from the qualified worker's skin weights at that grip pose. It creates no second
player or collision body. Returning to the ordinary camera hides the close view;
readiness and source-profile facts govern its visibility. Meshes and attachments
are retained across unchanged refreshes instead of being rebuilt each frame.

The original rig inspection and 26 focused ordinary/shared presentation checks
cover attachment, bounded hand geometry, resource identity, camera visibility
and unchanged invented state. These checks create no live Model. They do not
establish full-scene appearance, human understanding, timed tool use or contact
animation; those require their own actual consumer evidence.

## GDC-24: replaceable shared views must not queue behind old actor samples

The shared adapter originally published full state while native bodies moved.
The native P/Q opening at `921940f` warned that its approximately 16.8 KB
unreliable packet exceeded the pinned 1392-byte ENet MTU; the host advanced
28,549 transport serials during 518 World ticks. Fragment loss could hide a
whole view. Native Session now sends a compact two-actor view on ordered
unreliable channel 1 and sends full state reliably on independent channel 2
only when World revision or request order changes. The scripted Model retains
its earlier full-state delivery. Welcome, input, commands and original outcomes
remain reliable on channel 0. A welcome acknowledgement establishes the native
full-state boundary; one full state may be in flight per peer, and a newer
pending state replaces the older one until that peer acknowledges receipt.
Both incoming streams coalesce and obey serial, revision and order watermarks.
This changes presentation delivery, not the
World clock or actor authority.

The focused two-actor payload check encodes below 1,100 bytes. In the native
loopback consumer, P's server-owned X position moved from 1.65 to 2.20 while
Q's ordinary shared view observed it at 2.10 with unchanged World revision and
stock. The corrected server logged no oversized packet warning during that
motion, the P/Q construction/refusal run, or the fresh Store continuation.

Godot's [transfer-mode and channel documentation](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html#channels)
describes the independent streams. The [pinned ENet implementation](https://github.com/godotengine/godot/blob/ed1daf0bf/modules/enet/enet_multiplayer_peer.cpp#L315)
supports unreliable fragmentation. A lost compact native actor view is replaced
by a later one, while a native material change uses reliable full delivery.
This remains a bounded loopback adapter, not a claim of production networking,
packet-loss tolerance or scale acceptance.

## GDC-25: grouping opaque machine finishes reduces render surfaces

At the pinned Godot 4.7.2 runtime, a static machine composite can retain its
normal and roughness textures while putting albedo tint into vertex color.
For the shared nontriplanar surface family, vertex alpha and a second UV carry
metallic and roughness values to a spatial shader. Other eligible finishes keep
their original `StandardMaterial3D` settings. Meshes with unsupported attributes
stay on the original material path; moving pieces and preview scenes are separate.

In a scripted WSL X11 overview of 400 synthetic collector, conveyor, press,
and waterwheel visuals at 1280 by 800, this reduced the two visible static
composites from 21 and 8 surfaces to 3 each, and draw calls from 137 to 114.
The experimental grouped runs measured roughly 16.5 to 18.6 ms median frames;
their spread needs adjacent controls before assigning a reliable frame-time gain.
Screenshots and synthetic visuals do not establish active native simulation,
placement latency, whole-opening frame rate or human visual judgment.

`ImporterMesh.from_mesh`, `generate_lods`, and `get_mesh` also produced usable
distance levels, but three cached composites cost 137 to 142 ms to prepare and
two LOD samples gave only 20.03 and 20.41 ms around a 20.93 ms control.
Distance LOD is therefore not used in this change. `ArrayMesh.surface_get_lods`
is not a callable GDScript API in this runtime; an early probe raised a script
error.

## GDC-26: native visual phases can advance at their readers

The native World marks each changed projection with a new context or revision.
The transmission presenter retains confirmed signed rates and one elapsed time
for that revision. It calculates a part's cosmetic angle when a visible rotor,
shaft, belt or cog batch reads it, then carries the phase forward when a new
revision changes the rate. The World clock, saved state and mechanical motion
remain authoritative; this adapter changes only presentation work between
projections. Scripted fixtures that mutate one revision in place keep their
direct motion lookup.

The focused native-model fixture supplies invented projections rather than
running a native World. On the pinned Godot 4.7.2 WSL build, a 400-cog
`MultiMesh.get_instance_transform` readback check returned identity transforms
under the headless renderer after the update, but the same graphical
Compatibility check passed all 400 pose and pick assertions. Use the graphical
renderer for this batch-pose check; headless motion tests still cover phase and
state behavior. Neither fixture establishes full-opening frame rate or native
mechanical throughput.

## GDC-27: native Array export uses checked indexed writes

**Pinned engine/API and adapter observation.** The Godot 4.7.2 GDExtension
`variant_set_indexed` interface accepts children of a resized Variant Array.
The adapter checks the `resize` result and each setter's valid and bounds flags;
it preserves owned plain values, type fidelity and its existing quota checks.
The real-engine value fixture covers empty, mixed and 1,024-element arrays,
including detached ownership after an indexed mutation. An external 1,000-wheel
full-view probe preserved the complete view digest while reducing median Variant
export time from 12.497/13.383 ms in adjacent baselines to 10.976 ms. This is
wheel-only headless conversion evidence; it does not establish a mixed rendered
scene at 120 FPS.

## GDC-28: static machine cell batches have renderer-specific cost

The pinned Godot 4.7.2 Compatibility renderer responded differently to small
static machine batches on the two measured paths. On WSL2 X11/D3D12 with the
RTX 3090 at 1280 by 800, a passive 800-machine close field took 60.285 ms
median with four-pitch cells and 2,087 draw calls, versus 23.237 ms and 218
draw calls with whole-field composites. A 400-press animated close field took
31.917 ms with cells and 26.402 ms when kept whole. The cell version submitted
fewer primitives in the 800-machine case, but its draw overhead dominated.
On native Windows/NVIDIA Compatibility, the separate 1,000-static-machine
close fixture improved from 13.545 to 7.500 ms with the same spatial approach.

The Opening adapter therefore defaults to whole-field static composites on
non-Windows builds and enables four-pitch cells only for large Windows machine
fields. The fixture can explicitly override the cell count for comparisons.
These are local renderer observations, not a platform-wide rule or a claim
about active native machines. Revisit the default with paired measurements on
another GPU, renderer or scene layout. Evidence is in `factory-yau.9.25` and
`factory-yau.9.12.34`.

**Screen-space composite LOD, observed.** On the published `bffacfa` chapter
source plus one candidate change, `ImporterMesh.generate_lods()` kept the
full composite vertices, finish surfaces and materials while giving three
cached machine meshes index levels for distant instances. In exclusive native
Windows/NVIDIA Compatibility 1,000-static-machine mixed views, 600 measured
frames at 1280 by 800, two reachable 24 m candidate runs measured
7.239/7.608 and 7.223/7.530 ms median/p95, bracketing the 9.954/10.389 ms
baseline. The close camera changed from 8.086/8.428 to 6.106/6.350 ms. The
max-zoom candidate submitted 29.4 million rather than 47.8 million median
primitives with the same 2,822 draws. Inspected captures kept the finishes and
silhouette at normal view size; pixel differences concentrate on small machine
edges. With viewport LOD disabled, an earlier same-source close control had
zero pixels differing by more than one color byte, supporting unchanged full
detail. This is a static presenter measurement, not native production or a
whole playable frame. Source, captures and probe errors are in
`factory-yau.9.12.50`.

## GDC-29: batched conveyor phases should update their visible instance

The Opening still wrote hidden per-conveyor `StandardMaterial3D` UV offsets
after batching. In an exclusive pinned Godot 4.7.2 WSL X11 Compatibility
400-conveyor close fixture, updating each visible `MultiMesh` custom datum
directly instead of changing hidden material offsets and copying them later
reduced whole-frame medians from 26.149 and 26.930 ms in adjacent baselines to
24.571 and 25.577 ms in the candidate runs. The GDScript motion stage changed
by only about 0.1 ms; reduced material or render upload work is an inference,
not a GPU trace. A 400-mixed-machine pair varied more than the candidate effect:
baseline medians were 31.374 and 33.228 ms versus candidate 32.536 and
31.546 ms, so no mixed-scene gain is established.

Unbatched conveyors keep their material UV path. The graphical batch fixture
checks distinct visible phases, no overwrite by other moving batches and
rebuild catch-up; the separate body-motion fixture checks unbatched behavior.
Inspected animated close captures retain the authored loop finish, but their
pixel hashes differ with phase. This is adapter presentation evidence only;
it does not measure native custody, legal placement or player understanding.
See `factory-yau.9.26` for exact logs and source revisions.

## GDC-30: irregular support heights need shared primitive instances

The native presenter formerly keyed each cog support batch by foot and bearing
coordinates rounded to 0.0001 m. Different terrain seats could therefore
create one multi-surface draw group per cog, even while the gears themselves
were batched. An exact-source external fixture based on published `8b35c6a`
varied only the support foot height over 400 synthetic rotating cogs. At
1280 by 800 in pinned Godot 4.7.2 WSL X11 Compatibility on RTX 3090, the
close whole-Opening median and p95 were 54.657 and 57.531 ms with 2,343 draws;
the first build took 9.171 s and appending a cog refreshed in 112.5 ms.

The presenter now instantiates the support's exact box and cylinder dimensions
through shared primitive meshes, grouped by finish. The same external view
measured 23.693 and 24.944 ms with 304 draws, a 5.402 s first build and a
28.0 ms append refresh. With 400 identical flat supports, the old and new
paths measured 25.082/33.058 and 24.521/25.898 ms median/p95 respectively;
the new append refresh was 26.1 rather than 15.8 ms. A separate isolated
20-cog close image comparison changed 1,049 of 1,024,000 pixels, with maximum
channel difference 12; inspection found no missing support or cog geometry.
The small differences are consistent with scaling the shared primitive in an
instance transform, but their exact rendering cause was not traced.
The graphical native transmission view check passed 171 assertions, and the
isolated varied-support fixture passed with 100 cog picks, five support
primitive groups and 1,000 instances. A whole-Opening validation reached its
pass marker but reported two exit-time GL texture leaks; it is not used as a
clean check.

These are passive synthetic presentation measurements, not legal native World
placements or a human playtest. The WSL whole-frame result remains above the
16.7 ms budget for 60 FPS. The first cog still pays roughly 0.5 s of cold
procedural mesh setup in an isolated process; `factory-yau.9.22` tracks that
separately. The representative active mixed-machine and Windows targets remain
open in `factory-yau.9` and `factory-yau.9.12`.

## GDC-31: first transmission preview triggers cold procedural render setup

In a clean pinned Godot 4.7.2 WSL X11 Compatibility process on RTX 3090, the
first small-cog preview took 438.635 ms to construct and 770.847 ms through
its first draw. Selecting the same cog again drew in 6.787 ms. The first shaft
and large-cog draws took 12.905 and 65.813 ms. This is a local Godot
procedural mesh and render-resource cost, not a native construction rule.

The native opening now draws both cog sizes and the shaft while its existing
workshop preparation cover is visible, after the cover has itself drawn. A
graphical fixture calling the production warmup measured 650.689 ms of added
preparation; subsequent first selections of those three variants drew in
5.905 to 7.056 ms. A separate synthetic supported-cog presenter fixture fell
from 433.024 ms first build to 25.251 ms after prewarming the same mesh
resources. All measured runs had no engine errors. This trades approximately
0.65 s of covered preparation for a responsive first tool selection. One
exclusive passive native-opening pair reached cover removal in 18.653 s before
and 18.959 s after the change; one pair cannot isolate startup variance.
Human-perceived startup and a player-command placement were not measured.
See `factory-yau.9.22` for the exact fixture and revision evidence.

## GDC-32: packed preview loading does not remove first-use node cost

The default machine previews were already drawn behind the workshop cover,
but the first rotated press, alternate collector intake and nine-tile wheel
still assembled their sourced art on the selection frame. A passive native
opening probe measured cold procedural construction near 0.10, 1.0 and 2.26 s
respectively after its default preview preparation. Moving all art preparation
behind the cover removed the selection stalls but extended covered startup by
about 4.6 s in an earlier pair, so that option was rejected.

A packed whole-collector preview loaded asynchronously yet still spent about
107 ms on its first main-thread instantiation in an isolated graphical probe;
the rotated press packed scene spent about 6 ms and an uncompressed nine-tile
wheel about 3 ms. [Godot's thread-safety guide](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)
says detached scene chunks can be built in a worker, but instancing rendering
nodes on worker threads is not thread safe by default. The current preview
adapter therefore reuses the packed collector and press bodies, swaps small
prebaked intake or drive modules and rotates exact existing parts on the main
thread. Wheel sizes three through nine share one compressed baked rotor per
size, two alternate-axle support modules and the default packed wheel. This
preserves exact procedural geometry without duplicating every size for every
axle. Resource requests run four at a time during the native arrival reveal,
after the workshop cover is removed. The 18 variant resources keep the staged
Godot project below the existing 48 MiB compiler-input cap after the current
main character-asset join. The broader three-through-sixteen candidate passed
the same fixture on its own revision but exceeded that cap after the join.
The joined three-through-nine range passed 108 headless variant cases.

An invented-state graphical fixture on pinned Godot 4.7.2 WSL Compatibility,
RTX 3090 and 1280 by 800 measured the earlier whole-scene candidate's first
alternate collector, rotated press, nine-tile wheel and belt preview updates
at about 4.1, 1.8, 4.6 and 6.5 ms CPU after the default form had drawn. Their
first visible draw intervals were about 9 to 14 ms. The shared-rotor candidate
measured 5.672 ms CPU and 6.472 ms first draw for an alternate-axle nine-tile
wheel on WSL Wayland. One hundred twenty-nine headless variant cases compared
the broader candidate's baked world geometry with procedural forms. A passive
ordinary native opening for that candidate reached cover removal at 19.847 s;
its 25 resource requests completed at
20.606 s, before the 22.693 s end of the arrival reveal. The earlier
whole-scene candidate reached cover removal at 19.579 s, and its paired
no-request control at 19.774 s. These are source-matched adapter and WSL
renderer measurements, not a human selection or Windows target result.
Wheel sizes above nine retain procedural preview construction; this is a
preview-cache limit, not a native size rule. Exact logs and revision limits are
in `factory-yau.9.27.1`.

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
