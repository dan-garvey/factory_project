# Physical character and nearby construction

This is the thin implementation contract for the stationary opening. The user
requires a controlled physical character and nearby building; later technology
may extend reach. Stationary machines and subfactories have priority. Camera
perspective, the final range, movement tuning, line of sight and technology
recipes remain open. These are reversible demo defaults, not production
architecture or requirements imposed by Godot.

The current baseline has no opening character. `model.gd` owns entities,
carried parts, material, command order/cache and checkpoint validation;
`opening-session/session.gd` binds P/Q connections to commands and publishes
projections. `opening/opening.gd` currently converts a camera ray to grid cells
and uses `PITCH = 1.65`; that ray identifies a requested target, never the actor.
The existing rider controller is reference evidence for native collision only.

## One physical producer, one game authority

Chapter implements `opening/actor_world.gd`, a native character/collision adapter
reused by the offline opening and the dedicated shared server. It owns the
actual bodies, floor and machine colliders and advances them on native physics
updates. It publishes their actual native body origins to the existing Model.
It never owns item quantities, build permissions or command results. Shared
views render the server's actor projection; they do not run a second controller
whose reported position grants permission.

Platform extends Model with actor position/capability state and runtime native
readiness. The shared Session owns input binding and instantiates the same
adapter; the offline view uses it directly. A client can submit a bounded
movement direction/jump input for its bound actor, not a position, speed,
capability, physics epoch or another actor's name. The server chooses movement
steps, speed and collision. Holding an input cannot choose elapsed time or
teleport distance. Prediction, anti-cheat and rollback are outside this change.

Agreed prototype producer API:

| Adapter operation | Responsibility |
| --- | --- |
| `configure(model)` | Attach to the existing authority, with no second Model. |
| `ensure_actor(actor)` | Create the declared actor's body from its authority-owned saved position, or explicit new-world spawn; never replace a restored position with a spawn. |
| `set_control(actor, world_xz, jump)` | Accept finite bounded world-space XZ `Vector2` direction and a jump edge from the trusted local/server binding. |
| `release_control(actor)` | Clear held direction/jump on focus loss, disconnect and rebinding; keep position and inventory. |
| `sync_topology()` | Reconcile stationary colliders from authoritative entities after accepted build/load operations. |
| `pose_published(actor, sample)` | Signal a plain-value actual native position/readiness/epoch to the trusted Model bridge; this is not a game command or RPC. |

The offline binding controls P; shared Session binds P/Q. A trusted callback
passes the sample to `Model.publish_actor(actor, position, native_epoch)` and
controls readiness. Missing actors do not fall back to camera position. The
producer exposes read-only diagnostic native body RID/origin/world/epoch and
input/release observations for consumer evidence; those RIDs are not durable
actor identities or a second source of game state.

Projection exposes `actors[P/Q]` with `position: [x,y,z]`,
`capabilities: {build_reach: 4.0}`, `ready: bool` and `native_epoch: int`.
Position is the actual collision body's origin, not a mesh, camera, desired
movement target or caller argument. Readiness and epoch are runtime metadata;
the adapter must first observe the body registered in the correct native world
at its declared initial/restored position. Until then, construction refuses
`actor_unready`. Subsequent samples describe actual completed native state.
No forced physics flush or Node pose is accepted as a completed native sample.

The admission boundary must use the latest actual native sample available to
that authority and record its epoch. An adapter publication and a command cannot
be interleaved through user callbacks to use a stale desired pose. Producer and
consumer must agree their sampling/admission order before their first trial.
Movement updates do not consume material request IDs or increment build order;
Session still issues monotonic projection serials when actor state changes.
Only the current connection binding can change held input. Late input from an
old peer refuses after disconnect/rebind. Movement input schemas reject extra
pose, capability, epoch, actor and elapsed-time fields rather than trusting them.

## Shared geometry and the provisional reach rule

Chapter owns `opening/site_geometry.gd` as the single definition of site pitch
and target anchors used by the adapter, views and Model. The initial pitch is
the existing 1.65 world units. A ground-grid cell `[x,z]` has the neutral work
anchor `[x * 1.65, 0.5, z * 1.65]`. Existing entities resolve their anchors from
their authoritative cells; callers cannot supply an alternative nearer point.
These anchors are declared interaction references, not claims about tool faces
or physical surface distance. The opening still has a single ground grid; this
does not implement stacked construction.

The initial capability is a sphere of radius 4 world units about the actual
body origin. A target is reachable exactly when all three coordinates are
finite and `distance_squared(actor, anchor) <= build_reach * build_reach`.
Equality is allowed. Height contributes fully; horizontal distance alone is
insufficient. There is no extra permission epsilon, camera-distance test or
cursor-distance shortcut. Floating-point rendering comparisons may have a
separately stated observation tolerance, never a larger game reach radius.

The base capability is authority-owned and configurable at world creation,
not settable through player input. The initial physical profile allows only its
declared base value. Persist and validate it explicitly so a later technology
can introduce an intentional extension without inventing that progression now.
Reach grants no parts, stock withdrawal, delivery or teleportation.

| Command | Authoritative references that must all be reachable |
| --- | --- |
| `place` | Requested validated cell anchor. |
| `remove` | Current entity's anchor. Existing held-stock/stopped-edit rules still apply. |
| `connect`, `connect_drive` | Both current entity anchors, checked together at admission. Selecting the first endpoint reserves no permission. |
| `disconnect`, `disconnect_drive` | Both current entity anchors, regardless of link direction. |
| `retrieve` | Current press anchor; no remote pocket transfer. |
| `set_power` | Current waterwheel anchor; a missing wheel is not a remote control target. |

Read-only selection/inspection, camera orbit/zoom, explanation, save and explicit
inventory-goal confirmation do not acquire a proximity gate merely because
construction has one. Explanation-world interactions remain separate from the
worksite. No line-of-sight rule is introduced. The existing power, adjacency,
site, stock, kit and identity checks remain in force; reach cannot override one.

## Admission, refusals and recovery

Model keeps its existing context/client/request identity checks and exact
request-cache lookup **before** evaluating current reach. For a fresh, valid
operation, check targets and current authoritative actor state before its first
mutation. A reach refusal is an ordinary ordered/cached outcome with reason
`out_of_reach` and an instruction to move closer. It consumes no part, shaft or
material and changes no entity, connection, goal or production phase. Unsupported
or malformed targets keep their specific existing validation refusal; they are
not converted into a guessed nearby target.

An exact duplicate returns its original cached outcome after the actor moves.
Changing an old request's contents still refuses request reuse. A deliberate
retry from closer uses a fresh request ID. A queued/held command retains its
original target and identity, and uses current authority position when it is
actually admitted. Moving the camera, moving another player, rebuilding a
selected entity or changing an unsubmitted endpoint cannot retarget an already
issued command. A vanished entity keeps its original missing-target refusal.

Each reach-evaluated fresh outcome retains a plain-value admission receipt:
actor, actual position, native epoch, capability and resolved target points.
Accepted covered operations require that receipt. It is historical evidence,
not a second current actor projection. Schema validation checks receipt types,
finite bounds, permitted capability and reach against the recorded admission
pose and the relevant historical targets. It must not replay an old build
against the actor's final saved position. Existing topology, custody and command
history validation remains mandatory. The checkpoint is not an authenticated
movement log; actual native evidence is required independently.

On shared rejoin, use a fresh connection namespace and the current actor
projection. Keep the body's position and inventory, clear held controls and do
not automatically replay uncertain intents. An old outcome arriving later may
settle its request; it cannot move the body or replace a newer actor projection.
Current snapshot serials and historical outcome revisions remain distinct.
An exact cached outcome while the new body is unready remains an immutable
historical no-op; it does not bypass readiness for a new operation. Capture the
remote sender/binding inside its RPC before any defer/await; never recover actor
identity from a later callback's RPC context.
Movement continues independently of pending build acknowledgements. Opening
help releases held movement without pausing authoritative factory production.

## Persistence and the unrestricted baseline

Use explicit schema 2 for physical-character checkpoints, persisting validated
actor positions and capabilities alongside the existing factory state, command
history and pockets. Native bodies/RIDs, readiness, input latches and the current
physics epoch are not restored as live state. Historical admission-receipt
epochs remain persisted as inert evidence and never make a new body ready.
This first increment saves pose and capability only: restored velocity starts
released at zero, with no claim of continuous saved momentum or jump phase.
On reopen, rebuild bodies at the saved positions,
release controls and establish fresh native readiness before admitting work.
Do not snap a body into a safe spawn if its saved position cannot be realized.
The first physical increment supports save and reopen in a fresh isolated
session. In-scene Load explicitly refuses `load_requires_restart`, preserving
the current world and save; UI explains reopening instead. This is a scoped
adapter/prototype limitation, not a Godot restriction or permanent game rule.
A new session must
validate the candidate and realize its saved bodies without overlap before
publishing a playable world or accepting construction. Failure aborts that new
session and preserves the original input, with no fresh-world fallback. Natural
gravity after an evidenced correct initial registration is motion, not a spawn
conversion. Later live replacement requires geometry/native preflight before
atomically replacing Model and adapter; accepting Model first and failing after
losing the live world is not an acceptable implementation.

The normal offline and shared launchers select the physical profile explicitly;
legacy unrestricted harnesses must identify their fixture profile. Absence of
an actor or failed restore never switches the normal opening to unrestricted
permission. The caller fixes this profile before reading a save; incoming
options/schema cannot downgrade it. The normal physical profile explicitly
refuses schema-1/unrestricted saves as
`physical_state_required`, without changing the current world or original file.
There is no silent safe-spawn migration, pose invention, range grant or kit
refill. The old schema-1 baseline remains supported by explicitly identified
legacy harnesses; it is historical unrestricted evidence, not physical-character
compatibility. An explicit migration can be a later task. Store continues to
delegate validation to Model and retains its existing bounded verified atomic
publication; no separate file-side actor authority is introduced.

## Ownership and acceptance sequence

Platform owns this document, then Model/Session/Store admission and compatibility
under 5.21. Chapter owns the adapter, site geometry and offline/shared character
views under 6.36. Coordinate new source paths and concrete signatures before
editing; do not alter another owner's frozen checkout. Recovery reviews identity,
history, continuation and legacy handling. Playability's 6.37 independently
validates the combined actual character and enforcement candidate. Root owns
current-main integration and the Godot/game-requirements register.

Concrete source ownership: Chapter owns new `opening/actor_world.gd`,
`opening/actor_body.gd`, `opening/site_geometry.gd` and the opening view changes;
Platform owns `model.gd`, `opening-session/session.gd`, the dedicated server,
Store/launcher compatibility and core reach checks. Existing frozen UI changes
and check/runner input lists must be joined deliberately. One owner updates each
shared launcher or input-list file at a time, with a handoff for dependent paths.

Initial character defaults are a capsule radius 0.3/height 1.8, walk speed 3,
gravity 14 and jump speed 6 in world units, subject to actual collision evidence.
Use an orbit third-person demo camera, camera-relative WASD, Space to jump and P
to operate the nearby wheel. Labels/help must explain approaching the wheel;
P does not promise a global stop. These controls are not the final perspective
or movement design. Chapter records the explicit new-world P/Q spawns and site
bounds before its first runtime; saved positions never use those spawn defaults.

Current machine pickers are existing static bodies. Chapter isolates pickers to
layer 4/ray mask 4; the adapter alone supplies floor layer 1, fixed machine
layer 2 and actor layer 16 collisions. Share the existing machine box dimensions
(1.45 by 1.65 by 1.45, centre height 0.8) in site geometry so a view picker is
not a second physical obstacle. These are adapter defaults, not game construction
rules. If Model imports the shared geometry module, update every minimal
core/save/network copy manifest deliberately. Changes to central shared helper
inputs require the existing independent tooling review; omitting the dependency
or weakening the physical rule is not a substitute.

The contract unblocks parallel implementation only after Chapter and Recovery
agree the concrete seam. A documentation/source gate cannot prove the character,
server or game rule works. Required combined evidence includes:

- Real ordinary movement and collision, nearby placement and the finite
  collector/belt/press/retrieval loop, with the actual controlled actor visible.
- Near, far, vertical, equality and just-outside cases; camera-only changes and
  spoofed actor/pose/capability inputs cannot grant permission. Both connection
  endpoints must pass. Include actual refusal with exact parts/stock unchanged.
- Two real bound actors at different positions, movement across the boundary,
  exact duplicate refusal after movement and a fresh successful request.
- Delayed admission using the current position without target replacement;
  disconnect/rejoin clears input, retains position and does not replay work.
- Save/reopen with a new native process/body and preserved positions,
  capabilities, factory, pockets and cache; explicit atomic legacy refusal and
  malformed/non-finite/unauthorized capability rejection.
- Normal source/index/all-GDScript/hook checks plus bounded actual consumers,
  exact source/copy/runner/binary/process-group provenance and independent review.

The numeric range, target height, body shape, speed, spawn, orbit camera and key
bindings must be recorded as probe/demo choices. No production anti-cheat,
network responsiveness, permanent movement/camera choice or moving-world result
follows from this work.
