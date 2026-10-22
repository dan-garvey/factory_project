# Carried multitool

The combination cutter and reclaim heel are original Factory geometry, authored
for the experimental opening by factory-playability. `multitool.tscn` is the
editable Godot text scene and includes its mesh and material resources. It uses
metres, with the grip centre at the scene origin and the cutting tip along -Z.
It needs no external textures or third-party tool model.

The first-person hand is generated at runtime from the already qualified
[worker asset](../worker/README.md), under that asset's existing terms. The hand
is not stored in this tool scene. Its skin-weighted triangles and materials are
cached after applying the right-hand grip; no second player or physical body is
created. Cutting duration and contact animation remain gameplay work outside
this presentation asset.
