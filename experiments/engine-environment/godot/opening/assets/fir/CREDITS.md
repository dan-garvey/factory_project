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
the catalogue's five-metre X translation is omitted. The provider's combined
catalogue width is not the width of this individual tree. This component is
qualified art; its bank adoption is described below, separately from the
original source/resource result.

The catalogue-offset metadata was corrected after initial qualification. The
original external reports remain intact; the prepared resource, source-local
geometry, textures and later bank poses did not change.

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

The bank fixture mounts three instances at 1.45–1.55 times source scale, with
gravity-upright yaw and roots embedded two centimetres into the actual terrain
triangles. A deterministic bounded search preserves the eight-metre working
ring, whole-canopy river/rock clearance and separation between trees. The
current selected scales are 1.45, 1.55 and 1.5; this is an art default rather
than growth, harvesting or a permanent biome.

The two woody surfaces supply all 16,560 transformed triangles across the three
trees to ActorWorld's existing two-sided floor shape. Needles are visual
foliage; there is no invisible box obstacle or separate tree controller. The
same source geometry feeds the analytical capsule contact diagnostic. The
floor registration guard requires both the native body and its node at the
immutable world-space origin, so shifting them together cannot disguise a
different fixture. Old ground triangles and rock descriptors remain unchanged.

The first narrow placement search failed to find three sites and is retained.
The expanded search passed 435 geometry/interface assertions but logged two
fixture camera errors from building outside the node tree. That whole call
is not accepted as clean. A separate six-check mounting correction passed
inside the actual node tree without repeating the geometry checks. Fifteen
isolated physical-fixture checks then passed actual native capsule contacts,
clear working space and altered-shape/pose rejection. No real player, machine
authority or material command ran. These checks establish neither ordinary
traversal nor rendered appearance, performance, human preference or production
quality.
