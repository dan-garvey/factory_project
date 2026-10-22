# Production-quality assets for player construction

Original research date: 2026-10-20. The initial implementation map was made on
2026-10-21 against main `44f2af04cf85dae2c49d0d6da7e7731997e89e34`.
The current source inventory below was refreshed on 2026-10-22 against main
`b510fe89d34a9e96cfc097370ba0c035e317c295`. The original source study
proposed a production workflow; this update maps it to construction now in the
demo. It adds no asset import, test run or rendered assessment.

## Direction

Use a coherent kit of deliberately modeled components, shared materials and
controlled geometry generators. Players assemble the components; presentation
chooses the right joints, spans, exposed ends and moving pieces from confirmed
construction. Good source assets can supply materials and suitable components.
Original art remains necessary for the distinctive functional parts and their
interfaces. Geometry generation must preserve that art direction as dimensions
and arrangements change.

This applies to everything players build: foundations, structural supports,
frames, belts, cogwheels, shafts, tools and complete contraptions. A waterwheel,
multi-press or combined press/cut machine is an example of the system. The
construction vocabulary must also accommodate new families without requiring a
new bespoke renderer for every complete machine.

The [component source shortlist](component-source-shortlist.md) now identifies
specific industrial kits and models, their declared component separation and
the remaining adaptation work. It separates the original candidate study from
later qualified component adaptations.

The visual target remains the [production presentation target](production-quality.md).
Successful mesh generation alone cannot establish it. A beautiful source model
also needs appropriate composition, lighting and motion in the actual worksite.

## Original source baseline (historical)

The inspected baseline is main `42adffeb4a09b0a605cff5e2b0cb1fd857363873`.
These are source observations, with no new game execution:

- [The opening](../../experiments/engine-environment/godot/opening/opening.gd)
  constructs collector, belt, press and wheel visuals through separate functions.
  Its fitted details provide reusable modeling techniques, but each function
  still describes a particular complete asset.
- [Transmission assets](../../experiments/engine-environment/godot/opening/native_transmission_assets.gd)
  already parameterize gear radius and shaft length, reuse some meshes and keep
  decorative geometry inside established envelopes. The visible gear uses eight
  decorative teeth per native ratio unit. That is an adapter convention, not
  evidence of exact visible tooth contact or a general gear-design tool.
- [The transmission presenter](../../experiments/engine-environment/godot/opening/native_transmission_presenter.gd)
  consumes confirmed identities, axes, dimensions, engagements and signed rates.
  This is a useful authority boundary for a richer component kit. Its current
  refresh key includes motion state; the proposed cache below must distinguish
  geometry changes from changes that only need instance updates.
- [The native Host projection](../../native/factory-godot-world/src/host.cpp)
  exposes entities, transmission parts, material links and mechanical motion.
  [The stationary profile](../../native/factory-stationary/include/factory/stationary.hpp)
  has roles for collector, belt, processor, waterwheel, gear and shaft. Its first
  material profile has at most one collector, belt and processor. It does not
  implement a general multi-tool assembly, player-built foundation catalogue or
  freely routed conveyor system.
- [The mechanical kernel](../../native/factory-mechanics/include/factory/mechanics.hpp)
  describes exact geometry and rational rates. Its current power result does
  not model phase or load. A detailed animated assembly must not imply that
  coupled stroke timing or torque has already been simulated.

Those were the implementation boundaries at the stated baseline, not a current
inventory. They do not narrow the user's requested construction system. Visual
research can cover the wider system now; adopting new functional assemblies
requires appropriate native outcomes later.

## Components now implemented

The following is a source inventory at the 2026-10-22 revision above. The
[opening asset guide](../../experiments/engine-environment/godot/opening/assets/README.md)
links the individual source manifests and technical qualifications. Mesh,
resource and presenter checks support their declared technical scopes; they do
not establish the user's graphical-quality target.

| Family | Current reusable content | Boundary still to solve |
| --- | --- | --- |
| Foundations and floors | Native [Host construction](../../native/factory-godot-world/src/host.cpp) places individual and rectangular groups of finite foundation tiles. The opening renders neighbor-aware steel tops, concrete exterior courses and formwork bays from the confirmed tile grid. | A solid tile is still the physical support and obstruction. Openings, underpasses and nonrectangular supports need matching native occupied geometry; decorative cutouts cannot grant clearance. |
| Waterwheel | Selected sourced rim, hub and spokes combine with shaped timber paddles, cast stands and open journal bearings. The current native opening has a player-selected wheel diameter on supported horizontal axles. | The source model does not supply variable diameter or blade count. The current power and support rules do not establish an arbitrary player-designed hydraulic machine. |
| Press | Selected drill-press columns and mounting pieces combine with an authored [cast frame and crown](press-cast-assembly.md), open ram housing, guide sockets and existing tool motion. | One fitted press does not provide multi-press frames, interchangeable cutters or shared tool timing. |
| Collector and supports | Shaped cast cheeks, service details and an open skid support the existing machine. Ground placement has a source-facing pickup; raised placement has a bounded exterior lift and upper discharge. | The foundation still hides the lower raised route from the outlet view. A visible cutter-to-output path and a larger source-fitting body remain unresolved; any new carrier volume must match native admission and actor collision. |
| Shaft belts | Confirmed shaft endpoints now construct spans with a fitted rubber loop, rollers, side channels, end frames, cargo presentation and supported journals. The view follows the admitted straight or inclined span. | Flexible curves, arbitrary junction hardware and cosmetic routes through occupied structures are not supplied by the current native span. End and support variants must follow confirmed geometry. |
| Cogs, shafts and relays | Parameterized cog rims, teeth, spokes, through-bores, shafts, couplings and supported ends share cast and worked finishes. The native projection also exposes confirmed gearboxes and encased chain drives. | Decorative tooth pitch and marks do not prove exact contact phase, locking or torque. New compound transmissions require native connectivity and clearance before art may depict working joints. |
| Material interfaces | Sleeves, rigid end cuffs and fasteners follow confirmed material-link endpoints. | A visible sleeve cannot grant connectivity, transport or a route absent from native state. |
| Stock and products | Reusable source clusters, in-line billets and outlet plates follow confirmed custody. | Art variation cannot change quantities, recipes or retained item identity. |

The [collector seam-facing assembly brief](collector-seam-assembly.md) records
the next specific art prototype. It maps the confirmed mineral site and rotated
output port to a cutter, gathering floor and exposed-end outlet, while leaving
their visual fit for a matched ordinary-view comparison.

The [modular collector fit study](modular-collector-fit.md) measures the newer
five-component chapter-one layout, its present occupied-volume mismatch, and a
selected source guard candidate. That study does not adopt a new collector.

The practical division is to source surfaces and suitable subcomponents, author
the missing functional forms and joints, and generate the dimension-dependent
middle. A catalogue model is not the construction system. The waterwheel uses
selected spinning-wheel geometry rather than its source drive train. The press
uses selected column and mounting pieces rather than electrical controls or
the drill's original behavior.

### Mounts, dimensions and rigid detail

[The presenter](../../experiments/engine-environment/godot/opening/native_transmission_presenter.gd)
maps confirmed identities, centres, axes and signed mechanical facts to the view.
The current adapter uses a 1.65-metre cell and a 0.4125-metre transmission unit;
these are implementation scales, not permanent design limits. Preserve the
confirmed point, axis and admitted span. A native machine hub is a point and
axis, not a specification for a decorative cylinder's radius or endpoints.

[Transmission art](../../experiments/engine-environment/godot/opening/native_transmission_assets.gd)
keeps detailed ends rigid while changing shaft length. Its 30-millimetre shaft
core radius, collars and keys fit the 39-millimetre cog bore radius. Entry
chamfers expose the opening without changing the outer hub or selection shape.
This is a visual fit, not physical locking. The separate native gearbox and
chain-drive roles now have confirmed presentation; this bore fit alone does not
establish either connection.

Apply the same rule to other families: keep bolt heads, bearing bores, cuffs
and tool interfaces at their intended sizes. Extend a plain rail, repeat a
compatible frame bay or generate a belt middle with distance-based texture
coordinates. Scaling a detailed complete machine distorts its useful interfaces.
Short spans, removed neighbors, crossing material paths and unsupported mounts
need explicit variants or native outcomes, rather than hidden visual bridges.

Current helpers share local meshes and materials; rigid surface detail follows
the part. That reuse is not a measured large-factory rendering budget. Cosmetic
angle caches remain separate from native rates and saved mechanical state.
Detailed meshes add no second connectivity solver, collider, quantity owner or
processing clock. The constraint register records
[short-ray thresholds](../engineering/godot-constraints.md#gdc-14-short-segment-tests-can-miss-small-finite-mesh-faces)
and [snapped face lists](../engineering/godot-constraints.md#gdc-15-convenience-mesh-faces-are-not-the-original-render-vertices).
Correct an observer's representation without silently loosening dimensions or
moving authority. Rendered balance, editing cost and readability still need evidence.

## Primary sources and what they establish

Sources were consulted on the research date. Blender pages identify a 5.2 LTS
manual; Godot links use the rolling stable documentation. These describe
available workflows, not a verified local Blender installation or a new runtime
result. A future implementation must select and check its actual tool versions.

| Primary source | Supported observation and limit |
| --- | --- |
| [Blender: instances](https://docs.blender.org/manual/en/latest/modeling/geometry_nodes/instances.html) | Geometry Nodes can reference repeated geometry with independent transforms. Realizing instances creates unique geometry and increases memory use. This supports an authoring approach; no Geometry Nodes asset was built here. |
| [Blender: glTF export](https://docs.blender.org/manual/en/latest/addons/scene_gltf2.html) | The exporter can emit evaluated meshes with modifiers applied. Geometry Nodes instance export is marked experimental, and GPU instance export has hierarchy restrictions. An authoring graph is not a portable runtime construction program. |
| [Godot: available 3D formats](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) | glTF is a recommended scene format. Direct `.blend` import calls Blender to convert the scene. Exported `.glb` resources offer a route that does not require Blender on every runtime machine. |
| [Godot: import configuration](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html) | Imported scenes have explicit customization and inherited-scene workflows. Shared material resources and a separate runtime wrapper can preserve local bindings through reimport. Their exact behavior still needs implementation checks. |
| [Godot: ArrayMesh](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html) | Generated surfaces can supply positions, normals, tangents, texture coordinates and indices. Variable spans can therefore receive proper surface data rather than relying on stretched primitive materials. |
| [Godot: MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html) | GPU instancing reduces submission overhead for repeated meshes. Visibility is handled for the group, and blend shapes are ignored. One world-sized group is an unsuitable default for independently edited, widely dispersed parts. |
| [Godot: mesh level of detail](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html) | Imported scenes can receive automatic mesh simplification. Spatial grouping matters for instanced detail selection. Generated meshes require an explicit detail strategy; these facilities establish no frame-rate budget for our factory. |
| [Epic: spline components](https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-spline-components-overview-in-unreal-engine) | A spline path and a mesh deformed between two spline points serve different purposes. The transferable idea is to separate route geometry from the pieces arranged along it; this is not a proposed engine switch. |
| [Epic: populating meshes along a spline](https://dev.epicgames.com/community/learning/tutorials/39/unreal-engine-populating-meshes-along-a-spline-with-blueprints) | The official tutorial transcript demonstrates instancing rigid pieces along a path. This is a useful reference for rollers and supports that should retain their shape while a belt follows a route. |
| [Poly Haven: asset license](https://polyhaven.com/license) | The provider permits commercial use and redistribution of its CC0 assets. This makes it a candidate source for surfaces and suitable props. No particular machine component, complete industrial kit or import quality was verified. |

The first two complete HTML captures are retained outside source control under
`player-built-assets-research-20261020` in the local prototype evidence directory.
Earlier requests to obsolete manual paths failed; they supplied no evidence.
The GDC session abstract for *Fallout 4's Modular Level Design* was also found,
but its full presentation was not read or watched and is not used for detailed
production claims here.

## Compare the practical approaches

The following assessment and recommendation are original inferences from those
sources and our construction requirements.

| Approach | Useful contribution | Remaining problem |
| --- | --- | --- |
| Finished machine assets | A reference for silhouette, surface treatment and plausible detail; potentially usable separated subcomponents when the license and editable source permit it. | A fixed complete model cannot cover player-selected dimensions or arrangements. Motion, working openings and component boundaries may require substantial reauthoring. |
| Authored modular component kit | High-quality feet, frame joints, bearings, hubs, rollers, guards, sockets and tool heads can be reused across many builds. | Quality depends on compatible interfaces, proportion rules and enough corner/end variants. Raw mesh reuse alone leaves obvious seams or intersections. |
| Controlled geometry generation | Profiles, repeated sections, arcs and paths adapt spans and repetition while preserving a common surface language. | UV scale, thickness, normals, caps and short-span behavior must be designed. Arbitrary scaling of an entire detailed part damages its proportions. |
| One bespoke procedural generator for each complete machine | Can produce a chosen demonstration quickly. | Each new combination adds another special case. It does not establish a shared construction vocabulary. |

Use the modular kit and controlled generators together. Author the parts whose
silhouette carries identity, then let code assemble and adapt them. A bearing
keeps its modeled shape; a shaft between bearings changes length. A conveyor
retains its end drums and rollers while its central surface follows an admitted
route. Generated art can be sophisticated, but an algorithm does not remove the
need to design its proportions, joints and materials.

## A common component and connection vocabulary

The following is a proposed presentation contract, not an implemented native
schema. It should extend existing part facts where necessary rather than
introducing a second construction state.

| Record | Required meaning |
| --- | --- |
| Part identity and generation | Refer to the admitted object. Rebuilding must not retarget old selection or receipts to a new part. |
| Asset family and revision | Select compatible art, material slots and generator behavior. Artwork revisions do not silently alter mechanical rules. |
| Confirmed dimensions and local transform | Define the part's size and assembly-local mount using declared units and axes. World transforms come from its confirmed parent or part placement. |
| Connection frames | Name a mechanical port, material port or structural join with its position, orientation and compatible envelope. Renderer sockets visualize authoritative geometry or links; they do not independently grant a connection. |
| Body and tool separation | Identify rigid frames, rotating groups, sliding carriages and functional tool heads. Moving one member must not deform unrelated pieces. |
| Surface assignment | Map a small shared palette of paint, cast metal, machined metal, timber and rubber onto the part, with a declared physical texture scale. |
| Collision, picking and working envelopes | Keep decorative surfaces, physical obstruction, selection proxies and actual tool work distinguishable and mutually consistent. Detailed render triangles do not automatically become authoritative contact geometry. |
| Instance state | Carry confirmed motion, selection and bounded cosmetic variation separately from reusable mesh data. Stable visual variation cannot create holes, wear states or broken mechanisms that have gameplay consequences. |

Connection variants deserve as much art effort as the middle of a part. Provide
exposed ends, mating flanges, corner pieces, terminal plates and supported changes
of direction. A connected part must visibly meet its neighbor. A disconnected
part must not receive a decorative bridge that suggests a working route.

Use local transform composition for assemblies:
`part_world = assembly_world × part_mount × member_motion`.
This is a presentation design for future compound structures. The current
stationary projection does not already provide every term. Construction grids,
operating motion and camera transforms remain distinct.

## Apply the system across construction families

This is an initial coverage map, not an exhaustive part catalogue or a decision
to add every listed gameplay feature immediately.

| Construction family | Authored kit content | Adaptation and difficult cases |
| --- | --- | --- |
| Foundations and floors | Surfaces, perimeter trims, corners, underside beams, feet and accessible edge treatments. | The current player-built solid tiles and neighbor-aware edges provide a starting kit. Extend their interior at consistent texture scale, but require native support and collision for gaps, height changes, holes or open piers. |
| Frames, beams and supports | Foot plates, end connections, elbows, braces and load-bearing silhouettes. | Change a plain middle span or repeat compatible bays while keeping end details rigid. Very short spans need explicit variants. Automatic supports must never create free structural inventory or unmodeled collision. |
| Belts and material routing | End drums, rollers, side frames, junction fittings and support brackets. | Current shaft spans cover admitted straight and inclined routes. Generate only that confirmed surface; place rigid rollers and supports separately. Curves, grades outside the admitted profile, short segments and direction changes need distinct join and authority checks. |
| Cogwheels and shafts | Hub, spokes, rim profiles, tooth profiles, collars, bearings and couplers. | Parameterize compatible sizes and spans. Preserve circular profiles and signed axes. Visible tooth pitch and phase alignment need explicit treatment; the current decorative tooth multiplier is insufficient proof of meshing appearance. |
| Player-built waterwheels | Axle, hubs, spokes, rim sections, paddles or buckets, bearings and frame joins. | Assemble around an admitted axis with compatible dimensions. Player-selected paddle count or radius must remain separate from any unimplemented effect on power. Rim closure, water intersection and bearing support need visual scrutiny. |
| Presses and multi-press structures | Columns, crossheads, anvils, guide rails, rams, dies, guards and feed openings. | Reuse frame bays and individual tool modules for different layouts. Each ram follows its own confirmed work state. Shared framing must not invent a common stroke, capacity or synchronization rule. |
| Combined press/cut assemblies | Compatible mounting interfaces and distinct press dies, cutters, carriages and work supports. | Fit tools to the player's confirmed arrangement and maintain working clearance. A shared cosmetic enclosure cannot merge recipes or move material between tools. Different operation orders need independently meaningful native behavior. |
| Further construction families | Reuse the same surface, connection, identity and rigid-motion conventions. | Introduce genuinely new geometry families deliberately. Rails, gantries and travelling assemblies retain the broader design requirements and their own unresolved mechanics. |

For a multi-press, this permits the player to arrange multiple press modules on a
common frame, choose spacing and route shafts or belts to them. The art workload
is a frame kit and a press module with compatible joins, rather than a separately
modeled mesh for every possible whole machine. For a press/cut combination, the
same mount vocabulary accepts different authored tool heads. Native rules must
still determine which combinations can actually work.

## Materials, motion and assembly editing

Adopt a shared trim sheet for repeated edge and flange details, tileable material
sets for broad surfaces, and dedicated textures where a distinctive tool or
housing needs them. These are proposed art choices. Keep bolts, edge bevels and
rubber thickness at a stable physical scale when spans change. Encode UV density
along the generated surface instead of scaling a complete UV-mapped assembly.
Avoid baking an entire fixed machine's shadowing into parts that can separate.

Keep rigid machinery as transformable subparts. Skinning is useful for genuinely
deforming components, but a single skeleton for every possible player assembly
would introduce unnecessary coupling. Confirmed stopped, stalled and unpowered
states must remain visually distinct. The native projection now includes load
and overload results as well as signed rates. It still does not supply gear
tooth phase or coupled tool-stroke timing; animation cannot invent either
merely from rate.

Separate the reusable mesh cache key from instance state. A candidate mesh key is
`asset_revision + family + geometry_parameters + detail_level`. Identity,
selection, current angle and changing inventory are instance inputs. Cache
material resources separately. Rebuild only affected geometry and neighboring
join variants after a confirmed edit. Removal and reconstruction must release
the old instance binding. A preview may show proposed geometry but must not
alter confirmed support, connection, stock or work.

## Source assets, import and resource ownership

Search for usable modular components and surfaces before authoring every detail.
Prefer assets with editable parts, useful pivots, plausible thickness, materials
that transfer, and licenses that permit adaptation and distribution inside the
public game repository. A CAD-looking download is not enough: its license,
tessellation, hidden internals and independent moving pieces need assessment.
Specific source candidates are assessed in the linked shortlist. No external
industrial kit has yet been validated as a compatible runtime construction kit.

One immediately reusable sourced surface is the existing
[Metal Plate 02 set](../../experiments/engine-environment/godot/opening/assets/steel/CREDITS.md).
The [provider page](https://polyhaven.com/a/metal_plate_02) identifies its author,
CC0 terms, two-metre extent and available material maps. It can inform foundation
and broad sheet-metal surfaces. A coherent kit still needs distinct machined,
painted, timber and rubber finishes; using the same weathered plate everywhere
would erase those differences. This study downloads no additional asset maps.

Keep editable authoring sources and export settings reproducible. Use Blender
Geometry Nodes as an optional authoring tool for repeated variants; export
evaluated component meshes. Do not depend on an experimental instance export or
expect Godot to execute the Blender graph. A bounded native generator can later
implement the necessary variable shapes, with the existing Godot adapter binding
mesh buffers and presentation. This proposal adds no Python tool or dependency.

Import `.glb` components through a separate scene wrapper that owns presentation
bindings, material overrides, port metadata and selection proxies. Share surfaces
across compatible components and verify pivots and axis conversion explicitly.
Preserve the original source and provider terms for adopted assets. The normal
capture and launcher path must include the resources and metadata; a source-only
asset beside a fixed capture list is not a runnable integration.

For large builds, group repeated decoration by spatial area and shared mesh and
material. Keep independently editable identity and picking outside render batches.
Select simplified detail that preserves openings, gear silhouettes and tool
positions. Generated variants need their own detail path; imported automatic
detail selection does not automatically solve it. Measure vertices, submissions,
texture memory, edit rebuilding and frame time on a representative factory before
choosing numerical budgets. No such costs were measured in this study.

## Next construction sample

The original bearing, shaft, conveyor-end and solid-foundation samples now have
native construction and presentation increments. Reuse those components and
their qualified sources. The next sample should expose a missing composition
rule: two independently confirmed tool modules on one player-selected frame,
with explicit supports, rigid joins and a material-path versus shaft-routing
conflict. This is an art and interface study until native construction admits
that compound structure. Keep the shared palette and mount conventions across
structures, transmission and logistics before expanding the machine catalogue.

A [passive press-and-cutter sample](press-cut-frame-study.md) now tests two
distinct tool forms on the fitted frame. Its rotary cutter reads more clearly
than a second press at the sampled construction distance, but it adds no native
compound construction, item transfer or tool motion.

Start with a deterministic asset-comparison scene that consumes disclosed
construction descriptors and submits no gameplay commands. Exercise existing
admitted foundation tiles, shaft spans and axes as real inputs. Label compound
tool-module descriptors explicitly as presentation examples, with no claim of
implemented placement, transport or saved gameplay. Then mount applicable
components in the ordinary native scene through the existing confirmed
projection. A later native outcome owns new functional construction capabilities.

The next increment should distinguish these failures:

1. Long and short spans stretch bolt heads, change metal texture scale, invert
   normals or leave uncapped ends.
2. Neighbor addition/removal leaves a floating foundation trim, duplicated corner,
   stale selection binding or an invented support.
3. Axis changes rotate bearings, shafts or gear faces inconsistently with their
   confirmed connection frames.
4. Curves distort rigid rollers, leave seams at end drums or create a visible
   material route absent from the native state.
5. Motion-only updates allocate new meshes, rebuild the whole assembly or keep
   moving a stalled member.
6. A beautiful close-up becomes unreadable at normal construction distance, or a
   large repetition exposes tiling and disproportionate detail costs.

Relevant automated controls can verify geometric joins, physical material scale,
identity, resource reuse and authority boundaries. Human comparison must assess
whether the sample actually looks convincing in the worksite, including ugly
arrangements. Human feedback is not an extra code-landing approval. Agent desktop
testing remains disabled.

After that sample, extend the same component contract to a configurable wheel
and interchangeable press/cut tool mounts. Record any missing native geometry,
phase or process interfaces as specific implementation outcomes. Existing
components guide that work; production asset quality, a generally configurable
construction kit, exact tooth appearance and multi-tool gameplay remain unproved.
