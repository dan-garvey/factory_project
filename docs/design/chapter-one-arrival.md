# Chapter one: arrival and the first workshop

Status: user-directed chapter direction, 2026-10-22. The landing pod, manual
harvesting, locally made components, modular collector and modular press replace
the old complete-machine opening as the target experience. Names, quantities and
recipes here are reversible prototype choices until tested in a running game.
[DESIGN.md](../../DESIGN.md) owns the wider requirements. Existing collector,
press and four-plate fixtures remain useful regression evidence, not an opening
that new players must follow.

## The player's first ten minutes

The player is a field fabricator contracted by the **Meridian Combine**, an
industrial corporation whose operations manager is an AI. The Combine has sent
workers to an apparently peaceful alien frontier to ship manufactured components
for an off-site megaproject. The first work order is specific; its final purpose
is withheld. This premise supports dry humor and later discovery without making
dialogue, employment obedience or a single factory layout a construction gate.

A descent view establishes the forest, stream, ore outcrops and distant freight
beacon. The player wakes in a work suit with a visible multitool. The pod settles
on the same world grid as player construction, then unfolds into a small, usable
foundation deck, workbench, storage tray and detachable hand crank. The hatch
opens onto the site. The pod is the first example of a compact machine unfolding
into a useful arrangement, not a magical source of unlimited stock. The player
can inspect it, build beside it and eventually replace its functions and reclaim
its parts. The scene should be skippable and rejoin safely at its settled state.

The AI offers one instruction at a time, with replay in the work log. Candidate
lines are short enough to leave the game view readable:

> “Landfall confirmed. Your office is now the part of the planet under your boots.”

> “The kit makes tools. The tools make a factory. Corporate has provided the kit.”

> “Send one formed plate to the beacon. Its final destination is outside your pay grade.”

The player can cut nearby timber or ore first, make simple parts at the hub or
with the multitool, and choose the location of the first machine. A suggested
route teaches a hand-tended press and a hand-cranked collector, then shows how
the same functions can be driven and fed automatically. Those are examples, not
an exact blueprint or a tech lock. The first delivery asks for a formed plate;
a later order asks for repeated plates and makes unattended collection and feed
valuable. This order leaves time to design a collector without making a fixed
assembly sequence the only way to progress.

## Physical starting state

| Thing | Initial state and role |
| --- | --- |
| Player | One physical actor in a work suit, with a reusable multitool. Actor position limits harvesting, hub use and construction. The camera alone has no reach authority. |
| Pod | One deployed site object per landing. Its deck uses the global foundation origin and height denominator, with ordinary vertical and horizontal joins. Its hub and tray have explicit identities and stock custody. A late join never creates another free pod or kit. |
| Hub | A local clamp/cutting/forming surface for component work. It has modest carried-item input and output capacity, and can be replaced by a player-built bench. Basic wood shaping remains possible with the multitool away from the pod; metal forming needs a bench or an equivalent assembled fixture. |
| Hand crank | One detachable, reusable item. It supplies rotation only while an actor turns it at a shaft; it can be moved between early machines. The eventual waterwheel can run them without a player. No hidden motor, battery or endless pod power is implied. |
| Site | At least three reachable, visibly harvestable trees and one finite softmetal ore deposit near the pod, plus a stream and room for different layouts. These are world stocks rather than inventory grants. The pod is not a restricted build rectangle. |

Multitool cutting reduces a specific tree or deposit's finite stock and creates
carried items at that actor. Sawing timber and cutting a softmetal blank take
time and show contact/collection feedback. Refused range, wrong target,
full inventory and repeated command cannot duplicate or erase material. A tree
and ore outcrop remain visibly depleted after save and rejoin. The multitool
also reclaims construction components; occupied machines require recovery of
their actual retained work before an edit that would delete it.

The exact pod footprint and biome are art/layout choices. A 3 × 3 tile deck is
the first presentation target, not a special construction size or final pod
scale. Place it on a designed safe landing surface while letting the player
expand or build elsewhere on the shared world grid. If the terrain changes, the
same deployment transform must place both the visible panels and authoritative
foundations; avoid a visual-only floor or a second mutable pod model.

## Bootstrap materials and component bill

This is a deliberately small, **reversible balance fixture**. It proves a
path from accessible world stock to both machines without gifting either
complete machine. One tree yields eight usable timber pieces; an initial ore
deposit exposes sixteen softmetal blanks. At least three accessible trees give
layout and mistake margin. A different final yield is fine if the same
dependency and recovery proof is redone. Softmetal is a fictional workable
material for early cold forming; its geology and final name remain open.

| Component | Local fabrication input | Uses in the first arrangements |
| --- | --- | --- |
| Wooden frame | 3 timber | A load-bearing base for a collector or press. |
| Wooden shaft | 1 timber | Geometric drive from crank or later waterwheel. |
| Wooden cog | 2 timber | Change rotation direction or drive ratio within its stress rating. |
| Receiver tray | 2 timber | Catches a cut blank; full capacity pauses extraction. |
| Tool mount | 1 timber | Supports a head at a chosen height and orientation. |
| Sliding guide | 1 timber | Constrains the press ram beneath its drive. |
| Cutting edge | 1 softmetal blank | Fitted to the collector's tool mount. |
| Anvil | 2 softmetal blanks | The press work support. |
| Ram face | 2 softmetal blanks | Fitted to the press head's moving guide. |

An illustrative collector uses one frame, tool mount, cutting edge, receiver
and wooden shaft: **7 timber and 1 blank**. An illustrative press uses one
frame, tool mount, sliding guide, anvil, ram face, wooden shaft and cog:
**8 timber and 4 blanks**. Both consume **15 timber and 5 blanks** to build,
leaving one timber after harvesting two trees and eleven blanks at the original deposit;
the first plate consumes one more blank. A third tree is available for an
alternate route, support, chute or rebuild. A detachable crank is reusable
between these arrangements. This arithmetic is a starting fixture, not a
promise that every geometry or belt route can fit inside two trees.

The frame, mount, guide, head, shaft and receiver remain separate world items.
They have placement faces and physical clearance; a recipe creates a component,
not an instant collector or press. The first plate can be made from a blank
cut by hand. The collector reduces manual mining thereafter. Dismantling
returns components rather than a generic machine kit, subject to explicit
retained-item recovery. The player can use other valid arrangements and more
parts; no task requires an exact bill or punishes experimentation by destroying
the finite starter stock.

The pod bench can cold-shape these simple metal parts using blanks the player
has actually harvested. Better formed metal shafts and cogs provisionally cost
two blanks each, so higher quality is available before a production line is
perfect. Later alloys and hardened heads require a new process, not a coloured
copy of the old part. Early wood remains cheap and useful for low-load branches.
The stream is a route to lasting power. Short gravity chutes or wooden rollers
can handle early material; powered belts and future fiber/strip stock need their
own conserved recipes before this prototype's free belt kit is retired. No
single finite tree or deposit is silently made infinite to rescue the fixture.

## Machinery is an arrangement

The collector needs a frame that supports a cutting head at the deposit face,
a path for the blade to reach exposed stock, a receiver positioned at its
discharge, and a physical drive. Tool orientation and clearance should decide
whether it cuts; an internal “collector present” flag should not. A cutter
driven by the detachable crank can share the same finite deposit and output
port that a later waterwheel route uses. A full tray or belt output stops the
next cut without debiting ore.

The press needs an anvil under a guided ram face, a frame that carries the
reaction, a drive/cam arrangement that moves the ram, and room to insert and
remove work. A manually placed blank can become a plate before belt feed is
built. Different working heights, shaft routes, feed faces and gravity paths
are valid when the contact and clearance conditions hold. The same native
custody owner retains partial work, input and output through a stall, edit,
save or rejoin. A recipe restriction cannot replace the physical reason an
arrangement succeeds or fails.

At minimum, the playable chapter should demonstrate two meaningfully different
arrangements for each machine, such as opposite-side drive or alternate feed
height. Present one legible example in staged Help, then let the player alter
it. An engineering challenge after the first product should invite a more
compact or more continuous line using familiar parts, with multiple valid
solutions. It should not require hidden construction order.

## Material quality creates a choice

Part material sets transmitted load and suitable working conditions; geometry
still controls connection and direction. A wooden shaft or cog handles a small
early machine at ordinary speed. A heavier combined collector/press line
exceeds a wooden bottleneck but can run after replacing that bottleneck with
softmetal. Metal costs scarce blanks and more shaping, while wooden parts stay
useful for light branches and remote early builds. A later alloy can enable
still higher load or hostile-site operation through a genuinely new process.

For the first fixture, size the ratings so **one hand-cranked machine works
through wood, a combined powered line stalls at a wooden bottleneck, and the
same line runs through an equivalent metal part**. Exact torque, speed,
fatigue and load units must be tuned against the existing native solver before
being canonized. Stress above a part rating stalls the affected connected
drive without destroying parts or contents, matching the established
non-destructive obstruction rule. Couplings may isolate a weak branch. Clear
feedback names the limiting part and a likely remedy, without a wall of text.

Quality is not a random grade roll or a blanket “metal is better” tier. Each
material has a concrete affordance, cost and limit, and design choices can
reduce load, split branches or change ratios instead of always requiring an
upgrade. Wooden and metal parts use the same tile origin and connection rules,
including elevated foundations.

## Agency, multiplayer and evidence

The AI asks for a delivery, not a prescribed build. Orders can suggest a
collector and press, but manual acquisition, alternative layouts and early
exploration remain viable. The pod and hub provide a reliable foothold, not a
permanent base location. Any part needed to replace the hub must be obtainable
before dismantling it, and dismantling must return or preserve its nonconsumed
tooling. If an order consumes goods, its costs belong in the bootstrap budget.

The pod, tree/deposit reserves, hub buffers, carried items, placed components,
machine work and delivery stock have one native authority. Each operation is
actor-bound and retry-safe. A shared world gets one landing stock; personal
manager messages and learning pace remain separable from team/world ownership.
The old four-plate nonconsuming objective and complete-machine scene are
historical test fixtures until a new delivery contract is implemented.

The chapter task is complete only after a normal build can be played from
arrival through a first product, with a correct save/rejoin and two-client
stock path. Native tests can establish accounting and geometry; Godot checks
can establish rendering and control paths; screenshots can establish visible
details at a named revision. Only human play can establish whether the arrival,
part design and progression are understandable and enjoyable. The Bead subtree
`factory-yau.1.10` keeps those outcomes separate while owners integrate the
working game.
