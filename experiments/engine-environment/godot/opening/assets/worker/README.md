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
The existing confirmed-distance gait drives legs and arms, settles when movement
stops, and resets on world changes or discontinuous positions. Name labels retain
the local-player indication; skin colors are not tinted to identify players.

The asset has no collision or interaction shape, autonomous animation player,
command producer, material inventory or saved state. Its limbs do not replace
the capsule or grant construction reach. Facial animation, motion-capture clips,
customization, visible carried-item equipment, physical limb contact and rendered
performance remain separate work. Historical fixed source rosters that omit this
folder retain their identified procedural worker.

`worker_rig_check.gd` exercises the actual presentation adapter using invented
confirmed samples. It checks source bindings, materials, skinned dimensions and
walk poses, per-player isolation, projection immutability and the absence of input
calls. It also preserves the original procedural-worker controls. These are
headless resource and binding checks, not human playtesting or appearance approval.
