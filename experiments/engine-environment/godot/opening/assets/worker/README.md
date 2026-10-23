# Adult worker asset

The complete opening uses **Female_Adult_01** from the
[Microsoft Rocketbox library](https://github.com/microsoft/Microsoft-Rocketbox/tree/0943055db6ec570bcef9f2c8b41c9e5467c808f9/Assets/Avatars/Adults/Female_Adult_01).
The original publisher releases the model and textures under the included
[MIT license](LICENSE.md); keep that notice with redistributed or modified copies.
The pinned source contains the editable FBX and original textures.
[source.json](source.json) records their identities and preparation settings.
Human feedback still determines whether this revisable character meets the
requested appearance and motion quality.

The opening samples `body_field_suit_color.png` for a petrol field jacket and
graphite work trousers. It is an image-generated edit of the included body
atlas. `field_suit.gdshader` uses the original atlas to limit the alternate to
cloth; the original skin, footwear, empty UV margins, head, hair, body normal,
rig and animations remain. The edited atlas is 1,254 pixels square and its UV
islands are not pixel-identical to the original. This material boundary avoids
spilling the generated colors onto skin, while garment detail and fit remain
provisional until a human checks the actual character at ordinary and eye-level
camera distances. The field suit is presentation only.

The converted mesh has 5,438 vertices, 8,732 triangles, three material surfaces
and 80 skin bindings. Color maps are 1,024 pixels square; normal and alpha maps
are 512 pixels square. Conversion preserves the skin and mesh level, removes
unused animation and marker nodes, and assigns materials explicitly. Roughness
and alpha cutout are presentation defaults, not measured properties.

`character_presenter.gd` loads the GLB and mipmapped textures directly without
an editor import cache. Each player has a separate skeleton and shares immutable
geometry and materials. The rig keeps its rotated source parent, fits the
1.8-metre capsule, and composes local bone poses before entering the scene tree.
The visual root follows the confirmed actor exactly; limbs do not replace its
capsule or grant construction reach.

The matching Rocketbox [walk](https://github.com/microsoft/Microsoft-Rocketbox/blob/0943055db6ec570bcef9f2c8b41c9e5467c808f9/Assets/Animations/all_animations_max_motextr_xy/f_walk_neutral.max.fbx)
and [run](https://github.com/microsoft/Microsoft-Rocketbox/blob/0943055db6ec570bcef9f2c8b41c9e5467c808f9/Assets/Animations/all_animations_max_motextr_xy/f_run_neutral.max.fbx)
takes contribute 56 and 34 named-skeleton tracks respectively. Confirmed
horizontal travel advances one walk cycle per 1.30 metres and one run cycle per
2.30 metres. The full walking pose appears near 1.05 metres per second; observed
speed blends walking into running from 1.15 to 2.35 metres per second. A short
visual speed average steadies pose weight when native physics cuts unevenly
between rendered frames. Both clips begin mid-stride: leg channels retain their
absolute source rotations, while walking arm and non-leg torso channels remain
relative to the lowered-arm standing pose.

Walking keeps opposing arm swing with bent elbows and a softer finger curl.
Running retains the captured opposing arm drive, bounded torso sway, a slight
forward pitch and a fuller knee bend. The run clip has no finger tracks, so
grounded fingers retain subtle walk motion and reset untracked joints each
sample. The walking swing calf folds before the reaching boot meets support.
After retargeting, a two-bone visual correction puts each grounded knee ahead
of its hip-to-ankle line while preserving leg lengths, ankle path and foot
facing. This corrects the source calf's occasional backward bend; it does not
by itself establish natural motion from every camera angle.

At walking speed the incoming toe takes support while descending near terrain,
and the outgoing toe lifts through a short overlap. A planted toe holds its
observed world position through stance. At running speed the support
hold is shorter and the toe lifts as the pelvis passes it. These visual
contacts fade through walk-run blends, stops, jumps and landings. On a confirmed
run stop, one low boot plants while the other swings above terrain toward rest;
the planted boot then makes a short settling step. These corrections never
move the actor or produce input. Terrain under a posed toe can differ from the
native support height, especially on slopes.

Confirmed vertical motion switches into distinct takeoff, ascent, descent and
landing poses. A running takeoff leads with one knee, folds both legs near the
apex and reaches down on descent. In a moving landing the left boot starts
reaching before contact, accepts load first, and the opposite arm
counterbalances; the trailing boot joins during recovery. A stationary landing
settles both feet beneath the actor. Torso compression, lead-toe support and
the next stride unfold over several rendered samples. These are presentation
poses inferred from confirmed height and speed, not physical limb contact.
Because the shared projection has no floor-contact flag, the visual landing
may lag a changed support height by one native sample.

`worker_rig_check.gd` checks source bindings, walking and running knee
direction, toe clearance and planted-foot travel, arm carriage, landing and
stop contacts, skinned dimensions, exact actor roots and the absence of input
calls using invented confirmed samples. Passive native Opening screenshots
and traces remain necessary for visual judgement; record their source
revision, view and cadence. Neither those images nor this rig check establishes
human play experience or the quality of every playable view.

The asset has no collision or interaction shape, autonomous animation player,
command producer, material inventory or saved state. Facial animation,
customization, visible carried equipment and full-scene performance remain
separate work.
