# Qualified fir resource

[Fir Sapling Medium](https://polyhaven.com/a/fir_sapling_medium), modeled by
Rico Cilliers with photography by Rob Tuytel, is published by Poly Haven under
[CC0](https://polyhaven.com/license). Source and metadata were retained on
2026-10-21. The complete one-kilopixel glTF bundle was checked against every
provider file size and MD5 before conversion. `source.json` records original
SHA-256 identities and exact processing. No provider scene, camera or catalogue
layout becomes game content.

`fir_tree.res` contains the complete local `fir_sapling_medium_b_LOD0` mesh,
with its three materials and all 420,822 base triangles. Its source height is
about 7.8 metres, including the small below-origin root extent. Scale is one;
the catalogue's one-metre X translation is omitted. The provider's combined
catalogue width is not the width of this individual tree. This component is
qualified art, not yet a mounted forest or a physical tree fixture.

Preparation uses the pinned Godot 4.7.2 glTF importer and
[ImporterMesh](https://docs.godotengine.org/en/stable/classes/class_importermesh.html).
Generated distance levels keep the full original base. The pinned
[simplifier integration](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/resources/3d/importer_mesh.cpp)
uses attribute-aware simplification and original vertex indices. Its nominal
size is cumulative simplification error multiplied by source mesh scale.
Fine disconnected twigs can be pruned at coarser levels. These are locally
generated approximations, not provider-authored LODs or verified screen error.
Actual switching, silhouette stability and GPU cost remain unassessed.

The six original JPEG maps are decoded at 1024 pixels. Albedo is filtered in
linear light and re-encoded as sRGB at 384 pixels; linear normal and packed ARM
data are filtered at 256 pixels, with normalized OpenGL normals. RGB8 encoding
uses nearest clamped rounding, and all prepared images include mipmaps. The
three embedded materials share the two prepared map sets while retaining their
different source UV transforms. The descriptor does not bind occlusion, so its
ambient-occlusion state remains disabled. No missing alpha image is invented;
the actual descriptor's blend mode and importer material state are retained.

Normal-incidence dielectric reflectance follows the source IOR and scalar
specular factor. Godot Compatibility's `F0 = 0.16 * specular²` maps those values
to its material field; the dead-wood material retains the source defaults. This
is a bounded normal-incidence mapping, not a complete glTF scattering model.

The resource keeps importer-compressed native buffers. The largest measured
source-local position packing error is below 0.15 millimetres. Resource reload
preserves the native arrays, every generated distance index and the prepared
pixels exactly. The twelve-MiB component allocation and common project capture
limit remain distinct. The shared `site_surface.gd` reader checks the prepared
identity before deserialization; absent historical rosters can omit it.

This source/resource qualification establishes no game, collision, rendered
appearance, performance, human preference or production-quality verdict. A
later scene join must match woody collision to the actual tree geometry and
keep the working area clear rather than mounting large walk-through trunks.
