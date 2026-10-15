# Two-branch mechanical fixture

Experimental gantry/linear-clearance probe for the
[mechanical risk brief](../../../../docs/proposals/mechanical-risk-fixtures.md).
The basic opening is separate and unchanged. This fixture creates no items,
recipe, inventories, save files or networked gameplay; it owns only its mechanism.
The existing Model, Store, ENet and default project startup are not modified.

One `authority.gd` Node3D owns source/branch phase, gearing, coupling, construction
mounts and actual native physics bodies. Its physics-frame admission uses
[PhysicsBody3D.test_move](https://docs.godotengine.org/en/stable/classes/class_physicsbody3d.html#class-physicsbody3d-method-test-move)
with the real slider shapes and world obstacles before committing any connected
phase. Headless and rendered consumers instantiate the same authority. The view
submits commands and renders projections; it never moves the physical bodies.
Step completion is published at the next physics boundary after native body
integration. The single pending request remains owned until then; a changed Node
pose inside its earlier callback is not a completed physics observation.
`projection()` labels current requested/Node phase and poses tentative whenever
`native_pending` is true. Its `completed` snapshot contains the last coherent
native poses, phase and completed-step count; the view renders those facts with
a pending label until publication. Geometry commands acknowledge requested
configuration as `geometry_pending`; an immediately queued step remains owned
until native body/obstacle geometry matches before its sweep. This is a local
fixture boundary, not a network request or save protocol.

## Declared fixture, not game tuning

- Coordinates use one arbitrary construction unit, y up. Initial mount cells are
  B `[0,0]`, U `[0,3]`; initial setup may move U to `[0,4]`. Construction edits
  are admitted only before source advancement and while stopped. This chooses no
  universal stopped/docked edit or building rule.
- Each explicit drive step adds pi/8 source phase. U receives positive half-rate
  rotation. B uses 20:40 gears (half rate) or 20:20 (unit rate); one external mesh
  reverses B, an idler restores its sign. These are ideal kinematic relationships,
  not a tooth-collision or torque simulation.
- Slider x displacement is `2 sin(branch_phase)` from its retained construction
  mount. A default positive 20:40 cycle is 32 admitted steps, passing both fixed
  endpoints and returning to its initial pose without resetting unwrapped phase.
  Non-grid intermediate collider positions are part of this linear-motion proof.
- Actual slider boxes are 0.55 x 0.8 x 0.8, centered at y=0.75. They sweep against
  native solid layer 1. An optional 0.35 x 1.5 x 1.1 blocker sits at x=1.4 in B's
  lane or is explicitly parked at z=6. A rejected swept step commits no partial
  movement: source, B and U retain their prior phase/pose when K is engaged.
- A non-solid work-encounter Area3D sits at x=1.6 in B's lane. Native overlap
  records entry events only after admitted motion. It is a non-consuming fixture
  signal, not harvest, material production or a second stock owner. Matched input
  advancement with reversed gearing misses this actual encounter; ratio changes
  when it occurs. This is useful driven behavior beyond decorative gear angles.
- Opening K isolates B immediately; U and source may advance while B retains its
  phase/body. Re-engagement requires source stopped and input/output shaft phases
  aligned modulo one revolution within 1e-5. The test advances the isolated input
  a full output revolution, removes the blocker and re-engages without phase or
  member reset. That is a declared test coupling, not adopted docking policy.
- Sliders occupy separated lanes; only linear slider/static-solid clearance is
  claimed. Gear meshes are visual; angular swept collision, moving/moving
  collision, train-like machinery, passengers, injury, harvesting, transfer,
  moving save/rejoin and rotary/gantry scaling remain unproved.

## Verification and visible consumer

From the repository root, with the existing verified executable:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check_mechanics.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --artifacts /absolute/owned/mechanics-evidence --render
```

The runner downloads nothing and copies a small explicit project whitelist to a
new external directory with private XDG/cache/tmp paths. It reuses the shared
bounded process supervisor: one engine at a time, 30 minute run allowance,
headless 30s/import and rendered 180s, 8MiB logs, 256MiB aggregate artifact root,
and existing resource admission floors. Failures retain their first logs and
receipt; no cache/diagnostic cleanup is automatic. This is not a benchmark.

It runs the unchanged neutral assertions, then `res://mechanics/check.gd`
headlessly with native physics. With `--render`, the same checks instantiate
`res://mechanics/main.tscn`, exercise real Space input and capture the viewport.
Other scenario commands use the same view handler; this is not an entire
player-operated build session. Both structured reports face an independent
Python oracle and must agree within the declared 1e-5 fixture tolerance.

The checks pair clear/blocked paths, positive/reversed mesh parity, 20:40/20:20
timing, a complete fixed cycle, rejected moving edits, whole-drivetrain stall,
actual U-only collider continuation and misaligned/aligned coupling recovery.
An independent physics-frame observer reads engine body RIDs and probes actual
world overlap at moved and old construction positions. It cannot pass merely
because a mesh or parent transform moved. Machine-body identity survives the
stall/isolation/restart sequence. Explicit fresh scenes reset between independent
cases; the recovery case never resets its mechanism.
Every one of the 84 admitted steps additionally records the integrating and
earliest completed native boundary. Duplicate step and topology requests refuse
while pending; completed native poses must match the published outcome before
the next sweep. Source/U advance exactly once and isolated B remains retained.
These are separate boundary controls, in addition to the original retained
187-check old-failure/new-success regression evidence.
An added obstacle/removal case queues its next intersecting step immediately
after the geometry command, without a test-only synchronization wait. The first
sweep must block after insertion and clear after removal. Initial mount edits
also precede immediate drive admission; native poses are verified on completion.

`result.json` records exact revision, copied-source and runner hashes, stage exits
and failures. `physics.json` and `view.json` retain authoritative and independent
physical observations; `view.png` is visual evidence only. The scene itself is an
explicit entry point for this isolated fixture, not the default opening. Its
controls are Space start/pause, N step, O move blocker, K isolate/engage, right-drag
orbit and wheel zoom. No unattended interactive session is launched by the check.
