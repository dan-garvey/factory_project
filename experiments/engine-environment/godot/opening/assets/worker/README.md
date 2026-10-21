# Adult worker asset

The current complete opening uses **Female_Adult_01** from the
[Microsoft Rocketbox library](https://github.com/microsoft/Microsoft-Rocketbox/tree/0943055db6ec570bcef9f2c8b41c9e5467c808f9/Assets/Avatars/Adults/Female_Adult_01).
Its adult proportions, textured face, ponytail, fitted shirt, jeans and boots
provide a revisable realistic character direction. Human feedback must determine
whether its appearance meets the requested quality and attractiveness. Installing
a rig does not establish either outcome.

The original publisher releases the model and textures under the included
[MIT license](LICENSE.md). Keep that notice with redistributed or modified
copies. The pinned source contains the editable FBX and original textures;
[source.json](source.json) records their identities and the preparation settings.
The mesh remains editable through ordinary glTF tools as well.

The representative mesh has 5,438 render vertices, 8,732 triangles, three material
surfaces and 80 skin bindings. Color maps are 1,024 pixels square; normalized
body and face normal maps and the hair/lash alpha map are 512 pixels square.
The conversion preserves the source skin and mesh level, strips the unused
animation player and footsteps marker, and assigns materials explicitly.
Original specular maps are not treated as measured roughness. The chosen uniform
roughness values and alpha cutout threshold remain presentation defaults.

`character_presenter.gd` reads the GLB directly and creates mipmapped textures
from captured image bytes. Cold native captures do not depend on an editor
import cache. The rig retains its rotated source parent; fitting and bone-axis
conversion include that parent transform. Local pose composition avoids relying
on a skeleton's global-pose cache before it enters the scene tree.

Each player has a separate skeleton and shares immutable geometry and materials.
The standing skinned mesh is uniformly fitted to the existing 1.8-metre capsule
and its foot plane. The visual root remains exactly at the confirmed actor pose.
The [neutral female run clip](https://github.com/microsoft/Microsoft-Rocketbox/blob/0943055db6ec570bcef9f2c8b41c9e5467c808f9/Assets/Animations/all_animations_max_motextr_xy/f_run_neutral.max.fbx)
comes from the same Rocketbox library. Its compact native Godot animation resource
keeps 34 named-skeleton rotation and translation tracks. At runtime, each track
is applied relative to the clip's first pose and the worker's lowered-arm standing
pose. The matching [neutral female walk clip](https://github.com/microsoft/Microsoft-Rocketbox/blob/0943055db6ec570bcef9f2c8b41c9e5467c808f9/Assets/Animations/all_animations_max_motextr_xy/f_walk_neutral.max.fbx)
contributes 56 named-skeleton tracks. One walk cycle advances per 1.30 metres
and one run cycle per 1.65 metres of confirmed horizontal travel. Observed
speed blends the walk into the run from 1.15 to 2.35 metres per second; the
pose then settles toward rest when travel stops. The source calf motion bends
behind the leg after retargeting. A presentation-only two-bone correction
places each bent knee ahead of its hip-to-ankle line while retaining the
captured ankle path and foot orientation. The forearms retain extra flex and
the captured torso sway is bounded after retargeting. The clip's vertical root
variation is cosmetic, and its horizontal root travel does not move the physical
or visual actor root. The original FBX remains available at the pinned source
revision.

Confirmed rising and falling samples switch the visual skeleton into distinct
takeoff, ascent, descent and compressed landing poses. The running takeoff lifts
one knee while the trailing leg extends; the legs fold near the apex, reach
down on descent and compress at impact. The arms drive asymmetrically on takeoff
and open for balance in flight. Landing compression peaks after the first
support sample and settles over 0.24 seconds. These poses
evolve with observed vertical speed rather than holding one shape throughout
flight. A confirmed teleport, world
change or unready actor discards its motion history. Because the shared
projection has no floor-contact flag, landing is inferred from confirmed height
changes and can lag a new support height by one sample. This remains a
presentation choice, not an actor
simulation or proof of exact foot contact. Name labels retain the local-player
indication; skin colors are not tinted to identify players.

The asset has no collision or interaction shape, autonomous animation player,
command producer, material inventory or saved state. Its limbs do not replace
the capsule or grant construction reach. Facial animation, captured jump and
landing clips, customization, visible carried-item equipment, physical limb
contact and full-scene performance remain separate work. Historical fixed source
rosters that omit this folder retain their identified procedural worker.

`worker_rig_check.gd` exercises the actual presentation adapter using invented
confirmed samples. It checks source bindings, captured walk and run poses,
forward knee bending, skinned dimensions,
ascent, descent and landing transitions, per-player isolation, projection
immutability and the absence of input calls. It also preserves the original
procedural-worker controls. A passively rendered contact sheet in the retained
local evidence records specific visible findings; neither the fixture nor that
sheet is human playtesting or final appearance approval.
