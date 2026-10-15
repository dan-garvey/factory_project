# Rotary passenger probe

An optional local experiment toward `factory-yau.4.4`, following the
[linear passenger probe](../rider/README.md). An actual colliding player boards
a real rotating native deck. No player carry offset or transform parenting is
used. The original player controller, goal-phase mechanics, quantities, opening,
shared session, Store, default startup and bounded supervisor stay separate.

WASD walks; Space jumps. D and Space board the stopped deck from the ground.
F enables/pauses the source, N requests one gear step, **Repeat fixed cycle**
requests the next step when available, and R starts a fresh fixture. Right-drag
orbits and the wheel zooms. An already owned turn reaches its goal; stopping
Repeat prevents the next turn. This is a fixed-cycle test, not an expressive
controller or a final stopped/docked construction policy.

The unchanged phase owner requests positive 20:40 gear goals: each source step
of pi/8 requests B pi/16. The rotary subclass keeps B's centre `(0,0.75,0)` and
its actual `3×0.35×3` box. It follows a declared operating path through **24
physics updates per goal**, then waits for the native goal basis before publishing
completion. Each substep assigns the full unit basis at its absolute angle, so
native synchronization cannot accumulate scale into the fixed-size deck.
This is a reversible trajectory choice, not a production speed or
numerical performance target. U remains parked and the work-encounter area is off.

Requested goal, operating native pose and completed goal are different facts.
The deck view reads its actual native basis throughout each turn; finished-step
counts read native completion. A basis equal to an endpoint is insufficient proof
of a whole revolution: the check reconstructs signed unwrapped angle from every
native basis, including all substeps and intermediate poses.

The rider is the same separate `CharacterBody3D`, using its own real input,
native gravity/collision and platform velocity. Actual boarding supplies an
off-axis local radius between 0.3 and 0.5. The full standing trace, including
pending turns, must retain floor identity and the initial actual local pose
within 0.015; native basis/goal checks use 2e-5. No radius or tolerance changes may
turn a failed carry into success. A full 32-goal cycle, an eight-goal quarter-turn,
walking during a turn, a jump/landing, ordinary step-off and fixed-wall collision
are separate observations. These do not prove player enjoyment or final feel.

Use the existing verified executable and its exact lowercase SHA256:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_rotary_rider.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 VERIFIED_LOWERCASE_SHA256 --artifacts /absolute/owned/rotary
```

Ordinary entry is positional `res://rotary/main.tscn`. The default allowance is
900 seconds; `--duration-seconds` selects 1–1700 within the 30-minute total. Do not
leave normal play unattended. No engine is installed or fetched.

`--check --render` runs actual input and native physics in both consumers and
captures the actual quarter-turn passenger view as `rider.png`. The reused
per-physics collector retains every provisional target and pairs it with a
fresh native query before the next physics callbacks, with explicit input/source
epoch and engine-frame+1. Missing/coalesced native ticks fail; a separate actual
view clock can run more slowly without deleting physics evidence. Native shapes,
RIDs, centres, bases, floor identities and reported linear/angular platform
velocity remain in the report. The velocity getters describe the reported floor
contact after `move_and_slide`, rather than its exact pre-move solver input.
The independent Python oracle reconstructs the winding, trajectory and actual
local rider pose. Measured walk input plus that post-move floor velocity must
explain displacement within 0.02 as an approximate consistency check.

Two clearly labelled additional fixture API controls compare reverse initial
gearing and native platform following disabled. They change genuine native motion
and support; they are not player construction or new UI permissions. Normal entry
uses the positive fixture. `--smoke` instead reads actual normal startup through
a disclosed copied-project autoload, records distinct config/source hashes,
captures the view and exits. It cannot combine with `--check`; `--render` requires
`--check`, and duration selects normal play only.

The shared rider hooks retain the linear scene as their default. Its real
headless/rendered/native/normal checks must still pass after those hooks change.
No guard, pin, version, floor, job count or artifact limit is relaxed: one existing
engine, one outer heavy permit, 30 minutes/256 MiB aggregate evidence and 8 MiB per
log. Keep every first failure and source identity, not an unchanged retry-green.

The clear site avoids rotating machinery obstructions. This is **not an angular
obstruction sweep**, torque or damage proof. Injury, independent pushing, trains,
passenger networking/correction, moving harvest/conserved transfers, persistence,
construction and full 4.4/M6 acceptance remain separate work. No production stack
or game-scale performance claim follows from a bounded local passenger result.
