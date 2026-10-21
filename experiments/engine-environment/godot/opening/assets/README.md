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
`factory-yau.6.45`. Current complete captures use the sourced
[adult worker](worker/README.md). The other scenes here remain optional previews.

`worker.tscn` retains an earlier static clothing and equipment preview. Historical
fixed-roster character captures construct a rounded torso, fitted harness and
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
machine envelope. In the native profile, the head eases down by 0.015 metres only
when confirmed held work is present, and rises only after held work is empty.
The lowered head retains eight millimetres of clearance above the fitted billet's
raised boss; a composed control compares the actual head and redrawn item meshes.
Blocked READY work retains the lowered pose. The rod extends with its top fixed;
this is an observed held/empty pose, not a predicted stroke or processing clock.
Fresh contexts and replacement generations start at their observed pose, while
an unrelated geometry refresh retains the current travel. The drive stub is a visible interface, not a cogwheel
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

The collector drum, hub and eight cutter flutes share that same cached cosmetic
angle about their existing drum center. The press and cutter reuse the view's
freshness gates and leave their pick bodies, item counts and item positions
unchanged. The conveyor remains static: no belt surface speed or direction has
been inferred from the separate material-transfer rules.

Confirmed material links have static arrowheads and endpoints aligned with their
actual ordered grid direction, including routes along either axis. These indicate
the existing link direction, not simulated item motion or a pending command.
Power-link drawing remains unchanged. The separate `material_route_test.gd`
checks both directions on both axes, geometric arrow direction and projection
immutability; it can also run against the preserved predecessor as a negative
regression witness.

The primitive preview meshes and their materials are authored here using built-in
Godot resources. Sourced worker, ground, steel and foliage assets carry their own
provenance and license notices. The palette and geometry remain revisable until
normal-distance in-game evidence and user visual feedback support them.

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
beyond the normal worksite. The current complete capture adds a contoured valley,
recessed stream and millrace architecture around the flat construction pad.
The grid, construction anchors and machine envelopes retain their coordinates;
ActorWorld realizes the same displayed terrain and solid structures. Low foliage,
water and foam remain visual details. Historical fixed-roster captures retain
their flat surroundings and plane, and the explicit legacy fixture retains its
earlier sky and stream. No external sky download is required. The isolated
environment check validates assembly and resource/spatial contracts; it does not
establish the rendered balance, reflection quality or Satisfactory-level result.

The fixed-roster launchers already include `character_presenter.gd` and
`opening.gd`, retaining their identified procedural worker and machined surfaces.
Complete-project native capture includes the sourced adult worker and these
previews. No Python launcher changes are needed. Rendered quality,
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

The physical foundation panels use the sourced
[steel surface set](steel/CREDITS.md), with continuous world-space mapping and
separate albedo, OpenGL normal and packed scalar material data. Panel geometry,
machine finishes and all construction/collision rules stay unchanged. One cached
material serves the whole foundation, with mipmaps for the normal playable
camera. Current complete native captures include the images; historical rosters
without them keep their explicitly identified procedural floor. Source/image
checks do not establish rendered quality, reflection balance or GPU cost.

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

`native_transmission_assets.gd` supplies fitted render assemblies for the native
presenter: a closed turned gear rim, hub, four spokes, beveled trapezoidal teeth
and repeated fasteners, plus higher-resolution shafts with collars and keys.
Eight decorative teeth per native ratio/radius unit keep the visible density
proportional. This does not reinterpret the native wire, add a contact solver or
establish tooth phase. Gear surfaces stay inside the native radial envelope;
shaft fittings stay inside the unchanged pick radius and endpoint length. All
assemblies use shared machined surfaces and cached meshes, with no collider or
input node. The presenter retains mounting, direction, animation and pick
ownership. Isolated mesh checks do not establish the ordinary rendered result.

The ordinary offline and shared item redraw uses `workpiece_item_assets.gd` for
seam blanks, in-line billets and the visible press-outlet plate. The fitted
assemblies retain the original counts, world positions and item envelopes, using
shared machined surfaces and cached meshes without collision or state authority.
The helper loads after the opening script to reuse its existing surface library.
Historical scripted payloads with fixed file rosters keep their existing primitive
items when the optional helper is absent. Native presentation requires the complete
captured project and reports missing assets instead of taking that fallback.
`workpiece_item_mount_check.gd` exercises the actual refresh callbacks with
invented projection facts, including stock changes, item cleanup, resource reuse
and an explicitly incomplete historical payload. These controls establish callback
integration without human visual, native gameplay or shared-network acceptance.

The physical environment enables restrained screen-space ambient occlusion to
support the fitted bearings, frame joints and machine feet. The effect changes
ambient shading only; sun, exposure, geometry, collision and construction remain
unchanged. The [Godot 4.7 renderer table](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)
lists this effect for Compatibility, and the
[Environment properties](https://docs.godotengine.org/en/stable/classes/class_environment.html#class-environment-property-ssao-enabled)
describe its radius and strength controls. The current values are a reversible
presentation default. Their rendered balance, edge artifacts and GPU cost remain
unassessed; source compilation is not a pixel or performance result.

The worksite controls share an industrial drawing theme with restrained dark
surfaces, warm selected states, readable disabled text and a distinct keyboard
focus outline. Button and native MenuButton styles clone their own resolved
engine padding before changing borders, so effective content metrics, fonts and
minimum sizes remain unchanged. The existing panel margins and control actions
are preserved. Styles are built inside the captured opening script and add no
font or image dependency. Isolated style/inheritance controls establish metric
preservation and assigned-color contrast, not pixel appearance or human usability.

## Shared terrain and millrace

Complete captures replace primitive grass blades with a bounded CC0
[Grass Medium 01 tuft](foliage/CREDITS.md). One self-contained mesh and three
embedded maps are imported once and shared by the existing 96 terrain anchors.
The photographed double-sided cutout retains transparent blade gaps, dielectric
shading and normal mipmaps. This is noncolliding scenery; terrain, construction
pad and actor authority remain unchanged. Historical fixed rosters retain their
generated fallback. Import checks do not establish rendered production quality.

The same tuft also forms small spatially grouped meadow patches. Each patch
contains at most 32 instances, with at most 24 patches, sharing the existing
mesh and material. Roots follow the actual rendered terrain triangles and their
face normals. Steep faces, the pad, river and expanded static-solid envelopes are
excluded. The finite 62-metre visibility range is a reversible art/culling choice,
not a world or construction boundary. Patch bounds enclose the transformed mesh;
the original sparse foliage and historical fallback remain intact. No density,
culling or triangle count is a measured GPU-performance or human-quality result.

Complete current captures use the CC0 [Rocky Trail](ground/CREDITS.md) surface
for the valley ground. Shared albedo, packed scalar and OpenGL normal maps use
world-space mapping at the source's two-metre scale. Restrained elevation tint
preserves the photograph's brightness rather than applying another dark base
coat. This changes shading only: terrain triangles, support geometry, native
poses and construction anchors are unchanged. The steel material has its own
cache and files; both use the same bounded decoder with their declared normal
resolutions. Source packaging and material checks do not establish rendered
quality or GPU performance.

The worksite uses the contoured valley, stream, sluice and stepped tailrace from the retained millrace candidate. Terrain triangles, flat deck rectangles, wharf beams, architectural boxes and rock transforms are shared immutable inputs in `site_surface.gd`; ActorWorld alone constructs their native collision. Water, foam, foliage and small turned ornaments remain visual details. The scanned steel cache and floor channels are unchanged. The displayed finite site is adapter geometry, not a gameplay world boundary. Human visual quality has not been assessed.

The shared opaque water material now scrolls its repeated normal detail downstream
through the existing view frame callback. The absolute visual phase is idempotent
across views and wraps by a texture period, using the documented
[UV offset](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html#class-basematerial3d-property-uv1-offset).
Its 0.4 metres per second is an environmental art choice, never a production clock,
waterwheel rate or fluid simulation. The water remains dielectric and retains its
vertices, opaque depth behavior and shared normal resource. Historical fixed-roster
and explicit legacy views keep their earlier static surface. Headless material and
frame-consumer checks do not establish the rendered effect or GPU cost.
