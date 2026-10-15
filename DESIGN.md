# Factory game — working design document

Status: discovery draft, revised 2026-10-14 after the world, campaign, and multiplayer question round. Requirements below come from the user; proposals remain open for review. No implementation stack has been selected.

## Stated goals

- Build a standalone factory game inspired by what worked best in Create, particularly the Above and Beyond and CABIN modpacks.
- Go beyond routing resources between machines with fixed input/output recipes.
- Make constructing the means of production an important source of gameplay through contraptions and modular buildables.
- Make genuinely three-dimensional factory construction necessary or strongly compelling. Here, the user's original term "vertical integration" means spatial verticality, not economic integration through a supply chain.
- Make power transmission a spatial and mechanical design problem, including changing machine speed through gearing.
- Keep the technological identity mechanical throughout progression, expanding into fluid/gas management and alien substances. Electricity is excluded.
- Support substantial factories with good performance, without inheriting Minecraft's runtime and mod-stack constraints.
- Refine and scope the idea collaboratively before committing to implementation.
- Treat multiplayer as a first-order requirement, including dedicated servers, high tick rates, and rollback or a better solution for responsive interaction.
- Develop rapidly as a solo project supported by a significant AI budget and agent teams. Keep as much game simulation as practical independent of the presentation engine.

## Working pitch — proposed

Build a three-dimensional factory by inventing machinery from modular tool heads, moving assemblies, mechanical transmission, and later fluid/gas systems and expressive controls. The technological identity stays mechanical as alien materials introduce new possibilities.

Begin in a designed industrial frontier and progress through guided chapters with optional branches. A humorous manager commissions off-site deliveries for a mysterious megaproject. An initial campaign payoff leads into a more demanding true ending requiring throughput across several end-game recipes, with continuing factory play available. Multiple cooperative teams can inhabit the world, with progression arrangements that allow people to learn at their own pace.

The central hypothesis: satisfaction comes from solving geometry, motion, quantities, and timing together, with room to invent a working approach rather than reproduce one intended machine.

Three-dimensional play is required. A voxel/block construction system is a candidate; first-person play and freely simulated rigid-body machinery have not been selected.

## Reference experiences supplied by the user

| Experience | What the user found satisfying | Design implication to investigate |
| --- | --- | --- |
| A wood farm using a gantry shaft, a contraption, and bidirectional saw blades | A better, easier-to-scale oscillating design: expansion was perpendicular to the shaft and did not require lengthening it, whereas a rotating design's swept footprint grew in all planar directions around a fixed origin | Geometry should produce meaningful differences in scalability between working designs |
| A circuit-controlled singularity producer whose recipe requires exactly the specified materials to be present | Engineering precise quantities and conditions | Sensors, buffering, metering, and sequencing deserve attention alongside transport |
| Routing cogwheels to make belts turn correctly with few extra pieces | Solving directional and rotational constraints efficiently | Mechanical topology and part orientation are substantive puzzles |

These are test cases for the design. We do not need to reproduce the original recipes or assets to preserve their appeal.

## Confirmed requirements and preferences

### World and terrain

- Start with one designed world. This is an initial direction, not a permanent restriction on future world structure or generation.
- Aim for a peaceful industrial frontier where engineering, terrain, and resource acquisition supply the main challenges.
- Some areas and resources require technology that allows the player to visit them safely. Specific hazards and protective/traversal capabilities remain open.
- Support limited terrain reshaping for purposeful excavation and factory-site preparation. Gate these capabilities behind technology; reshaping should not be easy early on.
- Retain the more demanding in-base acquisition routes for required capabilities alongside exploration shortcuts. Region-access technology should be designed in conjunction with those alternatives.

### Construction and movement

- Rotation, gantries, moving factories, and trains are all required in the intended game. Their implementation can be staged; they must inform architecture and scope from the beginning.
- Moving factories should operate in motion, harvest their surroundings, transfer materials with stationary equipment, and carry players. Construction/editing while moving is excluded. Detailed stopped/docked editing rules remain open.
- Three-dimensional space is essential. Use a mix of mandatory vertical processes and softer constraints rewarding verticality through efficiency or scalability.
- Explore gravity-driven processing together with directional tool faces and working clearances as the first ordinary reasons to use height.
- A global grid governs construction alignment; it does not require moving mechanisms to remain aligned at every operating position. Block/voxel dimensions and alignment/docking details are not selected.
- Collision should matter. Pushing separate machines is deferred at the user's request; focus first on collision behavior. For this discussion, a gantry and its contraption count as a single machine, rather than an example of one independent machine pushing another.
- Machinery can injure players. The injury model and detailed player-contact behavior remain open.
- Camera perspective is flexible. Moving around, working in, and building the world should remain enjoyable over long sessions.
- The preferred starting construction level is complete functional tool heads, such as saws or press heads. Players construct their power transmission, feeding, and moving assemblies. The exact tool catalogue and the role of other complete machines remain open.

### Complexity and automation

- Begin with accessible mechanics and increase technical depth gradually.
- Everything should ultimately be automatable. It may be difficult to achieve full automation, but a solved system should be capable of running without recurring player upkeep.
- Automating away manual tasks, such as mining, is a meaningful reward.
- Incorrect component placement should not cause destructive cascades that break a large portion of the factory.
- Invalid processing conditions, such as an extra item entering an exact-count recipe, should stall the process until corrected manually or through a player-designed recovery mechanism.
- An unintended solid obstruction stalls the mechanically connected drivetrain without damaging machinery. Clutches or slipping couplings can isolate branches and preserve operation elsewhere. Detailed collision consequences remain subject to later review; this choice does not resolve every contact case.
- Collision should occur with reasonable consequences. Clearance previews, automatic warnings, and activation restrictions were not selected; revisit those details later.
- Expressive controls should unlock later, with their required use well into the latter half of progression. Early progression should emphasize solving limitations of mechanical arrangement.
- Early motion uses parts with predictable fixed cycles, such as reciprocating motion or gantries reversing at end stops. Players coordinate operation through arrangement and gearing. The exact component set is not selected.

### Progression and teaching

- Provide direction within the sandbox through guided branching chapters. Each chapter has a clear overarching objective and related projects, with flexibility in order and in how machinery is built. Include optional branches.
- Gradually automate activities the player previously performed manually.
- Support players who need guidance while retaining increasingly challenging construction problems.
- Include in-game visual explanations comparable in purpose to Create's Ponder.
- The experience should include the pleasure of watching a factory grow.
- Scaling rewards have an explicit hierarchy: overclocking provides no meaningful design reward; duplicating tools and splitting feed belts is minimally rewarding; a higher-tech, harder-to-implement method of performing the same recipe is more rewarding.
- Progression must also introduce new products that require new processes. Improved output of existing products is one consequence of capability growth, not the entire progression structure.
- The user's illustrative A/B/C relationship: a new process is necessary for Item B; Item C creates greater demand for existing Item A; the player can expand the old A method or adapt the new process to improve its supply. A/B/C are placeholders, not selected content.
- Earlier methods should remain usable for problems they can solve while having obvious disadvantages in new factory constructions.
- Inventory-based, player-confirmed quest completion is the starting preference. Do not require proof of sustained automation as the default completion rule. Alternatives and multiplayer progress ownership remain open.
- The true ending is a separate, more demanding objective that requires specific throughput across several end-game recipes. Its products, rates, and completion measurement have not been chosen.
- Follow the existing Ponder-style demonstration approach; camera rotation and zoom are welcome. An editable tutorial sandbox is not part of the current preference.

### Inventory and resource acquisition

- Global storage can be a satisfying unlock; granting its full capability immediately may weaken progression.
- Repeatedly walking to chests, remembering a build's requirements, and fetching forgotten parts are significant pain points.
- The user used unlimited-range toolboxes for factory parts in the reference experience, but now clarifies that item location should retain logistical meaning, including for player access. That past convenience is not a requirement for unlimited remote access in this game.
- Avoid solving inventory friction through unrestricted item teleportation that invalidates belt logistics. Actual retrieval, delivery, and network coverage rules remain open.
- Support both players who enjoy exploration and players who prefer to remain at their base.
- Avoid mandatory prolonged searches for a particular resource such as melon seeds.
- Complicated in-base synthesis is an acceptable possible alternative to exploration. A specific elemental or chemical system has not been selected.
- Exploration should coexist with a more demanding in-base production route in the same world: exploration can offer an earlier or cheaper shortcut. The user endorsed this direction.
- Early node-based raw-material automation should permanently deplete its node. The player can repeat the find/extract/deplete pattern or choose a more elaborate route to fully automate supply.
- Support a mix of infinite sources and autonomous acquisition of finite sources. An infinite-source reference supplied by the user is Create's hose extraction from a sufficiently large lava pool; no exact threshold or equivalent game resource has been chosen.
- Active recovery-cycle sources can be a third approach later in progression. They should require meaningful engineering beyond waiting for regeneration and accepting reduced average output; they are too involved for the intended early and middle game.
- Lasting-supply methods should become available through technology/progression milestones after initial extraction is established. They should not be available from the beginning, and their unlocks should not be triggered or timed by a node being exhausted. Exact milestones remain open.
- Exact resource types, alternate recipes, unlock timing, and qualifying conditions for lasting supply remain open. Timing is central to balancing useful early scarcity against recurring replacement chores.

### Technological identity

- Mechanical industry remains central throughout the game. Progression should deepen its tools, motion, arrangements, and material handling.
- Fluid and gas management are desired extensions, alongside some alien substances and processes.
- Electricity is excluded from the technological arc. A transition through electrical industrial eras is not part of the intended game.
- Later expressive controls remain in scope; their physical form and signalling medium have not been chosen.

### Campaign and manager

- The user likes Satisfactory's quippy, existential AI-manager humor and some mystery about what the factory is building or why.
- Chapter goals serve a mysterious megaproject, with products delivered off-site. Communications, discoveries, and later reveals expose its purpose; a visibly growing on-site megastructure is not the selected presentation.
- The manager primarily acts as a chapter guide: communicates objectives, responds to deliveries or milestones, and provides occasional mystery hints while leaving room for uninterrupted construction.
- The campaign has a semi-ending, followed by a much harder true ending requiring specific throughput of several end-game recipes. Players can continue building beyond campaign milestones.
- Choosing a preferred manager personality is a possible future feature to keep in reserve, not a current requirement.
- An alien-world premise is acceptable. The specific setting, megaproject, narrative reveals, manager personality, and meaning of the two endings remain open.

### Multiplayer and progression ownership

- Multiplayer is essential; many day-to-day tests will still be single-player.
- Design for multiple cooperative teams in the same world.
- People should have an option to keep their own progression and learn at their own pace. The sharing model within a team, including how individual learning and team unlocks relate, must be revisited.
- Friendly industrial competition is a possible motivation between teams. Leaderboards were suggested tentatively; neither they nor a competitive mode are committed requirements.
- How chapter progress, technology access, and megaproject/story milestones are scoped across individuals, teams, and the shared world remains open. Do not treat a single shared server progression track as settled.
- Dedicated servers, high tick rates, and rollback or better are explicit technical targets. Numerical budgets and the scope of rollback are open.
- Detailed performance targets are deferred to a later conversation. The user's rig can serve as an initial baseline; its specifications have not been collected.

### Development approach

- The user starts with little game-design or 3D-graphics experience and no fixed engine preference. Rapid iteration is a major priority.
- Heavy use of AI-generated assets is acceptable. No art style or asset pipeline has been selected.
- Portability of game mechanics is desired if a future budget or ambition justifies switching engines. It should be pursued without assuming an engine switch will be inexpensive.

## Candidate design pillars — not yet agreed

### Machinery assembled from useful parts

Begin with complete functional tool heads that combine with player-built power transmission, feeding, and moving assemblies. Their layout and behavior should matter. Further levels of component construction and any complete starter machines need separate review.

Design question: which tool heads and shared mechanisms provide the most useful construction vocabulary?

### Genuine use of three-dimensional space

Include both hard constraints requiring vertical construction and soft constraints rewarding it. The first direction to explore combines gravity-driven processing with directional tool faces and working clearances. Vertical power transmission and transport crossings remain additional candidates.

The user proposed an alien material that decays when transported horizontally. This is a carefully bounded candidate, not the foundation of every vertical constraint or a property of all materials. It could apply to a selected intermediate while its finished product is stable. No material or recipe has been adopted.

Evaluate ordinary spatial and process constraints alongside this candidate. If horizontal decay is used, define its affected states, the measurement frame, cumulative travel versus displacement, and treatment of containers, player inventories, and moving assemblies. Keep detailed decay rules deferred while broader collision and vertical-construction mechanics are developed.

Design question: which vertical constraints create interesting construction rather than obligatory scaffolding?

### Controls are part of the machinery

Exact-count recipes and motion reversal create opportunities for sensors, gates, counters, buffers, actuators, and sequencing. Expressive controls unlock later and become required well into the latter half of progression. Early tasks should exploit limitations of mechanical arrangement.

Use parts with predictable fixed cycles as the starting approach to early repetition: examples include reciprocating cranks and gantries reversing at end stops. Players coordinate these through placement and gearing. The precise parts and behaviors remain open; player-built general sequencers and configurable cycle timers are not the selected starting approach.

Design question: which fixed-cycle parts give players enough variety to invent machines within understandable mechanical limits?

### Power as visible infrastructure

Power sources, transmission paths, rotation, and gearing should shape layout and operation. Direction and orientation constraints have demonstrated appeal. Evaluate speed and load rules against gradual learning and sustainable automation.

Design question: how can mechanisms remain understandable while offering meaningful tradeoffs?

### Difficult to design, dependable when solved

Introduce depth through construction and control rather than recurring chores. Invalid processing conditions stall until a player or a designed recovery mechanism corrects them. An unintended obstruction stalls the connected drivetrain without machinery damage, with mechanical isolation available to contain it. Other contact and fault cases remain open. Any required consumable, replenishment, or recovery process should have an eventual automated solution.

Design question: which operating failures provide useful feedback, and can a correctly designed factory recover from them independently?

### Progression expands capability and removes manual work

Organize progression into guided branching chapters with optional projects, flexible order within prerequisites, and freedom in construction solutions. Exact chapter objectives and dependencies remain open.

Within that structure, unlock new motions, tools, materials, processes, fluid/gas management, and eventually expressive controls while replacing manual tasks with automation. Keep the technological arc mechanical. New processes must enable genuinely new products as well as possible improvements to existing supply.

| Illustrative stage | Production requirement | Engineering decision |
| --- | --- | --- |
| Establish Item A | An initial process can make A | Learn and arrange an accessible production method |
| Introduce Item B | B requires a newly introduced process | Learn the new process for a capability the old method cannot provide |
| Introduce Item C | C requires greater throughput of A | Expand the existing A method or adapt the newly learned process for better A supply |

This is a relationship to preserve across the tech tree, not a required three-step template for every product. Specific items, process order, throughput ratios, and unlock criteria remain open.

Keep multiple production methods for important products under consideration. An advanced method should demand a different arrangement, tool interaction, material presentation, or sequence and earn meaningful capacity or other advantages. A more expensive single-placement machine with a larger output number would not by itself meet this goal.

Earlier methods remain valid for the tasks they can solve. Their footprint, scaling, power routing, handling, or other practical disadvantages should be evident when building newer factories. Exact drawbacks need design; do not mandate replacement solely through a technology-tier prohibition.

The exact hierarchy of early methods remains open. In particular, do not assume that the gantry design is automatically a later technology than rotation; its geometry demonstrated a design advantage rather than an established unlock order.

Design question: which milestones introduce a new kind of engineering problem?

### Campaign closure and mastery

The guided chapters and off-site commissions lead to an initial semi-ending. A much harder true ending asks for specified throughput across several end-game recipes, extending the campaign into a substantial production challenge.

This objective can draw on the earlier progression pattern: new processes enable new products, while their demand prompts the player to expand or redesign earlier supply. Which systems the true ending combines, its narrative payoff, and how completion is recognized remain open.

Normal inventory-based quest checks and the true ending's throughput requirement serve different purposes. Preserve both when developing progression; do not silently replace the ordinary completion model with universal throughput tests.

### Performance supports the fantasy

Factory scale, moving structures, visible items, target hardware, and acceptable simulation/rendering rates need later investigation. These are deliberately deferred rather than assigned arbitrary numbers now. Engine selection should remain provisional until representative mechanisms and multiplayer interactions are measured.

Language choice alone is not a performance plan. An eventual prototype should measure the costly interactions the design actually requires.

## Possible play loop — to validate

1. Receive a comprehensible chapter objective or identify a manual task worth eliminating.
2. Learn the relevant parts through a visual demonstration and small experiments.
3. Construct material handling, motion, power transmission, and any necessary controls.
4. Observe behavior and diagnose direction, quantity, timing, or capacity problems.
5. Reach dependable automation and gain a new capability or remove a recurring manual task.
6. Learn a new process for a new product, then scale, adapt, or combine earlier machinery as new demands and off-site commissions emerge.

Unresolved: the concrete chapter content, number of effective solutions to each challenge, physical delivery requirements, and how individual/team progression fits the shared world.

## Design directions and proposals requiring review

### Construction convenience and logistics progression

Preserve item location while reducing memory and repetitive-fetching friction:

- Ghost placement or build plans retain the intended assembly and report missing parts.
- A remembered bill of materials removes the need to mentally track a shopping list.
- A searchable catalogue can show what exists and where, without granting remote physical access.
- A local toolbox or construction cache can reduce trips within a bounded area. Its radius and access rules remain open.
- Later conveyors, carts, trains, or other delivery infrastructure could fulfil construction requests. Specific systems are not selected.
- Bulk production inputs still require physical handling and infrastructure.
- Later storage and delivery upgrades can expand search, sorting, dispatch, and physically supported supply coverage. Global knowledge of storage does not imply unrestricted global withdrawal.

Open question: what connection or actual transport should be necessary before the player can build using parts stored elsewhere?

### Exploration and in-base alternatives

For required capabilities, provide an exploration route and a more demanding infrastructure route within the same world. Exploration can provide an earlier or cheaper starting resource; in-base production can require a longer but reliable process. The user endorsed this direction. Individual resources and cost differences are not designed yet.

Start with a designed world that can place these opportunities deliberately. Some regions require technology to visit safely, and substantial terrain preparation unlocks later. Account for those access conditions when creating exploration shortcuts and in-base alternatives; the specific dependencies remain open.

Avoid a required capability being hostage to an unbounded random search. Renewable or synthesizable inputs alone do not establish complete automation: extraction, replenishment, transport, byproducts, and eventual depletion all need consideration.

Open question: which forms of feedstock and capacity keep the infrastructure route challenging without making a required resource inaccessible?

### Resource pressure without recurring manual replacement

Early node-based extraction permanently exhausts its local deposit. Repeating discovery and extraction remains an available approach. More elaborate systems eventually automate the whole supply problem.

This makes the transition to lasting supply a progression choice. Lasting-supply routes unlock through technology milestones after initial extraction has been established, rather than being available from the beginning. Node exhaustion creates an incentive to pursue them; it is not an unlock trigger or a timing condition. The exact chapter, prerequisites, and pacing remain open.

Balance deposit lifetime against those progression opportunities without assuming every player exhausts a node at the same point. The game should offer a credible path to solving supply before replacement work becomes overwhelming.

| Supply route | Design direction | Progression role and unresolved detail |
| --- | --- | --- |
| Continue finding and exhausting nodes | A valid simpler approach that consumes finite local reserves | The player can defer the more elaborate supply project; deposit lifetime and travel burden need tuning |
| Establish an infinite source | Some materials can gain lasting supply through a qualifying physical source or engineered system | The user supplied a large-lava-pool analogy; eligible materials, construction requirements, and location rules remain open |
| Automate acquisition of finite sources | Surveying, movement, extraction, and connection can become factory operations | Alternate long-term route; scope and reliable handling of terrain/routes remain open |
| Engineer an active recovery cycle | Regeneration depends on designed operations rather than passive waiting alone | A later-game route with meaningful phase/control challenges, not a duty-cycle throughput penalty |

Use a mix of infinite-source and automated finite-source routes. The user also accepts a carefully designed late recovery-cycle route. This does not imply every material supports every route or that all sources eventually become infinite.

A lower-grade durable source or an in-base synthesis process remains a possible implementation of lasting supply, rather than a selected universal resource model. Preserve the agreed exploration shortcut and more demanding in-base path for required capabilities.

For threshold-qualified sources, consider how connected geometry, depth, source volume, or machinery could matter. Do not assume that merely accumulating enough items in any container makes every resource inexhaustible. These are implementation questions, not adopted world rules.

Any recovery-cycle design must involve useful construction or phase coordination that cannot be reduced to waiting out a timer at a lower mean rate. The exact operations, dependencies, and late unlock are not selected.

An eventual fully automated route must cover its necessary feedstocks, replenishment, transport, and recovery. Specific alternate recipes should be checked for dependencies that reintroduce mandatory manual acquisition.

If finite deposits are used before autonomous replacement or permanent supply becomes available, the transition should not depend on resources the player can permanently exhaust without another route. Existing production methods remain useful even after a more elaborate supply method unlocks.

### Quest completion

Start with obtaining the requested product in inventory and manually confirming the quest, following the user's preferred reference. Completion should not be presented as proof that the product was automated.

The true ending additionally requires specific throughput of several end-game recipes. This is a targeted late-game requirement, not a replacement for ordinary quest checks.

Proposed default: checking an item does not consume it. Consumption rules, the relationship between checks and physical off-site deliveries, and completion measurement for the true ending need discussion.

Multiple cooperative teams should coexist while people have an option to progress at their own learning pace. Per-player versus team sharing, credit for jointly produced items, and the scope of story milestones remain open. Friendly competition or leaderboards are possible future directions rather than required completion mechanics.

### Ponder-like explanations

Provide contextual, inspectable demonstrations of parts and interactions, following the user's preferred Ponder-like approach. Include camera rotation and zoom in the design direction. Pause/step controls, direction arrows, visible inventory counts, signal traces, and failure examples remain candidate presentation details.

Use shared mechanism definitions and simulation where practical so teaching scenes remain consistent with gameplay. Presentation can still be scripted. Keep editable practice scenes outside the initial teaching scope unless that preference changes.

Teach the relevant rule and a working example without making that example the only effective design.

### Predictable motion and physical appearance

Consider explicit rules for shafts, gearing, rails, and gantry travel, with controlled assembly transforms. This could preserve spatial engineering while reducing the need to solve every tooth contact or carried item through general rigid-body physics. Use the global grid for construction alignment.

Collisions are meaningful gameplay, and machinery can injure players. An unintended obstruction stalls the connected drivetrain without machinery damage; clutches or slipping couplings can isolate branches. Detailed collision consequences are reserved for later discussion.

Pushing separate machines is explicitly deferred. Treat a gantry and its attached contraption as one machine for this discussion; its internal clearances and intended tool interactions still need design.

Construction alignment does not require every operating position to align with the world grid. Reattachment, docking, allowed construction orientations, and connecting power or item ports still require concrete definitions.

Exclude construction/editing during motion. Stopping alone may or may not be sufficient for editing; requiring docking or grid alignment remains open. Existing control and transfer interactions while moving are required, subject to later detailed rules.

Keep collision handling provisional beyond those broad decisions. No policy was selected for clearance previews, automatic warnings, or refusing activation; the user prefers actual collisions with reasonable consequences and asked to revisit the details at a later stage. Distinguishing intended tool/material contact from an obstruction remains necessary design work.

The severity of player injury, contact with dropped items or other moving assemblies, and terrain interaction remain open. Do not infer a specific damage, health, or respawn system from the decision that machinery can injure players.

## Technical direction — proposed, not selected

### Separate rules from their presentation

Keep authoritative factory state, processing, mechanical topology, control signals, and machine definitions in a simulation core that can run without the graphics engine. Expose explicit commands and state/events to presentation and networking adapters.

The core should own exact recipe quantities and sequencing, so visual simplifications cannot change whether a precision recipe succeeds. Stable identifiers, controlled randomness, documented update order, and reproducible command replay are candidate foundations.

The engine would handle rendering, camera, input, UI, audio, and the chosen character/collision integration. That boundary still needs care for moving platforms and factories, where player movement and machinery interact.

Portability should protect the mechanics and headless verification first. Scene/editor workflows, rendering, UI, engine physics integration, and some assets may require substantial rework during an engine switch. Avoid building a general-purpose engine abstraction before a real need emerges.

### Multiplayer from the first representative prototype

Single-player should exercise the same authoritative rules as the server. A useful early verification setup is one headless server and two clients building and interacting with the same mechanisms, even if most iterative playtests use one client.

Evaluate server authority, input ordering, prediction, reconciliation, and rollback/resimulation against concrete interactions. Multiplayer requirements include simultaneous edits of stationary structures, precise-count processing, passengers on moving structures, collisions, transfers in motion, reconnects, and persistent factory operation. Construction/editing in motion is excluded. Independent machine pushing is deferred and should not be treated as an initial implementation requirement.

The eventual game supports multiple cooperative teams and a progression arrangement that preserves learning at different paces. Ownership and progression sharing are not yet designed. Account for that boundary before assuming all connected players share technology, chapter completion, or one megaproject state. Later unlocked terrain modifications also need to fit a shared persistent world.

The user's high-tick-rate and rollback-or-better targets remain intact. Do not assume that every factory object must be rewound after each late input. Determine which subsystems need prediction/replay and which can render confirmed or interpolated state. Simulation ticks, snapshot sending, and visual frame rates are distinct budgets; numerical targets remain deferred.

Relevant precedents, not selected architectures:

- Factorio documents a deterministically simulated game state with a smaller predicted latency state: [developer explanation](https://www.factorio.com/blog/post/fff-302).
- Unreal documents prediction and resimulation with stored state history, alongside interpolation modes with different costs: [networked physics overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/networked-physics-overview).

Neither precedent automatically solves this game's moving-world interactions or establishes its scale.

### Engine evaluation

Godot with a separately maintained native simulation core is a candidate for a prototype. Its documentation describes [headless dedicated-server exports](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html), [command-line tooling](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html), and [native-library integration through GDExtension](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/what_is_gdextension.html). This makes it worth evaluating against rapid iteration and portability goals; it is not evidence that it will meet the eventual performance budget.

Unreal is another candidate. As checked on 2026-10-14, Epic's published roadmap targets UE6 Early Access for the end of 2027, with full release 12–18 months later. UE6 should therefore not be assumed to be a production-ready starting point today: [Epic's roadmap](https://www.unrealengine.com/news/the-road-to-ue-6).

Before choosing, assess the actual edit/build/play loop and one representative mechanical scene, including a moving platform and multiplayer. Compare the integration burden as well as the visuals. No language, engine version, or networking library has been chosen.

## Open design topics

Continue discovery through question cards with suggested directions when the interface is available. Keep the discussion at the level of the intended experience, identity, and scope before resolving detailed simulation behavior.

- The first chapter and playable experience: core tools/processes that demonstrate invention, new-product progression, and scaling choices.
- Chapter objectives, optional-branch rewards, and the progression milestones that introduce lasting supply.
- The role of fluid/gas management and alien substances within the mechanical technological arc.
- The specific designed world, technology-gated areas, and limited terrain-reshaping capabilities.
- The megaproject, manager's personality, reveals, and narrative distinction between the semi-ending and true ending.
- The end-game recipes and throughput targets that define the true ending, including how completion is recognized.
- Construction supply and storage progression that reduce errands while preserving physical item location and transport.
- Individual/team/world progression ownership, preserving each player's learning pace, and how item checks relate to physical deliveries.
- The balance of natural sites and engineered systems for infinite sources, and the scope of autonomous finite-source acquisition.

Deferred conversations: detailed collision consequences and feedback; independent machine pushing; detailed horizontal-decay rules; exact performance budgets and rig baseline; preferred camera/navigation controls and visual direction; multiplayer player counts and network-quality targets.

Ideas held in reserve: selectable manager personalities and possible industrial leaderboards. Future world structure can be reconsidered after starting with a designed world. None is a commitment for the first version.

## Scope ledger

No engine, language, world format, camera, art style, simulation model, multiplayer architecture, numerical performance target, or production schedule has been selected.

| Topic | Current status | What will resolve it |
| --- | --- | --- |
| Essential experience | Motion invention, exact-count controls, cog routing, and geometry-dependent scaling grounded in user examples | New-product processes with optional benefits to earlier production |
| World and terrain | Start with a designed peaceful frontier; technology gates safe access to some regions/resources and limited terrain reshaping | Concrete world, access technologies, and excavation capabilities; future world structure stays open |
| Modular machinery | Complete functional tool heads; players construct transmission, feeding, and moving assemblies | Tool catalogue and shared construction vocabulary |
| Moving contraptions | Required; operation, harvesting, transfers, and passengers in motion; no construction in motion; machinery can injure players | Global-grid construction/docking rules; detailed collision consequences and pushing deferred |
| Spatial verticality | 3D required; gravity-driven processing plus tool faces/clearance are the first focus | Concrete processes and layouts; decay remains limited to possible special intermediates |
| Mechanical power | Direction and orientation constraints valued; connected drivetrain stalls without damage; isolation through couplings | Load rules, inspectability, and detailed collision handling |
| Automation | Fully unattended operation is a goal; invalid processing stalls and supports designed recovery | Resource lifecycle and other mechanical fault rules |
| Progression and teaching | Guided chapters with optional branches; new processes/products and scaling choices; fixed-cycle early motion, later expressive controls; ordinary inventory checks and demonstrations | First chapter, component set, delivery rules, and progression ownership |
| Storage and exploration | Item location matters; physical logistics retained; exploration shortcuts and harder in-base alternatives coexist | Construction delivery and individual acquisition recipes |
| Resource pressure | Early nodes deplete; lasting supply unlocks through progression, independently of exhaustion; infinite and autonomously acquired finite sources coexist; active recovery is late | Specific milestones, eligible sources, and acquisition recipes |
| Technological identity | Mechanical throughout, with fluid/gas management and alien substances; electricity excluded | Specific processes and physical form of later expressive controls |
| Tone and endgame | Humorous chapter-guide manager; mysterious off-site megaproject; semi-ending and harder true ending requiring several end-game recipe throughput targets | Specific project, reveals, recipes, rates, and recognition of completion; manager selection held in reserve |
| Performance | Important; details intentionally deferred | User's rig and representative scale benchmarks |
| Multiplayer | Required from the outset; multiple cooperative teams; people can retain their own learning pace; friendly competition remains tentative | Individual/team/world progression sharing, prediction/rollback scope, and measured responsiveness |
| Production approach | Solo plus substantial AI support; rapid iteration and mechanics portability desired | Representative prototype and engine evaluation |

## Candidate prototype — revised proposal, not a commitment

A small mechanical testbed could include a power source, shafts/gears, belts, complete functional tool heads, fixed-cycle rotary/gantry motion, and representative solid obstructions. It should explore arrangement, working clearances, repetition, and the broad connected-drivetrain stall rule before introducing expressive controls. Detailed collision policies remain deferred.

An initial progression slice could then add finite extraction, Item A, a new process required for Item B, and Item C's increased demand for A. Compare scaling the old A route with adapting the new process. Present this within a small guided chapter with an optional project. Lasting-supply availability should follow a technology milestone, not a depleted-node event. Include a minimal visual explanation and the multiplayer test setup from the beginning.

Use a small designed site to test early terrain constraints and a placeholder off-site commission. The full campaign, its two endings, multiple-team progression, and later terrain capabilities still require staging; their presence in the game concept does not select an implementation schedule.

A separate later-progression test can introduce sensors, metered input, and an exact-count task based on the user's circuit example. Testing that mechanism early in development does not mean unlocking it early in the player-facing progression.

Stage moving-factory and train development while validating their critical architectural interactions early, particularly passengers and transfers between moving and fixed structures. The testbed is an initial slice of the required game, not a removal of those requirements.

Explore a vertical process combining gravity with directional tool faces or working clearance once its physical rule is agreed. Use stationary editing. Keep independent machine pushing outside the current test scope.

A repeatable resource fixture can support isolated mechanism tests without setting the world's resource rules. This remains a proposal pending resource timing, collision behavior, process selection, and construction-supply decisions.

## Reference sources

These are the named inspirations, not a commitment to reproduce their content or systems unchanged.

- [Create: Above and Beyond — official project](https://www.curseforge.com/minecraft/modpacks/create-above-and-beyond) and [source repository](https://github.com/simibubi/Above-and-Beyond).
- [CABIN — project page](https://www.curseforge.com/minecraft/modpacks/cabin) and [source repository](https://github.com/ThePansmith/CABIN).
- [Create's Ponder documentation](https://github.com/Creators-of-Create/Create/wiki/Internal---Ponder-UI), describing contextual demonstration scenes and storyboards. This is a historical implementation reference, not a required implementation model.

## Decision log

- 2026-10-14: Captured the initial goals and opened discovery. All design pillars, the play loop, and the prototype example remain proposals.
- 2026-10-14: Recorded the user's first-round answers. Corrected the earlier interpretation of vertical integration to spatial verticality. Established required motion types, gradual complexity, unattended automation, Ponder-like teaching, 3D play, and multiplayer. Kept machine granularity tentative, performance targets deferred, and engine/simulation/storage/world choices open. Revised the candidate prototype around the three concrete reference experiences.
- 2026-10-14: Recorded the second-round answers. The gantry farm improved geometric scalability. Higher-tech methods of the same recipe are more rewarding than overclocking or tool duplication. Established mixed hard/soft vertical constraints, location-sensitive inventory, processing stalls with designed recovery, inventory-based quest checks, and exploration/in-base alternatives in one world. Captured the global-grid intuition, meaningful collisions/pushing, the late requirement for advanced controls, and exclusion of construction in motion. Resource pressure remains unresolved; added three candidate models rather than selecting universal finite or infinite deposits.
- 2026-10-14: Recorded the third-round answers. Corrected progression to include new products requiring new processes, with increased demand for earlier products creating optional redesign/scaling choices. Early node-based extraction permanently depletes nodes; everything should ultimately be automatable through a mix of infinite-source and autonomous finite-source routes, with active recovery cycles reserved for later. Earlier methods remain viable with practical drawbacks. Expressive controls unlock later; early creativity comes from mechanical limits. The global grid governs construction alignment. Deferred independent machine pushing and detailed horizontal decay; limited any decay proposal to selected materials/states and refocused discussion on collisions and ordinary vertical constraints.
- 2026-10-14: Incorporated the question-card answers. Selected connected-drivetrain stalls without machinery damage and isolation through clutches/slipping couplings. Lasting supply becomes available through progression after initial extraction, with no node-exhaustion trigger or timing dependency. Selected fixed-cycle early motion, complete functional tool heads, and a combined gravity/tool-face/clearance direction for verticality. Machinery can injure players; detailed collision consequences and feedback remain deferred. Selected guided branching chapters with optional branches and a mechanical technological identity expanded by fluids, gases, and alien substances; electricity is excluded. Future discovery should use question cards when available and stay at a higher level.
- 2026-10-14: Synthesized the world/campaign/multiplayer question session. Start with a designed world while keeping future structure open. Aim for a peaceful industrial frontier with technology-gated safe access and limited, later-unlocked terrain reshaping. A chapter-guide manager commissions off-site deliveries for a mysterious megaproject. The campaign offers a semi-ending and a much harder true ending requiring throughput across several end-game recipes, with continuing play available. Multiple cooperative teams are intended; independent learning pace matters, but sharing within teams remains unresolved. Friendly competition, leaderboards, and selectable manager personalities remain tentative or reserved ideas.
