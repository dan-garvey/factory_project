# Opening presentation assets

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

`press.tscn` prepares a cast-frame press with separate guides, a tool head, anvil,
output tray, feet and visible fasteners. It fits inside the existing conservative
machine bounds and uses the current working-height convention. It is not yet
connected to the opening presenter. Its ram is stationary scene geometry; any
later motion must follow the confirmed work phase. The drive stub is a visible
machine interface, not a cogwheel or evidence of mechanical engagement.

The materials and primitive meshes are authored here using built-in Godot
resources. No external artwork, model download or new runtime dependency is
included. The palette and geometry remain revisable until normal-distance
in-game evidence and user visual feedback support them.

The fixed-roster launchers already include `character_presenter.gd`, so the
playable worker has no new file dependency. Complete-project native capture also
includes these previews. No Python launcher changes are needed. Rendered quality,
ordinary interaction/collision correspondence and user feedback remain unverified
until exercised in the actual opening.

The visual task also covers machine silhouettes, lighting and composition.
This first asset does not complete that task, introduce geometric cogwheel
authority, repair window resizing or change the opening's teaching flow.
