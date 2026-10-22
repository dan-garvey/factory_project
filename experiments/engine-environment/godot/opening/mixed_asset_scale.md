# Dense chapter-one asset render fixture

`machine_visual_test.gd --mixed-scale` renders the chapter-one terrain, sky, water and foliage
with a regular field of the current collector, conveyor and press art. Each
assembly uses the opening's existing production visual constructors and the
shared construction pitch. The count is the number of complete machine
assemblies, distributed evenly among the three kinds, up to 1,000. Every assembly is
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

For this stationary fixture, `--share-static-conveyor-finish` also batches
the conveyor loop material. The production constructor duplicates that finish
once per belt so live belts can have independent texture phase. This fixture
never advances phase, and it groups only loops whose phase equals the original
source finish. Their mesh, texture maps, material properties and shadows stay
the same. The live opening has its own phase-aware conveyor batch; this option
does not change its behavior or prove moving-belt equivalence.

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

## One thousand assembly attempt, 2026-10-22

On main `2212b85f34745e214ac2df236a6d0a0d2a53b846` plus the fixture
changes in this guide, the 1,000-assembly field contains 68,022 source mesh
nodes. Godot 4.7.2 Compatibility used the same 1280 × 800 WSL2/Mesa D3D12
RTX 3090 setup. Each exclusive run used 30 warmup frames followed by 120
sampled frames. The VSync mode change was unsupported by the driver. This is
one run per condition, in the order shown; the frame-time difference is much
larger than the observed tail variation, but repeat-run variation is unknown.

| 1,000 assemblies | Median frame | 95th percentile | Median draw calls | Build time |
| --- | ---: | ---: | ---: | ---: |
| Ordinary repeated-mesh batch | 60.119 ms | 67.081 ms | 420 | 11.374 s |
| Plus shared stationary conveyor finish | 16.875 ms | 18.202 ms | 97 | 11.421 s |

The shared-finish run batched all 68,022 source meshes through 82 render
groups. The two 1,000-assembly PNG captures have identical SHA-256
`13be74a10c1de5081e1a7889d7a41962b6530e0ab3496eb72f9e461380947da3`.
At this wide camera distance, fog hides fine detail. A close nine-assembly
comparison at the same 1280 × 800 viewport was also byte-identical, with
SHA-256
`e39810fa157ebf5d4044711c1bbe61bf6b697d30b3e03696b8d687a443f51c47`.
Inspection shows the collector, conveyor and press silhouettes, finishes and
shadows intact at that camera. The close view measured 21.957 ms median before
the shared finish and 21.722 ms after it, so the large reduction is specific
to the hundreds of otherwise separate conveyor material draws.
Releasing all 67,689 already-hidden source nodes in a discarded experiment
left the capture byte-identical but measured 59.987 ms median, so retaining
them was not the dominant frame cost. An attempted Forward+ comparison used
software `llvmpipe` Vulkan on this host and was stopped before sampling; it
is not a viable hardware comparison or a passing performance result.

**120 FPS remains unmet.** The shared-finish candidate is about 59 FPS at
the median and about 55 FPS at the 95th-percentile frame interval. The joined
zero-assembly worksite measured 14.460 ms median in the earlier joined run,
already above the 8.333 ms target. The static fixture omits authoritative
machine operation, inventory, motion, UI and controlled character, so it
cannot establish playable 1,000-machine frame rate. Retained logs and images
use the `thousand-` prefix in the local directory above.

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

## One thousand assemblies after the motion-cache join

The relevant main was `930f3109cae68b30137829b725a0df1fd26d1d03`.
The measured fixture script SHA-256 was
`86406756f3d16d8bf875201eb956de5ea1f1605e6b121e300fc6faae2895e4c0`;
the joined `opening.gd` SHA-256 was
`e6f75366820e94ee91ea63fe8101adc78f742b91342011a898dbf8532f11bb6e`.
The same optimized 1,000-assembly case on the joined X11 Compatibility path
measured 17.290 ms median, 18.700 ms p95 and 97 draw calls. Its PNG was
identical to the earlier X11 capture, and the focused batch-motion fixture
passed 17 assertions. A separate Wayland/OpenGL3 run at the same resolution
measured 15.280 ms median and 16.170 ms p95 for 1,000 assemblies, while an
empty-worksite Wayland run measured 11.499 ms median and 12.775 ms p95.
Wayland and X11 PNGs of the 1,000-assembly scene were byte-identical. Each
display-path result is one exclusive run, so the 2 ms difference is not a
repeatability claim. Both remain above the 8.333 ms frame budget.
