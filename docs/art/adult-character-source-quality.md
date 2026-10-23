# Adult character source quality

Research date: 2026-10-23. Source comparison for `factory-yau.6.45.22.65`.
The source baseline is main `53066101a0c40aa730265e9e9ee86f001c30fa28`, which includes the
second adult worker. This note selects a **visual trial**, not a replacement
character or a new character-generation feature.

## The quality gap

The opening now shows two distinct adults. Their [first](../../experiments/engine-environment/godot/opening/assets/worker/README.md)
and [second](../../experiments/engine-environment/godot/opening/assets/worker-second/README.md)
Rocketbox sources are licensed, rigged, small enough for the current project,
and present through the same physical-actor boundary. Passive normal and near
views distinguish the faces, bodies and clothing. That does not establish the
requested attractive, realistic appearance. At close range, their face, hair,
garment form and material response still need human judgment against the
production target. The original art source was built for adaptable real-time
avatars, with four mesh detail levels and reusable animation, not specifically
for this game's close-up hero character.

The bottleneck is more than polygon count. A new source has to bring a coherent
head and body, suitable hair and field clothing, skin and fabric maps, a rig
whose rest pose can be mapped to the confirmed actor, and a defensible runtime
cost. Mixing a new face texture with the current hair cards already produced
visible card and ear artifacts in a rejected scratch study. A richer material
alone cannot correct a weak silhouette or badly fitting garment. These are
observations and adaptation risks, not a human attractiveness verdict.

## Official source comparison

| Source | Rights and source availability | Route into the current Godot view | Quality and cost risk |
| --- | --- | --- | --- |
| [Microsoft Rocketbox](https://github.com/microsoft/Microsoft-Rocketbox/tree/0943055db6ec570bcef9f2c8b41c9e5467c808f9) | The pinned collection uses [MIT](https://github.com/microsoft/Microsoft-Rocketbox/blob/0943055db6ec570bcef9f2c8b41c9e5467c808f9/LICENSE.md), including the notice obligation. FBX models, source textures, several detail levels and animation are available. Two prepared adults are already in this public repository with their source pins and notice. | The current Godot 4.7.2 route has proven separate skinned models, named bone compatibility, separate clips, materials, equipment and first-person hands. Same bone names did not imply identical rest poses, so the second worker retained its own motion clips. | Lowest integration risk and a small prepared package. The passive near view still needs a quality decision. More texture swapping will not create a new face shape, garment cut or convincing hair. |
| [MakeHuman and MPFB](https://github.com/makehumancommunity/makehuman/blob/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/LICENSE.md) | MakeHuman's bundled base mesh, modifiers, textures, clothes and poses are CC0; exported character data is usable in a commercial game. Its program code has a different AGPL license, and downloaded third-party clothing or hair must be checked individually. Local model files preserve editable body choices. | MakeHuman supports mesh and rig export. The practical proposed route is a locally created adult with explicitly licensed hair and work clothes, then a Blender glTF export and Godot import. Bone hierarchy, skin weights, axes, tangents, opacity and material maps would need measured checks. No such model was exported in this study. | Flexible body and wardrobe construction without buying an asset. Base output is **not** evidence of the requested close-up realism. [MPFB supports skin normal-map slots](https://github.com/makehumancommunity/mpfb2/blob/master/docs/ui/create_assets/makeskin.md), but the selected skin detail and hair still need direct inspection. |
| [Epic MetaHuman](https://www.metahuman.com/license?lang=en-US) | Epic currently says MetaHumans can be used with any engine under the applicable Unreal Engine license. This study has not established permission to publish a raw exported MetaHuman in this repository, and no Epic account, character or toolchain was used. | The [Export Tool](https://dev.epicgames.com/documentation/metahuman/metahuman-creator-export-tool-in-unreal-engine) packages head/body DNA and textures for digital-content tools such as Maya and Houdini; it is not a Godot-ready scene. The [assembler](https://dev.epicgames.com/documentation/en-us/metahuman/character-assembler) can combine head and body, but its described import excludes clothing and hair. A later glTF or FBX bridge would need tested skin, shader, hair, animation and facial-rig reductions. | Strong high-fidelity reference with several detail levels. Epic reports an average 1–2 GB cinematic assembly versus under 100 MB for its optimized assembly; those are **Unreal assembly sizes**, not measured Godot costs. The production face and groom may be difficult to preserve after conversion. |
| [Reallusion Character Creator](https://www.reallusion.com/Content/EULA/AP/EULA_TWAP.htm) | The current software agreement allows appropriately licensed model and animation outputs inside games, while content rights and base-model restrictions remain separate. It is a commercial tool and no software or content license was acquired here. Raw public-repository redistribution is not established. | It provides an external character-authoring/export route, but no Character Creator file, rig or Godot import was tested. | A possible purchased pipeline, not a near-term dependency. Its specific garment, hair, license and cost would have to be selected before a fair visual comparison. |

The [Godot 4.7 import controls](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html)
can retain named skins and skeletal animation, generate or use tangents, adjust
textures and generate mesh detail levels. They do not automatically reproduce
an external skin shader, groom, facial RigLogic, cloth simulation or motion
retarget. The current native World still owns actor position, collision,
identity, input and proximity; the imported character may consume those facts
but may not replace them.

## Measured scratch comparisons

The proposed core-only trial is complete. Blender 4.5.15 and MPFB 2.0.18
exported a rigged adult using the officially listed CC0 system pack. Godot
4.7.2 imported the 22.5 MB glTF package without an import error. Its mesh has
38,024 triangles, 53 joints and no animation clips. The same passive studio
rendered this adult and the published P and Q workers at matched camera
positions, light and output size. The model has a casual logo shirt, bare feet
and an unposed rig; its close appearance did not visibly exceed the two
prepared adults. The comparison is recorded in the external
`character-render-trial-20261023/assessment.json` family. This rejects the
**core sample as an immediate replacement**, not the MakeHuman authoring system
as a whole.

A second scratch export used individually attributed hair, jacket, jeans and
boots from the official [asset-pack catalogue](https://static.makehumancommunity.org/assets/assetpacks/index.html).
The selected works by Elvaerwyn, punkduck and Mindfront are listed as CC-BY;
none entered the public game repository. The outfit is more coherent than the
core sample, but the matched close view shows gaps at the sleeves, weak face
and hair material response, and no posed or animated motion. Its unoptimized
glTF is 31.9 MB with 166,116 triangles and 53 joints. Blender reported texture
sampler and four-joint-influence reduction warnings. The selected asset names,
creators, pack hashes, images and limits are retained in the external
`character-render-trial-20261023/attributed-assessment.json` family. This
specific assembly is also **rejected as a game replacement**.

The first full-environment scratch comparison produced no image after more
than two minutes of software rendering and was stopped with its failure and
cleanup preserved. The completed comparisons are isolated passive studio
renders; they do not measure full-scene performance, animation quality or
human attractiveness. Neither export changed the native actor, game assets
or input path.

## Next source requirement

Seek a coherent adult source with a modeled face, hair, fitted field clothing
and footwear, an editable rig and named material maps. Before integration,
measure rest-pose and animation compatibility with the physical actor, correct
garment clipping and material import, and reduce the selected runtime meshes
and textures against the current project capture budget. Compare normal and
near views with the published workers under identical lighting; keep every
source license and attribution explicit. A conditional optimized MetaHuman
export is still one possible route if its acquisition, outfit, hair, Godot
conversion and public redistribution terms can be established. Human
appearance feedback remains necessary before choosing the permanent art
direction.
