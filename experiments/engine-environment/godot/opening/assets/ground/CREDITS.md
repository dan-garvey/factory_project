# Forest-floor surface

The current source is [Brown Mud Leaves 01](https://polyhaven.com/a/brown_mud_leaves_01)
by **Rob Tuytel**, provided by Poly Haven under [CC0](https://polyhaven.com/license).
The provider declares a 1.3-metre square surface. Its loam, moss and organic detail
are a reversible art choice for the riverbank, rather than a permanent biome rule.
The exact acquisition technique is unverified. [source.json](source.json) records
primary metadata, original files, preparation and packaged identities.

The 1024-pixel albedo preserves the source JPEG's decoded RGB8 values and sRGB
representation, with lossless WebP delivery. It is not resized, gamma-adjusted or
subjected to another lossy encoding. This is decoded-pixel preservation, rather
than byte identity with the original JPEG container.

The 16-bit OpenGL normal and packed data PNGs are decoded by the pinned Godot 4.7.2
loader to RGB8 before float Lanczos resampling to 512 pixels. Normal vectors are
renormalized and packed with nearest-integer RGB8 encoding; maximum unit-length
error is 0.006403. Lossless WebP preserves the prepared bytes exactly. Neither
data map receives a gamma operation or green-channel flip. Runtime generates
mipmaps, with normal renormalization, and maps the surface at `1 / 1.3` per metre.

Packed red occlusion affects ambient lighting only, green supplies roughness and
the material retains the descriptor's zero metallic factor. The source descriptor
does not bind occlusion; using the separately provided red channel is an explicit
adapter choice. Texture shading adds no leaf geometry, displacement, collision,
authority or saved state. Resource checks do not establish rendered balance,
contact physics, performance or the overall production-quality target.

The prior Rocky Trail finish by Amal Kumar remains in Git history and the original
`scanned-valley-ground-20261020` evidence family. Its successful conversions and
first normal-packing failure retain their original scope and revision. Historical
captures without any bitmap set still use the procedural finish; partial or invalid
sets remain explicit failures.
