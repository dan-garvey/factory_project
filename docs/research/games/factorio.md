# Study: Factorio — base 2.0 stationary construction and logistics

Status: reviewed and catalogued for the declared base-2.0 stationary source-study
scope. This is not a current-build play study or adoption of its candidate mechanics.
Study Bead: `factory-yau.8.1`. Owner: factory-playability. Date checked: 2026-10-15 UTC.

Scope: ordinary base-game construction, local access, stationary item handling,
capacity, finite ore replacement, oil-output recovery and construction repetition.
The target is the 2.0 design, without a modpack. The official download listing
returned stable 2.0.77 when checked; **no executable/build was run**. Current wiki
pages can mix base and expansion content, so relevant revisions and exclusions
are recorded below. This is a bounded documentation/design study, not complete
coverage of every Factorio system or a claim about 2.1 behavior. [S00]

Evidence access: Wube developer articles and the official, collaboratively edited
manual. No first-hand play, new installation, video-derived measurements,
community popularity claim or independent player interview is included. Developer
reports of playtests remain attributed reports. Historical articles establish
design reasoning at their publication dates, not automatic proof of current code.

No other completed Factorio study was found in the catalogue or all-status task
search. Space Age planets/platforms, Quality, elevated rail design, mods, combat,
train scheduling/signalling, circuit programming and production-scale performance
are excluded. Selected expansion-era articles are used only for explicitly
identified base-game design reasoning. Satisfactory and Create have separate
owned studies; their mechanics are not inferred from Factorio.

## Evidence and source map

All sources below were checked on 2026-10-15 UTC. `S` references identify source
descriptions. Analysis and adaptations are ours and are labelled accordingly.
There are no quotations or reproduced puzzle layouts.

| ID | Source and date/version context | Supported claim and limit |
| --- | --- | --- |
| S00 | [Official download listing](https://direct.factorio.com/download), retrieved 2026-10-15 | Release metadata only; no build/runtime verification. |
| S01 | [Official manual: Player, revision 218270](https://wiki.factorio.com/index.php?title=Player&oldid=218270), accessed 2026-10-15 | Character versus player-view distinction and ordinary world interactions; mixed-version article, not a 3D movement specification. |
| S02 | [Official manual: Ghost](https://wiki.factorio.com/Ghost), accessed 2026-10-15, sections introduction and robot interaction | Planning markers do not function as machines; later fulfillment requires actual supplies and construction capacity. |
| S03 | [FFF 380: Remote view](https://www.factorio.com/blog/post/fff-380), 2023-10-13, proposed base 2.0 changes | Remote configuration and robot-served item requests; design account, not unrestricted inventory teleportation. |
| S04 | [FFF 92: Personal roboport](https://www.factorio.com/blog/post/fff-92), 2015-06-26, historical 0.12 introduction | Construction assistance extends a character's practical work area using carried supplies. Exact old capacities/radii are not imported. |
| S05 | [Official manual: Belt transport system, revision 216925](https://wiki.factorio.com/index.php?title=Belt_transport_system&oldid=216925) | Lanes, splitting/merging, priorities and crossings. Expansion tiers are excluded; no benchmark or rate table is reproduced. |
| S06 | [Official manual: Inserters, revision 220313](https://wiki.factorio.com/index.php?title=Inserters&oldid=220313), introductory handling and throughput sections | Transfer orientation and actual handoff capacity can constrain a line. Some measurements explicitly target 2.0.26; no numeric transfer rate is generalized here. |
| S07 | [Official manual: Oil processing, revision 218469](https://wiki.factorio.com/index.php?title=Oil_processing&oldid=218469), setup section | A full coproduct outlet can stop the refinery; storage and conversion are distinct responses. Expansion recipes are outside scope. |
| S08 | [Official manual: Mining, revision 219472](https://wiki.factorio.com/index.php?title=Mining&oldid=219472), drill coverage and output sections | Finite ore coverage, exhaustion and output orientation. Infinite-resource/productivity/Quality arithmetic is not studied. |
| S09 | [Official manual: Blueprint, revision 217341](https://wiki.factorio.com/index.php?title=Blueprint&oldid=217341), placement section | Reusable arrangements create construction plans that still need supplies and fulfillment. No blueprint is copied. |
| S10 | [FFF 263: Trains in blueprints](https://www.factorio.com/blog/post/fff-263), 2018-10-05, upgrade-planner section | Developer-reported failure from replacing only one end of an underground connection, and paired replacement as the remedy. Historical case, not a train study. |
| S11 | [FFF 383: Super force building](https://www.factorio.com/blog/post/fff-383), 2023-11-03 | Reducing repetitive replacement work can automate supporting edits; this is not permission for destructive automatic edits here. |
| S12 | [FFF 284: 0.17 experimental](https://www.factorio.com/blog/post/fff-284), 2019-03-01, introductory learning sections | Developer distinguishes teaching production concepts from prescribing placements, and difficulty from tool complexity. That historical tutorial is not presented as the current tutorial. |
| S13 | [FFF 409: Diminishing beacons](https://www.factorio.com/blog/post/fff-409), 2024-05-03 | Designer critique of repetitive late layouts and of changes that only demand more belts. Mod examples and expansion balance are not adopted mechanics. |
| S14 | [FFF 408: Statistics improvements](https://www.factorio.com/blog/post/fff-408), 2024-04-26, statistics section | Visibility of stored capacity, consumption and production at useful scopes. Expansion-specific examples do not prove base-game ratios. |

## How the game's engineering challenges develop

The useful progression is a change in decisions. Extraction and processing make
materials available; transport and handoff arrangements let those operations
run together. Additional inputs turn a line into a spatial allocation problem.
Unequal capacities and blocked destinations make a running arrangement different
from a merely connected recipe graph. Broader construction tools reduce the
cost of repeating a solved arrangement. This is a qualitative reading of the
sources, not an exact technology-order walkthrough. [S05], [S06], [S07], [S08], [S09]

The sources also expose two limits of borrowing the formula. Endless numerical
expansion can become repetition, and more complicated tools need not make a
better introductory puzzle. Wube's discussions provide useful design concerns,
not evidence that our player will enjoy the same tradeoffs. [S12, S13]

For this project, stationary means the assembly stays installed. Its tools and
drive can still move. Every adaptation below keeps physical construction access,
mechanical transmission, authoritative item custody and eventual unattended
operation in view. A vertical version must change the engineering decision;
putting the same planar layout on a balcony is insufficient. Nothing below
changes [DESIGN](../../../DESIGN.md), the new character requirement or the
priority of finishing its real opening consumer.

## Pattern factorio-01: plan remotely, fulfill from real locations

- **Goal and setup:** build or extend a local factory while the character,
  carried parts and desired site occupy different places. Source behavior:
  ghosts represent future work; actual construction requires supplies and a
  means of fulfillment. Remote view can configure work without moving pocket
  items there. [S01], [S02], [S03], [S04]
- **Player verbs:** approach and build by hand; mark an intended arrangement;
  later establish construction coverage and supply it.
- **Constraints:** physical access and material custody are hard constraints.
  Less travel and preparation time are soft rewards. A plan alone provides
  neither a working machine nor an item transfer.
- **Solution families:** carry a small kit and work locally; prepare supply
  near the site; later invest in an extended construction service. The tradeoff
  is preparation/infrastructure versus repeated personal journeys.
- **Appeal:** inference: a useful upgrade removes a solved access chore while
  leaving the factory's material routes meaningful.
- **Failure and recovery:** distinguish an unfunded plan from completed work.
  Missing supplies should be diagnosable. Repeated trips remain upkeep until
  the later service can replenish itself; camera-based free fulfillment would
  erase the constraint instead of solving it.
- **Teaching and progression:** first establish character position, part
  ownership and a nearby successful build. Extension is a new capability,
  not an unexplained larger interaction radius.
- **Adaptation here:** evaluate the already-required physical opening first.
  A later mechanical hoist/work platform could carry parts and extend work
  access to a stationary upper bay. It must preserve custody and require
  physical delivery; robots or electricity are not proposed.
- **Engineering risks:** one actor authority, 3D reach, delayed admission,
  plan-versus-built presentation and save/rejoin must agree. Remote planning
  is optional future scope, not an excuse to weaken current server reach.
- **Falsifier / smallest experiment:** the same camera view must not let a far
  actor spend a part; approaching must enable a fresh request. If later supply
  service merely hides unrestricted stock withdrawal, reject that adaptation.
- **Sources / related patterns:** S01–S04; current physical-character/reach
  increment; factorio-06 for repeating a solved arrangement.
- **Disposition:** evaluated as support for the existing access requirement;
  construction-service/remote-plan additions deferred.

## Pattern factorio-02: a route can connect yet feed the wrong interface

- **Goal and setup:** deliver two materials through a restricted service
  corridor to several consumers. Source behavior: belts have separate lanes;
  splitters preserve lanes and may prioritize a branch; an ordinary crossing
  is a different operation from splitting. [S05]
- **Player verbs:** orient, merge, split, cross and rearrange routes; choose
  which side feeds which intake.
- **Constraints:** interface orientation and occupied space are hard limits.
  Compactness, short travel and spare capacity are soft rewards. More transport
  parts do not automatically repair a wrongly presented material.
- **Solution families:** share a route and separate near consumers; use
  independent routes with extra space; relocate consumers to simplify feeding.
  Compact shared transport is harder to diagnose and expand.
- **Appeal:** inference: the player can explain a visible geometric cause,
  then change an arrangement rather than merely increase a resource number.
- **Failure and recovery:** diagnose which material reaches each intake.
  Stopping and rerouting must preserve items. A hidden lane-order trick or
  an unrestricted all-to-all sorter can respectively make the task opaque or
  remove its decision. Correct routing should run without recurring sorting.
- **Teaching and progression:** begin with one visible port and direction;
  introduce a second feed only after transport and intake are understood.
- **Adaptation here:** a fixed press with side-fed stock and a top-fed forming
  aid could permit an open elevated chute or a wider low-level route with a
  mechanical lift. This is an original later stationary challenge, not an
  adopted recipe or an initial-demo requirement.
- **Engineering risks:** port frames, 3D clearance and item holders must be
  authoritative. A cosmetic crossing cannot stand in for independent routes.
- **Falsifier / smallest experiment:** build both route families with the same
  finite inputs. If height changes no routing/access tradeoff, the vertical
  adaptation adds scenery rather than a puzzle.
- **Sources / related patterns:** S05; factorio-03 separates port correctness
  from capacity; Create study owns the project's cog-routing references.
- **Disposition:** candidate; defer until the nearby stationary opening works.

## Pattern factorio-03: improve the bottleneck, not every machine

- **Goal and setup:** meet a fixed delivery demand with machines linked by
  bounded handoffs. Source behavior: inserter orientation and loading conditions
  affect achieved transfer capacity; a nominal machine rate is insufficient to
  describe the whole line. [S06]
  Original paper example, not Factorio rates or a proposed recipe: demand is
  three pieces per beat, feed can supply four, one cutter handles two, and
  transfer/press handle four. Two cutters can meet demand if their handoffs fit;
  extra storage alone cannot fix the single cutter's sustained deficit.
- **Player verbs:** change handoff placement, add a parallel feed, buffer an
  intermittent stage or colocate two stages for direct transfer.
- **Constraints:** the slowest sustained stage bounds useful output. Finite
  buffers absorb a mismatch temporarily; they cannot create long-run capacity.
  Footprint, construction cost and intelligibility are competing soft goals.
- **Solution families:** parallelize a constrained stage; simplify transport
  through direct handoff; use a deliberately sized buffer for bursts. These
  solve different causes and have different expansion costs.
- **Appeal:** inference: observation produces a causal diagnosis, followed by
  a local redesign whose result is visible.
- **Failure and recovery:** empty inputs and full outputs need different
  explanations. Huge buffers can postpone recognition of a bad rate match;
  manual restocking is recurring upkeep, not solved automation. Statistics
  should reveal the relevant stage rather than only a global total. [S14]
- **Teaching and progression:** compare a short demand burst with sustained
  demand before adding an exact-ratio exercise. Later capability should offer
  a distinct process, not just an overclock slider.
- **Adaptation here:** compare a stationary reciprocating handoff with a
  rotary indexed transfer serving the same press. A shared shaft and actual
  phase/direction give different geometry and capacity choices. This depends
  on later component-level machinery; it does not expand mobile-factory work.
- **Engineering risks:** actual custody at transfer, phase under stalls and
  resumed work must agree. Engine frame frequency is not a chosen production
  rate, and throughput claims need separate measurement.
- **Falsifier / smallest experiment:** with equal stock and demand, identify
  a case where each arrangement has a practical advantage. If only arbitrary
  speed multipliers distinguish them, the proposed redesign is weak.
- **Sources / related patterns:** S06, S14; factorio-02 covers interface access.
- **Disposition:** candidate for later stationary mechanism comparison.

## Pattern factorio-04: a blocked coproduct is a process problem

- **Goal and setup:** sustain a desired output when one process produces
  several outputs. Source behavior: advanced oil processing can stop when one
  product outlet fills; storage and conversion of surplus are available
  responses. No recipe quantities or current ratio optimum is assumed. [S07]
  Original paper example only: a batch yields one wanted unit and one
  coproduct. A two-slot coproduct bin permits just two batches without a sink,
  regardless of the wanted outlet's capacity. This is not an adopted recipe.
- **Player verbs:** route every outlet, allocate storage, consume a coproduct,
  or convert surplus into a useful downstream material.
- **Constraints:** every output retains custody and needs a destination.
  Storage is finite. Demand imbalance, rather than missing recipe connectivity,
  creates the hard sustained-operation problem.
- **Solution families:** buffer a known short burst; support a useful parallel
  demand; add a conversion path for genuine surplus. More tanks only postpone
  an unbounded mismatch. A disposal void would remove the intended decision.
- **Appeal:** inference: a previously unwanted output becomes a reason to
  connect processes and understand the whole factory.
- **Failure and recovery:** name the blocked outlet and preserve unfinished
  work. Clearing its destination should resume the same work. Periodic manual
  emptying is an unsolved chore, even if a short demonstration finishes.
- **Teaching and progression:** first teach a single full outlet and recovery.
  Introduce coproducts when both destinations are understandable. Expressive
  threshold controls belong later; they are not prerequisites for the opening.
- **Adaptation here:** a fixed mechanical separation process could produce
  two useful fractions with gravity-directed outlets. Distinct product uses,
  rather than deleting one fraction, must support eventual automation. Fluids
  and exact materials remain later design work.
- **Engineering risks:** atomic multi-output custody, retained work and load
  continuation require one authority. A pause must not consume the input again.
- **Falsifier / smallest experiment:** exhaust a small destination, then free
  it and verify exact same-work recovery. Reject a proposed sustained solution
  if it depends on a player's repeated bucket-emptying action.
- **Sources / related patterns:** S07; the current one-output opening is only
  the simpler backpressure lesson, not evidence for coproduct implementation.
- **Disposition:** deferred; preserve single-output recovery before expanding.

## Pattern factorio-05: cover finite ground, then make replacement less costly

- **Goal and setup:** extract a finite ore patch and deliver its output to a
  fixed factory. Source behavior: a drill covers a particular area, directs its
  output to an adjacent destination and stops after its covered resources are
  exhausted. [S08]
- **Player verbs:** place and orient collectors, distribute coverage, connect
  extraction to transport and eventually relocate or replace supply.
- **Constraints:** resource geometry and remaining stock are hard limits.
  Coverage, transport length, access and later replacement effort trade off.
  A large buffer cannot make a finite patch permanent.
- **Solution families:** dense coverage with shared transport; sparser access
  corridors that ease servicing; a smaller installation reused at later sites.
  Fast initial collection can create more relocation work later.
- **Appeal:** inference: terrain matters to arrangement, while an improved
  acquisition method can remove a chore the player has already understood.
- **Failure and recovery:** distinguish depletion from blocked output. The
  supply must be honestly replaced; no hidden refill. Rebuilding identical
  outposts forever risks becoming routine work rather than new engineering.
- **Teaching and progression:** show finite stock and one transparent local
  extraction cycle first. Later automation must reduce replacement labor;
  lasting supply should follow capability progression, not a depletion timer.
- **Adaptation here:** a fixed hillside collection bay with accessible service
  ledges could compare dense collectors with a maintainable layered layout.
  Later engineered supply is a separate project; neither a moving harvester
  nor new lasting-supply policy is implied by this card.
- **Engineering risks:** world stock, per-machine custody and carried parts
  must survive replacement/save/rejoin. The opening's 16 blanks are a fixture,
  not balance evidence for patch size or replacement cadence.
- **Falsifier / smallest experiment:** compare total construction and servicing
  actions through one declared exhaustion/replacement. If both choices collapse
  to the same copied layout and travel time, the task needs a new decision.
- **Sources / related patterns:** S08; factorio-06 addresses repetition cost;
  Create/CABIN source-lifecycle coverage belongs in its separate study.
- **Disposition:** candidate later; no early mobile-factory expansion.

## Pattern factorio-06: repeat solved work without breaking its interfaces

- **Goal and setup:** expand or replace an established module without manually
  repeating every placement or silently breaking its connections. Source
  behavior: blueprints create plans for later construction; Wube describes an
  upgrade bug where changing one underground endpoint disconnected a route,
  then describes paired upgrades as the fix. [S09, S10]
- **Player verbs:** name and reuse an arrangement, supply its construction,
  change an interface deliberately and inspect pending versus completed work.
- **Constraints:** footprint, connection compatibility, actual materials and
  safe replacement are hard constraints. Repetition cost is a soft burden
  worth reducing after the first design is understood.
- **Solution families:** repeat isolated modules with explicit interfaces;
  share trunks between modules; rebuild a compact integrated layout. Isolation
  costs space/parts; sharing makes replacement affect more neighbors.
- **Appeal:** inference: reusable work lets attention return to the new
  engineering decision. It should preserve player-authored arrangements rather
  than reward memorizing a publisher-provided optimum.
- **Failure and recovery:** preserve material and unfinished work across
  replacement. A construction plan is not a completion receipt. Automated
  supporting edits can reduce chores, but unannounced dismantling can destroy
  a layout the player intended to keep. [S11]
- **Teaching and progression:** hand-build and diagnose one module first.
  Repetition aids should remove repeated execution, not remove the lesson or
  become the chapter's main intellectual reward.
- **Adaptation here:** later repeat a stationary mechanically driven cell
  whose shaft direction, feed height and service corridor are declared at its
  boundary. Keep proximity/carrying rules until a researched construction
  capability explicitly changes them.
- **Engineering risks:** group edits, stable IDs, refunds and unknown network
  outcomes need careful transactions. This does not select live editing of
  stocked machinery or a new blueprint subsystem for the prototype.
- **Falsifier / smallest experiment:** replace a paired interface while it
  contains work. If it loses stock, reconnects a different neighbor or needs
  undocumented manual repair, the repeat/upgrade abstraction is incomplete.
- **Sources / related patterns:** S09–S11; factorio-01 separates plans from
  fulfillment; current cached request semantics remain authoritative.
- **Disposition:** deferred; retain the interface lesson without importing a
  full construction planner now.

## Pattern factorio-07: teach a causal concept, then change the arrangement

- **Goal and setup:** learn to make an unfamiliar production arrangement work
  without following a single prescribed layout. Source evidence: the 0.17
  introduction's designer separated item traversal from inventory transfer and
  argued that a smaller toolset can be simpler while still being difficult.
  This is historical design reasoning, not measured success of our tutorial.
  [S12]
- **Player verbs:** observe a handoff, build a short route, inspect a stalled
  stage and rearrange parts to recover it.
- **Constraints:** a small initial vocabulary limits cognitive load; a real
  process objective supplies the hard requirement. Only one permitted placement
  would reduce the exercise to obedience.
- **Solution families:** direct nearby handoff, a longer accessible route or
  a vertically separated feed. They must solve the same process goal with
  different access/footprint costs, not merely use differently colored parts.
- **Appeal:** inference: understanding transfers to a changed site. Variety
  must survive optimization; a dominant repeatable grid can exhaust the design
  space even when its arithmetic becomes more elaborate. [S13]
- **Failure and recovery:** show which physical condition is absent, then
  permit an informed correction. Avoid forcing repeated supply walks, opaque
  ratios or combat pressure just to keep a simple lesson busy.
- **Teaching and progression:** begin with collect → transport → process →
  retrieve; later change a port direction, working height or product process.
  Support explanation without requiring an elaborate custom machine first.
- **Adaptation here:** after the character opening works, compare two small
  stationary sites with the same starter operations but different port/access
  geometry. Keep the read-only explanation; the actual factory remains the
  player's arrangement, not an editable tutorial copy.
- **Engineering risks:** help must describe current authoritative conditions.
  Do not confuse an engine/controller restriction with a pedagogical constraint.
  Learning/enjoyment needs actual user evidence, not an agent completion trace.
- **Falsifier / smallest experiment:** after one worked example, ask an actual
  player to recover a changed arrangement. If they can only repeat coordinates
  or cannot identify the obstructed handoff, the teaching hypothesis failed.
- **Sources / related patterns:** S12, S13; factorio-02/03 provide distinct
  geometry/capacity variations rather than more recipe nodes.
- **Disposition:** candidate teaching evaluation after physical-loop acceptance.

## Synthesis and proposed follow-ups

The present opening should prioritize factorio-01's clear actor/target/fulfillment
distinction and factorio-07's causal feedback. Those support existing requirements;
they do not justify remote construction or more machinery before the physical
collector → belt → press → plate loop works. The current independent character
consumer can test camera versus body permission and truthful failure feedback.
Actual user learning remains a separate observation.

Afterward, the strongest stationary experiment is a **two-arrangement handoff**:
same finite inputs and product goal, one direct low-level route and one elevated
route serving a different access constraint. Compare custody, working clearance,
build access and successful unattended continuation. Begin only with a concrete
owned contract; no implementation Bead is created merely to turn every card into
work. Stop if the elevated option is only a cosmetic version of the flat one.

Do not import electricity, passive radius boosters, giant universal inventories,
mandatory repeated outpost errands, or speed upgrades as the primary reward.
Factorio's later layout critique is a warning to test whether a new capability
changes the solution space. Our hierarchy favors a distinct process that enables
new products and can improve old supply, with simple duplication still useful
but less rewarding. [S13], [DESIGN]

Cross-game synthesis must await the separate Satisfactory/Create studies rather
than infer their rules from this one. Useful future Factorio scopes include
train deadlock/signalling, controlled batch systems and the substantially
different constraints of Space Age; each needs a distinct study task and actual
sources instead of relabelling this scope complete.

## Coverage and review ledger

- **Covered in this draft:** local character versus planning/fulfillment;
  oriented transport and handoffs; capacity/buffering diagnosis; finite ore
  replacement; blocked coproduct recovery; construction repetition and interface
  preservation; introductory concept sequencing and late-layout monotony risks.
- **Evidence limit:** source-based analysis only. No hands-on play, measured
  rates, player learning study, empirical best-layout claim or complete campaign
  walkthrough. The 2.0.77 listing is metadata, not a tested build pin.
- **Excluded/new-version scope:** 2.1 changes, expansion campaigns/Quality,
  mods, combat, rail scheduling, circuits, deep fluid dynamics and performance.
  Revisit unversioned manual pages before relying on changed rules.
- **Independent reviewer, findings and resolutions:** Chapter reviewed the full
  frozen note and all fifteen source rows, including historical/current limits
  and adaptation reasoning; no blocking source finding. Root reviewed the note
  and evidence scope before catalogue integration on 2026-10-19.
- **Final note revision/check/publication:** source freeze `3c218f0`; the
  integration changes only review/publication metadata, not claims or cards.
  Exact revision and source/index/hook results remain in the integration record.
- **Closure decision:** the declared base-2.0 stationary source-study scope is
  complete after catalogue integration. This does not close the excluded scopes
  above or establish hands-on play, current-build behavior or candidate adoption.
- **Next owned distinct target:** `factory-yau.8.2`, Satisfactory stationary 3D
  access/routing/progression, during safe waits for the higher-priority character
  implementation and actual consumer review.

The continuing parent `factory-yau.8` remains open after any per-game closure.

[S00]: https://direct.factorio.com/download
[S01]: https://wiki.factorio.com/index.php?title=Player&oldid=218270
[S02]: https://wiki.factorio.com/Ghost
[S03]: https://www.factorio.com/blog/post/fff-380
[S04]: https://www.factorio.com/blog/post/fff-92
[S05]: https://wiki.factorio.com/index.php?title=Belt_transport_system&oldid=216925
[S06]: https://wiki.factorio.com/index.php?title=Inserters&oldid=220313
[S07]: https://wiki.factorio.com/index.php?title=Oil_processing&oldid=218469
[S08]: https://wiki.factorio.com/index.php?title=Mining&oldid=219472
[S09]: https://wiki.factorio.com/index.php?title=Blueprint&oldid=217341
[S10]: https://www.factorio.com/blog/post/fff-263
[S11]: https://www.factorio.com/blog/post/fff-383
[S12]: https://www.factorio.com/blog/post/fff-284
[S13]: https://www.factorio.com/blog/post/fff-409
[S14]: https://www.factorio.com/blog/post/fff-408
[DESIGN]: ../../../DESIGN.md
