# Opening presentation assets

The [production presentation target](../../../../../docs/art/production-quality.md)
now sets Satisfactory as the minimum graphical benchmark. The existing primitive
silhouettes do not satisfy that target. The first integrated asset foundation
adds closed machined edges, shared lit surface finishes and coherent foundation
panels; rendered quality remains unassessed and the broader task remains open.

The `ProductionVisuals` class in the already captured `opening.gd` owns reusable
chamfered box meshes and creates the original procedural surface resources.
One shared height source supplies subtle roughness and normal detail. Textures
are seamless and mipmapped. Painted housings use low metallic response while
exposed bearings retain their steel finish. Shapes stay within the existing
envelope; no visual mesh is a physics or construction authority.

These original project scene assets prepare the visual work in
`factory-yau.6.45`. The character presenter constructs the playable worker from
built-in meshes in its existing script. The scenes here are optional previews;
neither public launcher needs to capture them to display the worker.

`worker.tscn` previews the worker's clothes, boots, safety helmet, visor and tool
pouch. The playable construction uses the same dimensions, with a slightly finer
glove sphere. Its origin is the confirmed actor-body origin. Both versions contain
only meshes and materials: no scripts, physics bodies,
collision shapes, input handlers or gameplay state. The existing native capsule
remains the collision proxy; visual geometry is not construction authority.

`press.tscn` previews a cast-frame press with separate guides, a tool head, anvil,
output tray, feet and visible fasteners. The playable view constructs the frame,
guides, anvil, head and tray directly in `opening.gd`; it does not load this optional
scene. The outlet plate now sits on that tray within the original conservative
machine envelope. The ram is stationary visual geometry; later motion must follow
the confirmed work phase. The drive stub is a visible interface, not a cogwheel
or evidence of mechanical engagement.

The same existing view script builds an open collector stock bed, supported
conveyor with contrasting cleats, and waterwheel with an open rim, spokes,
paddles and axle bearings. Shared frame/steel/copper finishes keep the silhouettes
coherent. The old decorative wheel rotation still follows the confirmed powered
flag. No rendered mesh supplies power, contact, placement, collision or reach.
Pick bodies, labels, interaction anchors and gameplay state are unchanged.

For the native scene profile, machine spindles, waterwheel axle and bearings
follow each entity's projected X, Y or Z axis through the confirmed hub height.
Older native projections without an axis retain X. The wheel is scaled to keep
its rim above the ground; a Y-axis wheel has a horizontal rotor on a pedestal,
and vertical machine stubs are shorter to fit the unchanged machine envelope.
Historical scripted views keep their original decorative stubs and wheel
dimensions. Native rotational phase is not published yet, so that rotor stays
still; the view does not invent a second phase clock from the global powered
flag. This changes no power rule, contact, shaft geometry or collision envelope.

Confirmed material links have static arrowheads and endpoints aligned with their
actual ordered grid direction, including routes along either axis. These indicate
the existing link direction, not simulated item motion or a pending command.
Power-link drawing remains unchanged. The separate `material_route_test.gd`
checks both directions on both axes, geometric arrow direction and projection
immutability; it can also run against the preserved predecessor as a negative
regression witness.

The materials and primitive meshes are authored here using built-in Godot
resources. No external artwork, model download or new runtime dependency is
included. The palette and geometry remain revisable until normal-distance
in-game evidence and user visual feedback support them.

The worksite uses a built-in procedural sky for its background, ambient light
and metallic reflections. A warm key light keeps its existing direction; a weak
cool fill lights the opposite faces without casting another set of shadows.
These are revisable presentation defaults. No screen-space effects or external
sky texture are required by the Compatibility renderer. Headless startup checks
resource initialization, not the rendered balance or quality of these choices.

The fixed-roster launchers already include `character_presenter.gd` and
`opening.gd`, so the worker and machined surfaces have no new file dependencies.
Complete-project native capture also
includes these previews. No Python launcher changes are needed. Rendered quality,
ordinary interaction/collision correspondence and user feedback remain unverified
until exercised in the actual opening.

`machine_visual_test.gd` checks mesh bounds against the existing machine envelope,
the unchanged pick contract and projection immutability. It samples the wheel at
24 orientations and uses an invented read-only fixture without game stepping or
desktop access. These automated checks cannot establish rendered appearance or
human understanding.

Rendered lighting, composition and human visual feedback remain unfinished. This
increment does not complete the visual task, introduce geometric cogwheel
authority, repair window resizing or change the opening's teaching flow.
