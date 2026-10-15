# First-chapter layout comparison

Status: conditional paper arrangements for `factory-yau.1.2`, 2026-10-14.
This develops the provisional softmetal/plate/channel candidate in
[first-chapter-challenge.md](first-chapter-challenge.md). Nothing here selects
game rules, parts, dimensions, unlocks or a simulation implementation. These
are reasoned operating sequences, not constructed or playtested machines.

## Shared assumptions that need review

- One complete press head forms one blank into one plate against an anvil. Its
  gravity-driven ram has an actual downward stroke and a mechanical stripper
  leaves the plate in its nest when the head rises. The nest fits the *finished*
  plate, not just the smaller blank. Material behavior remains a proposal.
- Each nest has a supported floor at the press and a mechanically opened floor
  at discharge. The stationary anvil carries pressing load; a flap hinge or the
  carrier drive bearing must not secretly carry the whole press load.
- A one-blank escapement feeds an empty nest. A receiving chute must accept its
  plate before the unload mechanism advances. Mechanical occupancy/backpressure
  stops are required; an overflowing chute cannot silently delete output.
- A shared cycle shaft drives repeatable cams/indexing and the press in fixed
  phase. Carrier movement has a **finite dwell**, not merely an instant of zero
  velocity. Dwell/index mechanisms, stripping, floor release and escapements
  are additions to the challenge's coarse vocabulary that need explicit review.
  They are fixed mechanisms, not configurable timers or general sequencers.
- Belts bring blanks to local hoppers and carry plates away. Shaft branches,
  gears and couplings power the mechanisms. When backpressure or an obstruction
  prevents a coupled cycle, the accepted drivetrain stall/isolation rule applies.
  Exact contact handling and restarting an out-of-phase machine remain open.

Without those responsibilities, the following drawings are incomplete. A
layout cannot claim unattended operation by assuming perfect manual loading,
instant pressing, parts falling through an anvil, or guaranteed empty output.

## R: indexed rotary carrier

Top view, clockwise travel; one nest at each quarter-turn position per track:

```text
                      P: press + supported anvil
                                  [P]
                           .-------^-------.
 blanks --> raised F      [F]      O       [D] --> plate drops below
 hopper / escapement       '-------v-------'
                                  [E]
                          E: empty return sector

                    F -> P -> D -> E -> F
              O: hub; bridge supports stay outside swept nests
```

One cycle-shaft revolution indexes the table one quarter turn, then holds it
locked. During the dwell, F loads one blank, P presses the previously loaded
blank and D empties the previously pressed plate. Four nests per track allow
those operations at different stations. After filling the pipeline, one track
produces one plate per cycle; each individual nest takes four cycles to return.

| Phase | Carrier and press | Feed/discharge |
| --- | --- | --- |
| Clear and index | Ram fully raised; table advances a quarter turn | Both escapements closed; all nest floors closed |
| Locate | Table locked; P floor backed by the fixed anvil | Align the empty feed nest and receiving chute |
| Work during dwell | P descends, forms, then retracts; stripper retains plate | F releases one blank; D opens its floor, empties and recloses |
| Reset | Ram clear before index drive can advance | Gates and floors finish returning before movement |

The cycle drive supplies the ordering. The press cam turns once per index
cycle, while the carrier averages one quarter turn; it is not a continuously
rotating table slowed down by a 4:1 gear pair. Gear meshing reverses direction,
so count mesh reversals or add an idler to preserve the drawn F→P→D route.
An ordinary free-running table under a stationary dropping head is rejected:
slower rotation does not create the required stationary work interval.

The feed nest has already discharged at D and passed E. If discharge cannot
finish, the common cycle stops before that occupied nest comes around to F;
the feed cannot cover an old plate with another blank. A coupling can isolate
this production unit from another branch, not let its press run on while its
own table is stalled. A missing input produces an empty pass, not an item.

### Grow one rotary unit

Add concentric tracks, each with its own F/P/D stations. All share the quarter
index, but the table, bridge and radial station banks grow outward. Put support
posts outside the complete swept envelope or at the central hub; a convenient
post through a nest's orbit makes the arrangement impossible.

For a comparison sketch let `p` be a clearance pitch large enough for a finished
plate and nest at every orientation, and let track radii be
`r_j = r_0 + j p`. Choose the inner radius so adjacent quarter-position nests
also clear: their centre separation is `sqrt(2) r_0`. These are continuous
envelope measures, not selected block sizes or construction-grid dimensions.

With `n` tracks, outer radius grows approximately as `r_0 + (n-1)p` plus nest
clearance. Its bounding square grows with radius squared, while the number of
presses and plates per index grows with `n`. A part travels roughly `pi r_j`
from F through P to D. Widening changes the sweep, bridge span, travel and
station access in both horizontal directions; extra heads alone do not explain
the cost. Outer nests also move farther per index, so equal cycle duration and
unchanged drive load cannot be assumed.

## G: fixed-stroke gantry with an orthogonal working bank

Top view; `x` is travel and added lanes extend along `y`:

```text
                       x: fixed travel d -->
                dock x=0                    press x=d
 lane 3    hopper / lower outlet  <---------->  P3
 lane 2    hopper / lower outlet  <---------->  P2
 lane 1    hopper / lower outlet  <---------->  P1
           [one cross-carrier holds a nest for each lane]
           ^ extend carrier, dock and press bank in y

           edge rails guide the same x stroke; no orbit
```

At the dock, finished plates unload **first**, floors close, then one blank
loads per empty nest. The carrier travels to the press bank, dwells while all
heads form and retract, then returns carrying the plates. The dock's upper
feed and lower discharge share a plan position but operate sequentially;
opening both gates together would mix incoming blanks with outgoing plates.

| Phase | Carrier and tools | Material state per lane |
| --- | --- | --- |
| Dock dwell | Carrier held at x=0; press bank is clear | Discharge old plate downward, close floor, then load one blank from above |
| Outbound | All floors/gates closed; carrier travels +d | One blank retained in each filled nest |
| Work dwell | Carrier held at x=d on supported anvils; heads descend and retract | Blank becomes one retained plate |
| Return | Heads clear; carrier travels −d | Plate stays in nest until next dock dwell |

A fixed-cycle dwell cam/linkage or a reversing drive with a mechanical dwell
supplies these intervals. Merely hitting an end stop and reversing instantly
is insufficient for loading and pressing. The same master drives the press
cams and carrier cycle; route a fixed shaft along the press bank, not through
the moving cross-carrier. Gear phase coordinates the two events, while positive
location holds the carrier during a stroke. No independently ticking timer is
assumed to remain synchronized after a stall.

To add a lane, extend the cross-carrier, dock, press bank and transverse power
distribution along `y`. Keep `d` and the length of the motion-axis rails the
same. Widen/reposition edge supports as necessary; a wider carrier still costs
structure, stiffness, drive force and loading/discharge infrastructure. It is
not an infinitely long weightless bar. Each part's out-and-back path remains
`2d`, unlike an outer carousel track's longer circular route.

The approximate sweep is `(d + end clearances) × (n p + edge clearances)`:
growth is mainly in one horizontal direction. That is a geometric benefit of
shared fixed travel, not a claim of free throughput from duplicating heads.
An elongated bank may not fit a compact site that suits a small R; G also
returns without productive forming and can spend substantial time at its dock.

## The shared vertical rule is operational

Side section through a loading/discharge dock and a separate press station:

```text
 z+       blank hopper             ram lift and drop envelope
          [one-item gate]                 |   v
                v                        [HEAD]
 z=0      [nest / closed floor]  ------>  [nest]  <-- tool's downward face
                |                      [ANVIL]  <-- solid load support
                v  only while unloading
 z−       receiving chute / belt
```

The press requires clear stroke/lift space above its tool face and a support
path below the work. Gravity loading needs a higher source; floor discharge
needs a lower receiving volume. The support at P must not occupy D's outlet
or the gantry dock's drop path. Raising the working deck or using a designed
ledge provides that volume without assuming early terrain excavation.

A flush-on-solid-ground machine cannot discharge through its floor. An output
belt at nest height cannot receive this downward-only release without another
handling mechanism. Turning the proposed gravity ram sideways also removes its
drive premise; it is not the same arrangement rotated for free. Alternative
valid ejectors, feeds or tool drives may change those constraints and should be
allowed if the eventual vocabulary supports them. No minimum-height recipe
tag, universal material decay, or automatic clearance UI is being selected.

## Flat rolls: a different A route, not a guaranteed upgrade

Place equal-radius roll shafts across the feed direction. An external gear
mesh reverses their angular directions so both surfaces at the nip pull +x:

```text
 side view:       upper roll ↺
 blanks -> guide === nip -> supported plate -> belt edge -> lower receiver
                  lower roll ↻
                  shaft axes point into the page; inlet/outlet stay clear
```

A hopper/escapement presents one aligned blank to the supported inlet; the
rolls must grip and pull it through. Flat tooling makes A; the provisional
channel profile makes B. Outlet support must fit the finished part and clear
it before the next blank enters. Gearing needs sufficient forming force and
compatible feed speed; neither a same-direction pair that pushes one face
backward nor an unsupported magical handoff through the nip is a working line.

This eliminates the press carrier's load–index–dwell–return handling cycle,
but adds paired drives, guidance, a long supported material path and forming
requirements. It may reduce height at the forming station; any raised supply
and downward outlet still occupy real levels. Faster gearing alone is an
overclock control, not the claimed design reward. No measured speed, energy,
yield or cost advantage is asserted.

| Arrangement | Potential advantage | Cost or condition that can reverse it |
| --- | --- | --- |
| One widened R | Shared indexed transport, separate feed/work/discharge stations | Outer radius, travel, bridge and annular access grow together |
| One widened G | Fixed travel; lanes grow perpendicular to it | Wider carrier and banks; combined dock dwell and unproductive return |
| Repeated small rotary units | Also permits roughly linear total envelope growth | Repeats hubs, index drives, station plumbing and maintenance access; a serious alternative to G, not an omitted control |
| Flat-roll A | Continuous pull-through can remove cyclic presentation work | More feed guidance and paired power; actual material/force and capacity benefit unproven |

Presses remain valid for small batches, existing sites, or footprints where a
roll line's supported path is awkward. Compare equal useful output and the
same feedstock; shared drives still pay for every operating head. If rolls do
not earn a worthwhile benefit, revise the challenge rather than forbid old A.
If old tools can form B through a valid arrangement, preserve that invention
and reconsider the new-process lesson rather than impose an arbitrary lock.

## Evidence required next

Reviewers can trace a single blank and an empty pass through every phase above;
check nest/finished-part envelopes, dwell ordering, support and gravity paths;
and enlarge each drawing by one lane without moving its goalposts. These are
paper feasibility arguments conditional on the listed parts, not test results.
Missing dwell, stripping or backpressure parts must return to the chapter
packet as explicit vocabulary choices, not disappear inside an all-purpose head.
If those parts make early construction too complicated, revise the process or
chapter. Removing dwell while keeping the same stationary-press drawings is
not a simplification that still works.

The later fixture must exercise wrong gear direction/phase, occupied output,
missing input, real forming clearances and coupled stall/isolation, including
restart assumptions. Build/diagnose/expand play evidence and source lifecycles
remain separate tasks. Detailed collision responses, injury/docking rules,
engine/physics model and numerical game/network budgets remain untouched.

Sources: [challenge proposal](first-chapter-challenge.md),
[reference experiences](../../DESIGN.md#reference-experiences-supplied-by-the-user),
[construction and movement](../../DESIGN.md#construction-and-movement),
[early motion and stalls](../../DESIGN.md#complexity-and-automation),
[3D construction](../../DESIGN.md#genuine-use-of-three-dimensional-space),
[method tradeoffs](../../DESIGN.md#progression-expands-capability-and-removes-manual-work),
and [review findings 1 and 4](../../DESIGN_REVIEW.md#prioritized-findings).
