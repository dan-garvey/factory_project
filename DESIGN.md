# Factory game — working design document

Status: discovery draft, revised 2026-10-20 UTC to include feedback from the user's first played demo. Requirements come from the user; demo defaults are identified separately. Godot use is accepted for current development, with its constraints explicitly recorded; no permanent production implementation stack has been selected.

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

Three-dimensional play with a player-controlled physical character is required. A voxel/block construction system is a candidate; first-person play and freely simulated rigid-body machinery have not been selected. Camera perspective does not replace the character's physical location or grant construction access.

## Reference experiences supplied by the user

| Experience | What the user found satisfying | Design implication to investigate |
| --- | --- | --- |
| A wood farm using a gantry shaft, a contraption, and bidirectional saw blades | A better, easier-to-scale oscillating design: expansion was perpendicular to the shaft and did not require lengthening it, whereas a rotating design's swept footprint grew in all planar directions around a fixed origin | Geometry should produce meaningful differences in scalability between working designs |
| A circuit-controlled singularity producer whose recipe requires exactly the specified materials to be present | Engineering precise quantities and conditions | Sensors, buffering, metering, and sequencing deserve attention alongside transport |
| Routing cogwheels to make belts turn correctly with few extra pieces | Solving directional and rotational constraints efficiently | Mechanical topology and part orientation are substantive puzzles |

These are test cases for the design. We do not need to reproduce the original recipes or assets to preserve their appeal.

## Confirmed requirements and preferences

### First chapter: basics before elaborate machinery

- The immediate objective is a demoable opening that lets the user give feedback on the initial systems. The user has now played the basic loop and confirmed that it meets the earlier functional scope, but requires substantially higher production quality. Satisfactory is the minimum graphical quality target; rough placeholder presentation must no longer set the baseline for continuing development. Graphics, machine design, interaction feedback and construction sound should develop together. See the [production presentation target](docs/art/production-quality.md).
- The first playable loop can be as simple as placing a resource collector, feeding its output into a machine, and collecting the machine's product. Complete, single-placement starter machines are acceptable for this phase; constructing a complicated processor or moving factory is not required.
- Fixed-place, stationary contraptions and subfactories are the priority for early chapter development. They may contain moving tools and mechanical transmission; this is not a ban on internal motion. Travelling factories, trains, and passenger integration must not displace the stationary basics.
- The player controls a physical character and places components/builds machinery within limited proximity. Integrating that character and construction reach into the basic opening is now required; the existing unrestricted free-camera builder is a historical prototype, not evidence that this requirement is met.
- Player-built motion is welcome later within chapter 1, after the basic placement, transport, and processing experience works. It need not be deferred to a later chapter, but it must not block the initial loop or feedback on it.
- The user's resource A → machine B → product C example describes one production chain, not three products or a requirement to fit the earlier new-process/scaling pattern into the opening.
- The broader engineering identity remains intact. Motion invention, cog routing, meaningful verticality, new-product progression, scaling choices, and eventual full automation can be introduced in stages rather than all being first-demo acceptance criteria.
- The played first shift lacks an engineering challenge. Preserve the working introduction and follow it with a concrete spatial or mechanical constraint using familiar parts and more than one valid arrangement. This does not retrospectively reject the earlier basic-loop scope.
- Building a belt between compatible devices should establish the material connection as part of that operation, without a separate connection step. Keep mechanical power transmission and authoritative endpoint validation intact.
- Help must eventually demonstrate assembly and operation in readable Ponder-style stages rather than only present a completed machine. The user has left this follow-up open while graphics receives substantial focus.
- The delegated opening defaults below resolve only the next reversible demo. Wider resources, recipes, reach distances, construction-supply details and progression remain open. Physical-character/proximity construction is confirmed, not an open choice. This scope clarification does not waive multiplayer-first development and authoritative item accounting.

#### Feedback from the first played demo

The user's subsequent play feedback revises the original opening defaults:

- Reduce visible text and introduce construction tools progressively. Keep the next action readable without presenting the whole catalogue at once.
- A bad or incomplete line must remain recoverable. Let the player remove retained material from the collector or other occupied machine, rather than directing every retrieval to the press or trapping the machine behind its contents. Preserve the material's actual form and ownership.
- Removing stationary equipment must not require stopping the whole drive. Reject destructive edits without losing material, and provide a usable recovery route. This does not authorize construction on travelling machinery.
- Offer individually placed cogwheels and shafts with meaningful orientation, engagement and rotation. Arbitrary cell-to-cell drive links, even with decorative gears, do not satisfy this requirement. Exact sizes, kits and introductory arrangements remain revisable.
- Improve character, machine and environment presentation into a coherent prototype, including readable silhouettes and flow. Responsive layout must keep controls usable when the window is resized. Final art style and production assets remain open.

These are requested outcomes, not claims that the current implementation or any automated fixture fulfills them. The native implementation and Bazel requirements below also follow the user's later directions.

#### Delegated defaults for the basic opening demo

The user has asked agents to choose from the documented preferences and wait for permission less often, with later course correction available. Use that authority for reversible prototype content and implementation decisions, recording assumptions and evidence. Do not turn an experimental default into a permanent game or production-stack commitment. Keep the established local resource limits, task ownership and independent integration review; ask about new paid commitments, destructive actions or publication beyond the already authorized scope.

Start with the following bounded defaults. They are chosen for the opening experiment, rather than assertions that their balance or wider progression is proven.

| Surface | Opening default |
| --- | --- |
| Production | A complete softmetal cutter/collector removes standardized blanks from a finite exposed seam. A short player-placed belt feeds a complete press; one blank becomes one plate. No channel rolls, component kits or custom carrier are required. |
| Starter power | A waterwheel placed in flowing water provides rotation according to the local current's speed and direction. Its axle shares the same world-space height origin and offset as shafts on foundations. The player places individual shafts and cogwheels; power follows their geometric engagement rather than arbitrary drive links. The initial current may be a declared non-consuming site field rather than a fluid simulation. The minimum wheel is one tile wide along its axle and three tiles in diameter; larger integer diameters, transmission sizes and kit remain revisable. |
| Site and construction | One small 3D site with an accessible seam and stream. A controlled physical character places nearby stationary complete machines and transport on the global construction grid. Camera/raycast location alone cannot grant reach. Choose and record a tunable initial range, rather than a permanent number. Begin with physically carried parts sufficient for one working path and a rebuild; placement consumes actual carried parts, dismantling returns them without loss. No remote withdrawal or hidden part refill. |
| Material handling | The seam starts with 16 blanks for this test fixture. Collector output, processor input, held work, belt contents and processor output have explicit authoritative owners. Use one-item machine input/output buffers; a full destination pauses upstream delivery or processing and retains the work. Removing the blockage resumes the same work without duplicate consumption/output. |
| Processing and editing | A fixed configured work cycle produces one plate from one blank; no scrap, wear, fuel or additional ingredients in this experiment. Missing power pauses work without clearing it. Stationary edits and dismantling do not require stopping the global drive. Reject changes that would delete retained material and offer recovery of raw stock, products and unfinished work without silently changing their forms or progress. No construction in motion is introduced. |
| Objective and credit | Retrieve four plates into the player's inventory and explicitly confirm the objective. Confirmation does not consume them. This is a session goal, with no technology unlock, off-site dispatch, shared campaign credit or proof-of-automation requirement. |
| Two-client access | Both provisional test participants may build and interact with the fixture stock and machinery. Construction requests are validated against their authoritative character location/reach and actual parts/quantities; show concurrent refusals and corrections. Shared fixture access does not select the game's team, learning or progression model. |
| Explanation and evidence | A small read-only rotate/zoom explanation shows placement, mechanical connection, the blank's path and occupied-output recovery. Verify the same rules headlessly, through two clients constructing stationary equipment, and across partial-work save/continuation; then observe the user's actual first session. |

The quantities and work-cycle duration are tunable fixture values, not game performance targets. Preserve finite-node depletion and exact item locations across save/rejoin. The initial stock is declared once; resetting between test runs is disclosed and never presented as lasting supply. No reserve-protection mechanic, infinite material source, carrier dwell/rehome system, full construction-part crafting, terrain reshaping or later chapter arc is adopted by these defaults. Later motion, lasting supply and broader ownership still get their own scoped decisions informed by the opening feedback.

### World and terrain

- Start with one designed world. This is an initial direction, not a permanent restriction on future world structure or generation.
- Aim for a peaceful industrial frontier where engineering, terrain, and resource acquisition supply the main challenges.
- Some areas and resources require technology that allows the player to visit them safely. Specific hazards and protective/traversal capabilities remain open.
- Support limited terrain reshaping for purposeful excavation and factory-site preparation. Gate these capabilities behind technology; reshaping should not be easy early on.
- Retain the more demanding in-base acquisition routes for required capabilities alongside exploration shortcuts. Region-access technology should be designed in conjunction with those alternatives.

### Construction and movement

- The player must control a physical character in the world. Proximity restricts placing components and building machines; later technology can overcome that restriction. The exact range, reach reference, operation coverage and upgrade mechanisms need scoped design and testing, not an unlimited baseline builder.
- Keep character location, construction reach, camera controls and construction-stock delivery distinct. A distant view or known storage location does not itself authorize remote construction or teleport its materials. Longer reach alone does not imply remote access to stock.
- Fixed/stationary contraptions and subfactories have early chapter priority. Internal gearing, moving tool heads and other local mechanisms can deepen those factories before mobile factories are introduced.
- Rotation, gantries, moving factories, and trains are all required in the intended game. Their implementation can be staged; they must inform architecture and scope from the beginning.
- Moving factories should operate in motion, harvest their surroundings, transfer materials with stationary equipment, and carry players. Construction/editing while moving is excluded. Detailed stopped/docked editing rules remain open.
- Three-dimensional space is essential. Use a mix of mandatory vertical processes and softer constraints rewarding verticality through efficiency or scalability.
- Explore gravity-driven processing together with directional tool faces and working clearances as the first ordinary reasons to use height.
- A global grid governs construction alignment; it does not require moving mechanisms to remain aligned at every operating position. Block/voxel dimensions and alignment/docking details are not selected.
- Player-built foundations create level factory surfaces across uneven ground. Foundations, machines and other constructables share a world origin and height denominator, so independently built sections can align horizontally and vertically. The former special construction rectangle is removed. Exact foundation dimensions, supply and height step remain tunable prototype choices.
- Foundations can stack vertically, float and intersect natural terrain, rocks and vegetation. Gravity and ground-contact requirements are omitted for now. Players can place a rectangular area of foundations at a chosen common-grid height; area placement may temporarily ignore construction distance. Finite carried parts and collisions with constructed machinery, other foundations and characters still apply.
- Collision should matter. Pushing separate machines is deferred at the user's request; focus first on collision behavior. For this discussion, a gantry and its contraption count as a single machine, rather than an example of one independent machine pushing another.
- Machinery can injure players. The injury model and detailed player-contact behavior remain open.
- Camera perspective is flexible. Moving around, working in, and building the world should remain enjoyable over long sessions.
- Complete functional tool heads, such as saws or press heads, are the preferred vocabulary for constructed machinery. Players construct their power transmission, feeding, and moving assemblies as those systems are introduced. Complete starter machines are also acceptable for the basic opening loop; the exact catalogue and later role of complete machines remain open.

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

The [stationary delivery ownership experiment](docs/engineering/progression-ownership-trial.md)
selects personal learning and recipe entitlement with explicitly optional shared
campaign credit for a later reversible trial. It does not implement those systems,
change the current four-plate session goal or settle permanent campaign policy.
Its physical custody, consumption and team-change rules remain experimental;
source review does not establish implementation or user-play evidence.

### Development approach

- The user starts with little game-design or 3D-graphics experience and no fixed engine preference. Rapid iteration is a major priority.
- Heavy use of AI-generated assets is acceptable. No art style or asset pipeline has been selected.
- Portability of game mechanics is desired if a future budget or ambition justifies switching engines. It should be pursued without assuming an engine switch will be inexpensive.
- The user explicitly delegates reversible design and technical choices toward the demo. Agents and the PM should use the documented preferences, record assumptions, keep implementation moving and allow later course correction instead of awaiting routine decisions. User play remains valuable evidence, not a prerequisite for all further development.
- Research UE5 and promising free 3D environments and establish a sandbox/tests on the most promising route. This is a reversible trial, not production lock-in. A first engine-native rules baseline may expose coupling/portability costs; it must not be reported as proof of an engine-independent core.
- Godot is acceptable for current development. Explicitly record constraints imposed by its APIs/runtime and by our adapters, separately from intended game rules, in the [framework constraint register](docs/engineering/godot-constraints.md). A convenient engine default, unsupported probe case or implementation shortcut must not silently become game design.
- If Godot cannot meet the production-quality target, explore alternative engines rather than reducing that target. Assess the actual asset and renderer path before attributing the current presentation to an engine ceiling; preserve the portable native simulation.
- Maintain a continuing research pipeline for factory builders and adjacent engineering-puzzle games, including Zachtronics games. Build an evidence-backed collection of interesting puzzles, not just a feature list. Thoroughly studied games can be marked complete under recorded coverage to avoid duplicate research; completing one batch does not complete the pipeline. See the [research catalogue and study contract](docs/research/README.md).

## Candidate design pillars — not yet agreed

### Machinery assembled from useful parts

Develop complete functional tool heads that combine with player-built power transmission, feeding, and moving assemblies. Their layout and behavior should matter. The opening may use complete starter machines before introducing that construction vocabulary; further levels of component construction remain open.

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
3. Place or construct the required machines and material handling; add power transmission, player-built motion, and controls as the current stage introduces them.
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

### Native implementation direction

After actual demo play, the user directed implementation toward a high-performance
language such as C++ or Rust and rejected further Python scaffolding. New project,
test-harness and operations implementation must not be written in Python. The first
reversible native increments use the existing C++ toolchain. Godot remains accepted;
the present GDScript authority and Python launch/check infrastructure are migration
baselines, not permanent architecture. See the [migration contract](docs/engineering/native-migration.md).

Bazel is the canonical build system. Use incremental builds and dependency-correct
cache reuse to shorten iteration; a faster build does not waive relevant tests or
independent review. Existing mandatory checks remain active until reviewed
replacements preserve their contracts.

Preserve one authoritative simulation, exact material ownership and the existing
mandatory checks while replacing boundaries in reviewed increments. A standalone
native rule library is a foundation, not evidence that the playable demo uses it.
Replacing a launcher does not improve simulation or rendering by itself. Production
engine adoption, measured performance and cross-platform support remain separate.

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

The user accepts using Godot for current development, provided its constraints are explicit. Continue building rather than repeatedly reopening engine selection. Keep [engine/API constraints, adapter coupling, fixture restrictions and unverified risks](docs/engineering/godot-constraints.md) separate from game requirements. Record evidence, affected promises, mitigations and owners as those constraints are discovered. Do not infer a small world, flat construction, a specific controller, deterministic physics or restricted factory scale merely from the current model. This permission does not establish cross-engine portability or measured production-scale suitability.

Godot with a separately maintained native simulation core is a candidate for a prototype. Its documentation describes [headless dedicated-server exports](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html), [command-line tooling](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html), and [native-library integration through GDExtension](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/what_is_gdextension.html). This makes it worth evaluating against rapid iteration and portability goals; it is not evidence that it will meet the eventual performance budget.

Unreal is another candidate. As checked on 2026-10-14, Epic's published roadmap targets UE6 Early Access for the end of 2027, with full release 12–18 months later. UE6 should therefore not be assumed to be a production-ready starting point today: [Epic's roadmap](https://www.unrealengine.com/news/the-road-to-ue-6).

Before production adoption, assess the actual edit/build/play loop and one representative mechanical scene, including a moving platform and multiplayer. Compare integration burden as well as visuals. Reversible trial selection is delegated; the current first baseline is Godot with engine-native rules kept separate from scene mutation. No production language, engine version or networking library is selected, and the baseline is not native-core portability evidence.

## Open design topics

Continue discovery through question cards with suggested directions when the interface is available. Keep the discussion at the level of the intended experience, identity, and scope before resolving detailed simulation behavior.

- Revise the documented opening defaults from implementation/play evidence and choose the next bounded chapter increment, potentially player-built motion. Use user feedback when available without waiting on routine approvals.
- Chapter objectives, optional-branch rewards, and the progression milestones that introduce lasting supply.
- The role of fluid/gas management and alien substances within the mechanical technological arc.
- The specific designed world, technology-gated areas, and limited terrain-reshaping capabilities.
- The megaproject, manager's personality, reveals, and narrative distinction between the semi-ending and true ending.
- The end-game recipes and throughput targets that define the true ending, including how completion is recognized.
- Construction supply and storage progression that reduce errands while preserving physical item location and transport.
- Physical-character movement/camera defaults, initial 3D construction reach and later reach-extending technology; the character and proximity restriction themselves are already required.
- Individual/team/world progression ownership, preserving each player's learning pace, and how item checks relate to physical deliveries.
- The balance of natural sites and engineered systems for infinite sources, and the scope of autonomous finite-source acquisition.

Deferred conversations: detailed collision consequences and feedback; independent machine pushing; detailed horizontal-decay rules; exact performance budgets and rig baseline; preferred camera/navigation controls and visual direction; multiplayer player counts and network-quality targets.

Ideas held in reserve: selectable manager personalities and possible industrial leaderboards. Future world structure can be reconsidered after starting with a designed world. None is a commitment for the first version.

## Scope ledger

No production engine/language, world format, final camera/art style, multiplayer architecture, numerical performance target or release schedule has been selected. Reversible prototype choices are delegated and recorded separately.

| Topic | Current status | What will resolve it |
| --- | --- | --- |
| Essential experience | Motion invention, exact-count controls, cog routing, and geometry-dependent scaling grounded in user examples | New-product processes with optional benefits to earlier production |
| First playable / chapter 1 | Basic collector → machine → product first; complete starter machines and delegated opening defaults; player-built motion welcome later in chapter 1 | Implement and validate basics, incorporate available user feedback, then iterate; not every intended-game mechanic or approval card is an opening gate |
| Early construction access | Controlled physical character; proximity-limited component placement/machine building; later technology can overcome reach restrictions | Integrate character and authoritative reach into the stationary opening; range, controls, operation coverage and upgrade details remain tunable/open |
| Early factory priority | Fixed/stationary contraptions and subfactories before mobile-factory expansion; internal machinery may move | Playable stationary production, construction and teaching evidence, then scoped later motion |
| World and terrain | Start with a designed peaceful frontier; technology gates safe access to some regions/resources and limited terrain reshaping | Concrete world, access technologies, and excavation capabilities; future world structure stays open |
| Modular machinery | Complete starter machines allowed for the opening; functional tool heads combine with constructed transmission, feeding, and moving assemblies as progression introduces them | Tool catalogue and shared construction vocabulary |
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
| Production approach | Solo plus substantial AI support; rapid iteration and mechanics portability desired; Godot use accepted with explicit constraint tracking | Maintain framework boundaries and representative evidence; no implicit engine-default game rules or production-scale promise |
| Design research | Continuing factory/engineering-puzzle research; per-game completion prevents duplicate studies, not closure of the pipeline | Source-attributed puzzle patterns, independent scrutiny and bounded adaptation experiments |

## Candidate prototype — revised proposal, not a commitment

Start the player-facing prototype with the basic shape and delegated defaults: control a physical character, approach a construction site, place a collector, physically feed one processor, and obtain its product in a small 3D site. Test nearby placement/assembly and out-of-reach refusal independently of camera movement, alongside connection, readable material flow, processing, and retrieval through actual authoritative state, with a small relevant visual explanation. Prioritize fixed/stationary contraptions and subfactories. Validate basics before elaborating machinery; obtain user feedback when available while continuing scoped development. This is a valid first-chapter opening, not an inferior substitute for a motion demo.

The existing free-camera opening and separate character/rider probes remain useful historical evidence, but neither proves the integrated physical-character/build-reach requirement. Implement and independently test that join without retroactively relabelling prior results.

A later chapter-1 project could introduce player-built motion using a small power source, shafts/gears, belts, complete functional tool heads, and fixed-cycle rotary or gantry motion. Explore arrangement, working clearances, repetition, and the broad connected-drivetrain stall rule before introducing expressive controls. The precise project is not selected; detailed collision policies remain deferred.

A further progression slice could add a new process required for Item B and Item C's increased demand for earlier Item A. Compare scaling the old A route with adapting the new process. This earlier three-product proposal is not the user's simpler collector/machine/product notation, nor a mandatory opening sequence. Lasting-supply availability should follow a technology milestone, not a depleted-node event; its chapter placement remains open.

Later extensions can use the small designed site to test terrain constraints and a placeholder off-site commission. Neither is an extra requirement for the basic opening. The full campaign, its two endings, multiple-team progression, and later terrain capabilities still require staging; their presence in the game concept does not select an implementation schedule.

A separate later-progression test can introduce sensors, metered input, and an exact-count task based on the user's circuit example. Testing that mechanism early in development does not mean unlocking it early in the player-facing progression.

Keep the authoritative single-player/server path, minimal two-client interaction, and basic save/continuation evidence in early development. Stage moving-factory and train development while validating their critical architectural interactions early, particularly passengers and transfers between moving and fixed structures. These representative technical risk probes run separately from the simple opening's acceptance: they inform later stack adoption without blocking initial user feedback. A basic-loop demo does not establish that the moving-world risks are solved.

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
- 2026-10-15 UTC: Corrected an agent-imposed first-chapter scope inflation. The user accepts an opening as simple as placing a collector, feeding a machine, and obtaining its product, without custom moving factories or elaborate processor assembly. Player-built motion is welcome later in chapter 1, but the basics come first. Separate early playable feedback from broader motion/scaling/supply and platform-risk evidence. Exact content, power, logistics, completion, and engine choices remain open; long-term engineering and multiplayer requirements are unchanged.
- 2026-10-15 UTC: The user delegated reversible choices from the documented preferences and asked for fewer permission waits. Selected a finite softmetal collector/belt/complete-press/plate opening, simple waterwheel power, physically carried starter parts, retained work under backpressure or loss of power, and a four-plate non-consuming inventory goal. These are course-correctable demo defaults, not permanent content, progression, production-stack or long-term supply decisions. Keep resource limits and independent integration review; do not repeatedly seek user approval for routine decisions within this delegated scope.
- 2026-10-15 UTC: The user accepted Godot use while requiring explicit documentation of framework-imposed constraints so they do not become assumed game rules. Required a controlled physical character and proximity restrictions for placing components/building machinery, with technology overcoming reach restrictions later; final camera and numerical reach remain open. Reaffirmed fixed/stationary contraptions and subfactories as early chapter priority. Established continuing factory-builder/Zachtronics-adjacent puzzle research, with thoroughly scoped per-game completion for deduplication and an ongoing pipeline that does not close after one round.
- 2026-10-20 UTC: Incorporated feedback from the user's first played opening: reduce text and simultaneous tools; recover material from bad lines; allow stationary removal without stopping the global drive; replace arbitrary drive links with individually placed geometric transmission parts; improve prototype graphics and resized layouts. Exact transmission content and final art style remain open. Recorded C++/Rust for new implementation and canonical incremental Bazel builds without treating either as proof of completed adoption or performance.
