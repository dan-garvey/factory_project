# Three ways to make the first plate: prototype trial

This is a dated comparison of three finite-stock Chapter 1 arrangements. Each
route reaches the same current objective: a worker carries a copper plate. The
headless ordinary-scene witnesses use the real native World, actor reach, local
fabrication and material ledger. They establish mechanical possibility, not
that a new player can discover or enjoy each route.

| Route | What changes in the factory | Observed result and cost |
| --- | --- | --- |
| Hand-tended small press | Carry ore to a single guided press and turn its unpowered shaft by hand. No belt or collector is needed. | The arrival witness carries two plates and two recovered offcuts after 75 accepted orders. The second plate exceeds the one-plate objective; each small stroke retains its offcut. |
| Collector, belt and powered small press | Build the collector, a material belt and a separate waterwheel transmission to the elevated guided press. The connected line extracts and forms finite work without hand turns. | The original belt-fed witness established one hand-turned plate. The later powered continuation makes two plates by native ticks across fresh Store loads. A full exit holds the second ready lot without duplicating output; ordinary pickup releases it. The worker collects both plates while two conserved offcuts remain in the separate tray. |
| Four-cell sheet former and cutter | Harvest and craft twenty individual work-area parts, connect a waterwheel on the working side of the drive, and feed three ore chunks into one broad sheet. Carry the sheet, exchange the forming faces for cutting blades, and make four cuts. | The broad route carries one plate and leaves three accessible plates after 173 accepted orders. It uses one twelve-mass sheet and produces no offcut. The route needs four-cell support, a correctly directed drive, a sheet transfer and blade changes. |

The numbers above are *whole witnessed routes*, not normalized production
rates. The hand and powered-line routes each make two plates, and the broad
route makes four. The earlier belt-only hand-crank result is a precursor, not
the completed powered route. Order counts include harvesting, fabrication
and construction, so they show setup cost as well as operation. The native
ledger conserves the original 16,384 mass units in all three results. The
small routes use four mass units per plate and retain one unit as an offcut;
the broad route converts three four-unit chunks into four three-unit plates.
The broad route's apparent stock advantage is provisional because the small
offcuts remain recoverable material.

The broad scene witness is a chain of four separate processes: `arrival-broad-pad`,
`arrival-broad-drive`, `arrival-broad-form` and `arrival-broad-cut-resume` in
`opening/native_adapter_check.gd`. Each continuation loads the preceding real
Store checkpoint. Native motion first exposed a wrong-way wheel connection:
the head was nominally ready yet had a negative stroke rate and its work did
not progress. Connecting the other side produces a positive rate and advances
the original lot. A later cutting step deliberately removes one blade after
two strokes; the next stroke refuses `incomplete_shear` without losing the
sheet, and replacing that blade lets the worker finish and collect a plate.
The other witnessed modes are `arrival-press`, `arrival-belt-fed-press`,
`arrival-belt-fed-press-resume`, and the four `arrival-powered-press-*` stages.
The powered stages build the finite press site, fabricate and connect two
vertical relays plus a horizontal relay and collector branch, load the first
automatic output, retain a blocked second work lot, then collect both plates
after fresh loads. The route uses one native World and a physical actor for
movement and reach. Its scripted craft steps still emit legacy workshop panel
actions after the shared inventory replaced the visible workshop menu; they
do not establish a complete current player input route. The result files and
first failures are retained under the task
evidence linked from `factory-yau.1.10.16.7.2` and
`factory-yau.1.10.10.22.6`.

These are different decisions, rather than three copies of a press: manual
handling trades construction for labor; the powered line trades substantially
more parts and alignment for automatic extraction, delivery and pressing; the
broad arrangement trades a larger driven work
area and sheet handling for four plates without offcuts. The present broad
scene reuses the *same* supported area after changing its working faces.
Separate forming and cutting areas have native World coverage, but are not yet
an ordinary-scene result. The powered route's offcuts are conserved in its
discharge tray, but the ordinary press recovery control does not collect them
from that location. This remains a separate custody and interface gap. The
broad feed, blade exchange and cutting
commands are script-driven through the ordinary scene's native command path;
they are not yet discoverable normal player controls. Fixed-pattern assembly
and a provisional drive are not the planned reusable powered-slide interface.
The current-main hand-press witness also stops at its old workshop-menu
assertion after the inventory change. Its earlier finite production result
remains valid at that revision, while the current inventory interaction needs
a fresh ordinary consumer. Rendered inspection, network continuation and
human play remain separate.
