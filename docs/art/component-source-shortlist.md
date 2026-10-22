# Source candidates for a reusable construction kit

Originally inspected on 2026-10-20. This extends the
[player-built asset research](player-built-assets.md) with specific source assets.
That study qualified candidates without importing them. The 2026-10-21 update
below identifies later component adaptations; rendered quality remains open.

## Inspection boundary

Read the provider pages and Poly Haven's asset information and file manifests.
Retain the one-kilopixel glTF JSON descriptors for three models and compare each
descriptor's byte length and MD5 with its provider manifest. Inspect their node,
mesh, material and animation declarations. View the providers' static previews
for the drill press, pipe kit and Kenney kit.

In the original study, referenced mesh buffers and material maps were not
downloaded. No Blender, Godot, desktop, animation or performance test ran.
Declared mesh separation in that study is
therefore source evidence, not verification of pivots, vertex contents, working
clearance or an engine import. Provider renders do not establish the appearance
of the assets in Factory. The complete captures and SHA-256 list are retained
under `player-built-assets-research-20261020/candidates` in the local prototype
evidence directory.

## Later component adaptation

At main `44f2af04cf85dae2c49d0d6da7e7731997e89e34`, selected drill-press column,
mounting collar, flange and fastener geometry is packaged as a reusable
[press support](../../experiments/engine-environment/godot/opening/assets/press-support/CREDITS.md).
Its manifest records the actual mesh selection, origin, uniform scale and
prepared attributes. The remaining drill, electrical controls and source scene
behavior are excluded. An authored cast crown and the existing native tool
presentation complete this particular adaptation, not a general multi-tool kit.

A separately qualified
[spinning-wheel rotor](../../experiments/engine-environment/godot/opening/assets/waterwheel/CREDITS.md)
supplies the rim, hub and spokes for the waterwheel. Timber paddles, supported
bearings and mechanical behavior are separate. This demonstrates component
adaptation beyond asset names; it does not turn the source spinning wheel into
a native power model. Both adopted components have their own retained source,
preparation and technical results. This documentation update repeats none of
those operations.

The pipe kit and crane below remain candidates. The measured pipe straight ends
below suggest a reusable visual connection profile, but no imported join or
working clearance has been verified. The original study also
did not import the Kenney archive. Use existing fitted shafts, open hubs, belt
ends and material sleeves as the current construction vocabulary; inspect a new
source for the interface it actually supplies. The
[updated construction map](player-built-assets.md#components-now-implemented)
separates those implemented pieces from missing foundation, route and compound
machine capabilities. Technical checks do not establish appearance in the
worksite or the user's production-quality target.

## Specific candidates

| Candidate and primary source | Facts inspected | Proposed use and remaining work |
| --- | --- | --- |
| [Modular Industrial Pipes 01](https://polyhaven.com/a/modular_industrial_pipes_01), Jorge Camacho, CC0 | The downloaded glTF declares eight separately named mesh nodes and two materials, with no animation or skin. The preview shows straight runs, elbows, branches and a valve with consistent flanged ends. [Provider metadata](https://api.polyhaven.com/info/modular_industrial_pipes_01) and [file manifest](https://api.polyhaven.com/files/modular_industrial_pipes_01) identify the source. | The strongest candidate here for studying realistic modular joins and reusable fitting detail. Check actual sockets, dimensions and tolerances before adapting it. It does not provide native fluid rules, a belt system or general machine internals. |
| [Drill Press 01](https://polyhaven.com/a/drill_press_01), Viktor, CC0 | The glTF declares thirteen separate mesh nodes and one material. Names distinguish the body, plate, catch, lid, belt, two pulley-like parts, handle, buttons, limiter, bit and plug. It contains no animation or skin. The viewed preview shows convincing cast-metal form, machined surfaces and wear. [Metadata](https://api.polyhaven.com/info/drill_press_01) and [files](https://api.polyhaven.com/files/drill_press_01) expose the source and available formats. | A useful adaptation source for a detailed machine head and a reference for purposeful component separation. It is a fixed drill press, not a configurable multi-press. A compatible mechanical drive, mounts, pivots, working openings and reusable frame must be authored or verified. Remove electrical components when adapting it to Factory's mechanical identity. |
| [Overhead Crane](https://polyhaven.com/a/overhead_crane), Timothy3D, CC0 | Its glTF declares three mesh nodes named for rails, winch and the rest of the crane. Two materials separate the trim from the main asset. No animation or skin is declared. The [provider metadata](https://api.polyhaven.com/info/overhead_crane) and [file manifest](https://api.polyhaven.com/files/overhead_crane) were retained. Its geometry and motion were not viewed in an engine. | A candidate for frame, trolley and trim adaptation. Three broad mesh groups do not establish independently adjustable supports, every wheel or hook motion. It needs a component and pivot audit before becoming a player-assembled gantry kit. |
| [Kenney Factory Kit](https://kenney.nl/assets/factory-kit), CC0 | The official page lists a 3D factory kit with variations and animation. Its viewed preview includes modular conveyors, corners, rollers, pipes, gears, supports and machine housings. The archive was not downloaded; the page's file count is not a verified count of distinct models. | A useful construction-vocabulary and decomposition reference. The preview uses simplified stylized forms and a limited palette; my visual assessment is that adopting that appearance would not deliver the requested realistic direction. Use it to study component coverage, without treating it as our production art solution. |

## Measured pipe-fitting geometry, 2026-10-21

The pipe kit's referenced glTF mesh buffer was then downloaded from the URL in
the retained provider file manifest. It is 515,160 bytes and matches that
manifest's MD5, `a18d063dc719e19b9c20d2f8c0a8bec4`. Its SHA-256 is
`2e11e1a7dabd56b1e158364f48b0b388bf316fcab61a01274740db75dbafa448`.
The local `pipe-geometry-study-20261021` evidence directory contains the exact
buffer, a read-only glTF accessor analyzer and its full JSON output. This is a
mesh-data inspection; no textures, engine import, render or native fixture were
added.

`pipe01` and `pipe02` are the two straight mesh nodes. Their local Y spans are
0.859062 m and 1.954640 m respectively, using the
[glTF 2.0 metre convention](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#coordinate-system-and-units).
Both have flange-end cross-section bounds of about 0.2071 m by 0.2063 m. Each of their
four extreme Y planes contains 25 positions. Comparing the short upper end to
the long lower end in local X/Z coordinates gives a maximum nearest-position
distance of about 0.0000051 m across those 25 points. The other short/long end
pairings are similarly within about 0.0000051 m. The flange profiles therefore
appear reusable without scaling the end geometry; the different middle lengths
can be treated as rigid candidate spans.

The candidate connection frames are the local end centers at Y = ±0.429531 m
for `pipe01` and Y = ±0.977320 m for `pipe02`, with normals along ±Y. Catalogue
node translations in the source glTF arrange its parts for display and must be
removed before these frames are used. A short and long span would meet when
their opposite end frames coincide; their center-to-center distance along a
shared axis would be about 1.406851 m. This is a proposed visual assembly rule,
not a verified socket, collision shape, fluid connection or mechanical rule.

The `pipe04` elbow has two candidate orthogonal end frames: an outward -X face
at X = -0.296728 m centered near (Y, Z) = (-0.086859, 0), and an outward +Y face
at Y = 0.254192 m centered near (X, Z) = (0.023870, 0). Each face has 50
positions, separating into 25 outer-ring and 25 inner-ring positions. Its
outer-ring radius is about 0.1035 m, like the straight flange. Under the best
right-angle cross-section orientation, nearest outer-ring positions differ from
the short straight end by at most 0.000238 m on the -X face and 0.000004 m on
the +Y face. That supports a candidate elbow-to-straight visual join while
exposing an asymmetry to inspect at close range. The other fittings and actual
join clearances remain unmeasured.

Packaging is already a constraint. At the inspected Git tree, the tracked Godot
project contains 31,334,099 source bytes across 258 files and 128 GDScript
files. The current native capture allows 33,554,432 bytes, 512 files and 128
scripts, leaving 2,220,333 bytes but no script slot. The mesh buffer is 515,160
bytes; the six original one-kilopixel JPEG material maps total 4,293,764 bytes
in the provider manifest. Importing that complete bundle would exceed the
source-byte allowance at this tree even before descriptor or prepared-resource
overhead. A selected mesh and deliberately prepared material package must be
measured against the then-current roster; this snapshot is not a future capacity
reservation. The isolated render below tests the delivered material appearance;
an in-worksite import and a capture-sized prepared package remain untested.

## Isolated visual join sample, 2026-10-21

The official descriptor, mesh buffer and six original one-kilopixel JPEG maps
were retained together outside Git. Every file matched its provider-manifest
size and MD5. Godot 4.7.2 imported eight meshes with albedo, normal and
roughness textures present on each material. The complete 4,823,938-byte
source package and six passive images are indexed by
`pipe-join-sample-20261021/source-and-render-audit.json` in the local prototype
evidence directory. No file was added to the captured game project.

The sample strips the source catalogue offsets, keeps flange geometry at its
delivered scale, and places a short and long straight with opposing Y normals.
It also turns the elbow's -X end to face the long straight's +Y end. The first
elbow image set aligned centers but pointed those normals the same way, leaving
an exposed upward flange; those original images and log remain retained as a
visual rejection. The corrected sample retains front and back close views of
both joins plus the short pipe after its neighbor is removed.

I inspected all six corrected views. At these angles, the bolted flange stacks
look continuous, the short and long tube surfaces read as one diameter, and
the elbow has no obvious visible gap at the join. The open flange of the removed
neighbor reads as a deliberate exposed end. The worn blue-gray steel, rusty
edges and small fasteners supply much more close-range material detail than
the current plain authored tubes, although the finish may need palette and
lighting adaptation to sit with Factory's other parts. This is an isolated
visual judgment, not a measured clearance, all-angle seam guarantee or human
quality verdict.

The three selected pieces are now packaged as a
[prepared pipe art kit](../../experiments/engine-environment/godot/opening/assets/pipe-fit/CREDITS.md).
It retains their original vertex and UV data in a smaller buffer, retains the
original 1K diffuse and normal maps, and prepares a 256-pixel packed material
map. The five loadable files total 1,446,125 bytes; an isolated import and
passive repeat of the six join views retained their visible flange detail.
They are tracked presentation resources within the inspected capture budget,
but are not mounted in the playable opening. The full original bundle still
does not fit the earlier 2,220,333-byte headroom. An actual native project
capture of art commit `1316b6b` retained all six new asset files from raw Git:
264 project files, 128 scripts and 32,784,501 source bytes, leaving 769,931
bytes under the present 32 MiB limit. The retained capture and rehashed resource
copies are under `pipe-component-kit-20261021/capture-actual` in the local
prototype evidence directory. This proves source packaging, not use in the
playable scene. The next step is an in-worksite view with explicit construction
interfaces and exposed-end behavior before gameplay use. The art kit supplies
no fluid, pressure, attachment or construction authority.

## Measured drill-press moving parts, 2026-10-21

The pinned [Drill Press 01](https://polyhaven.com/a/drill_press_01) geometry
buffer was read against its retained glTF descriptor. The source buffer is
1,911,136 bytes and matches the SHA-256 in the
[press source record](../../experiments/engine-environment/godot/opening/assets/press-support/source.json).
The measured bounds below include each glTF node's translation and rotation;
they are source-model dimensions, not native machine dimensions or mounting
frames. The full per-node vertex, triangle, node-origin and bounding-box report is
`drill-press-tool-module-20261021/geometry-report.json` in the local prototype
evidence directory. The source contains no animation or declared joint pivot.

| Source member | Measured shape and inspected view | Disposition for player-built machinery |
| --- | --- | --- |
| Complete body | 31,210 triangles in a 0.259 × 0.738 × 0.588 metre local box; the rendered body contains the drill housing, motor and column. | Keep the already adapted cast column and mounting pieces. The complete body fixes the machine's proportions and electrical identity, so it is not a modular press or cutter frame. |
| Adjustable plate and small catch | The plate is 0.191 × 0.093 × 0.343 metres locally, with 2,664 triangles. Its slotted face and rear circular clamp are visible in separate front and side renders; the catch is only 0.022 × 0.019 × 0.053 metres. | The plate could inform an authored clamped service table, but it is too small and too specifically attached to replace the current press anvil without redesign. The catch belongs to that mounting arrangement. Neither supplies a generic structural joint. |
| Open lid | The 5,068-triangle cover is an open, shallow housing about 0.511 metres long. Its source node is rotated away from the closed position. | Use its formed lip, thickness and worn finish as a visual reference. It needs a verified hinge frame, closed variant and mating frame before it can guard a configurable drive. Do not mount it as an arbitrary decorative cover. |
| Named `gear_a`, `gear_b` and belt | Each round member spans about 0.109 metres across and the pair sits about 0.35 metres apart in the donor. The isolated render shows stepped pulleys joined by a narrow belt, not meshing cog teeth. | Reject these as native cogwheel art. Their visible belt route, steps and ratio would claim a drive configuration the current press projection does not provide. A future confirmed pulley drive could reuse the surface language after its own mount and motion study. |
| Three-spoke handle and depth limiter | The handle spans 0.316 metres vertically and 0.364 metres in depth; the limiter is a separate 2,020-triangle stop assembly. Both are visibly tied to manual quill feed. | Reject them as live controls or implied adjustable depth until construction and command outcomes actually support those functions. Small fixed details may inspire original art, with no hidden authority. |
| Chuck and twist bit | The 5,052-triangle member is about 0.050 metres wide and 0.135 metres tall. Front and side views clearly show a keyed chuck and a narrow drill bit. | Reject it as a press die or cutter. A press face and a shear blade need distinct authored silhouettes and working clearances; changing the label or scaling this bit would not create them. |
| Buttons and power plug | Separate source nodes are present in the original machine. | Exclude them from mechanical Factory assemblies. Their presence would suggest electrical controls and a cord that the native machine does not have. |

The passive Godot sample retained sixteen views of the complete donor and the
selected rigid members. It used the original geometry and pinned 1K diffuse,
normal and packed material images. A local glTF copy changed only the two data-map
references and MIME labels to use the provider's PNG alternatives. The first
sample kept the old JPEG MIME labels and produced image-decoder errors despite
a zero process exit; those
images remain retained but are rejected as material evidence. The corrected
sample changed the two MIME labels to PNG, required all three maps to resolve
as 1024 × 1024 textures for every member, and completed without an import or
script error. I inspected the corrected whole, plate, cover, pulley, handle, limiter
and chuck views. Its source and frame hashes are in
`drill-press-tool-module-20261021/audit.json` outside Git.

The original diffuse JPEG plus two PNG data maps total 9,544,339 bytes before
the 1,911,136-byte mesh buffer or descriptor. That bundle exceeds the
769,931-byte headroom measured in the pipe-kit native capture. Any selected
donor geometry must reuse the already prepared press
material set or receive a separately measured compact adaptation; copying the
complete donor is not a viable game-resource path.

The useful reuse here is the cast support and material language, not another
complete donor machine. The next player-built sample should author a rigid
tool-module mount with a press die and a distinctly shaped cutting insert at
the actual existing work plane, using the shared cast and machined finishes.
Only a tool that the native World confirms should appear as operating. Check
the mount, exposed ends and working clearance at rest and held-work poses,
then inspect it in the ordinary worksite at construction-camera distance. The
present render establishes donor appearance and source dimensions only; it
does not establish tool compatibility, native mechanics, packaged export,
playable composition or human visual acceptance.

## Workshop H-frame press source, 2026-10-22

The close and construction-distance comparison for the current press showed why
small crown bevels do not solve its broad, slab-like silhouette. I inspected
[Innerscene's workshop hydraulic press](https://www.innerscene.com/tools/library/3d-parts/workshop-hydraulic-press-e68b66c7)
as a structural reference, not a replacement for the game's press. The provider
identifies it as an original [CC0 library part](https://www.innerscene.com/tools/library/terms)
and gives an overall size of 0.988 × 0.700 × 1.790 metres. Its downloaded
1,459,511-byte STEP file is an Open CASCADE AP214 assembly in millimetres. The
source contains 60 individually named child products, 60 assembly occurrences
and 60 closed boundary-representation solids. These are actual source records,
not an inference from a website image.

The useful rigid groups are two anchoring feet, two hollow uprights with pin
holes, foot gussets and fasteners, a bored top crossmember, a lower brace,
adjustable table beams and their support pins. This is a much more explicit
column-to-foot load path than the current crown-only art. The source places its
uprights at approximately ±0.340 metres; the playable press's sourced columns
are at ±0.480 metres. Moving those legs to the current mounts would leave the
source crossmembers and table too short, so fitting it is an authored assembly
adaptation, not a uniform scale or a raw import. The source's 1.790-metre height
also exceeds the current 1.65-metre pick-body height by 0.140 metres.

The hydraulic cylinder, hand pump, gauge, hose and ram are separately named
source parts, but their action is not the game's mechanically driven press.
Exclude them from any live adaptation unless the native World supplies the
matching behavior. STEP placements identify CAD assembly members; they do not
supply verified Godot pivots, animation channels, texture coordinates or a
production material set. The file has seven RGB CAD colors and no inspected
PBR texture package. I viewed the provider's linked preview: it makes the
H-frame, pinned table and foot gussets legible, while its plain blue CAD finish
is not a production-quality game surface. No local tessellation, Godot import or
game render of this STEP source was performed. The exact downloaded file, page,
provider preview and qualifications are retained in
`press-frame-source-20261022/source-audit.json` outside Git.

**Disposition:** accept the foot/upright/crossmember layout as a candidate
reference for an original, rigid press frame. Reject the full model as a
drop-in art replacement. A next prototype should tessellate only selected
structural parts, reauthor their mounts and finishes at the existing confirmed
press dimensions, keep the open feed and moving-tool envelopes, and compare the
complete result at the real construction camera. The present source audit does
not prove that those selected CAD solids will look good after conversion or
that a new frame is physically supported by native collision.

Poly Haven's [license page](https://polyhaven.com/license) permits adaptation and
redistribution of its CC0 assets. Its preview images and website content are
separate from the asset license. Keep those provider previews out of our public
asset distribution. Kenney's page directly identifies the kit as CC0. Actual
adoption still needs the selected source files and their terms retained together.

The Poly Haven metadata was fetched through its official public API with an
identifying `Factory-Asset-Research/1.0` user-agent, following the published
[API terms](https://github.com/Poly-Haven/Public-API/blob/master/ToS.md).
This is a local source study; it adds no API dependency to the game.

## What this changes in the production plan

The source search establishes that usable industrial art is more concrete than
an unspecified future marketplace search. A realistic flanged kit already has
separate fittings, and a realistic complete machine already separates several
potentially moving parts. We can begin adaptation from those assets. Their file
structure does not supply our construction semantics.

Three findings guide the next increment:

1. **Names require interpretation.** The drill-press descriptor calls its two
   drive members `gear_a` and `gear_b`. Their measured mesh and isolated render
   confirm stepped belt pulleys, not meshing cog teeth. Asset names must not
   select native cogwheel behavior.
2. **A delivered glTF is not necessarily the preferred material package.** The
   inspected one-kilopixel descriptors reference JPEG normal and packed material
   maps. The drill-press manifest also offers PNG versions of those maps. Select
   suitable lossless data maps and reproduce packing deliberately; converting
   the supplied JPEG to PNG would not restore lost information. The later
   passive sample used the provider's PNG alternatives, without a JPEG-versus-PNG
   quality comparison.
3. **Separate nodes do not establish a mechanical rig.** The three model
   descriptors contain no animation clips or skins. Independent rigid-node
   transforms may still be appropriate, but their pivots, parentage, bounds and
   clearances must be checked. The current Factory rate/state boundary remains
   authoritative; these sources add no phase, power or processing rules.

## Original recommendation and next adaptation

The original recommendation was a pipe component-connection study and a drill
press adaptation study. The pipe sample now establishes source end frames,
retains flange size and shows a corrected isolated join, but does not provide
fluid mechanics or an in-worksite assembly. The press study qualifies cast
supports and rejects the donor's remaining moving parts as drop-in press/cut
modules. These concrete outcomes replace the original descriptor-only inference
that separate source nodes might supply a modular machine head.

Apply the measured join and material conventions to the next construction
sample in the [main research note](player-built-assets.md). Current drums,
bearings and shaft fittings are starting components; variable foundation and
route cases still need compatible edges, corners and support variants. A pipe
kit supplies visual joints, not those other construction families. For new art
sources, inspect actual mesh buffers and materials, establish usable connection
frames and dimensions, preserve provider provenance, and include selected
resources in the ordinary native launcher capture. Evaluate finished assemblies
in the worksite with human visual feedback. Automated checks cover their
technical scope and do not establish the quality target. This study authorizes
no purchase or desktop-controlled test.
