# Opening presentation assets

The [production presentation target](../../../../../docs/art/production-quality.md)
now sets Satisfactory as the minimum graphical benchmark. The existing primitive
silhouettes do not satisfy that target. The first integrated asset foundation
adds closed machined edges, shared lit surface finishes and coherent foundation
panels; rendered quality remains unassessed and the broader task remains open.

The `ProductionVisuals` class in the already captured `opening.gd` owns reusable
chamfered box meshes and creates the original procedural surface resources.
One shared height source supplies subtle roughness and normal detail. Textures
are seamless and mipmapped. Painted housings use low metallic response while
exposed bearings retain their steel finish. Shapes stay within the existing
envelope; no visual mesh is a physics or construction authority.

Shared revolved profiles supply continuous wheel rims, bevelled washers and
bearing collars. Fitted hex fasteners, service covers, cutter flutes and press
joints express how the existing machines are assembled. These details stay
inside the conservative machine envelope and retain the same native spindle
axes. The geometry is authored presentation, not tooth-contact, drive, torque or
angular-phase authority. The isolated detail fixture checks closed profiles,
usable surface attributes, actual machine assembly and unchanged collision
separation; it cannot establish the visible quality at normal play distance.
The project selects four-sample 3D multisample antialiasing for mesh edges. This
is a revisable rendering default, not a measured performance result; it does not
remove normal-map or specular aliasing. The backend remains Compatibility.

These original project scene assets prepare the visual work in
`factory-yau.6.45`. The character presenter constructs the playable worker from
built-in meshes in its existing script. The scenes here are optional previews;
neither public launcher needs to capture them to display the worker.

`worker.tscn` retains an earlier static clothing and equipment preview. The actual
captured character presenter now constructs a rounded torso, fitted harness and
reflective bands, articulated sleeves/trousers, boots, helmet, visor and tool pack.
Its cached meshes and fabric materials add no resource file dependency. Facing
and cosmetic stride use only confirmed body displacement; held input alone cannot
advance them. Stops settle to neutral, while world changes and discontinuous poses
reset the disposable animation state. The visible root stays at the original
projected actor-body origin. No visual limb changes input, physical pose, collision,
construction reach or saved state. The native capsule remains the collision proxy;
precise limb contact and human-visible animation quality are not established.

`press.tscn` previews a cast-frame press with separate guides, a tool head, anvil,
output tray, feet and visible fasteners. The playable view constructs the frame,
guides, anvil, head and tray directly in `opening.gd`; it does not load this optional
scene. The outlet plate now sits on that tray within the original conservative
machine envelope. The ram is stationary visual geometry; later motion must follow
the confirmed work phase. The drive stub is a visible interface, not a cogwheel
or evidence of mechanical engagement.

The same existing view script builds an open collector stock bed, supported
conveyor with contrasting cleats, and waterwheel with an open rim, spokes,
paddles and axle bearings. Shared frame/steel/copper finishes keep the silhouettes
coherent. The old decorative wheel rotation still follows the confirmed powered
flag. No rendered mesh supplies power, contact, placement, collision or reach.
Pick bodies, labels, interaction anchors and gameplay state are unchanged.

For the native scene profile, machine spindles, waterwheel axle and bearings
follow each entity's projected X, Y or Z axis through the confirmed hub height.
Older native projections without an axis retain X. The wheel is scaled to keep
its rim above the ground; a Y-axis wheel has a horizontal rotor on a pedestal,
and vertical machine stubs are shorter to fit the unchanged machine envelope.
Historical scripted views keep their original decorative stubs and wheel
dimensions. The native projection publishes signed rotation rates, not saved or
synchronized rotational phase. The wheel and drivetrain illustrate confirmed
rates with local cosmetic angles; these freeze when motion is unknown or stalled,
or the view is in Help, unready or disconnected. This view-only animation does
not advance production or establish tooth-contact phase. It changes no power
rule, contact, shaft geometry or collision envelope.

Confirmed material links have static arrowheads and endpoints aligned with their
actual ordered grid direction, including routes along either axis. These indicate
the existing link direction, not simulated item motion or a pending command.
Power-link drawing remains unchanged. The separate `material_route_test.gd`
checks both directions on both axes, geometric arrow direction and projection
immutability; it can also run against the preserved predecessor as a negative
regression witness.

The materials and primitive meshes are authored here using built-in Godot
resources. No external artwork, model download or new runtime dependency is
included. The palette and geometry remain revisable until normal-distance
in-game evidence and user visual feedback support them.

Construction feedback uses original short PCM sounds synthesized in the captured
opening script: a belt latch, heavier machine assembly, coupling and release.
Only the local caller's fresh accepted decision can play a cue. Shared requests
wait for both the matching decision and confirmed snapshot; refused, pending,
duplicate, stale-world and unrelated actions stay silent. Refresh and reopening
do not synthesize construction events. These are local nonspatial acknowledgements,
not machinery ambience or a simulation of material speed. The isolated fixture
retains WAV previews and checks event guards and digital headroom; the quality
and balance of the audible result still need human listening.

The physical worksite creates an original HDR panorama with atmospheric colors,
distant silhouettes and a sun aligned to the key light. The silhouettes are sky
detail, not solid scenery or an implied traversable mountain. A restrained cool
fill supports shadowed faces without another shadow map, and distance haze starts
beyond the normal worksite. Ground color and normal detail, a reflective ripple
surface in the existing stream footprint, and low noncolliding foliage outside
the pad replace the bare surroundings. Ground height, grid, construction anchors
and physical collision remain unchanged. The explicit legacy fixture retains its
earlier sky and stream. All resources are constructed inside the already captured
opening script, with no external sky or launcher file dependency. The isolated
environment check validates assembly and resource/spatial contracts; it does not
establish the rendered balance, reflection quality or Satisfactory-level result.

The fixed-roster launchers already include `character_presenter.gd` and
`opening.gd`, so the worker and machined surfaces have no new file dependencies.
Complete-project native capture also
includes these previews. No Python launcher changes are needed. Rendered quality,
ordinary interaction/collision correspondence and user feedback remain unverified
until exercised in the actual opening.

`machine_visual_test.gd` checks mesh bounds against the existing machine envelope,
the unchanged pick contract and projection immutability. It samples the wheel at
24 orientations and uses an invented read-only fixture without game stepping or
desktop access. These automated checks cannot establish rendered appearance or
human understanding.

Rendered lighting, composition and human visual feedback remain unfinished. This
increment does not complete the visual task, introduce geometric cogwheel
authority, repair window resizing or change the opening's teaching flow.

Machine placement now previews the fitted assembly at the pointer's grid square,
including the selected native spindle axis. Neutral translucent amber shows form
and footprint, not accepted placement or construction reach. It reuses the placed
mesh resources with instance-only material overrides and has no collider, script,
command or shadow. Moving the pointer repositions a cached assembly. The preview
is hidden over interface controls and in Help, non-machine tools, pending or
disconnected views, occupied squares and exhausted kits. The existing guided
outlet-square suggestion remains separate. Isolated geometry and visibility
controls do not establish rendered readability or human usability.

The native physical worksite adds quiet original spatial machinery loops only
for explicit confirmed rotating motion. Four cached two-second mono streams
distinguish collector, conveyor, press bearings and wheel. They do not imply a
press impact, successful material transfer or an authoritative rotation phase.
Mechanical stalls, unknown rates, disconnected/unready views and Help are silent;
a material backlog alone does not imply stopped shaft motion. The listener uses
the confirmed local body position plus a small ear offset, with camera orientation
used only for stereo direction. A bounded pitch change is disposable sound
presentation, never a limit on native mechanical ratios. Context changes and
machine removal clear old playback identities. The generated WAV files support
human listening; finite digital levels and isolated Dummy-audio controls cannot
establish the audible mix or production quality.
