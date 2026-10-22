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
The original full rotor remains byte-identical: 5,632 vertices and 8,574
triangles with 16-bit indices. The same verified source also produces a rim-only
mesh (1,576 vertices, 1,872 triangles) and a centered hub with twelve spokes
(4,056 vertices, 6,702 triangles). These two new meshes preserve the exact
selected source triangles and atlas records; only their independent vertex
indices differ. Runtime mounts two rim instances at symmetric local axle seats
around one centered hub/spoke instance. The second rim adds 1,872 visual
triangles per wheel. The recipe adds no source node, collision, skeleton,
animation or state. Godot performs its ordinary glTF coordinate and front-face
conversion, generating tangent data when necessary.

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
half-resolution data maps kept the original component near 1.14 MB. The two
new separated geometry files add 233,605 bytes to this resource set. This is a
revisable art packaging choice, not a quality or performance target.

The actual geometry extraction, changed-source and existing-output refusals,
image conversion and isolated wheel fixture are retained in
`sourced-waterwheel-20261020` under the local prototype evidence directory.
The fixture verifies real resources, all three native axes, material channels,
mesh reuse and unchanged authority. It does not assess rendering, human
preference, production quality or a new ordinary gameplay campaign.

## Cast press support

`//native/asset-preparation:inspect-press-components` inventories disconnected
components in the pinned Drill Press 01 body without writing assets or creating
a scene. `//native/asset-preparation:prepare-press-support` extracts the selected
column, cast collar and mounting hardware. Source and delivered identities are
in the [press record](../../experiments/engine-environment/godot/opening/assets/press-support/source.json).

Both writers use the same topology-discovery helper. Extracting that helper
retained the complete rotor buffer and descriptor exactly. The previous tool
and source remain outside mutable build outputs. Discovery preserves separate
delivered UV/normal vertices and changes no gameplay geometry or admission.

Build and run through the existing bounded Bazel and admission path:

```bash
"$FACTORY_INSPECT_PRESS" "$PRESS_SOURCE/original.bin"
"$FACTORY_PREPARE_PRESS" "$PRESS_SOURCE/original.bin" "$PRESS_PREPARED"
"$FACTORY_GODOT" --headless --path "$CAPTURED_IMAGE_PROJECT" \
  --script res://opening/machine_detail_check.gd \
  -- --prepare-press-support-maps "$PRESS_SOURCE" "$PRESS_PREPARED"
```

The source directory contains verified provider files as `original.bin`,
`albedo.jpg`, `normal.png` and `arm.png`. Outputs must be fresh. Geometry keeps
the source Y axis and centres X/Z on the actual column. Its mounting datum is the
underside of the source flange plate, retaining the small lower bolt penetration.
One uniform scale fits 1.16 metres from that plane to the original bridge. Runtime
repeats it at the original support positions and turns the right copy by half a
revolution. The current plinth, anvil, head, guides, outlet, spindle and physical
envelope remain. The complete donor foot and electrical/drive parts are excluded.

The image adapter now takes an internal filename prefix. Its original waterwheel
command and delivered map bytes remain exact. Both assets retain original albedo
JPEGs, prepared 512-pixel normal/scalar maps and explicit source/processing records.
The isolated fit check compares actual imported support triangle boxes with the
existing work meshes at both visual head end poses. This is a reusable support
component and visual fit result, not a structural-force, native-contact, general
freeform-machine or rendered-quality result.

## Sourced shaft coupling

`//native/asset-preparation:prepare-coupling` adapts the first straight member of
Poly Haven's CC0 **Modular Industrial Pipes 01**, by Jorge Camacho. It accepts
one exact source buffer and accessor layout; it is not a general mesh importer.
The selected pipe has blind caps behind its apparent openings. The recipe keeps
source Y at or above 0.39 metres, removing the cap and lower pipe while retaining
the upper flange and its eight fasteners. The cut contours are slightly uneven.
They remain unchanged: the writer requires two nested, single-winding,
star-shaped contours, refuses touching or crossing boundaries, and triangulates
an annular closure with verified area. It never fills the shaft passage.

The source Y axis remains local Y. An authored datum at Y = 0.42954 metres and
one uniform scale of 0.72 produce the compact fitting. This is an adaptation
datum, not a provider socket or game rule. Retained vertices keep source UVs and
normalized normals; new cut vertices interpolate attributes. The separate cut
surface has hard outward normals and an existing machined-metal material.
The complete prepared half contains 312 source triangles and 48 closure
triangles. Two copies mate using a proper half-turn about local X.

```bash
"$FACTORY_PREPARE_COUPLING" "$COUPLING_SOURCE/original.bin" "$COUPLING_PREPARED"
"$FACTORY_GODOT" --headless --path "$CAPTURED_IMAGE_PROJECT" \
  --script res://opening/machine_detail_check.gd \
  -- --prepare-coupling-maps "$COUPLING_SOURCE" "$COUPLING_PREPARED"
```

The absolute output directory must be fresh. The image command uses the same
qualified component adapter above, with a coupling filename prefix. Source
inputs and delivered identities are in the
[coupling record](../../experiments/engine-environment/godot/opening/assets/shaft-coupling/source.json).
Run `//native/asset-preparation:coupling_test` for the in-memory cut, bore,
attribute, seam and malformed-input controls. This non-host test joins the
canonical native package selection automatically; the actual donor remains an
explicit input to the preparation consumer.

The native presenter mounts the pair only for an explicit coaxial shaft/cog
engagement, outside the existing hub and inside the original shaft envelope.
The pair follows the owning shaft's existing cosmetic phase. No World command,
connection solver, collider, pick, clock or saved state is added. Other kinds of
coupling, complete-machine routing, force transmission, rendered quality and
human preference are separate outcomes.
