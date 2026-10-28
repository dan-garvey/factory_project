# Factory

Current accepted requirements. Numerical recipes, dimensions and prototype
names remain tunable unless explicitly fixed below. Beads holds alternatives,
implementation status, research, historical decisions and evidence.

## Direction

Build a standalone, three-dimensional mechanical factory game where players
invent the means of production from useful components. Geometry, motion,
quantities, power routing and material handling should support several effective
solutions with different costs. Inspired by Create, Above and Beyond and CABIN,
the game should go beyond routing resources between fixed recipe machines.

The reference pleasures are a gantry wood farm whose useful width scales
differently from a rotating machine, an exact-count production problem, and
routing cogs to obtain the required belt direction with few parts. Preserve
those kinds of engineering choices, without copying their recipes or assets.

Mechanical industry remains central throughout progression. Fluids, gases and
alien substances expand it; electricity is excluded. Fixed/stationary
contraptions, including their moving tools, have early priority. Rotation,
gantries, moving factories and trains remain intended-game requirements.

## Chapter 1: arrival and first fabrication

- An AI corporation sends a field fabricator to a peaceful industrial frontier.
  A landing pod unfolds into foundations, a crafting hub and storage. The
  worker wears a work suit and carries a multitool.
  The arrival should be skippable and settle safely on rejoin.
- The pod uses the same world grid as player construction. It is one finite
  shared landing stock, not a build boundary, unlimited supply or per-join gift.
  Players can leave it, replace its functions and reclaim its parts. Replacement
  tooling must be obtainable before reclaiming the hub could strand the player.
- Nearby finite trees and an ore deposit supply the bootstrap. Provide at least
  three reachable harvestable trees and **at least 1280 raw-resource units of
  finite native stock**. The current 4096-unit ore reserve is prototype tuning,
  not a different minimum. Verify enough reachable materials for fabrication,
  physical transport, power, rebuilding and experimentation without hidden grants.
- Manual harvesting takes time and gives visible contact/progress feedback.
  It debits the actual source and creates carried material once. Depletion
  survives saves and rejoin. F3 toggles developer conveniences such as faster
  harvesting; these are distinct from ordinary play.
- Wood shaping is possible with the multitool; metal work needs a local bench
  or equivalent assembled tooling. Avoid a small hidden carrying limit in the
  opening; weight systems are a later choice.
- Players fabricate components and design their own collector and press.
  The first objective is **one formed plate in the player's inventory**.
  There is no opening shipment destination. Manual ore acquisition and a
  hand-tended press are viable before collector or belt automation.
- The experimental first-plate opening starts with an empty hotbar. Only an
  anvil, flat head, wooden slide and timber hand crank are craftable before
  the actor carries a plate; the slide's integral shaft accepts a placed
  crank. Carrying that plate unlocks the other construction recipes for that actor. The
  advanced catalog includes external shafts and cogs, waterwheels, belts,
  collector parts, foundations, receiver trays and broad-work parts. Later
  introductions remain an open teaching and progression choice.
- A finite crafted crank is a separate, free-floating source placed at a rotary
  input. It supplies rotation only while an actor turns it. Reclaiming a
  connected shaft or machine part leaves the crank in place for separate
  recovery, and a disconnected crank supplies no power. An engaged waterwheel
  precludes placing or operating a crank on the same shaft network; a stopped
  wheel may be driven manually. Waterwheels in flowing water supply unattended
  rotation from local flow speed and direction; compatible wheels may share a
  route, and their axles align with elevated shafts on the common grid.
- The collector needs a supporting frame, cutting head/mount, exposed stock
  contact, a receiver at the discharge and physical drive. Direction, support
  and clearance determine operation. A full receiver pauses the next cut
  without debiting more ore.
- Demonstrate at least two meaningfully different arrangements for each machine.
  After the first product, offer a compactness, continuity or spatial challenge
  with several valid solutions. Suggested builds are examples, not hidden
  construction-order requirements.
- The AI gives brief objectives and occasional mystery hints, leaving layout,
  build order and optional automation to the player. “Meridian Combine,” the
  biome, pod footprint, yields and detailed component prices are provisional.

### Plan of record: powered slides and interchangeable working heads

- A **powered slide** contains its rotary input shaft, internal rotary-to-linear
  mechanism, rails and carriage. It defines motion direction, stroke, swept
  clearance and force capacity. Its recipe includes one same-material shaft.
  Do not require separately installing local bearings, cams or that input shaft.
  Other rotary-driven tool components follow the same embodied-shaft cost rule;
  reclaim must not create an extra shaft.
- An **interchangeable working head** defines contact shape, working area and
  material. The flat pressing face and cutting edge are the first required uses
  of the same slide. Larger/stronger heads still obey its load and clearance.
- An **anvil/workbed** is passive support for forming and cutting, with no rotary
  input or compulsory machine recipe. Early slides and heads may float above
  it: structural mounting is deferred, while workpiece support and collision
  remain required. Collector framing is unchanged.
- An unloaded slide can cycle without a head, anvil or recognized recipe when
  its travel is clear. Processing requires compatible tool/material contact,
  support, sufficient force/work and available output custody.
- Previewed, standalone and connected components retain the chosen geometry and
  physical envelope. Only the carriage moves within the declared sweep.
  Neighbors or named-machine recognition must not grow rails or replace shapes.
  Explicit size/stroke choices use the common grid.
- Inspection shows capabilities, ports and actual local failures. An anvil
  must not prescribe a missing-ram/guide/cog checklist. Independent shafts and
  cogs remain useful for external routing, ratios and direction.
- Prove pressing/cutting reuse in the ordinary chapter, recoverable obstruction,
  and save/shared continuation. Keep early cycles simple; fine cam timing and
  tiny mechanism recipes are not prerequisites. This component split is settled;
  exact ratings, dimensions and costs remain tunable.

### Scale, materials and handling

Keep a hand-tended 1 × 1 press viable. A 2 × 2 work area uses independently placed
workbed and working-face parts to act on one broad workpiece. Matching contact,
contiguous support, clearance, coupling and drive capacity decide validity.
Working area does not mandate a whole actuator or shaft/cog pair per cell.
Players with sufficient parts may attempt it early; avoid a recipe per footprint.
The ordinary build controls expose both sizes for the anvil and current flat
head; V switches the selected part between them. A broad placement spends four
carried ordinary parts in one click to build one continuous surface or face,
then returns those parts on reclaim. One slide may drive that face when its
actual input and load permit.
The 2 × 2 press uses one slide housing across the four foundation unit tiles
above its bed, with a central piston and internal shafts that reach tile-center
ports on its perimeter. Its fixed housing posts meet the broad base, and the
base legs meet the ground or four raised foundations arranged in a square.
Either foundation row may face a one-wide belt at the work surface height.

Conserve material mass and form through extraction, carrying, processing,
offcuts, storage, recovery, edits, saves and shared continuation. The prototype
comparison is:

| Route | Material accounting | Cost |
| --- | --- | --- |
| Four small strokes | Four stock chunks × 4 mass = four plates × 3 plus four offcuts × 1 | Repeated feed/work/removal and offcut recovery |
| Broad sheet, then cutting | Three stock chunks × 4 mass = one sheet of 12, then four plates × 3 | Higher peak drive, support, clearance and broad-sheet handling |

Three-quarter fresh-stock use is provisional balance, not a mass discount.
Offcuts remain recoverable; reprocessing is explicit. After recycling and tuning,
the broad route must retain a material or sustained-throughput advantage.

A broad sheet has a real footprint and cannot ride a one-wide belt. A gantry
carriage transferring work between forming and cutting, or a clear slide/drop
to a lower cutter, should offer different physical solutions. Preserve support,
swept clearance, backpressure and accessible blocked work. A gantry with attached
tooling is one internally moving stationary installation, not independent
machines pushing one another. Exact carriage attachment and later sizes are open.

Begin with one thickness and stock, sheet, plate and offcut forms; derive size
variants from geometry and quantity. “Copper” is provisional workable
stock, not a claim that ordinary copper ore can be cold-formed. Add preparation
if the selected deposit yields ore rather than workable metal.

Wooden shafts/cogs are cheap and useful at low loads; metal supports greater
stress at greater material/process cost. The initial comparison should allow a
hand-cranked wooden route, stall a combined powered route at a wooden bottleneck,
and run that route with an equivalent metal part. Exact ratings are tuning.
Gearing, splitting branches and lower loads remain alternatives to upgrading.
Later alloys and heads require new processes, not merely recolored tiers.

## Construction, motion and recovery

- A physical character provides construction and interaction proximity. Camera
  position grants no reach. Later technology can extend access; longer reach
  does not imply remote stock withdrawal.
- Foundations, machines and components share one world origin and one height
  denominator based on foundation height. Independently built sections must
  join horizontally and vertically. No per-tool height grids or restricted
  construction rectangle.
- Foundations may stack, float and intersect natural terrain/rocks/vegetation.
  Ground contact and gravity requirements are omitted for now. Rectangular
  area placement may temporarily ignore reach; finite parts and collisions
  with constructions and characters still apply.
- Shafts and cogs each occupy one 1 × 1 × 1 base tile on the common grid,
  including vertically. Their orientation and engagement determine power;
  decorative gears on arbitrary links are insufficient. Tile dimensions remain
  tunable. Building a material belt between compatible endpoints establishes
  its connection without another connection action.
- Deposits must be recognizable, have useful coverage and match the extraction
  footprint. Use “ore deposit,” not “mineral seam.” Leveling foundations must
  allow bounded extraction depth without moving, refilling or duplicating ore.
  One large collector versus multiple local collectors remains open.
- Invalid recipe conditions and overload stall without destructive cascades.
  An unintended solid obstruction stalls its connected drivetrain; clutches
  or slipping couplings can isolate branches. Partial/ready work stays owned
  and resumes when the condition clears.
- Recover retained raw stock, products and partial work from bad arrangements.
  Stationary removal does not require stopping the whole drive. Reject edits
  that would destroy contents and provide a recovery path.
- Moving factories must ultimately operate, harvest, transfer to stationary
  equipment and carry players. Construction/editing in motion is excluded;
  stopped/docked editing and alignment rules remain open. Construction alignment
  does not require every operating pose to lie on the grid.
- Collision matters and machinery can injure players. Injury severity, contact
  with dropped items/other assemblies and detailed terrain interaction remain
  open. Pushing independent machines is deferred.
- Use both mandatory vertical processes and rewards for useful verticality.
  Gravity, directional tool faces and clearance are early directions. An alien
  intermediate that decays under horizontal transport is only a candidate.

## Progression, resources and world

Guided branching chapters provide clear objectives, optional projects and freedom
of arrangement/order. Introduce new products through new processes, and let later
demand reward redesign of earlier supply. Overclocking has little design value;
duplicating tools and splitting feed is a modest step; a harder new method should
earn a substantial benefit. Earlier methods stay usable with practical drawbacks.

Everything should ultimately be automatable, including replenishment, transport
and recovery. Solved systems should run without recurring manual upkeep.
Expressive controls unlock later and become necessary well into the latter half
of progression. Early repetition uses predictable fixed cycles coordinated by
arrangement and gearing, not mandatory general sequencers.

Start with one designed peaceful world. Technology enables safe access to some
regions and later limited terrain reshaping for purposeful excavation/site
preparation. Support exploration and more demanding in-base production routes
for required capabilities. Exploration can be an earlier/cheaper shortcut;
avoid mandatory prolonged searches for one random resource.

Early extraction permanently depletes deposits. Repeated discovery remains valid;
later technology offers infinite qualifying sources and autonomous acquisition
of finite sources. Unlock lasting supply through progression, not exhaustion.
Late active recovery cycles must involve engineering beyond passive waiting.
Avoid a required transition depending on permanently exhausted stock with no
alternative. Exact resources, milestones and recovery processes remain open.

Item location retains logistical meaning. Reduce shopping-list memory and
repeated fetching without unrestricted teleportation that erases belts.
Storage knowledge, build reach and physical delivery are separate capabilities.
Global storage may be a later reward; its access and delivery rules remain open.

## Campaign, teaching and multiplayer

The AI manager commissions products for a mysterious off-site megaproject,
with dry/existential humor and discoveries revealing its purpose. No growing
on-site megastructure is selected. A semi-ending leads to a harder true ending
requiring throughput across several end-game recipes; building can continue.
Ordinary quests start with player-confirmed inventory possession, not proof of
automation. Consumption, physical delivery and throughput measurement are separate
open choices. The Chapter 1 carried-plate objective is non-consuming.

Ponder-style demonstrations should show construction, operation and recovery,
with rotation/zoom and readable stages. Teach rules and examples without imposing
one blueprint. An editable tutorial sandbox is not selected. Implement and
validate mechanics before spending effort on new lessons.

Multiplayer, dedicated servers, high tick rates and rollback or a better approach
to responsive interaction are requirements. Multiple cooperative teams can share
a world while people retain an option to learn/progress at their own pace.
Individual/team/world ownership of unlocks, story and joint credit is unresolved.
Manager selection and industrial leaderboards are reserved ideas, not requirements.

## Presentation and implementation

Satisfactory is the minimum graphical-quality target. Build an original,
coherent mechanical frontier with recognizable silhouettes, believable material
response, useful lighting, construction feedback and sound. Judge at the normal
play camera as well as close up. Players should see the structures they built;
presentation must not invent authoritative geometry, structures or motion.

Prefer icons, direct manipulation, keyboard paths and concise contextual text.
Use a coherent inventory/crafting grid, a placement-options menu with rotation,
E for machine interaction and a separate deconstruction key. Snapping must have
visible confirmation, retain placed shafts/cogs, and work on elevated foundations.
The carried grid shows at least 32 cells: actual owned items first, then empty
cells. Scroll to reach further item kinds; the grid does not cap native cargo.
Bind a carried placeable to a numbered hotbar key by dragging it onto that slot
or by hovering or focusing its inventory tile and pressing 1–8. The single
hotbar remains in the world view, and binding a key keeps the inventory open
for further assignments. Outside the inventory, number keys select bound tools.
Clicking an inventory tile selects placement without changing a binding.
Machine workbeds show actual occupied material and only carried inputs accepted
by the selected assembly. Empty work locations are blank; the whole carried area
accepts recoverable output drops. Material tiles depict the item, with progress
and operations explained separately.
The hand-tended press keeps each completed plate on its supported work surface
until the player collects it directly or transfers it into carried inventory.
An adjacent empty tile or passive receiver cannot eject it. An aligned, powered
and clear belt or slide may move the plate into available receiving space;
inactive or blocked transport leaves the finished plate visible and prevents
another load. Copper offcuts remain recoverable, with exact material accounting.
Point at loose material and press E to pick it up. The world interaction uses the
visible item and confirmed native custody, with normal reach and obstruction
limits. Manual push commands belong only to developer diagnostics. Connected,
powered material transport must advance automatically; players do not issue
push commands to operate it.
Escape cancels active placement and its unfinished steps; from neutral it opens
the worksite menu. Placement footprint outlines lie horizontally. Resizing must
preserve usable UI.

Keep simulation native and practical to run without rendering, with one authority
for exact quantities, sequencing, identity and continuation. Use C++/Rust and
Bazel; no new Python implementation. Godot is accepted for current development,
with engine/adapter limits explicit in the [constraint register](docs/engineering/godot-constraints.md).
A production engine is not permanently selected; changing it must protect
mechanics rather than excuse a lower visual target. Portability, character/physics
integration, network scale and performance need actual representative evidence.

Exact camera tuning, dimensions, recipes, controls beyond the specified paths,
collision consequences, performance/network budgets and final setting remain
open. Reversible choices are delegated. Research and measured experiments belong
in Beads; they do not change these requirements without an adopted decision.
