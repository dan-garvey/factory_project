# Coupled carriage passenger experiment

An optional next moving-world experiment: an actual independent player walks
between two separate moving native carriage bodies. This is a technical slice
toward the intended game's trains, following the linear and rotary passenger
experiments. It does not select a full railway system or a chapter unlock.

The original signed phase authority drives both original B/U bodies. Fixed
positive 20:40 gearing makes their phases equal. Their literal centres are
`(2 sin(phase), .75, 0)` and `(3 + 2 sin(phase), .75, 0)`. Each native box is
`3 × .35 × 3`, so their top faces meet at one joint. Both use layer 4 and native
platform following; the unchanged player uses its own gravity and collision.
No player parenting, manual carry transform or body replacement crosses the joint.

The straight path is a controlled assembly transform. The fixed-cycle steps
retain the accepted linear fixture's discrete native motion and bounded completion
handoff. Rails are visual guides; no wheel/rail solver, flexible coupler, smooth
train speed, steering or free rigid-body train dynamics is claimed. The wall at
X=9 lies beyond the assembly's full X envelope `[-3.5, 6.5]`.

WASD walks, Space jumps, F enables/pauses the source, N requests one step,
Repeat fixed cycle requests subsequent steps, and R starts a fresh fixture.
Right-drag orbits and the wheel zooms. Board the front gold carriage using D and
Space, start the source and Repeat, then walk onto the blue carriage. The displayed
support identifies the actual carriage. Both meshes and finished-step counts
consume the single completed native packet.
Initial publication also verifies both actual native centres against their
literal phase goals. Matching a Node to its old native pose cannot declare a
queued configuration complete; the meshes stay hidden until that first packet.

The input check boards B, rides to the first reversal at goal 8, crosses to U
while real Repeat input drives both carriages, and rides U through goal 24 and
home at 32. It then pauses, jumps/lands on U, leaves onto the ground, and walks
into the fixed wall. Crossing must retain native support from B or U and show a
real floor-identity handoff with the same player and carriage RIDs. Both native
shapes, poses and fixed separation must match their literal phase law. Contacts
at the joint can overlap; separate B-only and U-only support windows must lie
farther than the capsule radius from that joint. Identical platform velocities
alone cannot identify which carriage supports the player.

The inherited observer retains each provisional input and its fresh native result
before the next physics callbacks, at engine frame +1. No target may be dropped
or coalesced. A source-only completion event is distinct from player completion;
one pending native handoff tick remains visible. Standing local offset must stay
within .015 after native completion; pose/separation checks use 2e-5. Crossing
displacement must agree with measured own-input duration within .02 relative to
the coupled path. The actual view has its own observation clock; the extra mesh
is checked there and at source completion, rather than inferred from an input
snapshot. First failures
and exact source identities remain evidence, never an unchanged retry to green.

Use the existing verified executable and exact lowercase SHA256:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_train_rider.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 VERIFIED_LOWERCASE_SHA256 --artifacts /absolute/owned/train
```

Normal play enters positional `res://train/main.tscn`; it defaults to 900 seconds,
with `--duration-seconds` allowing 1–1700. Close the window to finish; do not leave
normal play unattended. `--check --render` instead runs actual headless and
rendered input and captures the rear-carriage view. `--smoke` reads ordinary
startup through a disclosed copied-project autoload and captures the initial view.
These modes stay separate. One existing engine, one outer heavy permit and the
original 30-minute/256-MiB/8-MiB-log limits apply; no engine is downloaded.

The automated witnesses exercise this bounded local fixture. The original linear
and rotary consumers must remain validated when their shared hooks change.
Full moving harvesting, conserved transfers, networking, persistence, editing policy, injury/pushing,
angular obstruction, user enjoyment, performance and production adoption remain
separate work.
