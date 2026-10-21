# Fern undergrowth

This component derives from [Fern 02](https://polyhaven.com/a/fern_02), modeled by
Rico Cilliers and scanned by Rob Tuytel for Poly Haven, under
[CC0](https://polyhaven.com/license). [source.json](source.json) records the source
URLs, delivery checksums and exact hashes.

Only `fern_02_a` (`Plane.006`, catalogue mesh 2) is included: 544 vertices and 784
triangles. Its original local metre scale is preserved, omitting the catalogue's
one-metre Z display offset. The clump is approximately 0.55 metres wide, 0.61
metres deep and 0.29 metres tall. The provider's two-metre width describes the
whole four-clump catalogue.

The existing [image preparation](../foliage/prepare_maps.gd) combines photographed
sRGB color and separate linear opacity at 384 pixels. OpenGL normals are resized
to 256 pixels, renormalized and nearest-rounded to RGB8. Packed linear
occlusion/roughness/metallic is 256 pixels. All prepared maps use lossless PNG.
The [native writer](../../../../../../native/foliage-assets/README.md) embeds these
maps and selected geometry using `--fern`, preserving their bytes without mesh
simplification or quantization. Verify source hashes before packaging.

The first alternative glTF re-export failed exact-data controls and remains in
the external evidence. The shipped package uses native byte copies and reuses
the passing image preparation.

Runtime import obtains only the mesh resource, without an asset scene or editor
import cache. Shared double-sided cutout material uses the prepared channels and
generated mipmaps. Low clumps root on existing terrain outside construction space
and existing solids. They add no collider, input, state or authority. Historical
rosters without this asset omit the optional plant. Rendered balance, alpha
overdraw, GPU cost and human visual preference remain unassessed.
