# Proposed delivery stages

Proposal against [DESIGN][design], snapshot `698667b`.
Neither release envelope below is selected. This addresses the first-release
boundary in [design review finding 2](../../DESIGN_REVIEW.md#prioritized-findings);
it changes no requirement, gameplay choice, production stack or delivery date.

The current opening supports place → connect → process → retrieve, finite stock,
blocked/paused work, a separate working explanation and compatible-save reopening.
Stationary two-client/save fixtures and a separate native linear-drive fixture
provide bounded technical evidence. They do not establish a networked player UI,
arbitrary moving factories, trains, passengers, sustainable supply, campaign,
production performance, native-core portability or actual user understanding.
The [launcher](../../README.md) and [mechanical fixture][mechanics] state limits.

The basic opening remains a valid first feedback opportunity. The wider
representative prototype below follows it; no matrix row expands that opening's
acceptance gate. Earlier [chapter proposals][chapter] remain optional inputs,
including their unselected recipes and motion layouts.

## Two release envelopes to compare

| Boundary | Chapter development release | Compact intended-game campaign |
| --- | --- | --- |
| Meaning | A limited public development release containing one coherent chapter. Explicitly incomplete relative to the intended game. | A candidate first complete campaign, with a small catalogue and world but all required system families. |
| Production experience | Basic opening, then a new product/process, useful player-built rotary/gantry work, one functional height constraint and a reason to expand or redesign earlier supply. | Several capability changes and new products, meaningful old/new process choices, required motion types including a train route, fluids/gases/alien processes and later expressive controls. |
| Shared foundation | Dedicated co-op UI, scoped multiple-team/independent learning and save/rejoin of introduced work. | Same foundation across campaign, moving interactions and team/story progress. Two shared fixture participants satisfy neither envelope. |
| Supply and closure | Every introduced required production chain has an eventual unattended route, including its inputs/recovery. One chapter payoff and optional projects; no claim to either campaign ending. | Mixed infinite and autonomous finite acquisition, technology-gated access/terrain work, off-site mystery progression, semi-ending and harder multi-recipe-throughput true ending; continued play afterward. |
| Deferred content | Player-facing trains, broader moving-world cases, fluid/gas/alien progression, later controls, terrain tools and campaign endings remain explicit later obligations. Their architecture risks are probed early. | Broader catalogue, more regions and additional challenges can follow. Required system families and both endings cannot remain absent while this envelope is called complete. |
| Solo/agent risk | Smaller content surface; motion × multiplayer × saves and complete supply still need integration. Risk: the slice becomes the ceiling or finite fixtures masquerade as automation. | More systems, teaching/content/balance and integration. Agents still need shared authority, review and player evidence. Risk: campaign completion outgrows the team. |

Evaluate the chapter envelope first as the smaller external iteration. It remains
incomplete against the intended game; the campaign envelope names a possible
complete-game boundary. This ranking selects no release contract. Boundary
review still needs play evidence and the unresolved contracts below.

## Requirement-to-stage matrix

Cells describe proposed work and acceptance evidence, **not completed features**.
Architecture proof exercises the risky real join; representative prototype lets
a player use a bounded integrated slice. “Later” preserves required work after
the chapter envelope, with catalogue depth remaining after the campaign envelope.

| Requirement / DESIGN source | Architecture proof | Representative prototype | Proposed first release | Later delivery | Unresolved |
| --- | --- | --- | --- | --- | --- |
| Standalone game, rapid iteration, mechanics portability [goals] [development] | Shared commands/state; real headless/3D joins and engine-coupling cost. | Runnable packaged slice, usable setup/diagnostics. | Both: supported build and evidence-based production direction; Godot remains a trial. | Broader platforms; extraction if justified. | Engine/language, art/pipeline (AI assets allowed), platforms. |
| Modular production; complete functional heads [construction] | Parts/mount/feed/power ownership; conserved construction stock. | Complete starters, then constructed transmission, feeding and moving assemblies. | Both: useful bounded vocabulary; campaign deepens it. | More tools/interactions. | Catalogue, granularity, crafting and convenience. |
| Required rotation, gantries and trains [construction] | Non-grid native poses, fixed-cycle reversal, constrained train bend, stable membership. | Rotary/gantry production; early train risk rig. | Chapter: local rotary/gantry work; campaign: usable train route too. | Trains after chapter; more routes afterward. | Parts, attachment/alignment and route/edit rules. |
| Operate, harvest and transfer while moving [construction] | Actual tool/world encounters and moving-to-fixed item custody; conserved refusals. | Useful moving work/harvest/transfer using the existing item owner. | Introduced paths work in motion; campaign covers the required family. | Remaining combinations after chapter. | Reach, eligibility and transfer boundaries. |
| Carry players; contact and machinery injury [construction] | Real controller/collision/authority on rotary, gantry and train-like motion; no parenting substitute. | Ride/leave with correction and declared contact limits. | Chapter discloses omissions; campaign includes riding/injury behavior. | Remaining cases after chapter. | Injury/respawn and contact consequences; separate-machine pushing deferred. |
| Global grid; no moving construction/editing [construction] [motion] | Refuse edits without stock/topology change; retain off-grid phase. | Build/run/stop/edit under an explicit scoped rule. | Both: enforce limits without grid-snapping operation. | Further construction forms. | Voxel dimensions/orientations, stopped versus docked editing. |
| Essential 3D; hard vertical processes and soft height benefits [construction] [vertical] | Real gravity/tool-face/reach/clearance controls, including flat/reversed/empty cases. | Height-required process and advantageous vertical layout. | Both: functional spatial construction. | More process combinations. | Processes/gravity; horizontal decay remains a bounded candidate. |
| Spatial power, cog direction and gearing [goals] [power] | Signed phase/ratio changes useful work; native/published bodies agree. | Route drive and diagnose direction/connection. | Both: topology affects production; no assumed gantry-after-rotation unlock. | Harder arrangements. | Power/load rules, parts and feedback. |
| Geometry-dependent scaling; worthwhile redesign [progression] | Compare equal opportunities/demand, including sweep, feed and construction costs. | Expand or adapt earlier output after learning a new process. | Both: advantage beyond overclocking or a larger-output box; old routes stay useful. | More tradeoffs; duplication stays a modest fallback. | Balance/advantage axes; no universal winning layout. |
| Dependable automation, non-destructive stalls/isolation [automation] | Wrong counts/full output/solid obstruction retain stock/phase; isolate and recover. | Diagnose/recover work; misplaced parts cause no cascade damage. | Every introduced chain runs unattended once solved. | Extend to later processes/supplies. | Fault/contact feedback; previews/warnings/activation restrictions unselected. |
| Exact counts and later expressive controls [controls] [automation] | Wrong/extra inputs stall without loss; real metering/recovery. Probe early technically. | Fixed-cycle placement/gearing first; required controls well into latter half. | Chapter can omit late unlocks; campaign includes late precision work. | More control combinations. | Signal medium/parts; no electricity. |
| Guided branching chapters, optional projects, new processes/products [progression] | Separate capability/prerequisite/credit from simulation. | New process for new product; later demand allows expansion or redesign. | Chapter: one arc; campaign: broader capability structure. | More projects; preserve old methods. | Products/dependencies; A/B/C is no mandatory three-item opening. |
| Ponder-like teaching and live legibility [teaching] | Shared rules, isolated teaching model/world; no stock/save leakage. | Rotate/zoom working example, then build/diagnose; observe a player. | Both: readable construction and failure/recovery explanations. | Teach new systems. | Camera/feedback/art; editable practice outside current preference. |
| Physical item location, storage and construction access [inventory] [logistics] | Explicit custody/access; catalogue knowledge grants no remote withdrawal. | Fetch/build/rebuild with fewer forgotten-part errands, retaining transport. | Both: usable physical supply; chapter can stay local. | Storage/search/delivery upgrades; global storage as possible unlock. | Cache range, delivery/withdrawal, plans/catalogue. |
| Exploration and harder in-base alternatives [inventory] [exploration] | Capability/access dependencies; no mandatory unbounded random search. | Both routes in one world; exploration earlier/cheaper. | Chapter: introduced capabilities; campaign: wider choices. | More sites/processes. | Resources, recipes, access dependencies and costs. |
| Depleting nodes; milestone-unlocked lasting supply [inventory] [supply] | Finite conservation; complete replenishment/recovery graph; exhaustion never unlocks. | Extract, then engineer supply before replacement becomes a trap. | Automate all required inputs; no hidden refill or finite-only sustainability claim. | Broader lasting-supply coverage. | Milestones/lifetimes/bootstrap; no adopted protected reserve. |
| Infinite sources plus autonomous finite acquisition [supply] | Qualifying geometry and automatic find/extract/connect; no universal infinite container. | Full sustainable route; early proof of other required family. | Chapter may ship one family; campaign includes both. | Second family after chapter, then more routes. | Eligible materials/terrain/routes; active recovery is a late candidate, never passive waiting. |
| Designed peaceful frontier, safe access and limited reshaping [world] | Access/terrain changes join machinery, resources, multiplayer and saves. | Designed site; later gated visit/preparation with base alternative. | Both: one designed world; campaign adds gated access/reshaping. | Required capabilities after chapter; more regions afterward. | World format/generation, hazards/excavation; no easy early reshaping. |
| Mechanical throughout; fluids/gases and alien substances [technology] | Extend quantity/port/control contracts without a second owner. | Processes change arrangements/products while retaining mechanics. | Chapter: solids can suffice; campaign: fluid/gas/alien extensions. | More processes/materials. | Substances/flow/machines; electricity excluded. |
| Inventory-confirmed ordinary goals; off-site commissions [quests] [campaign] | Separate checks, dispatch custody, credit and persistent story counters. | Confirm product; real bounded commission after its contract is scoped. | Preserve ordinary inventory checks; campaign adds off-site progression. | More commissions. | Consumption/delivery and credit scope; session acknowledgement is no quest system. |
| Humorous guide, mystery, semi/true endings and continued play [campaign] [endings] | Milestone/reveal ownership; actual multi-recipe throughput across continuation. | Guide/delivery/hint without interrupting building. | Chapter payoff disclosed; campaign has both endings, harder throughput and play afterward. | Both endings after chapter; further narrative depth. | Project/story, recipes/rates/recognition; no required on-site megastructure. |
| Multiplayer from outset; dedicated servers, high tick rates and responsiveness [multiplayer] [network] | Authority, edits/correction/rejoin and moving passenger/transfer/save joins under network variation. | Real co-op UI on single-player's rules. | Both: actual dedicated co-op, including introduced machinery. | Broader moving-world cases. | Tick/latency budgets, rollback-or-better scope and production network architecture. |
| Multiple cooperative teams; independent learning pace [multiplayer] | Individual/team/world ownership of learning, unlocks, credit, deliveries, story/world changes. | Novice/advanced groups coexist without forced unlocks or resource exclusion. | Both: tested scoped sharing; campaign covers all progression. | Deeper shared-world cases. | Sharing/access/reveals; no assumed single global progression. |
| Substantial factories, performance and long-session usability [goals] [performance] | Measure real motion/items/players/network/saves on declared hardware with correctness intact. | Build/navigate/diagnose a growing crowded factory. | Both: measured quality for declared scope. | Larger-scale testing. | Rig/scale/rates, camera/assets; local resource floors are no game targets. |
| Reserved alternatives [open] | Investigate when a concrete decision needs it. | Prototype choices remain reversible. | Neither automatically adopts them. | Reconsider without promising them. | First-person, voxels/rigid bodies, special horizontal decay, manager selection, competition/leaderboards. |

## Evidence needed before accepting a boundary

Release evidence must join introduced mechanics with player input, multiplayer,
save/rejoin, supply and teaching, retaining quantities, identities and phase.
Passenger/train/moving-transfer risk proofs inform production adoption even when
content is deferred. Current engine-native rules do not prove portability.

Actual play/building observations inform the boundary; agent checks cannot supply
understanding, comfort or enjoyment. Continue scoped development while waiting.
Compare effective constructions and fair scaling controls; the old paper carrier
and recipes are optional.

A boundary decision needs its feature list, deferred requirements, ownership/
check/dispatch policy, full supply graph, quality targets and evidence gaps.
Contact/edit rules and production foundation need explicit choices. DESIGN owns
requirements; the [roadmap](../../ROADMAP.md) owns dependencies. This proposal
selects no rules, shipping commitment or production stack.

[design]: ../../DESIGN.md
[goals]: ../../DESIGN.md#stated-goals
[development]: ../../DESIGN.md#development-approach
[construction]: ../../DESIGN.md#construction-and-movement
[motion]: ../../DESIGN.md#predictable-motion-and-physical-appearance
[vertical]: ../../DESIGN.md#genuine-use-of-three-dimensional-space
[power]: ../../DESIGN.md#power-as-visible-infrastructure
[automation]: ../../DESIGN.md#complexity-and-automation
[controls]: ../../DESIGN.md#controls-are-part-of-the-machinery
[progression]: ../../DESIGN.md#progression-and-teaching
[teaching]: ../../DESIGN.md#ponder-like-explanations
[inventory]: ../../DESIGN.md#inventory-and-resource-acquisition
[logistics]: ../../DESIGN.md#construction-convenience-and-logistics-progression
[exploration]: ../../DESIGN.md#exploration-and-in-base-alternatives
[supply]: ../../DESIGN.md#resource-pressure-without-recurring-manual-replacement
[world]: ../../DESIGN.md#world-and-terrain
[technology]: ../../DESIGN.md#technological-identity
[quests]: ../../DESIGN.md#quest-completion
[campaign]: ../../DESIGN.md#campaign-and-manager
[endings]: ../../DESIGN.md#campaign-closure-and-mastery
[multiplayer]: ../../DESIGN.md#multiplayer-and-progression-ownership
[network]: ../../DESIGN.md#multiplayer-from-the-first-representative-prototype
[performance]: ../../DESIGN.md#performance-supports-the-fantasy
[open]: ../../DESIGN.md#open-design-topics
[mechanics]: ../../experiments/engine-environment/godot/mechanics/README.md
[chapter]: first-chapter-decision-packet.md
