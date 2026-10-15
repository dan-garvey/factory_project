# Godot and prototype constraint register

Updated 2026-10-15 UTC against accepted source `ecd80b486066fe78d7e8e3ed6483981c3599f438`.
Godot use is approved for current development. This register prevents the
modeling framework from silently defining the game. It is an initial inventory,
**not an exhaustive engine audit**; `factory-yau.3.10` owns that first audit.

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
Platform and Ops; first build/backend/precision audit in `factory-yau.3.10`.

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

## Required follow-through

Ops audits exact backend/build behavior, precision, lifecycle and source citations;
unknowns stay visible rather than being resolved by assumption. New engine/backend
versions, authority/controller changes and newly discovered restrictions must
update this register with their actual impact and evidence. PM checks it during
hourly reviews. Do not postpone stationary chapter work for an exhaustive engine
comparison, and do not mark this maintained register permanently finished after
its initial audit.
