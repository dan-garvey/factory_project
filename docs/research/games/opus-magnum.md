# Study: Opus Magnum — machine design, optimization and feedback

Status: **partial**, source study in progress; not thoroughly studied.
Study Bead: `factory-yau.8.4`. Owner: factory-ops. Checked 2026-10-15 UTC.
Scope: original campaign's design principles as described in 2017/2019 developer
interviews, dated 2022/2024 player-authored worked examples, and later developer
updates. No executable build
is pinned and no first-hand play, installation or purchase occurred. Current
base-game mechanics must not be inferred unchanged from those interviews.

This note follows the [continuing research contract](../README.md) and
[template](../STUDY_TEMPLATE.md). It supplies original candidate adaptations,
not levels, copied recipes or new requirements. The physical-character,
nearby-building and stationary-first direction in [DESIGN](../../../DESIGN.md)
takes precedence. No duplicate study was found in open/closed Beads.

## Evidence and source map

| Source | Date / coverage actually read | Supported claim and limit |
| --- | --- | --- |
| [Official game page](https://www.zachtronics.com/opus-magnum/) | Checked 2026-10-15; About section | Machines, open-ended solutions, speed/simplicity/compactness and sharing; marketing is not a control manual |
| [Barth and Burns, Road to the IGF](https://www.gamedeveloper.com/business/road-to-the-igf-zachtronics-i-opus-magnum-i-) | 2019-02-18; minimum tools, creative solutions and tinkering sections | Developers describe emergent combinations, physical arm motion, cost/area/cycle objectives and optional optimization without an in-game optimization reward; not a current-build mechanics specification |
| [Developer Q&A transcript](https://www.gamedeveloper.com/business/dev-q-a-zachtronics-team-on-building-personality-into-puzzles) | 2017-11-14; story, GIF and skill discussion | Product purposes and mechanical problems developed together; readable repeating motion helps explain a solution. No video timestamp claimed: the transcript was read |
| [Official update archive](https://store.steampowered.com/news/posts/?appids=558990&enddate=1774910502&feed=steam_community_announcements) | Entries dated 2022-01-17, 2024-01-15, 2026-03-17/22/24 | Collision validation and conflicting dual-grabber pivots have changed; 2026 adds a halt instruction and changes a journal output requirement. This is a dated archive window, not verification of the latest build |
| [Official De Re Metallica page](https://www.zachtronics.com/de-re-metallica/) | Checked 2026-10-15 | Separate later campaign, new glyphs and second-half-like difficulty; its puzzle content is outside this first pass |
| [Official ZACH-LIKE page](https://www.zachtronics.com/zach-like/) | Project Lightning and Codex sections | Historical prototype lineage and discarded approaches; the full design book and prototype were not accessed |
| [omsim README](https://raw.githubusercontent.com/ianh/omsim/master/README) | Community implementation, checked 2026-10-15; supplementary only | Explicit unsupported behavior and track-reset discrepancies make it unsuitable as unquestioned game ground truth; no clone/build/execution performed |
| [biggiemac42, instruction optimization](https://biggieblog.com/optimizing-instructions-in-opus-magnum/) | 2022-04-09; What Counts, Silver Paint, Tracks, Purified Gold sections | Attributed player-authored examples of repeated tapes, geometric state and finite-output solutions that later congest; historical observations, not developer specification or our play |
| [biggiemac42, Refined Bronze](https://biggieblog.com/defeating-refined-bronze-and-losing-a-cow-bet/) | 2024-02-07; limitations of scoring, movement, latency and instruction-seeking sections | Attributed construction/diagnosis account distinguishing rate, latency and finite completion; current build and records unverified, no example layout copied |

## How the engineering challenges develop

The developer accounts support a small expressive toolset, spatial machine
design and several optional optimization goals. They do not establish the exact
current instruction grammar, glyph activation order, collision shapes, output
validation or campaign unlock sequence. Those remain research gaps below.
The cards therefore distinguish supported inspiration from our own proposed
stationary mechanical problems. Their appeal and teaching effects are hypotheses;
no player study or enjoyment claim follows from developer intent.

**Historical player evidence:** the 2022 author distinguishes a tape loop from
one completed product, demonstrates geometric state persisting across loops and
describes designs that meet a finite goal before clogging. Short instruction
lists can move complexity into long tracks rather than remove it. These are
counterexamples to treating a compact program or a successful finite run as
proof of simplicity or sustained production; they are not current-build rules.
[2022 worked examples](https://biggieblog.com/optimizing-instructions-in-opus-magnum/).

The 2024 account separates first-product latency from sustained rate, and describes
using an instruction-targeted fast-forward to inspect a later execution point.
It also records movement/handoff restrictions, which are source-game rules,
not general physical laws or Godot limits. This is historical player evidence,
not validation of those controls today. It does not establish a rewind/editable
timeline or multiplayer-safe rollback for our game.
[2024 construction and diagnosis account](https://biggieblog.com/defeating-refined-bronze-and-losing-a-cow-bet/).

## Pattern opus-magnum-01: solve an orientation problem through layout

- **Goal and setup:** candidate here: send a finite blank through two stationary
  work faces, then deliver it in the required orientation. Begin with complete
  stations and a small set of visible transport/turning components.
- **Player verbs:** approach, place, rotate, connect and inspect components;
  run the mechanism and revise while stopped. Do not require a program editor.
- **Constraints:** actual work-face direction, attachment clearance and physical
  access are hard constraints. Route length is initially only a soft incentive.
- **Solution families:** reorient the blank at a turntable; rotate/reposition a
  complete station; use a longer route with a different approach. These trade
  footprint and parts against mechanical complexity.
- **Appeal:** inferred: the player can explain success from visible geometry,
  rather than guessing an arbitrary recipe or clicking a prescribed arrangement.
- **Failure and recovery:** expose the missed face or clearance; retain the blank
  at its real holder, allow stopped correction, then resume without spawning one.
  Avoid a bypass that accepts every face, or maintenance requiring repeated hand turns.
- **Teaching:** one face first, then the second orientation. The second station
  enables a different useful product, rather than merely another output multiplier.
- **Adaptation / engineering risks:** stationary 3D layout with internal motion;
  no travelling factory. Tool contact, obstruction, quantity custody and admission
  need declared rules. A top-down view must not grant remote building permission.
- **Falsifier:** if every orientation works, or only one visibly premarked layout
  can work, the proposed spatial decision is absent.
- **Sources / disposition:** physical-arm/toolset inspiration from the 2019
  developer interview; the blank, stations and alternatives are original
  **candidates**, not verified Opus Magnum mechanics or selected implementation.

## Pattern opus-magnum-02: trade separation for coordination

- **Goal and setup:** candidate here: two fixed stations share a constrained
  working region while each must complete its operation on the retained workpiece.
- **Player verbs:** separate stations, reroute delivery, change mechanical phase
  or isolate a branch. Give an early low-control solution using more space.
- **Constraints:** incompatible simultaneous occupancy must be observable; a
  prescribed phase number must not be the only correct answer. Timing controls
  belong later unless the player can solve the early version geometrically.
- **Solution families:** independent wide lanes; compact sequential use with a
  mechanical interlock; later coordinated parallel machinery. Compare robustness,
  footprint and explanation burden, rather than demanding one fast schedule.
- **Appeal:** inferred: coordination can buy compactness that the player chooses.
- **Failure and recovery:** show which work regions conflict, stop the connected
  drivetrain under DESIGN's rule, retain material and support isolation/restart.
  Never repair a bad schedule by losing a workpiece or resetting the factory.
- **Teaching / automation:** teach separate lanes before phase alignment. A solved
  mechanism must repeat without the player releasing a clutch every cycle.
- **Adaptation / engineering risks:** ordinary fixed-place machines; this requires
  meaningful swept clearance or a declared equivalent, not endpoint screenshots.
  See [Godot constraints](../../engineering/godot-constraints.md).
- **Falsifier:** if waiting forever or placing everything far apart removes every
  meaningful tradeoff, refine the task or defer it; do not add arbitrary timing chores.
- **Sources / disposition:** developer arm-motion discussion and dated official
  incompatible-pivot/collision fixes motivate the question. This card's shared
  work region and stall/recovery are our **candidate adaptation**, not a claim
  that Opus Magnum uses our collision or recovery policy.

## Pattern opus-magnum-03: working completion before optional refinement

- **Goal and setup:** candidate here: build a stationary line delivering the
  required useful component, then optionally improve that same design.
- **Player verbs:** build, test, inspect real input/output accounting and compare
  saved designs. Optimization is a player choice, not a compulsory rerun tax.
- **Constraints:** correct product and conserved quantities are hard. Parts cost,
  footprint and throughput are independent soft measures; no single weighted
  score is assumed to represent everyone's preferred engineering result.
- **Solution families:** reuse one slower station; duplicate complete stations for
  throughput; shorten routing for space; accept more parts for readable robustness.
- **Appeal:** inferred: the first valid solution establishes competence while
  giving a curious player reasons to revisit a functioning mechanism.
- **Failure and recovery:** preserve a working design when experimenting, and
  disclose whether a comparison measures startup, finite completion or steady rate.
  Prevent an empty source or hidden stock cache from producing a misleading score.
- **Teaching / automation:** teach completion before metrics; subsequent learning
  should add new capabilities. A valid line should work unattended, regardless
  of whether its owner chooses optimization.
- **Adaptation / engineering risks:** actual physical parts/location and nearby
  construction remain meaningful. Comparison aids must not clone campaign stock;
  hypothetical previews and real-world edits need distinct ownership.
- **Falsifier:** if every objective favors the same topology, or players must
  optimize merely to escape a tedious wait, these measures add little choice.
- **Sources / disposition:** the 2019 developers explicitly distinguish optional
  optimization and its several metrics. Our production line, preservation and
  measurement rules are **candidates**, not adopted game systems.

## Pattern opus-magnum-04: distinguish a productive cycle from a good opening burst

- **Goal and setup:** candidate here: two stationary arrangements produce the
  first few components, but only one clears its reusable work holders. Diagnose
  the difference before supplying the rest of a finite, declared blank batch.
- **Player verbs:** inspect holders and outputs, stop and drain safely, reroute
  returns or provide a legal outlet. No periodic manual clearing is a solution.
- **Constraints:** count supplied, held, rejected and delivered material together.
  A completed product is insufficient if the mechanism quietly fills another
  indispensable holder. State the observation window and remaining input.
- **Solution families:** one spacious serial route that fully releases its jigs;
  a pipelined route with enough independent holders and a return path; a clearly
  labelled finite-batch process where manual reset is an intentional different task.
  Do not silently call that last family unattended factory automation.
- **Appeal:** inferred: the player learns to recognize a reusable system rather
  than meeting a number through stockpiling or an attractive animation.
- **Failure and recovery:** retain the congested work and holder identity. Let a
  real outlet drain it before changing the route; no reset, free extra holder or
  deletion of rejected material. A finite source becoming empty is a different
  condition from internal congestion.
- **Teaching / fit:** start with one visible full return bin, then an optional
  pipeline. This suits the existing stationary backpressure vocabulary; first
  search current opening evidence before proposing another experiment.
- **Engineering risks:** quantities and return-path state need one owner across
  pause and save. Repeated samples can support a bounded cycle claim, not prove
  arbitrary programs productive forever.
- **Falsifier:** two layouts with identical early output but different later
  congestion must be distinguishable through actual holder/flow evidence. Reject
  a task solvable only by waiting longer or by an undisclosed infinite buffer.
- **Sources / disposition:** the 2022 player's finite-prefix counterexamples
  motivate this original **candidate**. No source puzzle, scoring threshold,
  infinite-input rule or reset policy is imported.

## Pattern opus-magnum-05: let mechanical position remember the next operation

- **Goal and setup:** candidate later challenge: a fixed indexing fixture must
  expose successive work faces to a shared tool, then release the completed
  piece and return the empty holder to its intake position.
- **Player verbs:** arrange indexing stops, gear relationships, tool orientation
  and return routing. Later clutches or cams may coordinate it; an early version
  must offer a simple complete machine or remain deferred.
- **Constraints:** the same holder must traverse the required sequence. Its
  position and phase are state; returning one arm to its start is not proof that
  the workpiece, other holders and shared tool have also reset coherently.
- **Solution families:** a larger single indexed fixture; several dedicated
  stationary operations connected in series; later reuse of a compact shared
  operation with a mechanically enforced sequence. Compare access, part count,
  clearance and ease of diagnosis rather than minimizing controls at any cost.
- **Appeal:** inferred: a visible physical arrangement can explain sequencing
  without introducing an abstract programming language in the opening.
- **Failure and recovery:** stop at a readable misalignment, retain the piece
  and allow disengagement/rephasing under a declared rule. Avoid compulsory hand
  indexing, a hidden timing exception or a reset that invents a fresh workpiece.
- **Teaching / automation:** teach one orienting operation first. The later rig
  must release, return and accept another blank without the player counting turns.
- **Engineering risks:** persistent phase, holder identity, working contact and
  obstruction need explicit semantics. Source-game collision exclusions and
  timing tricks do not choose our sweep or drivetrain behavior.
- **Falsifier:** if the visual index disagrees with actual work admission, or
  one special phase is merely an unexplained password, this is poor mechanical
  teaching. A paper state trace should explain each transition before a runtime.
- **Sources / disposition:** persistent geometric state in the 2022 player
  examples inspires this original **deferred** card. No alchemical level, tape
  program or source-game movement limit is reproduced.

## Synthesis and proposed follow-ups

The most immediate hypothesis is orientation/layout using complete stationary
machines. Compact coordination is later vocabulary; importing an instruction
timeline into the opening would conflict with gradual control progression.
Optional refinement looks promising, but numerical scoring and comparisons have
not been selected. Card 04 strengthens the distinction between finite completion
and unattended flow; card 05 belongs after basic physical production and
understood mechanical controls. None authorizes gameplay work by itself.

Before extending or closing this study, investigate actual representative
input-to-output construction, exact assembly requirements, early versus advanced
tool vocabulary, finite completion versus repeatability, and the feedback available
when a run fails. A looping GIF alone cannot prove indefinite production or
recovery without a reset. Dated 2026 base-game changes mean excluding the DLC is
insufficient to treat 2017 instruction descriptions as current behavior.

## Coverage and review ledger

- Covered so far: attributed design intent, several optimization dimensions,
  readable internal motion, product purpose, dated version-change cautions and
  historical player examples of finite versus repeating operation, geometric
  sequencing and diagnosis. These are source observations, not our play.
- Remaining: detailed control/glyph/quantity rules, representative progression
  and scaling challenges, actual failure diagnosis/recovery, steady repetition,
  current production-cabinet restrictions and current-build differences. Historical
  cabinet examples were read, but no representative current campaign play was
  observed. De Re Metallica, a systematic tournament/exploit survey and the full
  ZACH-LIKE book remain outside this pass.
- Independent review: Playability accepted the starter at `f3f0f1f` for partial
  publication; Recovery separately accepted the `1cb671a` successor delta after
  checking both attributed player sources. Root reviewed the full five-card
  note and both review scopes before catalogue integration on 2026-10-19.
  Claims and cards are unchanged from that frozen successor; this remains
  partial publication, not thorough-study or gameplay acceptance.
- Closure: `factory-yau.8.4` stays **in progress**. The continuing parent
  `factory-yau.8` stays open. SpaceChem `8.5` remains a distinct queued study;
  it is not evidence that the gaps here are resolved.
- Next owned action: obtain primary or explicitly attributed representative
  control/feedback evidence, then revise cards and arrange source/adaptation
  review. Character/reach implementation and the Godot audit take precedence.
