# Godot and prototype constraint register

Updated 2026-10-15 UTC against accepted source `ecd80b486066fe78d7e8e3ed6483981c3599f438`.
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
The official `stable` documentation linked below was checked on this date; it
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
No new engine invocation, backend switch, download or precision build was used
for this document audit.

| Evidence anchor | What it supports | What it does not establish |
| --- | --- | --- |
| `a7d4cce` rotary rider, [authority](../../experiments/engine-environment/godot/rotary/authority.gd) and [fixture](../../experiments/engine-environment/godot/rotary/README.md) | Real native operating poses and an unparented local passenger, with explicit request/completion clocks | Arbitrary angular clearance, networked passengers or a complete physical factory |
| `e967cbc` [train probe](../../experiments/engine-environment/godot/train/README.md) | Coupled kinematic carriages and a real local passenger | Freely simulated train dynamics, moving-save or multiplayer movement |
| `d1e32f0` [retrieval continuation](opening-recovery.md) and `e7eb73e` [shared opening](../../experiments/engine-environment/godot/opening/shared_opening.md) | One bounded stationary authority, interrupted retrieval custody, inspection/reconnect feedback | Adversarial movement admission, internet reliability, crash durability or user play |
| `ecd80b4` [moving-port probe](../../experiments/engine-environment/godot/moving-transfer/README.md) | Native sampled port geometry and finite transfer ownership | Continuous contact, real item bodies, campaign logistics or a production network join |
| `2e8665f` [exact-count bench](../../experiments/engine-environment/godot/precision/README.md) | Exact material quantities, retained work and recovery | Floating-point spatial precision: its directory name is not a coordinate-precision benchmark |

**Observed** below means a named code path or retained bounded consumer witness.
**Documented** means an upstream API contract, with no broader runtime result.
**Unknown** means the current evidence cannot decide it. These confidence labels
qualify the claim, not a score for the engine. Full local receipts and independent
review pins remain in the owning Beads; the linked tracked consumers are reusable.


## GDC-01: engine-coupled rules are not an independent core

**Adapter, observed.** [model.gd](../../experiments/engine-environment/godot/model.gd)
uses GDScript, `RefCounted` and Godot value/container APIs. Running it headlessly
removes graphics, not its runtime dependency. Scene physics has additional coupling.

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

## GDC-03: a character API is not the game's movement design

**Engine/API plus fixture.**
[CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)
provides scripted collision/movement APIs with floor, slope and platform settings.
Our [rider controller](../../experiments/engine-environment/godot/rider/player.gd)
chooses a capsule, gravity, walk/jump values and collision masks for a local probe.

**Boundary/exit:** these choices do not fix the game's body dimensions, speed,
jumping, camera or injury model. A physical controlled character and limited
construction proximity are user requirements, not Godot defaults. The opening
still needs that integrated controller/authority/reach join; a rider success does
not supply it. Owners: Chapter and Platform; `3.11`, `5.21`, `6.36`, `6.37`
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
checkpoint continuation. It does not establish adversarial movement validation,
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

## GDC-08: a planar construction fixture does not make this a flat game

**Adapter/fixture, observed.**
The opening's [model](../../experiments/engine-environment/godot/model.gd) accepts
a small two-coordinate placement grid; its [view](../../experiments/engine-environment/godot/opening/opening.gd)
picks a worksite plane. The current builder has no integrated physical character
or proximity admission. These are current implementation gaps, not Godot limits.

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

The actual Compatibility/WSLg captures establish the inspected 1280×800 controls
and text. Pending inspection and disconnect feedback have their own declared cuts;
a decorative panel entering a footer edge is not a whole-window layout proof.
There is no current certification of other resolutions, input devices, rendering
backends, packaging or accessibility. Keep picking/camera and authority separate;
validate the actual character-building consumer as its UI changes. Owners: Chapter,
Playability and Ops; `6.36`/`6.37` and actual-user feedback `6.11`.

## Required follow-through

This first source/API/evidence audit leaves actual backend identification,
far-origin precision, concurrent factory scale, predictive movement and moving-save
behavior explicitly unknown. Owners must add a scoped measured follow-up when
one becomes necessary; unknown is not a claim of impossibility. No exhaustive
runtime characterization was performed for this register. New engine/backend
versions, authority/controller changes and newly discovered restrictions must
update this register with their actual impact and evidence. PM checks it during
hourly reviews. Do not postpone stationary chapter work for an exhaustive engine
comparison, and do not mark this maintained register permanently finished after
its initial audit.
