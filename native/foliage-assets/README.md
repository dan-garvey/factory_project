# Foliage preparation

`//native/foliage-assets:pack_tuft` has fixed profiles for Poly Haven
`grass_medium_01_mid_b_LOD0` and `fern_02_a`. Verify original file hashes
from the [grass](../../experiments/engine-environment/godot/opening/assets/foliage/source.json)
or [fern](../../experiments/engine-environment/godot/opening/assets/ferns/source.json)
manifest first; finite geometry validation does not authenticate an arbitrary
same-sized buffer.

Put source files in an owned directory as `source_geometry.bin`,
`source_albedo.jpg`, `source_alpha.png`, `source_normal.png` and
`source_arm.png`. Under normal admission:

```bash
"$FACTORY_GODOT" --headless --audio-driver Dummy \
  --path experiments/engine-environment/godot \
  --script res://opening/assets/foliage/prepare_maps.gd -- \
  --family="$FOLIAGE_SOURCE_FAMILY"
"$FACTORY_PACK_TUFT" "$FOLIAGE_SOURCE_FAMILY/source_geometry.bin" \
  "$FOLIAGE_SOURCE_FAMILY/prepared-maps/albedo.png" \
  "$FOLIAGE_SOURCE_FAMILY/prepared-maps/normal.png" \
  "$FOLIAGE_SOURCE_FAMILY/prepared-maps/arm.png" \
  "$FOLIAGE_SOURCE_FAMILY/grass_tuft.glb"
```

The map/output paths must be fresh. Add `--fern` before the five packer paths
for the fern profile. Source color is sRGB; normal/scalar maps are linear.
Normal resizing renormalizes vectors. The GLB embeds selected geometry and
three PNGs with opacity cutout; it supplies no collision, scatter or authority.

Use `//native/foliage-assets:tuft_test` through
[native builds](../../docs/engineering/native-builds.md). Header/geometry tests
do not replace image decoding, runtime import or visible inspection.
