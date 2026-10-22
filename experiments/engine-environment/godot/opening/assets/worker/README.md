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
keeps 34 named-skeleton rotation and translation tracks. The matching [neutral female walk clip](https://github.com/microsoft/Microsoft-Rocketbox/blob/0943055db6ec570bcef9f2c8b41c9e5467c808f9/Assets/Animations/all_animations_max_motextr_xy/f_walk_neutral.max.fbx)
contributes 56 named-skeleton tracks. One walk cycle advances per 1.30 metres
and one run cycle per 2.30 metres of confirmed horizontal travel. The run
distance matches the captured low-toe travel during support; the previous
1.65-metre timing moved the low toes backward against confirmed travel. The
walk reaches its full captured stride around 1.05 metres per second so slow
confirmed movement does not advance a full cycle with only a partial leg pose.
Observed speed blends the walk into the run from 1.15 to 2.35 metres per
second. A short visual speed average prevents uneven native physics cuts per
rendered frame from pulsing stride strength at a constant walking command;
confirmed distance still advances the gait phase and the pose settles toward
rest when travel stops. Both imported
clips begin in a stride pose. Their leg rotations retain those absolute source
poses in the matching named rig; subtracting the first frame removed the walk's left
support step. Walk arm channels and non-leg torso channels remain relative to
the first clip frame and the worker's lowered-arm standing pose. The walking
shoulder swing is shortened and both forearms retain a modest bend, so the
hands move opposite each other without the clip's long, nearly locked reach.
This adjustment fades through the walk-to-run blend. At run speed,
the source upper-arm pose retains its absolute stride position; the forearms
blend that pose toward a less raised elbow angle. A small forward spine pitch
develops with the run blend, while the hands continue to swing opposite each
other through the captured cycle. The run take has no finger tracks, so it
retains the walk take's subtle finger motion and a light, mostly proximal curl
instead of exposing straight bind-pose fingers. The curl is softer during
walking and releases during flight; untracked joints reset from the imported
rest pose on every sample. The source calf motion still bends
behind the leg at some phases after retargeting. A presentation-only two-bone correction
places each bent knee ahead of its hip-to-ankle line while retaining the
captured ankle path and foot orientation. The forward walking swing also folds
the airborne calf before the boot reaches ahead, then releases that extra bend
before stance. This preserves the captured swing path until support.
During a steady walk, the first near-ground boot holds its observed world toe
position briefly, then releases through toe-off. The correction fades as the
walk becomes a run and does not move the confirmed actor root. The fuller
running leg pose lowers
its cosmetic visual root by 4.7 centimetres at full run weight to meet the
unchanged support plane. The forearms retain extra flex and
the captured torso sway is bounded after retargeting. The clip's vertical root
variation is cosmetic, and its horizontal root travel does not move the physical
or visual actor root. On a confirmed stop, the current stride pose holds for
about two 60 Hz samples before settling toward rest, so a trailing boot does
not stay suspended through the older six-sample pause. The first low boot
plants at its observed world position during this settle, then lifts and takes
a short step into the neutral stance. This avoids dragging a low toe toward
rest while the confirmed actor root is stationary. The visual contact uses the
confirmed actor's support height; uneven nearby terrain can still differ.
Airborne and landing poses retain their longer transition. The original FBX remains available at
the pinned source revision.

Confirmed rising and falling samples switch the visual skeleton into distinct
takeoff, ascent, descent and compressed landing poses. The running takeoff lifts
one knee while the trailing leg extends; the legs fold near the apex, reach
down on descent and compress at impact. The arms drive asymmetrically on takeoff
and open for balance in flight. During the final metre of a moving descent,
the leading leg begins reaching toward its contact pose in proportion to
confirmed horizontal speed. This spreads the forward boot motion across
descent and first contact instead of snapping the full step into one frame.
The arm opposite that boot reaches modestly ahead and the upper torso leans
slightly forward during the final approach, before the foot takes load. This
counterbalance leaves earlier flight and an in-place jump unchanged.
When recent confirmed horizontal travel reaches contact, the left boot takes
the first load while the right
leg trails. The torso leans over that support, both knees absorb the fall, and
the trailing boot joins as the body recovers over 0.32 seconds. A stationary
jump settles both boots under the body without inventing a forward recovery
step. At moving contact the arm opposite the leading boot reaches farther
forward for balance; the amount follows confirmed landing speed, so a
stationary landing remains symmetric. The airborne pose fades through this recovery
instead of disappearing in four frames. The lower of the two posed toes anchors
the visual body to the confirmed support height during landing; the physical
actor root stays unchanged. On a moving landing, the leading boot also retains
its first supported world position during the initial load. A two-bone visual
leg correction keeps the knee forward, preserves leg lengths and foot facing,
and releases the boot as the step rolls into walking or running. The running
release starts earlier because the actor travels farther during the same
contact interval. As the opposite boot accepts the running recovery, the lead
ankle lifts slightly before following the next stride, avoiding a low backward
drag. This is a presentation anchor, not physical foot contact;
the support height still comes from the confirmed actor and can differ from
the rendered terrain on a slope. These poses
evolve with observed vertical speed rather than holding one shape throughout
flight. A confirmed teleport, world
change or unready actor discards its motion history. Because the shared
projection has no floor-contact flag, landing is inferred from confirmed height
changes and can lag a new support height by one sample. This remains a
presentation choice, not an actor simulation or proof of physical foot contact.
Name labels retain the local-player
indication; skin colors are not tinted to identify players.

The asset has no collision or interaction shape, autonomous animation player,
command producer, material inventory or saved state. Its limbs do not replace
the capsule or grant construction reach. Facial animation, captured jump and
landing clips, customization, visible carried-item equipment, physical limb
contact and full-scene performance remain separate work. Historical fixed source
rosters that omit this folder retain their identified procedural worker.

`worker_rig_check.gd` exercises the actual presentation adapter using invented
confirmed samples. It checks source bindings, captured walk and run poses,
forward knee bending, mid-swing knee flex, planted toe height and horizontal
stance travel at dense and native snapshot cadences,
opposing running hands, relaxed walking elbows and bounded lateral carriage,
loose grounded fingers that release during flight,
opposite-arm balance at moving contact,
early walking and running landing boot placement, running toe-off clearance,
exact actor roots and no input,
skinned dimensions,
ascent, descent, leading-toe continuity, staged landing contact and skinned support height, per-player
isolation, projection
immutability and the absence of input calls. It also preserves the original
procedural-worker controls. A passively rendered contact sheet in the retained
local evidence records specific visible findings; neither the fixture nor that
sheet is human playtesting or final appearance approval.
