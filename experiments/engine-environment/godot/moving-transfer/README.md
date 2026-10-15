# Finite moving-port transfer trial

This isolated experiment transfers the original **three A** from a native rotating
carrier to a real fixed receiver. Launch it with the existing verified engine:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_moving_transfer.py \
  --godot /absolute/existing/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 VERIFIED_LOWERCASE_SHA256 --artifacts /absolute/owned/external/evidence
```

`--check --render` first runs an initial-only wrong-facing native control, then the
headless authority, then real ordinary scene input and three viewport captures.
Each stage must pass before the next starts. Without `--check`, the normal scene
has a 900 second limit; `--duration-seconds 1..900` changes only interactive runs.
The runner never downloads an engine or changes the project's default scene.

| Input | Action |
| --- | --- |
| F | Toggle source on/off when its current goal has completed |
| N | Request one inherited signed 20:40 source goal |
| R | Toggle repeated source requests |
| T | Toggle one automatic contact request per measured visit |
| P / Q | Submit a new local request to transfer one A |
| C | Submit fresh P and Q requests together, in that order |
| D | Retry P's last request identity and payload |

The ordinary buttons call the same paths as these keys. Cyan cubes show symbolic
cargo counts; they are read-only displays, without item rigid bodies. The cyan
outlet and gold inlet follow actual native poses. The visible gold stub reaches
the inlet beyond the fixed receiver's box face. There is no reset/replenishment
control in this scene; another launch is a separate finite experiment.

`authority.gd` extends the unchanged accepted rotary authority and is the **only**
owner of both the native drive and this trial's quantities. Carrier A + receiver A
is always 3, with integral nonnegative holders. Its B deck retains a stable native
RID, 3 × .35 × 3 box, centre (0, .75, 0), layer 4/mask 1, 20:40 signed goals and
24 natural physics updates per requested turn. Existing source logic, including
its limited translational obstruction query, is unchanged. This trial adds no
claim about angular swept collisions or mechanical docking forces.

The outlet is B-local (1.4, .3, 0), facing local +X. The real fixed StaticBody box
is .55 × .10 × .55, centred at (1.95, 1.05, 0), layer 1/mask 4. Its inlet is local
(-.55, 0, 0), facing local -X; this point overhangs the box's left face by .275 m.
The box bottom is 1.0, .075 m above the deck top .925 at every yaw. Native body
transforms, shapes, layers, world spaces and RIDs are read from PhysicsServer3D.
An initial-only control rotates the receiver by PI and uses centre (.85, 1.05, 0):
the native port points still coincide at (1.4, 1.05, 0), while facing is wrong.

Before tests, the trial freezes eligibility as distance ≤ .08 m **and** opposing
port facing dot ≥ .995. One successful unit is allowed per measured visit; native
leave and re-entry reopen it. These discrete port, visit and sensor rules are
revisable experimental defaults, not final throughput, dwell or docking policy.

Every natural `physics_frame` boundary reads both actual native bodies and updates
the visit latch, including cuts with no requests. The authority retains an
explicit initial readiness boundary. Startup attempts before native registration
refuse; no observations are silently warmed up or removed. Read-only projection
and renderer calls never advance contact state. Requested angle, previous completed
packet, actual operating basis, prior native outlet, raw angular velocity and
physics frame/cut are separate fields. The existing native sync callback is not
replaced, and no body is force-flushed or manually carried. Godot's pinned
[AnimatableBody3D implementation](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/physics/animatable_body_3d.cpp)
explains why a requested Node transform can differ from native sync. The pinned
[PhysicsServer3D body-state API](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/servers/physics_3d/physics_server_3d.h)
provides the actual angular-velocity query used here.

A new registered local request gets **queued intake**, with `final: false`, a
queue identity, submitted frame and unchanged stock; this is not a transfer
acceptance. The next measured boundary drains fresh requests FIFO, then tries the
automatic request. Each final receipt records exact before/after stock and fresh
native eligibility. Leaving the port before admission can therefore cause an
honest refusal. Automatic requests occur once per visit and use the same final
admission method, including spent-window refusals when a manual request wins.

The local P/Q/sensor request cache stores immutable accepted or refused original
dispositions. An exact retry is looked up before current geometry/stock gates and
returns that historical receipt without moving another unit. Its separate current
observation may differ. Reusing an identity with a changed payload refuses. Queue
acknowledgements and final dispositions are distinct; this trusted in-process
fixture is not an authentication, network, persistence or unbounded service API.
Pending retries can queue twice but finalize once plus a cached duplicate.

`check.gd` consumes the actual native authority headlessly. The copied-only
`observer.gd` autoload attaches before ordinary authority readiness and drives real
keys through `view.gd`; the normal project has no observer autoload. Both share
`probe.gd`. Reports retain every native cut, queued intake, final event and ordinary
input. They exercise pre-ready refusal/retry, detached snapshots/cache receipts,
same-cut P/Q competition, unsupported moving edit refusal, no-request leave and
re-entry, separated ports (including a labelled backend distance-only refusal
whose facing still passes), altered payloads and invalid one-unit types, a moving
manual admission competing with the sensor, a subsequent moving automatic
admission, exhaustion, and historical replay after leaving and after exhaustion.
The two moving admissions must differ from both previous completed and requested
goal bases, have consecutive native displacement and nonzero raw angular velocity,
and be followed by further actual native movement. The final scene must actually
stop with no pending goal or transfer; submitting a stop toggle is insufficient.
The moving edit API is
unsupported even when stopped; no construction interface or general edit policy
is proved. The larger passenger/harvesting/transfer outcome remains open.

The Python runner additionally checks literal port math, contiguous physics cuts,
FIFO completions, stable native identities, immutable replay, typed conserved stock
and visible token counts. It captures source/config/runner/binary hashes and actual
engine PID/PGID/exit/reap evidence. It uses the existing supervisor and one worker
group per serial runtime, max one engine, one outer heavy permit, a 30 minute /
256 MiB family allowance and unchanged 8 MiB stage-log / 2 MiB source limits. No
performance, user-play, item-body, multiplayer/save or production-stack result is
implied by this fixture.
