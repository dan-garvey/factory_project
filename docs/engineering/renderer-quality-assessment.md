# Renderer and production-quality assessment

Assessed on 2026-10-20 against main `685de50`. This is a source and capability
assessment, with existing observations reused. It includes no new engine run,
desktop operation, hardware probe or performance measurement.

Continue the coherent asset foundation and prepare a Godot Forward+ desktop
presentation path. The current scene has substantial content and configuration
gaps before an engine ceiling can explain its appearance. Godot's documented
features make that next increment viable; they do not establish Satisfactory
quality. Fully editable indirect lighting and large detailed factories remain
concrete risks. Unreal is a practical comparison candidate for those risks,
with the bounded migration described below. This recommendation is reversible
and does not delay asset work or select the production engine.

## What the current opening actually uses

[project.godot](../../experiments/engine-environment/godot/project.godot)
explicitly selects `gl_compatibility`.
[opening.gd](../../experiments/engine-environment/godot/opening/opening.gd)
builds the worksite from a plane, 49 separate floor tiles, primitive machine
parts, a procedural sky, a shadowed sun and an unshadowed fill. Its material
helpers allocate a mesh and a plain material per part. The tracked opening has
no imported glTF model or bitmap material texture set at this revision.

The [worker and press previews](../../experiments/engine-environment/godot/opening/assets/README.md)
are original primitive-based assets. Their guide distinguishes previews from
the geometry actually constructed by the view. Existing silhouettes, metal and
rubber finishes, and routing marks are useful starting work. Bevels, surface
variation, coherent terrain dressing and polished character animation still
need authored content. Calling every visible gap a renderer limitation would
misdiagnose this source.

The [historical environment trial](engine-environment.md) records a WSLg
OpenGL/Compatibility observation. An existing Windows capture from `c239314`
shows the older Help scene, tiled floor and primitive assemblies; it predates
this assessment's source and the current asset work. The latest human rejection
of visual quality did not identify a build. Neither observation establishes how
the new assets look or whether the target has been reached. Headless mesh and
native gameplay results establish their respective contracts, not visual parity.

## Target, capability and owning gap

| Desired result | Source gap and viable route | Classification |
| --- | --- | --- |
| Designed industrial machinery at normal play distance | Author readable frames, cast or machined edges, supports, joints and material transitions. Reserve small fasteners for details that survive the normal camera distance. | Content and art direction. |
| Convincing steel, paint, rubber and terrain | Replace uniform finishes with shared physically based materials, consistent texture scale, roughness variation and authored normal/occlusion detail. | Content and material setup. |
| Grounded, readable lighting | Tune exposure, sky reflections, direct shadows and local occlusion around the actual worksite. Keep shaft direction, material ports and recovery cues readable. | Lighting setup, with backend-specific options. |
| Stable fine machinery in motion | Compare edge smoothing on thin shafts and teeth when the scene is assessed by a human; temporal filtering may obscure the very motion being taught. | Backend configuration and later visual evidence. |
| Rich atmosphere and reflections | Forward+ exposes volumetric fog and screen-space reflections absent from Compatibility. Use these where they serve the scene. | Current backend limit. |
| Lighting that follows arbitrary construction | Choose an explicit indirect-lighting strategy; the static and editable cases below have different limitations. | Engine technique and scene cost. |
| Tactile construction sound | Trigger presentation from confirmed accepted actions, preserving pending/refused/replayed outcome semantics. | Audio assets and event integration; changing renderer does not supply them. |

Godot's standard materials provide roughness, metallic, normal and baked
occlusion inputs. A normal map changes shading rather than silhouette, so it
cannot replace modeled edge shape. Godot expects OpenGL-style normal maps;
DirectX-style maps need their green channel corrected. These are an available
asset workflow, not evidence that our existing materials use it.
[Material documentation](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html).

The Godot 4.7 renderer matrix lists ambient occlusion and glow for Compatibility;
their absence from our configured environment is not an engine-wide prohibition.
Forward+ additionally supplies temporal antialiasing, higher-precision color,
decals and the advanced lighting options above. On Windows, its documented
drivers include Vulkan and Direct3D 12. Driver/backend fallback can change the
appearance, so retain the actual selected renderer when a human evaluates a
build. The earlier WSLg result does not certify this Windows path.
[Renderer comparison and fallback](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html).

For reusable authored assets, glTF 2.0 is Godot's recommended import format.
Explicit exported `.glb` files avoid requiring Blender on every consumer machine;
direct `.blend` import invokes Blender. Preserve source provenance and original
editable assets. Keep imported render meshes separate from existing collision,
pick identifiers and authoritative construction anchors.
[Import formats](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html).

## Editable lighting and practical costs

SDFGI, Godot's signed-distance-field global illumination, supports dynamic lights
but not dynamic occluders or emissive surfaces. Nearby geometry changes can leave
incorrect indirect light until its spatial data refreshes. It is therefore an
unsuitable default promise for freely placed, removed or moving factory parts.
Its demanding cost and convergence artifacts also require an actual scene
comparison before choosing it.
[SDFGI limitations](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html).

VoxelGI offers a bounded alternative for a small worksite: dynamic meshes receive
and contribute indirect light, at a substantial cost. Its volume extent,
resolution, light leaks and static-data rebaking constrain expansion. This is a
candidate for an editable worksite comparison, not a demonstrated solution for
an entire factory world.
[VoxelGI behavior](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_voxel_gi.html).
Baked lightmaps suit immutable scenery; their static result cannot follow player
construction. They also require a separate reflection solution.
[Lightmap behavior](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html).

Start with authored geometry, shared surfaces, a controlled sky/sun setup and
dynamic direct shadows. Add an indirect technique only with a declared treatment
of editable geometry. This lets material and silhouette work advance while
keeping the unresolved lighting behavior visible.

Practical costs already visible in source include per-part mesh/material
allocation, separate floor instances and revision-driven item reconstruction.
Retain geometry when its confirmed inputs are unchanged. Reuse mesh/material
resources and consider combined static surfaces or instancing for repeated
noninteractive details. Preserve independent pick and collision proxies.
Godot documents Forward+ automatic instancing for shared opaque meshes/materials,
manual MultiMesh, distance-dependent detail and the costs of transparency and
dynamic lighting. These are available tools, not measurements of this scene.
[Performance guidance](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html).

A 2048-by-2048 RGBA8 texture with a full mip chain occupies approximately
21.3 MiB before compression; three such maps use about 64 MiB. This is arithmetic,
not an observed engine allocation. Shared trim/material sets can avoid paying
that cost for every individual part. Triangle, draw-call, texture, import-cache
and GPU-time budgets should follow a representative scene and actual hardware;
the local admission floors are not game performance targets.

## Unreal comparison and bounded migration

Unreal's Lumen supplies dynamic indirect lighting and reflections through screen
traces plus software or hardware tracing. Its surface representation, update
latency, thin geometry and tracing cost still need evaluation for dense shafts,
small teeth and rebuilding machinery.
[Lumen technical details](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-technical-details-in-unreal-engine).
Nanite supplies streamed geometry detail and automatic detail selection, while
material complexity, instance counts and output resolution retain practical
costs. It does not author machinery or solve the game's state and input boundary.
[Nanite documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/nanite-virtualized-geometry-in-unreal-engine).
Epic recommends 32 GB system memory and at least 8 GB graphics memory for
development; advanced features have additional requirements. Those recommendations
do not establish the availability, installation footprint or runtime performance
of an Unreal setup on this machine.
[Hardware requirements](https://dev.epicgames.com/documentation/en-us/unreal-engine/hardware-and-software-specifications-for-unreal-engine).

If editable lighting or representative scene costs defeat the Godot path, compare
one worksite rather than restarting the game:

1. Reuse the same authored collector, belt, press, wheel and transmission assets,
   camera distances, material intent and lighting conditions.
2. Link the existing Bazel-built C++ World through a small Unreal host module.
   Keep command validation, finite custody, retry history and logical checkpoint
   validation in that same authority.
3. Implement engine-specific actor observation, picking, UI and presentation
   adapters. The current Godot Variant conversion, ActorWorld physics, Session
   facade and Store envelope are not automatically portable. Preserve their
   contracts explicitly; native logical checkpoints alone do not prove old binary
   saves can be opened.
4. Compare appearance, construction/removal lighting changes, thin-part motion,
   incremental asset iteration and measured CPU/GPU/memory costs on the same
   hardware. Establish actual package/cache costs before installing an engine.

This is a bounded alternative, not a launched comparison or an approval gate.
Continue the active production asset slice now. Its next human assessment should
use the actual playable opening, identify the build and judge normal-distance
machinery, materials, surroundings and interaction feedback. A feature checklist,
beauty render or passing automated fixture cannot establish the requested quality.
