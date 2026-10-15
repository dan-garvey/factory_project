# Spatial scaling and top-face access

This isolated experiment compares two mechanism layouts and a real directional
work-access rule. It extends the [mechanics probe](../mechanics/README.md) by
composition: its unchanged `authority.gd` owns every source and branch phase.
Each spatial head consumes only the drive's completed B phase. The spatial
owner waits for the head's native RID transform before querying or publishing.
The opening, item Model, Store, multiplayer fixture and project default stay
unchanged. This is not an additional item or recipe owner.

The useful operation is a **non-consuming top-face inspection** of immutable
coupons. Native ray queries from the head's actual oriented lower face must
reach a coupon's upward face before any other solid. A native hit's point,
normal and collider determine eligibility. This is a geometric encounter probe,
not production, harvesting, a gravity simulation or a selected game tool.
It provides a functional reason for a head above its work with clear access:
reversing its face, lowering its mount below the work, or interposing a real
shield prevents inspection while the carrier continues its unchanged cycle.
The shield lies below the moving carrier and never collides with it; this work
access refusal does not replace the connected-drivetrain obstruction rule.

## Fixed experimental geometry

Coordinates are arbitrary fixture units with y up, not selected voxel sizes.
There are two baseline coupon centers at `(-2,0,0)` and `(2,0,0)`; growth adds
`(-2,0,3)` and `(2,0,3)`. Each native coupon box measures `0.5 × 0.2 × 0.5` and
has a top face at y=0.1. Its collision layer is 16. Head boxes measure
`0.4 × 0.4 × 0.4`, centered at y=1.2. Their collision layer/mask are zero: this
probe does not test carrier collision or arbitrary rotating assemblies.

Each head's ray starts 0.2 units along its local downward face and extends 1.2
units along that direction, querying layers 16 and 32. Top-face inspection
requires downward direction and upward native normal with dot product >0.99.
[Godot's ray query](https://docs.godotengine.org/en/stable/classes/class_physicsrayqueryparameters3d.html)
returns the first native solid encounter. The shield is a `5 × 0.1 × 4` box at
`(0,0.55,1.5)` on layer 32, or explicitly parked at y=5 in the clear control.
A reversed head rotates 180 degrees about z; its ray points up. A low mount has
head center y=-0.6, so its downward ray cannot reach the higher work face.
The distinct far mount retains the downward face but raises its center to
y=2.4: its ray ends at y=1.0, above the same coupon, discriminating finite reach.
The empty control removes the actual coupon colliders.

A source request advances the inherited source by pi/8. Default 20:40 idler
gearing gives completed B phase pi/16 per request; 32 requests cover one full
unwrapped cycle. A gantry head follows `x=2 sin(B), z=0`; its grown version adds
a second head at z=3 without changing stroke. A rotary head follows
`x=2 cos(B), z=2 sin(B)`, zero angle along +x. Its declared grown arrangement
adds a concentric head at radius sqrt(13), reaching the same extra coupons.
These are two particular arrangements, not proof all rotary designs must grow.
Heads stay facing down; no rotating tooth/arm collision is simulated.

Finite coupon extents and the declared pi/16 sampling matter: the grown rotary
sites near 56.31 and123.69 degrees fall within coupon faces at the nearby56.25
and123.75-degree samples. The probe records discrete encounters; it does not
claim continuous material coverage between samples. A future higher speed or
smaller face could alias a contact and would need a swept-contact rule.

| Arrangement, 32 source requests | Unique coupon faces | Real drives / heads | Native head-path x / z span |
| --- | --- | --- | --- |
| Baseline gantry | 2 | 1 / 1 | 4.4 / 0.4 |
| Baseline rotary | 2 | 1 / 1 | 4.4 / 4.4 |
| Grown gantry | 4 | 1 / 2 | 4.4 / 3.4 |
| Grown concentric rotary | 4 | 1 / 2 | 2sqrt(13)+0.4 / same |
| Two baseline rotary rigs, second translated z=3 | 4 | 2 / 2 | 4.4 / 7.4 |
| Overclocked baseline rotary, unchanged reach, 20:20 | 2 of 4 | 1 / 1 | 4.4 / 4.4 |

These bounds enclose sampled native head boxes. The full-cycle samples include
both axis extrema, so they match this declared ideal center-path envelope plus
head extent. They are not complete factory, supports, power-routing, swept
collision or access envelopes. The two real duplicated drives remain a viable
solution; overclock completes two B cycles without reaching another row.
Head/drive counts are construction proxies, not prices, torque, power budgets,
measured throughput, balance or a universal gantry advantage. Eligible samples
can repeat on retained coupons; unique faces and exact request/cycle counts are
reported separately and create no products.

## Run and inspect

Use the existing verified engine, shared heavy admission, and an external
artifact directory. No download or installed-engine change is performed:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check_scaling.py \
  --godot /absolute/path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --artifacts /absolute/path/outside/git/spatial-scaling --render
```

The run is bounded to20minutes,128MiB retained aggregate artifacts, one engine
at a time, with per-stage timeouts. It copies and hashes exact source/runner
bytes, uses an isolated profile, performs real `--check-only` before runtime,
and preserves the first failed stage/log. Neutral Model checks run unchanged.
The original mechanics implementation/control sources remain unchanged; their
accepted evidence is reused, not claimed as a new full mechanics execution.

Eleven actual fixture cases run through the same authority in headless and real
rendered consumers. Each records initial state plus32 completed requests,
native head and inherited slider transforms, actual shape extents/layers,
independent native contact queries,
full owner snapshots and precise point/normal traces. Python's independent
segment/AABB oracle checks each known path, coupon/shield first hit, unique
coverage, eligible samples, exact source cycles and native box bounds. Its
expected sites do not come from the authority's hit counter. Rendered checks
also verify actual mesh positions against native RIDs and save a real PNG.
Every parent-drive completion separately witnesses the still-owned child-native
window: another step, source change and construction edit are refused without
changing the prior published observation. Outer completion occurs exactly once
after head-native synchronization.
This is additional geometry coverage, not an old-failure regression claim.

For supervised manual exploration, use the copied project's explicit
`res://scaling/main.tscn` entry point with `-- --case=rotary_grown` (any case key
in `authority.gd`). Space starts/pauses, N requests one advance; right-drag
orbits and wheel zooms. The default project startup remains neutral. The
fixture is configured before entering the scene tree; construction changes
are refused after admission and during requests. Launching another case is
an explicit fresh fixture reset, not editing a running machine.

No user play, production process, inventory, gravity, harvest/transfer, player,
train, network/save, arbitrary angular/continuous swept collision, scale,
performance or permanent engine/camera/tool/process adoption is established.
