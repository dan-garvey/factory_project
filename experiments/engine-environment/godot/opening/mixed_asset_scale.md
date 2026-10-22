# Dense chapter-one asset render fixture

`machine_visual_test.gd --mixed-scale` renders the chapter-one terrain, sky, water and foliage
with a regular field of the current collector, conveyor and press art. Each
assembly uses the opening's existing production visual constructors and the
shared construction pitch. The count is the number of complete machine
assemblies, distributed evenly among the three kinds. Every assembly is
visible from a fixed camera. The fixture uses the project's Compatibility
renderer and its normal material, mesh and lighting resources.

The default path draws the individual meshes. `--batch` groups only repeated
mesh resources with the same whole-mesh material, overlay, shadow mode and
visibility layer into `MultiMeshInstance3D` draws. The current opening helper
bakes any per-surface override onto a shared mesh with the same vertex arrays
and surface materials. The candidate keeps the original geometry, materials,
transforms and shadows; it does not simplify geometry or textures.
The original nodes remain hidden in the fixture so their identity and local
transforms can be inspected. This is a rendering experiment, not a change to
the playable opening.

After importing the project, run without `--headless` and admit the whole
measurement through the repository's exclusive `factory-local benchmark`
mode. For example:

```bash
factory_local="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources/factory-local"
factory_godot="$(git config --get factory.godotExecutable)"
"$factory_local" --root "$PWD" benchmark -- "$factory_godot" \
  --path experiments/engine-environment/godot --resolution 1280x800 \
  --script res://opening/machine_visual_test.gd -- --mixed-scale --count=200 --batch \
  --capture=/absolute/path/outside/git/mixed-200.png
```

The script disables VSync, warms 30 frames, samples 120 frames and emits one
`MIXED_ASSET_SCALE` JSON line with the median and 95th percentile frame
interval, median draw calls and construction time. Compare equal counts and
the same viewport/camera on the same source and hardware. A 120 FPS frame
budget is 8.333 milliseconds. Save the image and inspect the actual pixels
before calling the candidate visually equivalent.

The density is synthetic: the fixture does not place these machines through
the native World, supply their inventory, run recipes, animate confirmed
machine motion, test picking or prove playable frame rate in the complete
opening. It measures the existing chapter-one scenery and current machine
visual assets in a rendered scene. A game-wide 120 FPS result requires an
additional complete-opening measurement with authoritative activity and a
representative player-built layout.

## Measured result, 2026-10-22

The exact opening source was main commit
`b3d0f6ba05f70f2547382163996663ad6ef5b338`. Its SHA-256 was
`92aac056b56b9319ee320e0e5b541434f65c92469dea130555891e4ee26b3afd`.
The complete `machine_visual_test.gd` had SHA-256
`ef0322041df2c368a6902a9404079535cc5013a0529567323f9383f483c5e291`.
The renderer was Godot 4.7.2
Compatibility on WSL2, Mesa 23.2.1 D3D12, NVIDIA GeForce RTX 3090 driver
610.88, at 1280 × 800. All timing runs held the exclusive local benchmark
permit. The driver reported that changing VSync mode was unsupported. Runs
were ordered zero, 100 individual, 100 batched, then 400 batched. Each had 30
warmup and 120 sampled frames; one run of each condition was retained.

| Assemblies | Presentation | Median frame | 95th percentile | Median draw calls |
| ---: | --- | ---: | ---: | ---: |
| 0 | Current worksite scenery | 15.006 ms | 16.718 ms | 86 |
| 100 | Individual meshes | 577.136 ms | 583.893 ms | 15,191 |
| 100 | Repeated meshes and surface finishes | 28.848 ms | 31.397 ms | 308 |
| 400 | Repeated meshes and surface finishes | 36.361 ms | 39.263 ms | 322 |

The 400-assembly case constructed 27,222 mesh nodes. The candidate drew
27,089 of them through 81 batches, leaving the original nodes hidden in the
fixture. A close nine-assembly rendered comparison showed the same visible
silhouettes, material finish and shadows; the wide 400-assembly image shows
the full field but fog and distance hide fine detail. The candidate uses the
same mesh arrays and surface materials, but these images do not establish
pixel equivalence at every angle or gameplay quality.

**120 FPS was not reached.** The 8.333 ms budget is exceeded even by the
empty worksite in this renderer setup. At 400 assemblies the measured median
was about 27.5 FPS, before authoritative simulation, UI, a controlled
character or player-built inventory. The large 100-assembly reduction is a
measured result for this visual fixture only; run-to-run variation and other
machines remain unmeasured. Local logs, exact source hashes, environment and
PNG captures are retained under
`/home/dan/.local/state/factory-prototypes/mixed-chapter-assets-20261022`.

## Current-main join measurement

The fixture was joined with main at merge commit
`0d63174185e3582fc2b93f4b3381a49bb4cf38c0`, including the landscape
variety, wheel culling and landing-pod work then present. The joined
`opening.gd` SHA-256 was
`b2c8adac6e323723d86e1667d74b05cf1c6e6e61c47d97d162cdc985008a3918`;
the joined `machine_visual_test.gd` SHA-256 was
`598235108c1599f06fa486ed96c655e8fb81fa9ee40a0b82752c0a92fc24de9c`.
The same machine, renderer, viewport, camera, warmup and sample count were
used. The exclusive runs measured 14.460 ms median and 20.903 ms 95th
percentile with no machine assemblies (93 median draw calls), and 36.960 ms
median and 39.727 ms 95th percentile with 400 batched assemblies (322 median
draw calls). The latter is approximately 27 FPS at the median. The joined
batch motion fixture passed 17 assertions. Godot import reported no parser
errors.

The captured 400-assembly field is present beside the river, with repeated
machine silhouettes visible across the bank. At this camera distance, fog and
scale obscure small surface details. The zero-assembly capture shows the
updated water, vegetation and rock silhouettes. These images establish the
rendered arrangement at this revision, not close-view equivalence or human
play quality. Logs and both captures are retained in the local directory
above. The 8.333 ms frame budget remains unmet even before machine assemblies.
