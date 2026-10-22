# Collector seam-facing assembly brief

This is a design brief for the **presentation** of the existing collector, not a
new mining or material rule. It follows the rejected small-chute trials in
`factory-yau.6.45.23.82`. The current source and the ordinary native view were
read on 2026-10-22 at main `b76ddea`. The next step is a matched visual
prototype; no alternative below has passed that comparison.

## Why the current assembly is hard to read

The [ordinary confirmed worksite](../../experiments/engine-environment/godot/opening/assets/README.md)
shows an irregular mineral rock immediately behind a compact hood and stock
table. From the construction camera, the drum reads as a round detail on the
hood. The player cannot readily trace a physical route from exposed seam to
tool, then to a material outlet. The previous small rails and sloped channel
read as added decoration or covered the bed. Their preserved images and patches
are linked from `factory-yau.6.45.23.82`.

For comparison, Komatsu's [12HM continuous miner brochure](https://www.komatsu.com/content/dam/komatsu/sales-and-marketing-documents/brochures/room-pillar/12hm/en-12hmscm01-12hm-continuous-miner.pdf)
separates cutting, gathering and conveying as visible subsystems. That is an
industrial form reference, not a compatible machine model or a proposed power,
traction or production mechanic. Factory's stationary, one-cell collector must
use its own original proportions and the admitted material state.

## Current coordinate and authority map

The numbers below describe the current native adapter and Godot art. They are
not permanent gameplay dimensions.

| Fact | Current source and implication |
| --- | --- |
| Cell and ground | [Site geometry](../../experiments/engine-environment/godot/opening/site_geometry.gd) uses a 1.65 m cell and places the machine anchor at the cell centre and confirmed level. The existing plinth and pick box belong to the machine assembly. |
| Mineral site | [Mineral-site policy](../../native/mineral-site/include/factory/mineral_site.hpp) admits two opening cells, `(0, 0)` and `(0, 1)`. [Host admission](../../native/factory-godot-world/src/host.cpp) checks the chosen centre against that site and the terrain depth, including a bounded elevated-foundation reach. This is the extraction permission; no visible cutter triangle supplies it. |
| Exposed rock | [The one site-surface descriptor](../../experiments/engine-environment/godot/opening/site_surface.gd) places the fitted outcrop at world `x = -1.05`, `z = 0.05`, with its centre height derived from real terrain. The prepared local box is about 0.572 × 0.753 × 2.288 m; the [outcrop source study](mineral-outcrop-source.md) records the larger unmodified donor. The visible and physical hull share this rigid descriptor. It is one geological cue spanning the two-cell seam, with one finite reserve. |
| Existing tool | [Collector art](../../experiments/engine-environment/godot/opening/opening.gd) puts the drum centre at local `(-0.22, 1.10, -0.19)` with a 0.24 m radius and its stock bed at `(0, 0.51, 0)`. These nominal centres do not alone prove tool-to-rock surface contact; the actual transformed hulls and all cutter poses need measurement. |
| Material outlet | [World material routing](../../native/factory-world/src/world.cpp) selects the collector's single horizontal output from the confirmed quarter-turn rotation. At rotation zero it faces `+X`; the other rotations turn that vector. An adjacent belt receives material only when its endpoint faces this output and its slot is free. Any outlet art must rotate with the collector and stop at an exposed end when no accepted belt exists. |
| Custody and motion | Native World owns extraction, finite stock, cached commands, power and material transfer. The view may depict only confirmed source quantity and machine/cutter state. A decorative chute must not invent a travelling billet, extra reserve, working connection or cutting contact. |

The fitted rock remains outside both machine construction envelopes and reaches
near each permitted seam cell. Turning the output still rotates the entire
machine visual while the outcrop stays put. The first prototype should show an
intake at the **admitted cell surface**; the passive fit does not yet prove that
its cutter contacts the rock in every rotation. Before adoption, inspect the
real outcrop hull, pick envelope, tool
sweep, actor obstruction and rotation cases. An AABB overlap is neither proof
of visible contact nor a licence to alter collision.

## Assembly alternatives

**A. Enclosed scoop below the present hood.** Keep the existing high drum and
wrap a low steel scoop around the rock-facing side. It can meet the table and
suggest gathering, but the drum remains visually detached from the seam at the
ordinary camera. The previous rail/channel trials are evidence that another
small underside piece will not fix that. Do not develop this as a further
trim-only edit.

**B. Open surface-intake carriage with a separate outlet cassette.** An open
roof, broad lower arms and a gathering floor were tried in passive renders.
The arms read as braces, and the floor did not explain the seam-to-tool route.
A second low pan with five teeth read as forklift forks from the seam side and
was barely visible from the outlet side. Both source trials were rejected and
are retained under `collector-open-intake-20261022` and
`collector-gathering-lip-20261022` in the local prototype evidence directory.
Adding another small carriage part to the present press-like body is no longer
the chosen prototype.

**C. Ground-facing cutter and gathering body.** Replace the collector's visual
silhouette as an assembly: an exposed low cutter head, a continuous gathering
surface rising to the existing stock bed, a supported mechanical input and a
separate outlet facing the native output direction. The cutter, bed and outlet
must appear physically related at both the seam and output camera angles.
Preserve the established native pick envelope, material ports and states; the
view cannot create extraction, an additional reserve or a working connection.
This is the next **visual prototype**, not accepted game art or proof that the
cutter touches the fixed boulder in every admitted placement.

The cutter-and-gathering body must fit the unchanged 1.45 × 1.65 × 1.45 m
machine pick box. The rejected carriage used a provisional intake mount at
local `(0, 0.25, 0)` and a 0.60 m entry below the existing 0.51 m stock bed;
those values do not locate the new cutting head. A provisional
outlet socket is at local `(0.725, 0.51, 0)`, with its outward normal `+X`;
rotation must transform that normal using the native quarter turn. These are
**art-study targets**, not proven clearances, new native sockets or a promise
that the present plinth can be cut there. A matched mesh test must measure the
real rock hull, terrain, plinth and tool sweep before retaining either shape.
An elevated collector permitted by native extraction depth needs a separate
verified support/intake variant; this ground-level artwork must not draw an
invented shaft down through foundations.

![Illustrative ground-cutter assembly concept](concepts/collector-ground-cutter-concept.png)

The image is an AI-generated **form reference** made for this study on
2026-10-22. It is not a measured asset, source mesh, validated mechanism or
render from the game. Its strong ideas are a low exposed cutter, a visibly
continuous gathering bed, rigid bearing supports and a separate lateral outlet.
Its pictured loose rocks cannot be mounted as static stock: actual visible
material must follow native quantity and custody. The large upper gear and
side housing also cannot imply a mechanical connection absent from the native
projection. The next modeled candidate must resolve those limits in real
geometry and pass the normal-scene comparisons below.

The module vocabulary should be reusable: `seam_frame`, `cutter_carriage`,
`gathering_floor`, `stock_bed`, `output_end` and `drive_bearing`. Each carries a
local origin, a facing direction, a physical-size declaration and its shared
material role. The `output_end` selects a connected cuff or a visibly open
terminal according to the actual native material link; it never grants that
link. Width variation belongs in a plain middle span; bearings, cutter teeth,
edge thickness and fasteners stay rigid instead of stretching with a whole
machine. An empty or depleted seam changes the rock/ore overlay according to
native stock, without dismantling the frame.

## Falsifiable prototype before adoption

Build the chosen modules as an isolated art candidate in a new owned worktree.
Retain exact-parent before/after images at the ordinary construction camera,
from both the rock side and outlet side. A front close view alone is insufficient.
In each view, the viewer should be able to point to the outcrop as geology and
then to the local cutter intake, gathering surface and terminal outlet without
reading labels. Reject the candidate if the cutter is still a hood ornament,
the rock disappears behind sheet metal, the outlet implies a live belt where
none exists, or the body becomes a single larger box. Compare both permitted
cells, rotation zero and one, powered/stopped states, a connected belt and an
exposed output. Preserve the actual source rock's physical hull, machine pick
body and native output port; test the real tool sweep and actor clearance
against any new triangles. Check reusable
materials and meshes, then inspect passive normal native pixels. Headless
geometry checks alone cannot establish this visual criterion or human quality.

No existing source model is approved for this role. The qualified drill-press
parts serve the press, not a mineral cutter. The inspected pellet hopper and
small channel failed the collector's form/function fit. A sourced detail may be
adapted later only after its pivot, scale, license, materials and socket fit are
checked. This brief selects an original structural silhouette first.
