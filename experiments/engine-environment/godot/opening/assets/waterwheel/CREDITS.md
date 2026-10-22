# Sourced timber rotor

The rim, hub and twelve spokes are adapted from **Spinning Wheel 01**, by
**Sofia Pahaoja**, published by [Poly Haven](https://polyhaven.com/a/spinning_wheel_01).
The model and material maps are available under
[CC0](https://polyhaven.com/license). Attribution is retained for provenance.
Poly Haven's website preview is not included in this package.

The original asset depicts a spinning machine. Factory extracts its rim separately
from the hub and twelve spokes, retaining the source mesh and atlas coordinates.
One centered hub/spoke mesh and two instances of the same rim mesh make a
double-sided waterwheel presentation. Three-tile wheels use the exact prepared
geometry; larger wheels reshape the source radial coordinates to keep the timber
wall and hub from scaling as quickly as the outer diameter. Normals and tangents
follow that visual transformation while the UV atlas stays unchanged. This is
an experimental art proportion, not a load-bearing design rule. The complete rotor
files remain unchanged for historical captures. A declared rigid coordinate
change and uniform scale fit the existing assembly. The stand, belt, treadle and
other machine components are excluded. This adaptation does not imply that the
source model is a mechanically functional waterwheel or supplies Factory's power rules.
The source material's double-sided shading is retained.

The photographed color remains the original one-kilopixel provider JPEG.
The centered hub and spokes also use a derived color atlas made from that JPEG.
Its deterministic warm shadow lift adds `(0.18, 0.11, 0.06) * (1 - luminance)^2`
to RGB, clamped to one, and leaves the rim on the untouched provider color.
The 1024-pixel derived map is encoded as lossy WebP at quality 0.82 to fit
the current native launcher source allowance. It keeps the same UV coordinates
and packed normal/occlusion/roughness/metallic maps; it is an art-grade choice,
not a new source photograph or a lighting/gameplay rule. Run the
[offline color recipe](../../machine_detail_check.gd) in
`--prepare-wheel-center-color` mode with a fresh output path to reproduce the
map. Historical
captures without the derived map retain the original shared color material.
The OpenGL normal and packed occlusion/roughness/metallic maps are prepared at
512 pixels, with floating-point Lanczos sampling, normal renormalization and
nearest RGB8 encoding. WebP delivery is lossless relative to that prepared
representation; it is not pixel equality with the original larger maps.
No channel reorder, green-axis flip or color-space transform is applied.

[source.json](source.json) records exact input and delivered hashes, dimensions
and processing. The [C++ preparation recipe](../../../../../../native/asset-preparation/README.md)
describes reproducible extraction. Runtime code shares the two meshes and one
material between wheels, keeps the existing hub, paddle and bearing placement,
and consumes the existing confirmed wheel motion. The art has no collision,
quantity or transmission authority. The second rim adds visual triangles;
GPU cost, circumference texture density and human visual acceptance remain unassessed.
The current native launcher captures raw source assets; packaged Godot exports
are outside this fixture's verified resource closure.
