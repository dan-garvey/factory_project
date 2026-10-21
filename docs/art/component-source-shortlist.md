# Source candidates for a reusable construction kit

Inspected on 2026-10-20. This extends the
[player-built asset research](player-built-assets.md) with specific source assets.
The result qualifies candidates for adaptation work. None has been imported into
Factory, demonstrated in our lighting or adopted as working machinery.

## Inspection boundary

Read the provider pages and Poly Haven's asset information and file manifests.
Retain the one-kilopixel glTF JSON descriptors for three models and compare each
descriptor's byte length and MD5 with its provider manifest. Inspect their node,
mesh, material and animation declarations. View the providers' static previews
for the drill press, pipe kit and Kenney kit.

The referenced mesh buffers and material maps were not downloaded. No Blender,
Godot, desktop, animation or performance test ran. Declared mesh separation is
therefore source evidence, not verification of pivots, vertex contents, working
clearance or an engine import. Provider renders do not establish the appearance
of the assets in Factory. The complete captures and SHA-256 list are retained
under `player-built-assets-research-20261020/candidates` in the local prototype
evidence directory.

## Specific candidates

| Candidate and primary source | Facts inspected | Proposed use and remaining work |
| --- | --- | --- |
| [Modular Industrial Pipes 01](https://polyhaven.com/a/modular_industrial_pipes_01), Jorge Camacho, CC0 | The downloaded glTF declares eight separately named mesh nodes and two materials, with no animation or skin. The preview shows straight runs, elbows, branches and a valve with consistent flanged ends. [Provider metadata](https://api.polyhaven.com/info/modular_industrial_pipes_01) and [file manifest](https://api.polyhaven.com/files/modular_industrial_pipes_01) identify the source. | The strongest candidate here for studying realistic modular joins and reusable fitting detail. Check actual sockets, dimensions and tolerances before adapting it. It does not provide native fluid rules, a belt system or general machine internals. |
| [Drill Press 01](https://polyhaven.com/a/drill_press_01), Viktor, CC0 | The glTF declares thirteen separate mesh nodes and one material. Names distinguish the body, plate, catch, lid, belt, two pulley-like parts, handle, buttons, limiter, bit and plug. It contains no animation or skin. The viewed preview shows convincing cast-metal form, machined surfaces and wear. [Metadata](https://api.polyhaven.com/info/drill_press_01) and [files](https://api.polyhaven.com/files/drill_press_01) expose the source and available formats. | A useful adaptation source for a detailed machine head and a reference for purposeful component separation. It is a fixed drill press, not a configurable multi-press. A compatible mechanical drive, mounts, pivots, working openings and reusable frame must be authored or verified. Remove electrical components when adapting it to Factory's mechanical identity. |
| [Overhead Crane](https://polyhaven.com/a/overhead_crane), Timothy3D, CC0 | Its glTF declares three mesh nodes named for rails, winch and the rest of the crane. Two materials separate the trim from the main asset. No animation or skin is declared. The [provider metadata](https://api.polyhaven.com/info/overhead_crane) and [file manifest](https://api.polyhaven.com/files/overhead_crane) were retained. Its geometry and motion were not viewed in an engine. | A candidate for frame, trolley and trim adaptation. Three broad mesh groups do not establish independently adjustable supports, every wheel or hook motion. It needs a component and pivot audit before becoming a player-assembled gantry kit. |
| [Kenney Factory Kit](https://kenney.nl/assets/factory-kit), CC0 | The official page lists a 3D factory kit with variations and animation. Its viewed preview includes modular conveyors, corners, rollers, pipes, gears, supports and machine housings. The archive was not downloaded; the page's file count is not a verified count of distinct models. | A useful construction-vocabulary and decomposition reference. The preview uses simplified stylized forms and a limited palette; my visual assessment is that adopting that appearance would not deliver the requested realistic direction. Use it to study component coverage, without treating it as our production art solution. |

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

Three findings matter for the next increment:

1. **Names require interpretation.** The drill-press descriptor calls its two
   drive members `gear_a` and `gear_b`, while the preview shows stepped belt
   pulleys. Asset names must not select native cogwheel behavior. Assign an
   explicit visual role after inspecting the actual geometry.
2. **A delivered glTF is not necessarily the preferred material package.** The
   inspected one-kilopixel descriptors reference JPEG normal and packed material
   maps. The drill-press manifest also offers PNG versions of those maps. Select
   suitable lossless data maps and reproduce packing deliberately; converting
   the supplied JPEG to PNG would not restore lost information. No conversion
   or texture comparison was performed here.
3. **Separate nodes do not establish a mechanical rig.** The three model
   descriptors contain no animation clips or skins. Independent rigid-node
   transforms may still be appropriate, but their pivots, parentage, bounds and
   clearances must be checked. The current Factory rate/state boundary remains
   authoritative; these sources add no phase, power or processing rules.

## Recommended first adaptation

Use the pipe kit for a small offline component-connection study and the drill
press for one machine-head adaptation study. The first demonstrates whether
source detail survives removing catalogue offsets, normalizing connection
frames and creating compatible lengths. The second tests whether a finished
asset can supply reusable, independently moving subparts without inheriting its
original electrical identity or enclosing fixed proportions.

The comparison should expose a short span, a long span, a corner, an exposed end
and a removed neighbor. Keep flange and fastener dimensions rigid while adapting
the plain middle. Separately identify the drill-press body, tool and drive
members, and inspect where a new native-compatible shaft would meet them. These
are art experiments over disclosed descriptors, not fluid or new-tool gameplay.

Apply the resulting connection, material and import conventions to the planned
foundation, belt and shaft sample in the main research note. Those families
still need their own shaped edges, end drums, bearings and supports. A pipe kit
is evidence that realistic reusable joins can be sourced; it cannot substitute
for all those components.

Before choosing an art source for that sample, inspect the actual mesh buffers
and materials, establish reusable pivots and dimensions, preserve provider
provenance, and include the imported resources in the ordinary native launcher
capture. Evaluate the finished sample in the worksite under human visual
feedback. Automated checks cover their technical scope and do not establish the
quality target. This source study authorizes no purchase or desktop test.
