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

## Next reversible trial

Try one **core-asset-only MakeHuman/MPFB adult** outside the game repository.
Use an adult body, a plainly licensed hair and work-clothing set, and an
editable local source file. Export a skinned glTF with the material maps and
one neutral walk. Import it into a scratch Godot 4.7.2 project and render it
beside the two existing adults at identical normal and near camera positions,
light and output size. Keep the result external until the source licenses and
pixels justify adoption. This trial does not require a new character controller,
native rule or public asset commit.

The trial should record source hashes and licenses; body and head mesh counts;
bone names, parent order and rest transforms; animation track and bind
coverage; textures, alpha and normal orientation; imported resource size; and
observed draw calls or frame cost in the same passive fixture. Reject it if
the hair, skin or clothing looks less convincing than the shipped adults, if
the footwear cannot meet the current actor ground at idle and walk, or if the
source cannot be reduced to the project's artifact budget without obvious
visual loss. A technically successful import is not a visual acceptance.

If that local trial cannot beat the current models, the next source-quality
step is a **properly licensed optimized MetaHuman export**, with the original
head, body, textures, hair and outfit accounted for before conversion. The
export and legal route must be established before putting any third-party raw
asset on public main. Do not treat the Unreal optimization figures as a Godot
performance prediction. Compare passive normal and near renders and ask for
human appearance feedback before choosing a permanent character direction.

This research did not download a new character, install software, launch a
game, run Godot, or test human preference. It recommends a falsifiable art
trial while the existing two actors and their independent review remain in
place.
