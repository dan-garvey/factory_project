# Chapter 1 mechanical feeding candidates

This note records small, reversible geometry and forming rules for
`factory-yau.1.10.17.1`, `factory-yau.1.10.17.2`,
`factory-yau.1.10.17.3`, `factory-yau.1.10.17.4` and
`factory-yau.1.10.17.5`.
They are design choices for future native and ordinary-scene work, not claims
about the current runtime or requirements for the first plate. The first plate
remains hand-fed. `factory-yau.1.10.16.4` owns broad-item carrier behavior and
`factory-yau.1.10.16.6` owns the raised gravity route; this note gives them one
common fit question to answer.

The [powered-slide and working-head plan of record](chapter-one-arrival.md#plan-of-record-powered-slides-and-working-heads)
owns the motion/tool boundary for these candidates. References to a ram mean a
flat working face on a reusable powered slide. Pressing and cutting share that
motion contract; they do not require a separate local shaft/cog recipe. The
transport channels below guide material and are distinct from powered slides.

## Shared fit rule

- Use the existing world origin and one construction denominator. One workcell
  pitch is 1.65 m, or four shared grid increments in X, Y or Z. Each increment
  is 0.4125 m. A foundation is two increments (0.825 m) deep; a full workcell
  rise is four increments (1.65 m). Foundation depth and workcell rise are
  different distances on the same grid. Every guide, support, inlet and outlet
  uses this origin and denominator; no tool gets a separate height increment.
  A normal stock piece or plate has
  a 1 × 1 horizontal footprint; the proposed broad sheet has a 2 × 2 footprint
  and keeps one item identity until cutting. One thickness is enough here.
- A straight channel has a cardinal X or Z travel axis, a declared clear width
  in whole workcells, a supported floor across that width, and an entry and
  exit face. Width 1 admits a one-cell item; width 2 can admit a two-cell item
  only if the item's orientation and the complete swept footprint fit. A bend
  needs the same swept-footprint test around its corner. A carrier or receiving
  tool must expose a matching aperture and free landing area. Rotating a broad
  sheet is a separate physical action, not an automatic result of reaching a
  narrower channel.
- A level guide aligns and supports an item, but needs a push, roller or
  mechanical drive to advance it. A gravity guide descends by a whole number
  of shared height steps between grid-aligned endpoints. Its down direction
  must match travel, its complete swept footprint needs support and headroom,
  and its lower receiver must be present and free. A gap without a landing
  surface is not a transfer permission. The exact useful slope and speed can
  be tuned in implementation; downward height alone does not move an item.
- A channel never recognizes a recipe or changes material form. A transfer is
  permitted only when the next segment or receiver fits the item's current
  footprint and orientation and has capacity. The authoritative owner changes
  once at the handoff. On a refusal or stop, the same item remains accessible
  at its prior owner with its identity, quantity and orientation intact. Save
  and rejoin retain the owner and any bounded in-segment position; neither
  creates a second loose item nor silently finishes the transfer.

The player reads the rule from the visible width, rails, support and clear
mouth of the route. Separate variants for every product would hide the shared
fit decision; a 2 × 2 sheet and any later broad workpiece use the same test.
Full loose-pile physics, arbitrary slope angles and per-recipe channel tokens
are outside this candidate.

## Two useful arrangements

| Use | Valid route | Refusal and recovery |
| --- | --- | --- |
| Feed a small stock piece to an anvil | A one-wide level guide points at a clear press inlet. A hand push or driven roller moves one stock piece into the free work position; the guide may be rotated to another open side of the same press. | An outlet aimed beside the inlet, an occupied anvil or a blocked guide stops the piece at its last owner. Moving the obstacle or turning the guide permits the same piece to continue. |
| Move one broad sheet from a raised former to a lower shear | A two-wide supported slide starts at the clear upper outlet, descends to a matching two-wide landing, and meets the shear's broad inlet. The sheet stays one oriented item. After shearing, individual plates may enter one-wide belts. | A one-wide belt, sideways broad sheet, reverse slope, missing landing support or occupied shear refuses the handoff. The sheet stays at the upper outlet or last supported segment for pickup or rerouting; no plate appears early. |

These routes make a real layout choice: a driven level guide spends power and
keeps elevation, while a gravity slide spends vertical room and requires a
lower receiver. Both use the same fit and custody rule. A broad gantry carrier
from `factory-yau.1.10.16.5` can also pass this fit test with its own supported
deck and motion; the guide design does not implement or replace that carrier.

For a concrete grid fit, call the lower floor surface height level 0. Its
foundation occupies levels -2 through 0. An independently placed raised floor
can have its surface at level 4 and occupy levels 2 through 4. A raised press
and its level inlet share that upper surface; a two-wide slide can leave its
clear upper outlet at level 4 and meet a supported, two-wide lower landing at
level 0. Those endpoints differ by four common increments, or two foundation
depths. The intervening chute, swept sheet and headroom still need geometry
and support checks; this sketch grants no transfer merely from the height
difference. A grate on the same raised route can similarly retain broad work
at level 4 while an aligned offcut tray at level 0 receives only shapes that
fit its aperture. Its upper path, lower landing and fall volume use the same
grid coordinates. These are relative surface levels, not new local height
origins or a requirement to raise every press or grate by a full workcell.

## Passive sizing grate candidate

`factory-yau.1.10.17.2` proposes a grate with open slots above a real lower
receiving channel. This is a shape proposal, not a claim that today's copper
items have these visible dimensions. The copper mass owner in
`factory-yau.1.10.16.1` keeps its four-unit stock, three-unit plate and
one-unit offcut accounting unchanged. For this paper fit check, one stock
chunk and one plate each occupy about 3 × 3 quarter-grid steps in plan. The
offcut is a visibly narrow 1 × 3 strip; a broad sheet spans 8 × 8 steps. A
different final mesh can be used only if its actual projected dimensions and
collision/fit rule agree.

The grate uses the same world grid as the channels. It offers two easily
distinguished clear aperture widths: two quarter steps for slivers and four steps for
single-cell pieces. Every opening has a supported upper path and a declared
lower receiver. A piece falls only when its *oriented swept outline* fits an
opening, the lower fall and landing volume are clear, and the receiver has
capacity. Otherwise it bridges on the upper grate or stops at its inlet. It
never tests an item name, mass, recipe or forming progress. A piece arriving
with unknown or unstable orientation waits for a guide or manual correction;
random jam rolls do not replace the fit rule. A transverse 1 × 3 offcut can
bridge a narrow slot even though its one-step side would fit when aligned.

| Paper layout | Visible separation | Custody when interrupted |
| --- | --- | --- |
| Recover small-press offcuts | Four stock chunks hold 16 mass units. Four presses leave four 3-unit plates (12) and four 1-unit strips (4). An aligned narrow grate passes the four strips to a lower recovery tray while the plates continue on the supported upper route. The tally remains 16. | If the lower tray fills after two strips, those two units stay there, the remaining two strips stay on the upper path or at its inlet, and the four plates remain above. The route stops before moving another strip. All 16 units remain accessible. |
| Separate broad work from small feed | Six original stock chunks hold 24 units; three are formed into one 12-unit sheet while three 4-unit chunks remain. A four-step grate passes the three small chunks (12) to a lower feeder but supports the 8 × 8 sheet (12) on its upper route toward a broad cutter. | A blocked lower feeder retains each untransferred chunk above. The sheet stays one item on its upper owner, not four plates. The combined tally stays 24. |

Stock and plate have the same relevant 3 × 3 outline here, so neither aperture
can sort one from the other. Depth-1 and depth-2 formed sheets likewise share
the relevant 8 × 8 outline; this grate cannot tell whether forming is complete.
The channels before and after the grate determine where each supported or
fallen stream goes. Removing a jam, rotating an accessible strip, or emptying
the lower receiver resumes the same items without a product menu, hidden
filter or tuned cycle timing. This is optional routing after the first plate,
not a prerequisite for hand recovery.

## Fixed-pocket metering slide candidate

`factory-yau.1.10.17.3` proposes one sliding pocket behind a housing that
never exposes a straight path from inlet to outlet. Choose a one-slot or
three-slot insert; each slot is one shared-grid workcell wide and supports one
standard chunk-shaped item. The three-slot insert is three distinct spaces,
not permission to put a 2 × 2 sheet in one long cavity. The visible empty or
occupied spaces define capacity. Any item that physically fits may enter,
including mixed materials; the slide has no recipe or item-name filter. A
downstream process may refuse a mixed batch without making it disappear.

The slide runs one fixed basic cycle. The fill mouth is open only at its home
stop. When every slot is occupied, a full-pocket latch permits one powered
travel to the sealed unloading stop. A blocked receiver holds that same full
pocket at the unload stop. Once the receiver admits the whole batch, all
items transfer in one custody change and the empty pocket returns home.
Housing, latch and end stops are one supplied mechanism, not separate tiny
parts the player must phase-align. No timing, delay, count or phase control is
exposed to the player.

| State | Visible pocket and authority | Next admitted event |
| --- | --- | --- |
| Filling | Home at the fill mouth; the pocket owns zero to capacity-minus-one items. | Each fitting arrival occupies one free slot. Empty supply waits here. |
| Ready | Home with every slot occupied; the same pocket owns the full batch. | Power and a clear travel volume move the sealed pocket. A partial batch never triggers this move. |
| Transfer | Inlet and outlet are covered; the pocket still owns every item. | Reaching the unload stop exposes the receiver. Power loss stops the pocket in place with its contents. |
| Unloading or blocked | At the unload stop; the pocket still owns the full batch until the matching receiver accepts every item. | On full admission, one atomic handoff changes ownership and empties the pocket. A full or incompatible receiver holds the pocket here. |
| Return | Empty pocket moves to its home stop. | The fill mouth opens only at home; a power loss holds the empty pocket without losing a cycle. |

For a three-slot example, two copper chunks `C1` and `C2` hold eight mass
units in the filling pocket while the third slot is visibly empty. Starvation
leaves those exact two chunks there; it cannot send a two-chunk batch. Arrival
of `C3` raises the pocket tally to twelve units and makes it ready. If power
stops halfway, the sealed pocket still owns `C1`, `C2` and `C3`. If the former
is occupied at unloading, all three remain at the unload stop. Only a clear
receiver takes all three together; an accepted handoff moves twelve units,
with none left in the pocket. A stopped, stationary pocket has an accessible
service face for manual retrieval of its exact contents before a repair or
reroute. The same owner, slots and travel stop survive save and rejoin.

Two uses share this cycle. A three-slot slide batches three stock chunks for
one broad forming inlet, making supply and backpressure visible. A one-slot
slide spaces pieces into a cutter inlet without demanding a new controller.
Both may receive any fitting piece; destination fit and recipe checks remain
with the destination. A wrong-shaped sheet never enters the standard slots,
while three fitting but unsuitable pieces stay recoverable when the receiver
refuses them. The closed `factory-yau.4.23` fixed-pattern distributor proves
an ordered one-item planner can hold its index under backpressure. It owns no
live items or physical pocket, so this design takes only the hold principle;
World would still need one authoritative transfer and cycle state.

## Repeated cold forming candidate

`factory-yau.1.10.17.4` compares three ways to reach the *same* finished
2 × 2 sheet before shearing. These numbers are an illustrative tuning fixture,
not adopted copper physics or a first-plate prerequisite. The sheet keeps its
one identity and twelve mass units through every accepted pass. Its bounded
forming state is depth 0, 1 or 2; only depth 2 can enter the shear. Progress
belongs to the workpiece, not to a particular press or an intermediate recipe
output. It travels with the sheet through pickup, blockage, save and rejoin.

Two fixed stroke choices are enough for this comparison:

| Stroke | Admission | Effect on one supported sheet |
| --- | --- | --- |
| Full | Peak drive force at least 8 units and at least 12 work units in one guided, clear cycle | Depth 0 reaches depth 2. |
| Shallow | Peak drive force at least 5 units and at least 6 work units in one guided, clear cycle | Depth increases by one, at most to 2. |

Both strokes require the same matching workbed and working-face footprint,
contact and powered-slide clearance. The larger sheet uses four supported
workcells on the common grid; the slide needs no structural anchor. Force below 5,
insufficient work, a missed work face or a blocked discharge completes no pass and changes
no forming state. Weak taps cannot accumulate fractions of a pass. The
illustrative total useful work is at least 12 units on either route; the
single full stroke buys time with higher peak force.

| Arrangement | Productive cycles and cost | Handling and footprint |
| --- | --- | --- |
| One strong stage | One full cycle at peak force 8 and work 12. | One 2 × 2 working area, one feed and one exit. Needs a stronger drive but can process a new sheet on the next cycle. |
| Two shallow stages | Two shallow cycles at peak force 5 and work 6 each. | Two distinct 2 × 2 working areas plus a clear transfer between them. Each station has a fixed depth setting, so an unattended line can pipeline separate sheets without timing controls. |
| One shallow stage with return | Two shallow cycles at peak force 5 and work 6 each, plus at least one return transfer. | One 2 × 2 working area and a broad, supported return route. Hand-tended pickup or a later mechanically justified fixed diverter can send the depth-1 sheet back; the depth-2 sheet leaves for cutting. |

A stopped first pass remains a depth-1 sheet at the station exit or its last
accepted carrier. An occupied return, stopped drive or full downstream shear
does not erase progress or produce a second sheet. Clearing the route, carrying
the sheet to another capable press or restoring drive resumes from depth 1.
The compact return layout saves a second press at the cost of extra handling
and lower unattended throughput. The two-stage layout spends area and parts to
reduce peak force while preserving flow. The strong layout spends peak force to
save area and cycles. None dominates every site.

A simple width grate cannot distinguish depth 1 from depth 2 when their
horizontal outline is unchanged. The two-stage route needs no sorting sensor;
the compact loop is hand-tended until a physical thickness or other observable
change can drive a fixed diverter and its custody can be tested. Heating is a
separate later candidate under `factory-yau.1.10.17.5`, not an implicit force
discount here. This comparison belongs after the first hand-fed product as an
optional later Chapter 1 forming and throughput challenge.

## Heated forming as a later companion

`factory-yau.1.10.17.5` adds one *candidate* route to the same finished 2 × 2,
twelve-mass sheet. This is a game balance sketch, not a statement about real
copper metallurgy. The cold force and work numbers above are unchanged. A
heater supplied by finite fuel or a later renewable heat source can make one
workpiece hot. A hot sheet can take one full guided stroke at peak mechanical
force 5 instead of 8, still requiring 12 work units. Heat lowers the peak
force in this example; it does not create forming work or material. The fuel
charge and heat delivery need their own conserved resource rule before native
adoption.

| Route to depth 2 | Useful case | Price paid |
| --- | --- | --- |
| Heavy cold, one full stroke | Limited floor area and plentiful strong drive. | Peak force 8, work 12, one forming cycle and one work area. |
| Repeated cold, two shallow strokes | Weak drive with room for two stations or a return. | Peak force 5, work 6 twice, two forming cycles and extra stations or handling. |
| Heated, one full stroke | Weak drive and scarce floor area when a nearby heat supply already serves other processes. | Peak force 5, work 12, one heat admission plus one forming cycle, a short insulated route and cooling capacity. |

Use only three readable thermal states on the same workpiece: **cold**, **hot**
and **cooling**. The heater changes cold to hot after one admitted heat cycle
and one accounted fuel charge. A hot workpiece has two fixed machine-cycle
intervals to reach and finish the press; travel, waiting at a blocked inlet
and forming consume those intervals. When they expire before pressing, the
workpiece becomes cold and may be reheated without losing its depth or mass.
Accepted hot forming moves it to cooling at the press output. A supported
cooling rack holds it for one cycle before ordinary hand or carrier transfer;
an occupied rack blocks the press discharge and leaves the original item and
its forming progress at the press. No new item is minted for a temperature or
an intermediate pass.

Power loss freezes mechanical position and custody; heat may still expire at
the next bounded cycle boundary. A partly formed depth-1 item can cool and be
reheated, or finish through a valid cold stroke. A failed hot stroke below its
force or work threshold grants no progress and does not refund the heat charge.
Reheating affects only thermal readiness, not copper mass or prior accepted
forming depth. Save and rejoin retain the owner, depth, thermal state and
remaining hot interval; a restored blocked line resumes or cools under the
same fixed rule. These are proposed behavior contracts, not measured runtime.

A solved unattended layout stocks fuel, feeds the heater, uses a short fitting
guide to the press, and clears the cooling rack into later handling. Starved
fuel, a blocked press or a full rack stops safely with every item accessible;
restoring supply resumes without repeated manual button presses. This route
adds a fuel source, heater, cooling surface, thermal indicators and a lesson
about heat travel and recovery. That learning cost is too large for the first
hand-fed plate. Keep it for later progression, with at most an optional late
Chapter 1 preview after cold forming and ordinary item routing are playable.
No furnace implementation or new first-product prerequisite follows from this
paper candidate.
