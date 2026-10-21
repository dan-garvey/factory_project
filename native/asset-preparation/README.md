# Waterwheel component preparation

This source-specific offline C++ recipe extracts the rim, hub and twelve spokes
from Poly Haven's CC0 **Spinning Wheel 01**, by Sofia Pahaoja. Its exact source and
delivered identities are in the
[asset manifest](../../experiments/engine-environment/godot/opening/assets/waterwheel/source.json).
It is not a generic mesh importer or game-state tool.

Build `//native/asset-preparation:prepare-waterwheel` using the existing bounded
[Bazel workflow](../../docs/engineering/native-builds.md). Put the verified
provider model buffer in an owned source directory as `original.bin`. Run the
built executable through ordinary resource admission:

```bash
"$FACTORY_PREPARE_WATERWHEEL" "$WHEEL_SOURCE/original.bin" "$WHEEL_PREPARED"
```

The output directory must not exist. The writer verifies the exact source size
and SHA256 before reading the documented float and index arrays. It welds
coincident positions at a declared grid solely to discover disconnected source
components, then selects fourteen recorded component seeds. Output vertices
keep their actual separate UV and normal records; discovery welding does not
merge them. The selected set must contain 8,574 triangles. The original stand,
drive belt and other spinning-machine components are never selected.

The source hub centre is subtracted, then a proper rotation maps the original
X axle to local Z. One uniform scale makes the maximum radial distance 0.57
metres, inside the existing procedural rim. Normal vectors follow the same
rotation and are normalized; source UVs and triangle order are preserved.
The result contains 5,632 vertices with 16-bit indices. It adds no source node,
collision, skeleton, animation or state. Godot performs its ordinary glTF
coordinate and front-face conversion, generating tangent data when necessary.

Put the original pinned maps beside the source buffer as `albedo.jpg`,
`normal.png` and `arm.png`. Use the pinned Godot image API in an immutable
captured project, under ordinary heavy admission. This image-only mode does not
mount a game scene or create authority:

```bash
"$FACTORY_GODOT" --headless --path "$CAPTURED_IMAGE_PROJECT" \
  --script res://opening/machine_detail_check.gd \
  -- --prepare-waterwheel-maps "$WHEEL_SOURCE" "$WHEEL_PREPARED"
```

The original 1024-pixel albedo JPEG is copied byte-for-byte. The linear data
maps are Lanczos resized to 512 pixels in floating-point precision, normals are
renormalized, and channels are rounded to nearest RGB8 values. The script refuses
degenerate normals or normal encoding with length error at least 0.01 or angle
error at least 0.5 degrees. Those bounds concern encoding the resized vectors;
they do not claim that resizing preserves all original spatial detail.
Lossless WebP delivery must decode to those exact prepared pixels. Existing map
paths are refused, and no channel reorder, normal-axis flip or gamma conversion
is applied. There is no resize or additional lossy encoding of the albedo.

The first full-resolution conversion remains retained externally. The shipped
half-resolution data representation keeps this source-derived component near
1.14 MB within the shared project input allowance. This is a revisable art
packaging choice, not a quality or performance target.

The actual geometry extraction, changed-source and existing-output refusals,
image conversion and isolated wheel fixture are retained in
`sourced-waterwheel-20261020` under the local prototype evidence directory.
The fixture verifies real resources, all three native axes, material channels,
mesh reuse and unchanged authority. It does not assess rendering, human
preference, production quality or a new ordinary gameplay campaign.
