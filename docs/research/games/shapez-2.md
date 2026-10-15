# shapez 2: spatial processing, persistent factories and readable faults

Status: reviewed source study scoped below. Study Bead: `factory-yau.8.7`.
Owner: factory-recovery. Last checked 2026-10-15. This is a set of candidate
puzzle patterns, not adopted game rules. No completed shapez study existed in
the catalogue or all-status task search when this leaf was claimed.

## Evidence and source map

This study covers vanilla shapez 2's spatial processing and logistics as described
by tobspr Games: the April 2026 1.0 Classic/Manufacture split, the June 2025
Dimension update, July 2026 troubleshooting guidance and August 2026 1.2 notes.
Earlier stacking, crystal and simulation devlogs explain design decisions, with
their dates retained below. No game was installed or played for this study; no
exact installed build, measured throughput, player reaction or current mod
behavior is established. An announcement describes shipped intent, not an
independent play observation. In particular, early alpha handling details are
historical evidence and need a current-build check before implementation.

The official Steam announcement feed was inspected through 2026-10-02. Its last
numbered shapez 2 update in that snapshot is 1.2; that does not establish the
latest executable hotfix. Later announcements about the separate puzzlez project
are outside this study. No DLC, modpack, community blueprint or hexagonal campaign
has been evaluated.

| Source | Date and scope | Evidence used and limit |
| --- | --- | --- |
| [Stacking, devlog 003](https://steamcommunity.com/games/2162800/announcements/detail/3712697417374567226) | 2023-04-21; alpha design | Support, falling groups and pins were intended to make difficult transformations intelligible. Do not treat its first pin-pusher implementation as the current specification. |
| [Crystals, devlog 009](https://steamcommunity.com/games/2162800/announcements/detail/3650785607754834895) | 2023-09-15 in the app feed; early development | Negative-space molds and handling restrictions change operation order. Exact modern adjacency/shatter rules remain unverified. |
| [Simulation, devlog 027](https://steamcommunity.com/games/2162800/announcements/detail/4469355336712585839) | 2024-11-28; demo/early-access comparison and planned changes | Compatible ports, occupied lanes and matching launcher/catcher arrangements explain flow and blocking. Its optimization claims are not our performance evidence. |
| [Dimension update](https://steamcommunity.com/games/2162800/announcements/detail/526468444896364471) | 2025-06-02; release notes | Platform-level vertical routing, overflow splitting, previews and throughput explanations. No numerical balance is assumed to survive later updates. |
| [Manufacture, devlog 037](https://steamcommunity.com/games/2162800/announcements/detail/534374481398857999) | 2026-02-05; prerelease rationale | Continuous trade-station supply keeps earlier factories useful; alternate conversions introduce choices. Announcement warns balancing may change. |
| [1.0 release](https://steamcommunity.com/games/2162800/announcements/detail/518618855026721216) | 2026-04-23; shipped modes and interface | Confirms Manufacture's permanent-factory direction; distinguishes introductory Certification from Classic and Manufacture. Documents incompatible old saves. |
| [Troubleshooting a factory](https://steamcommunity.com/games/2162800/announcements/detail/684131849711128933) | 2026-07-09; developer guidance | Reusable operation modules, belt-based rate comparison, downstream bottleneck tracing and backward wrong-item diagnosis. This is advice, not observed player success. |
| [1.2 release](https://steamcommunity.com/games/2162800/announcements/detail/672876654794637787) | 2026-08-13; compatibility and maintenance | Blueprint migration and branch-specific preservation matter to reusable designs. No claims about engine suitability for this project follow from its engine update. |

The developer's [game overview](https://shapez2.com/) also describes freely
replaceable buildings, inexhaustible sources, multiple construction layers and
open machines. Those conditions substantially reduce experimentation costs;
our carried parts, finite stock and physically nearby character cannot inherit
them implicitly.

## How the engineering challenges develop

The ordinary loop extracts a shape, changes it with processing machines and
routes the result to a delivery goal. Delivery unlocks additional tools. Free
construction and replacement let players explore layouts without first making
the buildings' ingredients. The official overview describes later wire-based
automation and configurable production, but this study does not establish an
exact make-anything-machine design or its correctness. These are different
challenges from supplying physical carried components near a character.
[Developer overview](https://shapez2.com/).

**Documented behavior:** shape processing includes cutting, rotation, stacking
and coloring. The historical stacking proposal makes unsupported pieces settle;
the crystal proposal fills a prepared void and penalizes certain later handling.
These make the *order and geometry* of transformations matter, rather than merely
requiring another intermediate item. The simulation article separately describes
blocking when a lane lacks room, and transfer depending on compatible paired
ports. [Stacking](https://steamcommunity.com/games/2162800/announcements/detail/3712697417374567226),
[crystals](https://steamcommunity.com/games/2162800/announcements/detail/3650785607754834895),
[simulation](https://steamcommunity.com/games/2162800/announcements/detail/4469355336712585839).

**Inference:** a useful puzzle has at least two plausible arrangements whose
different outcomes follow from a visible rule. Extra machines alone do not supply
that distinction. A transformation puzzle asks *when and from which direction*;
a logistics puzzle asks *where flow and clearance can coexist*; a scaling puzzle
asks *which scarce capacity must change*. A diagnostic puzzle lets the player
locate the cause without knowing the intended answer in advance.

**Documented progression contrast:** Manufacture was introduced because solved
one-off tasks could leave factories without a purpose. Its trade stations need
continuing supply, while Classic retains the more individual shape challenges.
The launch guidance places introductory learning before this larger factory
mode. [Manufacture rationale](https://steamcommunity.com/games/2162800/announcements/detail/534374481398857999),
[1.0 modes](https://steamcommunity.com/games/2162800/announcements/detail/518618855026721216).

**Project inference:** keep a small subfactory useful after its first successful
product, but introduce a new handling or spatial decision when expanding it.
Indefinitely increasing a delivery number would preserve activity without adding
a new process. All cards below are original proposals; their numbers are puzzle
fixtures, not measurements or recipes from shapez 2.

## Original pattern cards

### Pattern shapez2-01: Support the work before releasing it

**Objective and verbs:** make an offset bracket that must remain at a working
height while a side operation completes. Place a support, orient the work,
connect the drive, stop it, remove the support and carry the finished bracket.
Start with one blank, one tool and two reusable supports, with room to rebuild.
This borrows the historical stacking devlog's idea that loss of support should
have an intelligible consequence, not its shape alphabet or exact solver.

**Constraints and satisfaction:** the bracket must occupy a marked working
envelope; the tool approaches from one side and the character needs physical
access to the fastener. Correct support must allow that approach. Stable placement
is a hard requirement; compactness and fewer handling steps are soft goals. The
payoff is explaining a failed arrangement by contact and clearance rather than
guessing a hidden recipe.

**Solutions and tradeoffs:** support from below with a longer feed path, or clamp
from the opposite side using more fixture space. A wide accessible rig is a valid
beginner solution; a tighter fixture trades spare space for careful sequencing.

**Failure, recovery and shortcuts:** premature release leaves identifiable work
in a catch area; stop and recover that same item. No disappearing material or
automatic successful reset. Infinite adhesive, remote placement and a support
that intersects the tool would bypass the decision. Fixture replacement must be
driven by actual geometry, not periodic wear chores.

**Learning and fit:** first show a single supported object, then obstruct one
approach. Mechanical support and three-dimensional access suit this project;
the completed rig must accept successive blanks without manual resets. Start
with one stationary bench. General falling/deformation rules and moving rigs
are outside this candidate and require their own evidence.

**Engineering risks and falsifier:** one authority must own support/contact
state and the same workpiece across save/reopen; a renderer-only support check
would diverge. The smallest paper/geometry experiment compares an obstructing
bottom support with an accessible side clamp. Reject this card if the declared
geometry admits only one usable arrangement, or a valid automated cycle needs
the player to replace its supports each time.

**Source and disposition:** [dated stacking design](https://steamcommunity.com/games/2162800/announcements/detail/3712697417374567226).
Deferred: needs a support/working-envelope rule beyond the opening.

### Pattern shapez2-02: Shape the carrier, finish the fragile surface last

**Objective and verbs:** deliver a finished insert whose coating cannot survive
the next cutting operation. Shape and orient a reusable carrier, load the blank,
apply the finish, release it and route both product and carrier. The historical
crystal devlog inspires a negative-space/operation-order problem; it does not
establish a real material property for our game.
Start with a finite blank batch, one reusable carrier and a declared finish
supply; no replenishment is assumed.

**Constraints and satisfaction:** the finish must reach a recess, the carrier
must expose that face, and the finished item must exit without a harmful handling
step. The surprise is that building the right absence can be more useful than
adding another solid component. Coating and damage rules must be shown before
they can invalidate a product.

**Solutions and tradeoffs:** finish a fully shaped blank in a simple open jig,
or finish two independently supported pieces before a safe final assembly. A
returning carrier saves repeated part use but adds space, a return route and
possible congestion. Neither approach should be mandatory.

**Failure, recovery and shortcuts:** a bad order produces a visible rejected
piece in a known bin; retain its quantity and decide whether rework exists before
testing. Material must not simply vanish as crystals do in the dated source.
Deleting rejects, free carriers or manually moving every carrier would hide the
cost or defeat true automation. Give a safe way to stop, drain and correct the
line; no random breakage or routine maintenance timer.

**Learning and fit:** teach an exposed face before a recessed face, then offer
the carrier-return optimization. A cam-driven clamp and a fixed applicator could
support mechanical, three-dimensional automation. This is a later stationary
process experiment, not a reason to delay the collector-to-product opening.

**Engineering risks and falsifier:** define ownership of the carrier, coating,
reject and product before simulation; retain those states in continuation. A
small two-order demonstration must make the harmful handling step visible. Drop
the idea if players can only memorize a hidden exception, or if a returning
carrier adds obligatory handling without an unattended solution. No coating or
damage physics has been implemented here.

**Source and disposition:** [historical crystal design](https://steamcommunity.com/games/2162800/announcements/detail/3650785607754834895).
Deferred: material/rework rules and carrier custody are unresolved.

### Pattern shapez2-03: Cross two routes while keeping the worksite usable

**Objective and verbs:** deliver two distinguishable streams across a narrow
stationary worksite without mixing them or blocking the character's route to a
service point. Route, elevate, rotate a transfer, reposition a machine and test
the finished path. The Dimension update is evidence for vertical routing as a
real design axis, not evidence for our eventual elevator mechanics.
Start with two sources, their destinations and a finite kit sufficient for a
wide detour; height is an optional new transport capability.

**Constraints and satisfaction:** use a declared transfer clearance and a marked
walkway, with both stream identities preserved. Those are hard conditions;
footprint, additional shafts and construction effort are tradeoffs. A successful
solution makes a physical crossing legible rather than hiding an edge in a graph.

**Solutions and tradeoffs:** elevate one stream and preserve floor access, take
a wider detour, or move one downstream tool so the streams no longer cross. The
smallest layout need not be the easiest to build or inspect. A beginner can spend
space; an experienced player can reclaim it with a new transport process.

**Failure, recovery and shortcuts:** blocked transfers retain items where they
stop; shutdown and reroute without refunds or silent deletion. A high route that
the character cannot reach must be assembled from an accessible position under
the shared reach rule. Camera movement, clipping and manual item teleportation
cannot solve the puzzle. Keep a usable access path rather than adding repeated
maintenance visits as an artificial requirement.

**Learning and fit:** demonstrate one height transition, then a crossing, then
an optional denser layout. Gravity-fed chutes or shaft-driven lifts are candidate
mechanical implementations; their collision and transfer rules remain open.
Begin with fixed transport and static machinery, with repeated unattended flow.

**Engineering risks and falsifier:** height, collision, transfer and build
anchors must share one geometry definition across offline/shared views and
saved state. A cheap layout comparison needs both an accessible detour and a
legal crossing under the same kit constraints. Defer if either route requires
remote construction, or if camera occlusion makes blockage impossible to read.
Do not introduce detailed lift simulation merely to draw the example.

**Source and disposition:** [Dimension release](https://steamcommunity.com/games/2162800/announcements/detail/526468444896364471).
Candidate after a supported transport process exists; not selected for work.

### Pattern shapez2-04: Find the bottleneck before adding another machine

**Objective and verbs:** sustain a declared output after the first stockpile is
used up. Inspect occupancy, follow the material, split and merge flow, change a
ratio or add a parallel tool. Developer troubleshooting recommends comparing
modules against a common belt rate and tracing where backed-up flow changes;
Manufacture supplies the reason for keeping upstream lines useful.

**Constraints and satisfaction:** use the same finite starting material and
actual item custody. For a paper fixture, suppose supply is four blanks per
cycle and one tool serves two: an extra belt or buffer alone cannot make that
single tool sustain four. Test beyond the initial buffer and report output plus
inventory changes. These illustrative rates are our proposed fixture only.

**Solutions and tradeoffs:** add a second driven tool, improve the tool's process
if an agreed rule permits it, or deliberately accept lower output to serve
another branch. A bounded buffer can absorb an interruption but cannot cure a
persistent rate deficit. Parallel tools cost parts, drive capacity and footprint;
larger buffers cost real space and delay discovery of a bad balance.

**Failure, recovery and shortcuts:** blocked output stops upstream work while
retaining the held item. Drain through the real outlet, then resume. A dashboard
showing only a short burst, prefilled invisible buffers, free duplication or
unbounded storage would conceal the distinction. Once balanced, the line should
run without periodic player clearing.

**Learning and fit:** start with one visible occupied outlet, introduce one
capacity mismatch, then optionally share supply between subfactories. Mechanical
speed/load consequences can deepen the choice only after those rules exist.
This card fits the stationary opening most directly; it does not import
shapez's inexhaustible inputs or make a fixed throughput a game-wide requirement.

**Engineering risks and falsifier:** one stock ledger must distinguish produced,
buffered and delivered quantities, with the same phase across continuation.
Define the sampling interval before comparing output; do not confuse a quick
native test with a performance target. A hand-worked stock trace with and
without the buffer should show the same sustained bottleneck. Reject a scenario
where waiting alone solves every blockage, or where the inspector cannot locate
the capacity that actually limits output.

**Sources and disposition:** [throughput troubleshooting](https://steamcommunity.com/games/2162800/announcements/detail/684131849711128933)
and [continuous-supply rationale](https://steamcommunity.com/games/2162800/announcements/detail/534374481398857999).
Candidate; compare existing opening evidence before proposing implementation.

### Pattern shapez2-05: Diagnose the first wrong handoff

**Objective and verbs:** repair a line that sometimes produces the wrong facing
or sends work down the wrong branch. Observe the product, inspect progressively
earlier handoffs, stop, isolate the faulty branch, change one arrangement and
run the retained work again. The developer's backward-tracing advice motivates
causal inspection rather than a glowing answer marker.
Start with an already functioning line and one reversible wrong orientation or
branch, preserving the original finite stock and kit.

**Constraints and satisfaction:** every inspected item must be the actual item
at that location. Expose entry/exit facing, occupied capacity and the last
completed operation; do not replace causal evidence with a guessed diagnosis.
Finding the earliest divergence is the goal. Fast diagnosis and small edits are
optional mastery measures, not a timed gate.

**Solutions and tradeoffs:** inspect by walking the line, add a visible staging
area, or arrange an accessible bypass that isolates a branch. A compact line
uses fewer parts but can hide the crucial view; a spacious diagnostic layout
trades density for clarity. A reusable operation module can reduce repeated
mistakes without giving away the whole factory.

**Failure, recovery and shortcuts:** a downstream correction may mask the first
error and fail when inputs change. Test a second input case before accepting
the repair. Retain rejected and in-flight stock in named locations. Unlike the
source game's documented clear-belts shortcut, our recovery cannot erase it.
Explanations must reflect the running factory; a separate perfect demonstration
must be identified as such and cannot quietly repair the player's line.

**Learning and fit:** first make the faulty handoff visible, later let players
choose inspection points. Open tool faces, a stopped sample and mechanical
position markers fit three-dimensional physical play without requiring electric
sensors. The repaired stationary line must continue automatically; inspection
is read-only and can remain broader than construction reach.

**Engineering risks and falsifier:** inspection must name the current entity
generation and actual stock, not a stale local selection or historical outcome.
Current shared-snapshot and uncertainty evidence is relevant, but it cannot
prove learning. A minimal observer session should distinguish wrong input from
wrong tool orientation before revealing the cause. Reject automatic diagnosis
that gives the answer away, or evidence that stays ambiguous after inspecting
the relevant handoff. No extra sensors or speculative query framework is needed.

**Source and disposition:** [backward diagnosis and modular tools](https://steamcommunity.com/games/2162800/announcements/detail/684131849711128933).
Candidate; current teaching/inspection tasks may already cover the useful part.

## Candidate progression and bounded next experiment

Begin with 05's readable handoff evidence and 04's occupied-output recovery in the
existing stationary production loop, after physical-character/reach work lands.
Then consider 03's optional crossing only when a new transport process is ready.
01 and 02 need new support/material rules and belong later; none is approved by
this document. This sequence increases spatial and process decisions while
keeping a wide, simple solution available.

A useful bounded follow-up would ask whether a player can distinguish an empty
input, a held workpiece and an occupied outlet using the actual press and its
current inspector. Preserve the same parts and sixteen blanks; deliberately
produce one output blockage, recover through the existing outlet and verify
unattended continuation. Compare observations with the inspector's claims and
record what was understood. Search existing opening/teaching evidence first;
create a task only for a concrete uncovered observation. Do not implement a new
hint system or repeat an existing native witness merely to attach this study.

## Limits and follow-up questions

- No first-hand play, time-to-understanding, accessibility or enjoyment result is
  claimed. Developer reports of feedback explain their decisions, not ours.
- Verify present pin/support/crystal behavior in an explicitly identified build
  before using any exact interaction. No train package size, processing ratio,
  platform layer count or campaign unlock order is adopted from an old devlog.
- General mold recycling, damage/rework, support physics and lifting do not exist
  in the accepted opening. Their material and failure rules remain design work.
- Multi-layer routing needs physical access and unambiguous occlusion handling;
  a free camera alone is insufficient for the user's character requirement.
- Reusable blueprints need a declared version/compatibility boundary. The 1.0
  save break and 1.2 blueprint migration are cautions about evolution, not a
  recommendation to make player work disposable.
- Current-mod behavior, hexagonal puzzle coverage, full Manufacture balance and
  the separate puzzlez game are distinct deeper studies. New versions need an
  explicit follow-up scope, not a claim that this game is researched forever.

The [recurring research catalogue](../README.md) remains open regardless of this leaf's eventual
review result. A source-complete declared study can inform an experiment; only
actual implementation and consumer evidence can establish that the experiment
works in this project.

## Coverage and review ledger

- Covered by dated primary-source analysis: ordinary transformation and
  delivery; support/handling design rationale; vertical routing; modular rate
  comparison and buffering tradeoffs; persistent versus one-off factories;
  inspectable failure/recovery; save/blueprint evolution.
- Remaining and excluded scope: exact current-build handling, independently
  observed play, detailed wire/MAM correctness, full Manufacture balance,
  hexagonal mode, mods and puzzlez. No thorough current-build play study is
  claimed. Historical alpha mechanisms remain explicitly historical.
- Independent review: Ops accepted source attribution, declared coverage and
  all five candidate cards on 2026-10-15. This is source-analysis acceptance,
  not an independently played current-build result or adopted game mechanic.
- Original authored source freeze: `d7d77c75aa80227ae5055ebd5f4fc433b4f4c4af`.
  Root integrates this note and its catalogue entry; exact published revision
  and canonical-check evidence are recorded in the owning Bead. The cards and
  source claims are unchanged from the independently reviewed freeze.
- Closure: the declared source-analysis scope is complete; root records leaf
  closure after reviewed catalogue integration. Distinct deeper changeover and
  retained-work research belongs to `factory-yau.8.9`, not a duplicate survey.
  The recurring `factory-yau.8` stays open afterward.
- Next useful distinct work: compare 04/05 with existing stationary teaching
  evidence for a concrete gap; deeper current-build handling needs a separately
  declared permitted observation rather than repeating this source survey.
