# Linear passenger probe

An isolated local technical experiment toward `factory-yau.4.4`. A real player
collision body boards a moving deck, rides, walks relative to it, jumps, lands
and steps off onto fixed ground. Primitive visuals and character feel are
reversible test choices. This is separate from the basic opening and workshop.

WASD walks in world directions; Space jumps. Move right with D and jump to board
the stopped deck. F starts/pauses the source, N advances one step, and **Repeat
fixed cycle** operates the existing step cadence. R starts a completely fresh
local fixture. Right-drag orbits and the wheel zooms. Closing the window ends
the bounded normal session.

The unchanged [mechanics authority](../mechanics/README.md) owns source phase,
20:40 positive gearing, admission, native obstruction and completed publication.
The subclass turns its existing B native body into a `3×0.35×3` passenger deck,
enables `sync_to_physics` for that body, parks unused U outside the site and
disables the encounter area. B's center follows `x=2 sin(B phase)` at y=0.75.
Eight fixed steps reach x=2; the ninth begins the return. Enabling synchronization
is a fresh engine boundary requiring evidence, not inherited proof from the
earlier tool-head fixture.

The player is a separate root `CharacterBody3D`, with a radius 0.3 / height 1.8 capsule,
2 units/second walking, gravity 14 and jump 6. It uses native `move_and_slide`,
floor contacts and moving-platform velocity. It is never parented to the deck,
and no script applies a carry offset or repositions it after its initial spawn.
The ground starts at y=0; the deck top is y=0.925. A fixed wall's near face is
x=4.875. These are fixture units, not chosen game or voxel dimensions.

The deck occupies collision layer 4 and queries machinery obstruction layer 1.
The player occupies layer 16 and collides with layers 1/4; its native platform
following filter includes layer 4. This fixture tests floor support; it does not
define crushing, injury, a passenger stopping machinery, independent pushing or
construction/docking rules.

[AnimatableBody3D's native velocity estimation](https://docs.godotengine.org/en/stable/classes/class_animatablebody3d.html)
and [CharacterBody3D's platform following](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)
motivate the probe. Documentation is not pinned-runtime or gameplay evidence.

Use an already verified engine and its exact lowercase SHA256:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_rider.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 VERIFIED_LOWERCASE_SHA256 --artifacts /absolute/owned/rider
```

Normal entry is the actual positional `res://rider/main.tscn`. Its default
allowance is 900 seconds; select 1–1700 with `--duration-seconds`, within the
30 minute total bound. Do not leave normal play unattended. No engine is fetched.

`--check --render` instead exercises the actual player, key/button paths and
native physics in headless and rendered consumers. It records raw native RID
poses/shapes/layers, slide contacts, floor identity and platform velocity. It
retains provisional samples inside the player's movement callback, then pairs
every target/identity/tick with a fresh native observation at the **next physics
frame signal, before new controller callbacks**. The engine physics-frame number
is explicitly one greater; the player's input tick still identifies the prior
move. Its source/input/contact snapshot and the observer's current source state
are kept separately. Missing or coalesced native ticks fail. Neither the immediate callback
nor `call_deferred` is a completed native transform boundary: the pinned
[SceneTree processing order](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/main/scene_tree.cpp)
flushes transform notifications after deferred callbacks. No observer forces a
flush or moves a body.

The joined native completed cut verifies player RID/target equality, actual deck
RID/phase/completed publication and floor support. A separate view observer after
the ordinary refresh checks the latest player/deck meshes against actual native
poses. A slower renderer may consume fewer snapshots; every physics target still
has its own native completion. The existing Drive's
advanced event is separately checked for the deck; it does not assert that the
player's callback has already completed. All pending native handoff samples stay
in the report, bounded to one physics tick per step and followed by that step's
joined completion. The original first run and its premature samples are retained;
correcting this observation cut does not change the movement/controller code.

The Python oracle checks the inherited phase law, native deck coordinates,
standing drift ≤0.015 at every joined completed cut, walk displacement against actual
input duration within 0.02, reversal, jump/landing, wall contact and retained
identities. The actual standing-rider viewport is captured. Input durations are
measured independently; matching source outcomes does not imply identical
headless/rendered player trajectories.

An explicitly labelled additional native API control sets only the player's
`platform_floor_layers=0`: the same deck moves while the grounded player stays
behind. This distinguishes native following from parenting or scripted carry;
it is not an exposed player control or a new game rule.

`--smoke` observes the real normal startup using a disclosed copied-project
read-only autoload, captures the grounded player and exits. Original, post-import
and instrumented configuration/observer hashes are recorded separately. It cannot
combine with `--check`; `--render` requires `--check`. Duration selects normal
play only and is refused in check/smoke modes. CLI guard tests use valid fixture
paths/hashes and require the intended refusal, rather than an unrelated error.

All modes use the existing bounded helper, one engine at a time, one outer heavy
permit, original disk/memory floors, a 30 minute total and 256 MiB aggregate
retained evidence (8 MiB per log). Source/staged compilation and native runtime
results are separate. Keep first failures; a repeated green run cannot erase them.

There are no items, resource proxies, harvest, production, transfers, inventory,
networking, persistence, injury or a construction editor here. This does not
complete `factory-yau.4.4` or its multiplayer passenger/correction witness:
rotary/train-like carriage, moving harvest and conserved moving/fixed transfers
remain separate work. No production character controller, stack adoption,
game-scale performance or actual human-play claim follows from this probe.
