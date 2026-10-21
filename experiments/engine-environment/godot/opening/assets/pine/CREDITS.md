# Young pine understory

The complete `pine_sapling_small_b` mesh comes from Poly Haven's
[Pine Sapling Small](https://polyhaven.com/a/pine_sapling_small), modeled by
Rico Cilliers with photography by Rob Tuytel. The source is licensed under
[CC0](https://polyhaven.com/license). `source.json` records the original files,
selection, preparation and shipped resource identity.

The selected plant is approximately 1.05 metres tall with a roughly three-centimetre
lower stem. It is young, noncolliding understory, not a mature rigid tree. Six
instances at most share its full bark and modeled-needle geometry; no authored
distance level exists in the source. The source catalogue's one-metre X offset is
omitted, without changing the selected mesh coordinates.

The pinned Godot 4.7.2 importer supplies compressed position, UV and normal/tangent
attributes. We preserve those buffers rather than expanding and repacking them.
This is not bit-for-bit preservation of the original floating-point glTF: measured
position differences are below 15 micrometres per component and UV differences
below 0.00007. The imported arrays and prepared embedded pixels survive native
resource serialization exactly. All 122,235 source triangles remain.

Preparation in `../foliage/prepare_maps.gd` resamples albedo in linear light to
384 pixels, normal and packed roughness/metallic data to 256 pixels, renormalizes
normals and adds mipmaps. The original maps are opaque JPEGs; no alpha channel is
invented. Bark is opaque and the needle surface retains the source cutout mode.
The native resource contains the importer's specular-0.5 dielectric defaults.
At load time, two cached material copies map the original IOR and gray specular
color to normal-incidence reflectance: approximately 0.0016 for bark and 0.0008
for needles. The [glTF extension](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_specular)
defines that source response. The pinned [Compatibility shader](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/drivers/gles3/shaders/scene.glsl)
uses `F0 = 0.16 * specular * specular`, giving adapter values 0.1 and approximately
0.070710678. Imported material references, geometry and prepared images remain
intact. This preserves the specified normal-incidence response, not a complete
cross-renderer scattering conversion. The source has no bound occlusion texture,
so ambient occlusion stays disabled.

The self-contained compressed `ArrayMesh` adds no scripts, collision, authority,
wind simulation or harvesting rules. Whole-plant envelopes clear the river and
rocks; confirmed machines suppress intersecting plants and removal restores them.
Resource and placement controls do not establish rendered balance, GPU cost,
collision for larger trees or the overall production-quality threshold.
