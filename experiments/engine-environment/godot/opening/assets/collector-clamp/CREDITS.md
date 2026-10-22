# Sourced modular tool-mount casting

The cast body and fixed jaw come from [Bench Vice 01](https://polyhaven.com/a/bench_vice_01)
by Antanas Kep (modeling and texturing) and Yann Kervran (rigging), distributed
by Poly Haven under [CC0](https://polyhaven.com/license).

The official [1K glTF file manifest](https://api.polyhaven.com/files/bench_vice_01)
was captured on 2026-10-22. The original descriptor, buffer, three maps,
provider metadata, exact byte checks and preparation inputs are retained outside
Git under `collector-clamp-source-20261022`. The original donor is a rigged vise.
This preparation selects only `bench_vice_frame` and `bench_vice_clamp`, removes
their skin attributes and excludes the dial, bar, rig and animation controls.
The mesh buffer and three 1K source maps are byte-identical to the provider files.
The prepared glTF changes only the scene and node selection, names and unused
skin declarations; it does not alter selected positions, normals, UVs or indices.

The two rigid members mount at the native `tool_mount` occupied centre, yawed
90 degrees so the fixed jaw faces the cutter, and shifted 8 cm down onto the
existing support foot. They remain passive presentation: the player cannot
adjust the jaw or use this donor as a separate vise. Native World and Host own
part identity, placement, collision, work and material. Imported triangles do
not add contact, clamping force or a new gameplay rule. The 1K JPEG data maps
and isolated import are technical choices; ordinary-distance appearance and
human visual quality still require assessment.
