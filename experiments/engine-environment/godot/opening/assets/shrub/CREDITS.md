# Woody bank shrubs

The bushes derive from Poly Haven's [Searsia Lucida](https://polyhaven.com/a/searsia_lucida),
modeled by James Ray Cock with photography by Jenelle van Heerden, under
[CC0](https://polyhaven.com/license). The exact one-kilopixel glTF, its shared
geometry, color, OpenGL normal, packed material and separate opacity maps were
captured on 2026-10-23. Download URLs, sizes and source hashes are in
[source.json](source.json); the preparation script verifies every source SHA-256
before importing it.

The shipped taller and lower forms retain complete source plants 4 and 5 of
the seven-plant glTF. They have solid bark, separate leaf and twig cutouts,
original vertices and UVs, and three complete material surfaces. Their native
bounds are about 1.03 and 0.74 metres high. The source leaf color is tinted a
restrained green for the river biome; bark and narrow twigs keep their original
color. Prepared color and opacity maps are 128 pixels, while normal and packed
material maps are 64 pixels, with mipmaps. The resources contain 27,701 and
7,232 triangles and have no external dependencies. Their exact serialized
hashes are pinned in `opening.gd`.

Fresh preparations can serialize different `.res` bytes. Compare the complete
mesh arrays, material settings and bound texture pixels before substituting a
new preparation; the runtime pins identify the shipped resources.

Each form uses one shared mesh in a bounded terrain-rooted `MultiMesh`. Whole
plant envelopes clear the river, rocks, trees and existing solid construction;
confirmed construction suppresses overlapping plants, and removal restores
them. The bushes are soft scenery without collision, harvest, save or production
authority. The placement scan accepts at most twelve roots per form after
clearance checks. Whole-scene frame cost and human visual preference remain
unmeasured outside the focused scene and passive camera checks.
