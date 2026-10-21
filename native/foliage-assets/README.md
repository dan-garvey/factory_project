# Bounded grass asset preparation

This optional C++ writer extracts only `grass_medium_01_mid_b_LOD0` from the
recorded Poly Haven Grass Medium 01 buffer. It is not a general importer, new
game authority or build-gate replacement. Source identity, license, all input
hashes and the shipped output hash are in
[the asset manifest](../../experiments/engine-environment/godot/opening/assets/foliage/source.json).
Verify those source hashes before running the fixed-offset writer. It validates
the selected finite positions, unit normals, UVs and index bounds independently;
it does not authenticate arbitrary similarly sized source buffers.

The source mesh has 1,386 vertices and 1,257 triangles. Its source-local root is
preserved, including a few millimetres below zero. The writer omits the catalogue
node's X placement and applies a declared uniform scale of two. It copies the
original normals, UVs, indices and winding without simplification. Godot performs
its ordinary glTF coordinate conversion and tangent generation at runtime.

Preparation uses the pinned Godot image API, without a game or desktop. Put the
verified provider files in an owned directory as `source_geometry.bin`,
`source_albedo.jpg`, `source_alpha.png`, `source_normal.png` and `source_arm.png`.
Under normal resource admission, run:

```bash
"$FACTORY_GODOT" --headless --audio-driver Dummy \
  --path experiments/engine-environment/godot \
  --script res://opening/assets/foliage/prepare_maps.gd -- \
  --family="$FOLIAGE_SOURCE_FAMILY"
```

This creates a fresh `prepared-maps` directory and retains exact decode, opacity
coverage and normal-vector checks. It refuses to replace earlier preparation.
Color and separate opacity are Lanczos resized to 384 pixels and combined into
RGBA8. The OpenGL normal is resized to 256 pixels, renormalized and explicitly
rounded to nearest RGB8 values. Linear packed occlusion/roughness/metallic is
resized to 256 pixels with no channel or gamma conversion. Prepared PNG files
are lossless. The scanned color is sRGB, and the data maps remain linear.

Build `//native/foliage-assets:pack_tuft` and run the relevant
`//native/foliage-assets:tuft_test` through the existing bounded
[Bazel workflow](../../docs/engineering/native-builds.md), then run the built
binary under cheap admission:

```bash
"$FACTORY_PACK_TUFT" "$FOLIAGE_SOURCE_FAMILY/source_geometry.bin" \
  "$FOLIAGE_SOURCE_FAMILY/prepared-maps/albedo.png" \
  "$FOLIAGE_SOURCE_FAMILY/prepared-maps/normal.png" \
  "$FOLIAGE_SOURCE_FAMILY/prepared-maps/arm.png" \
  "$FOLIAGE_SOURCE_FAMILY/grass_tuft.glb"
```

The self-contained GLB embeds the selected geometry and all three PNGs. It uses
the provider's dielectric factor and double-sided surface, with a deliberate
0.5 opacity cutout instead of blended cards. No external resource URI, animation,
skin, collision or catalogue scatter is shipped. The C++ controls use invented
geometry and PNG headers; actual image decoding and mesh/material integration
are covered separately by the headless environment fixture.

The ordinary presenter imports the buffer once using
[GLTFDocument](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html),
then obtains its single
[ImporterMesh](https://docs.godotengine.org/en/stable/classes/class_importermesh.html)
without instantiating an asset scene. It explicitly generates image mipmaps and
renormalizes normal mip levels before caching the mesh/material. No editor import
cache is required. The original runtime check found missing mipmaps; that first
failure remains retained, alongside the focused correction. Headless checks do
not establish rendered quality, GPU performance or human preference.
