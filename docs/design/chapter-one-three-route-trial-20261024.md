# Three ways to make the first plate: prototype trial

This is a dated comparison of three finite-stock Chapter 1 arrangements. Each
route reaches the same current objective: a worker carries a copper plate. The
headless ordinary-scene witnesses use the real native World, actor reach, local
fabrication and material ledger. They establish mechanical possibility, not
that a new player can discover or enjoy each route.

| Route | What changes in the factory | Observed result and cost |
| --- | --- | --- |
| Hand-tended small press | Carry ore to a single guided press and turn its unpowered shaft by hand. No belt or collector is needed. | The arrival witness carries two plates and two recovered offcuts after 75 accepted orders. The second plate exceeds the one-plate objective; each small stroke retains its offcut. |
| Collector and belt into a small press | Build the collector and belt to bring a finite blank to the guided press. The press still needs hand turns and offcut pickup. | The ordinary belt-fed witness carries one plate and one recovered offcut after 111 accepted orders. A fresh process also completes the saved in-flight blank. The extra machinery changes delivery labor and layout, but does not yet automate pressing. |
| Four-cell sheet former and cutter | Harvest and craft twenty individual work-area parts, connect a waterwheel on the working side of the drive, and feed three ore chunks into one broad sheet. Carry the sheet, exchange the forming faces for cutting blades, and make four cuts. | The broad route carries one plate and leaves three accessible plates after 173 accepted orders. It uses one twelve-mass sheet and produces no offcut. The route needs four-cell support, a correctly directed drive, a sheet transfer and blade changes. |

The numbers above are *whole witnessed routes*, not normalized production
rates. The hand route deliberately makes two plates, the belt route makes one,
and the broad route makes four. Order counts include harvesting, fabrication
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
The other witnessed modes are `arrival-press`, `arrival-belt-fed-press` and
`arrival-belt-fed-press-resume`. The result files and first failures are retained
under the task evidence linked from `factory-yau.1.10.16.7.2`.

These are different decisions, rather than three copies of a press: manual
handling trades construction for labor; the belt trades construction for
automatic blank delivery; the broad arrangement trades a larger driven work
area and sheet handling for four plates without offcuts. The present broad
scene reuses the *same* supported area after changing its working faces.
Separate forming and cutting areas have native World coverage, but are not yet
an ordinary-scene result. The belt route still lacks a powered, repeating
press and blocked-output recovery. The broad feed, blade exchange and cutting
commands are script-driven through the ordinary scene's native command path;
they are not yet discoverable normal player controls. Fixed-pattern assembly
and a provisional drive are not the planned reusable powered-slide interface.
Rendered inspection, network continuation and human play remain separate.
