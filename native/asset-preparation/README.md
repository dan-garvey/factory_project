# Mechanical asset preparation

These source-specific native writers consume exact provider buffers, not arbitrary
models. Build through [native builds](../../docs/engineering/native-builds.md);
run under ordinary admission with owned, fresh output directories. Retain source
hashes, licenses and delivered identities in the asset's `source.json`.

| Target | Source and output record |
| --- | --- |
| `//native/asset-preparation:prepare-waterwheel` | [Spinning Wheel 01 adaptation](../../experiments/engine-environment/godot/opening/assets/waterwheel/source.json) |
| `//native/asset-preparation:inspect-press-components` | Read-only Drill Press 01 component inventory |
| `//native/asset-preparation:prepare-press-support` | [Selected press column/support](../../experiments/engine-environment/godot/opening/assets/press-support/source.json) |
| `//native/asset-preparation:prepare-coupling` | [Industrial Pipes 01 flange adaptation](../../experiments/engine-environment/godot/opening/assets/shaft-coupling/source.json) |

Geometry writers take `SOURCE/original.bin OUTPUT_DIRECTORY`; the inspector
takes only `SOURCE/original.bin`. Put verified maps beside it as `albedo.jpg`,
`normal.png` and `arm.png`. In an imported captured project:

```bash
"$FACTORY_GODOT" --headless --path "$CAPTURED_IMAGE_PROJECT" \
  --script res://opening/machine_detail_check.gd -- \
  --prepare-waterwheel-maps "$WHEEL_SOURCE" "$WHEEL_PREPARED"
```

The corresponding modes are `--prepare-press-support-maps` and
`--prepare-coupling-maps`. The map adapter preserves source albedo and prepares
linear data/renormalized normal maps. Verify actual decoding/import separately
from native geometry tests.

Topology discovery welds only to identify components; delivered UV/normal vertices
remain distinct. Wheel output excludes the original stand/drive. Press output
excludes the complete donor foot and electrical parts. Coupling preparation
removes blind caps and closes an annulus without filling the shaft passage.
Exact source layouts, dimensions and refusal predicates live in source/tests.

Prepared meshes supply presentation only. They cannot alter native occupancy,
connections, motion or material authority. Inspect both isolated fit and the
ordinary view before making visual-quality claims.
