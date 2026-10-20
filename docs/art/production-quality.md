# Production presentation target

The user’s latest playtest sets **Satisfactory as the minimum graphical quality
benchmark**. The earlier allowance for rough placeholder graphics no longer
defines the working target. Graphics receives substantial development focus now,
so modeling, materials, interaction and sound grow together.

The current basic first shift meets its earlier functional scope. The same human
playtest reports inadequate presentation and a lack of engineering challenge.
Those findings do not erase the valid functional results. The quality work is
`factory-yau.6.45`; its first active asset slice is `factory-yau.6.45.2`.

## Art direction

Build a believable mechanical industrial frontier. Cast frames, machined steel,
painted guards, copper fittings, timber and rubber must have distinct surface
responses. Forms should express assembly and force: supported bearings, fasteners,
separate housings, sensible thicknesses and edges that catch light. Avoid shapes
whose only readable identity comes from floating labels.

Use the [official Satisfactory gallery](https://www.satisfactorygame.com/#media)
as a quality reference for coherent machinery, material response, environmental
composition and readable industrial scale. Create original Factory assets; retain
the mechanical technological identity and the actual physical construction rules.

Judge the normal playable camera as well as close inspection. Detailed surfaces
must remain stable in motion and at distance. Material and power paths need clear
interfaces, purposeful placement previews and feedback that explains accepted
construction. Environmental richness must not hide controls or invent terrain
that the physical actor can walk through.

## First integrated asset slice

- Give machine housings, rails, feet and foundation panels closed machined-edge
  geometry with actual normals, UVs and tangents inside their original envelopes.
- Replace per-piece flat materials with shared, lit surface finishes. Use bounded
  seamless roughness and normal detail with mipmaps and distinguish paint from
  exposed steel. Keep material and mesh reuse explicit.
- Remove the debug checkerboard. Preserve construction seams and replace the
  alternating squares with a coherent foundation surface and subtle panel wear.
- Keep the reviewed projected-axis machine hubs, wheel pedestal, native phase
  boundary, actor kit, placement cue and recovery presentation intact.

This is the asset foundation, not completion of the quality target. Further work
must address authored machine detail, terrain and environmental composition,
character quality, readable confirmed motion and the complete lighting result.
The existing flat terrain and simple stream remain unfinished. Headless mesh or
material checks cannot establish visual quality or Satisfactory parity.

## Sound and interaction

The user specifically calls out the sound of a belt snapping into place. Follow
the graphics foundation with restrained construction sounds and feedback tied to
confirmed accepted actions. A refused or uncertain request must not play a success
sound. Duplicate replies, reconnect and load must not replay construction audio.
Mechanical ambience should follow observed operating state and have a deliberate
mix; it must not suggest a rate, motion phase or material transfer absent from the
authority. No audio result is claimed by the first material slice.

## Engine and evidence

Godot is an accepted development tool, not an obligation to accept lower quality.
`factory-yau.6.45.3` compares the target with the actual renderer/asset path and
explores alternatives if Godot cannot satisfy it. Distinguish shortcomings in our
assets or current Compatibility settings from an engine limitation. Keep the
native simulation independent so an engine change remains practical.

The initial source assessment identifies three paths. These are documented
capabilities and integration considerations, not a rendered comparison:

| Path | Quality capability and remaining work |
| --- | --- |
| Current Godot Compatibility | The present project chooses this backend. Its normal-mapped, lit material path can consume the new asset foundation; the present simple scene does not establish Godot's ceiling. |
| Godot Forward+ | The [renderer comparison](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) documents additional illumination and volumetric features. Assess representative assets and the actual target hardware before selecting this path; changing a renderer does not author the missing content. |
| Unreal | Epic documents [Lumen lighting and reflections](https://dev.epicgames.com/documentation/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine) and a [C++ integration path](https://dev.epicgames.com/documentation/unreal-engine/programming-with-cpp-in-unreal-engine). It is a concrete alternative if the quality or practical production path fails in Godot. The native authority can remain, while scene, physical-body, input, asset and tooling adapters need replacement. No Unreal implementation, download or performance claim is made here. |

No engine ceiling has been demonstrated. Continue the asset work while assessing
the renderer, and make an engine change if the evidence supports it rather than
lowering the user's quality target.

Use relevant automated checks and one independent reviewer for code landing.
Human assessment establishes the rendered and audible result; it is not another
code-landing approval. Agent desktop testing remains disabled. Preserve existing
images and outcomes without replay, and state unavailable visual evidence plainly.

The authored material resources use Godot's
[NoiseTexture2D](https://docs.godotengine.org/en/stable/classes/class_noisetexture2d.html)
and [standard material](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)
paths. Their original parameters are constructed in the already captured opening
script, so both fixed-roster launchers receive the same surfaces without new
resource files or launcher changes.
