# Focused Godot fixture runner

`factory-godot-fixture` runs one headless project script through the existing
native build-support supervisor. Generic runs supply `--script` and
`--pass-line`; registered Chapter 1 and transmission endpoint cases below
supply both and their deadline through `--case`. It requires the pinned Godot
executable, one exact complete success line, exit zero, and a retained log
without `SCRIPT ERROR:`, `ERROR:`, parse/compile errors, or failed script
loads. A partial result is insufficient. The supervisor retains combined output
in a fresh bounded log and
keeps its existing process cleanup and resource checks. This command is an
opt-in focused fixture entry point, not another commit or landing gate.
`--list-cases` prints every registered name, script, completion line, timeout
and required arguments without starting Godot.

Import project resources before a normal fixture run. A missing import sidecar
is a setup failure: keep its log and import the unchanged project before trying
the intended component check. A zero Godot exit does not override a script-load
error or a partial PASS line.

`machine_body_motion_check.gd` needs an actual renderer for its batched cutter
transform readback. Its default suite reports JSON `mode: default`; its sole
selector `--clearance-only` reports `mode: clearance-only` for the held head and
workpiece check. Unknown, repeated, malformed and empty arguments exit 2 before
either suite starts. Run both selections through
`launch-factory-latest.sh --agent-window` with `--test-purpose` and its
`--script` path. Require exit zero, `status: pass`, the selected `mode`, a
positive check count and no engine or script errors.

`machine_visual_test.gd` selects one of five routes: default geometry (no mode
argument), `--batch-motion-check`, `--compare-images=LEFT|RIGHT`,
`--performance-benchmark`, or `--mixed-scale`. The default emits JSON
`mode: default`, `status: pass` and a positive check count. Batch motion emits
`MACHINE_BATCH_MOTION_PASS 41` and needs an actual renderer to read GPU instance
transforms. Image comparison emits `MACHINE_IMAGE_DIFFERENCE` and requires two
nonempty paths separated by `|`; the caller evaluates the reported difference.
Performance emits `MACHINE_PERFORMANCE`; mixed scale emits either
`MIXED_ASSET_SCALE`, `MIXED_MESH_INVENTORY`, or `MIXED_SCENE_PROFILE` according
to its selection. These metrics identify a completed diagnostic run, not a speed
or game acceptance target.

Performance accepts `--count=0..500`, `--kind=collector|belt|processor|wheel`,
`--prewarm`, `--batch`, `--describe-unbatched`, `--close`, `--silhouette`, and
`--capture=PATH`. Mixed scale accepts `--count=0..1000`, `--frames=60..6000`,
`--batch` or `--production-batch`, `--share-static-conveyor-finish` with fixture
batching, `--mesh-lod` and `--spatial-cells=NONNEGATIVE_INTEGER` with production
batching, `--camera-close`, `--capture=PATH`, `--inventory-only`, or
`--profile-scene` with optional `--profile-hidden-control`. Inventory-only and
scene profiling exclude ignored frame and capture options; inventory-only also
excludes camera and profiling options. `--capture=PATH` needs an actual renderer;
the headless dummy renderer refuses capture before building a scene. Unknown,
duplicate, conflicting, empty and orphan options exit 2 before scene
construction or a success receipt. Use
the labeled tracked launcher for rendered checks on checked clean main. Headless
geometry and parser checks do not establish rendered quality or human play.

`production_environment_check.gd` runs `environment` with no case argument, or
one `--environment-case=NAME`: `botanical-species`, `collector-carrier`,
`foundation-depth-vegetation`, `construction-vegetation`,
`bank-fir-lifecycle`, `bank-firs`, `fir-resource`, `pine-reflectance`,
`pine-roots`, `pine-understory`, `stone-material`, `sourced-sky`,
`meadow-patches`, `foliage-mipmaps`, `sourced-foliage`, `ground-material`,
`ground-render`, `site-render`, `water-flow`, `water-pattern`, `water-render`,
`bank-ferns`, `rock-collision-shape`, `surface-composition`,
`foreground-bank`, or `foliage`. The resource and capture cases `bank-firs`,
`fir-resource`, `pine-reflectance`, `pine-understory`, `stone-material`,
`sourced-sky`, `sourced-foliage`, `ground-material`, `ground-render`,
`site-render`, `water-render`, and `bank-ferns` require
`--artifacts=EXISTING_ABSOLUTE_DIRECTORY`. The `bank-firs` case instead accepts
`--fir-layout-only` without an artifact directory to inspect its existing
layout without moving the optional source asset. The three `*-render` cases
require an actual renderer and a labeled tracked agent launch. Every selected
case emits JSON `mode`, `status` and `checks`; require the selected mode,
`status: pass`, a positive check count, zero exit and no engine or script errors.
Unknown, repeated, empty, unsupported-renderer and orphan arguments exit 2
before the case starts. This fixture tests scenery and presentation; it does
not establish gameplay authority, ordinary use or human play.

`mechanical_audio_check.gd` runs its digital waveform and invented scene
observation checks with no arguments. `--scene-only` selects just the scene
checks. The full route may take one `--preview-dir=EXISTING_ABSOLUTE_DIRECTORY`
outside the project to save four WAV files for later listening; it refuses
existing output names or linked paths rather than replacing them. Unknown,
repeated, empty, conflicting, relative and missing-directory options exit 2
before checking or writing. Require zero exit, JSON `status: pass`, the selected
`mode`, a positive `checks` count and no engine or script errors. The waveform
metrics and invented observations do not establish audible quality or human play.

`parts_view_check.gd` runs its default parts display suite with no user arguments,
or one named `--...-only` suite. An unknown or repeated selector exits 2 before
any suite starts; capture paths are accepted only with their corresponding
suite. Select the exact completion line emitted by that suite when using this
runner. The default suite emits an `OPENING_PARTS_VIEW_PASS` count, while
`--buttons-only` emits its JSON status and check count. These are
scripted view checks, not native gameplay, rendered, or human-play evidence.

`machine_detail_check.gd` likewise runs its default geometry suite only with
no user arguments. Select one direct check mode at a time; the retired
one-cell conveyor selectors deliberately fail. Asset preparation takes its
named `--prepare-...` selector first, followed by that case's required path
arguments. `--render-buildable-resources` may combine its declared
`--...-check` prerequisites; `--foot-seat-geometry` applies only to
`--wheel-foot-seats-only`. Unknown, duplicate, conflicting or orphan options
exit 2 before any case runs. Existing suite-specific completion and exit
contracts remain; resource renders are isolated passive evidence.

`machine_preview_check.gd` runs the full invented-observation preview suite
with no user arguments, or exactly one of `--variant-assemblies-only`,
`--assemblies-only`, `--transmission-previews-only`,
`--selection-cursor-only` and `--foundation-heights-only`. Each check mode
and the default emit a JSON `status` and `checks` count; require `status: pass`
and exit zero for the selected mode. `--bake-packed-previews` and
`--bake-preview-variants` are separate source asset-writing operations; they
emit `PACKED_MACHINE_PREVIEWS` or `PACKED_PREVIEW_VARIANTS`, respectively, and
exit nonzero if a save fails. Use them only in a source checkout where those
generated assets are intended. Unknown, repeated, conflicting, empty and
orphan options exit 2 before either checks or asset writes begin. The check
results are scripted presentation evidence, not native gameplay or human play.

`native_transmission_endpoint_check.gd` runs its full detached shaft, pointer
and guidance suite with no user arguments. Select exactly one of
`--common-frame-only` for shared placement-frame barriers,
`--inspection-only` for synthetic inspection guidance, or
`--terrain-host-only` for terrain-cleared pointer requests through the native
Host. Each mode emits JSON with `status`, `checks`, `failures` and an
`evidence` label; require `status: pass`, a positive check count, zero failures
and exit zero for the selected mode. The terrain Host mode needs the captured
native library. Unknown, repeated, conflicting, malformed and orphan arguments
exit 2 before any suite begins. These headless checks do not assess rendered
quality or human play.

The four named runner cases select these modes without a manually supplied
completion line. Their exact JSON receipts include the check count, zero
failures, evidence label and `status: pass`; a different count or a partial
result fails the runner. The counts below match the current fixture revision:

| `--case` selection | Godot arguments | Required checks | Native library |
| --- | --- | ---: | --- |
| `transmission-endpoint-default` | None | 316 | No |
| `transmission-endpoint-common-frame` | `--common-frame-only` | 3 | No |
| `transmission-endpoint-inspection` | `--inspection-only` | 40 | No |
| `transmission-endpoint-terrain-host` | `--terrain-host-only` | 48 | Yes |

Use `--case NAME` in place of generic `--script` and `--pass-line`, and put
the listed Godot argument after `--`. For the default case, omit `--` and user
arguments. The terrain Host case needs the source-matched native extension in
the captured project. Import project resources before running any case;
missing imported assets or native library are setup failures, not fixture passes.
When the fixture's checks change, update its named receipt and rerun that case
before publishing the new source.

`native_transmission_view_check.gd` runs its default transmission suite with
no user arguments or exactly one direct `--...-only` mode. The supported
component modes are `--supplied-hardware-only`, `--component-boxes-only`,
`--press-components-only`, `--guided-press-components-only`,
`--broad-press-components-only`, `--broad-press-raised-only`,
`--channel-components-only`, `--channel-z-only`, `--channel-sheet-only`,
`--support-frame-only` and `--finish-only`. Projection and control modes are
`--physical-topology-cache-only`, `--physical-actor-bridge-only`,
`--advance-projection-only`, `--native-actor-view-only`,
`--native-view-cache-only`, `--tool-guidance-only`, `--refresh-cache-only`,
`--belt-surface-only`, `--direction-basis-only` and `--loose-material-only`.
Material, collision and transport modes are `--slide-material-only`,
`--mechanical-collision-only`, `--collision-lifecycle-only`,
`--cog-axle-collision-only`, `--river-pier-collision-only`,
`--belt-actor-only`, `--inclined-belt-actor-only`,
`--nonhorizontal-presentation-only`, `--belt-picking-only`,
`--cog-axles-only`, `--belt-spans-only` and `--belt-spans-missing-only`.
Unknown, duplicate, conflicting and orphan options exit 2 before a suite
starts. Each direct suite emits `NATIVE_TRANSMISSION_VIEW_PASS` with its exact
revision-matched check count on success and exits nonzero on failure.
Among direct suites, `--capture` and `--crank-capture-prefix` belong only to
the guided press mode; `--broad-capture` belongs to either broad press mode;
`--channel-capture` and `--channel-after-capture` belong to a channel mode; and
`--slide-material-image` belongs only to slide material; `--loose-material-image`
belongs only to loose material and captures its pointed E pickup cue. Use
`--test-purpose=TEXT` on agent graphical launches through
the tracked launcher. Passive capture output is rendered evidence only.

`--scale-benchmark` is a separate selection. Only its declared `--count`,
`--large-every`, `--capture`, `--supports`, `--varied-supports`, `--close`,
`--cycle-axes`, `--verify-only`, `--whole-opening`, `--stopped`,
`--refresh-every-frame` and `--trusted-revision` companions are accepted.
`--verify-only` emits structured `COG_SCALE_VALIDATION` with status `pass`;
the measurement route emits structured `COG_SCALE` values. Treat those as
synthetic validation or performance evidence, separately from the direct
fixture PASS line and native/human-play results.

`site_surface_check.gd` runs its default terrain/physics suite with no user
arguments or one of `--outcrop-native-only`, `--belt-water-native-only`,
`--belt-water-native-forward-only`, `--water-samples-only`,
`--water-native-only`, `--flow-sections-only`, `--waterwheel-visual-only`,
`--bank-firs-physics-only`, `--mature-tree-depletion-only`,
`--native-hull-matching-only`, `--convex-only` or `--structures-only`.
Unknown, repeated and competing modes exit 2 before a suite starts. The
default, outcrop, tree, hull, convex, structure and wheel-visual suites emit
JSON with `status: pass` and a check count. Water samples emit `terrain flow
cell and riverbed section controls passed`; belt-water modes emit `native
actual river belt route controls passed`; flow sections emit `native riverbed
flow and wheel-size sections passed`; and native water emits `native water site
controls passed`, each with its check count. Require the complete
revision-matched line, exit zero and a log free of engine/script errors.
Modes that instantiate `NativeModel` require a captured native library; a
missing library is a setup failure. `--test-purpose=TEXT` is accepted for a
tracked agent graphical launch, but headless results do not establish
rendered or human-play behavior.

`guidance_cue_check.gd --mouse-look-only` emits `OPENING_MOUSE_LOOK_PASS 15`.
It checks first-person capture policy, relative camera motion, menu release and
held-key refusal in a headless view. It does not establish actual OS focus or
human mouse control.
The guidance fixture's no-argument default and `--route-report-only` run its
route report; one other `--...-only` selector runs its named suite. These modes
emit `OPENING_GUIDANCE_CUE_PASS` with that suite's check count, except camera
profile, zoom and mouse look, which emit their own `OPENING_CAMERA_*_PASS` or
`OPENING_MOUSE_LOOK_PASS` line. The explicit `--verifier-negative-control` must
fail. Unknown, duplicate or combined suite selectors exit 2 before checks.
Screenshot paths belong only to their channel hotbar, slide manager or inventory
goal suites; empty, repeated or unrelated screenshot arguments also exit 2.
Select the complete revision-matched PASS line for a positive generic run.

`native_adapter_check.gd` requires exactly one nonempty `--native-check-mode`
and `--native-check-output`. It refuses unknown, repeated or empty arguments
before constructing the scene. Its optional event routes are checked against
the selected mode before the scene starts. At most one anvil stage may accompany
an arrival press mode. `--native-check-prior` belongs only to `arrival-channel-small-resume`;
`--arrival-reveal-probe` belongs only to `arrival-resume`. `--resume-input`
is required for `resume`, modes ending in `-resume`, `arrival-broad-drive`,
`arrival-broad-form`, `arrival-channel-broad` and `arrival-channel-small`.
Fresh modes refuse it before scene startup. The existing `--save-slot`,
`--arrival-capture-prefix` and `--test-purpose` options remain available
where their selected consumer uses them.

Build `//native/godot-fixture:factory-godot-fixture` with the verified Bazel
8.4.2 toolchain described in [native builds](../../docs/engineering/native-builds.md).
The binary is the supported external entry point; its implementation library
and local test are private to this package.
Then run from a linked checkout, substituting existing absolute paths, the
verified lowercase SHA-256, an owned private artifact directory, and the full
PASS line for that exact fixture revision:

```bash
FACTORY_LOCAL="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources/factory-local"
FACTORY_ADMISSION="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources"
"$FACTORY_LOCAL" --root "$PWD" heavy --inherit-permits -- \
  /absolute/verified/factory-godot-fixture \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --godot-sha256 VERIFIED_LOWERCASE_SHA256 \
  --project "$PWD/experiments/engine-environment/godot" \
  --script res://opening/native_transmission_view_check.gd \
  --pass-line 'NATIVE_TRANSMISSION_VIEW_PASS EXPECTED_EXACT_COUNT' \
  --artifacts /absolute/owned/private-fixture-artifacts \
  --log /absolute/owned/private-fixture-artifacts/fresh-run.log \
  --admission "$FACTORY_ADMISSION"
```

Create the artifact directory before the command with owner-only permissions
(`install -d -m 700`). Generic runs may set `--seconds` from 1 to 300 seconds;
their default is 180. Named cases own their deadline, so they reject
`--script`, `--pass-line` and `--seconds` overrides. Arguments after `--` reach the Godot fixture as user
arguments. The executable limits its log to 2 MiB and its owned artifact family
to 128 MiB. It never accepts or prints the log contents as a PASS receipt.

## Chapter 1 scene event selection

The following named `native_adapter_check.gd` selections exercise Godot event
routing through the arrival scene and assert native outcomes. Channel cases
explicitly enable developer material tools; their push/popup routes are diagnostic
coverage, not the ordinary player interaction contract. Run each
with `factory-godot-fixture` above, replacing `--script` and `--pass-line` with
the listed `--case` and passing its arguments after `--`. The runner supplies
the exact line and deadline shown, and rejects omitted, duplicate or unexpected
case arguments before starting Godot. Named case input paths must be absolute;
their result and save-slot paths must be fresh files inside the canonical owned
artifact directory. Give every run a fresh `--log` and
`--native-check-output` inside an owner-only artifact family. The runner rejects
engine errors, nonzero exits, missing completion lines and oversized logs. The
fixture rejects a selected route if its required actions were skipped.

| `--case` selection | Godot arguments | Exact completion line | Maximum time |
| --- | --- | --- | --- |
| `arrival-first-plate` (placement and focus guard) | `--native-check-mode=arrival-first-plate --event-route-pointer --native-check-output=FRESH_RESULT` | `CHAPTER 1 SCENE EVENTS PASS: arrival-first-plate` | 180 seconds |
| `arrival-raised-starter-snap` (raised press starter placement) | `--native-check-mode=arrival-raised-starter-snap --event-route-pointer --native-check-output=FRESH_RESULT` | `CHAPTER 1 SCENE EVENTS PASS: arrival-raised-starter-snap` | 180 seconds |
| `arrival-raised-press` (raised press assembly and plate) | `--native-check-mode=arrival-raised-press --event-route-pointer --native-check-output=FRESH_RESULT` | `CHAPTER 1 SCENE EVENTS PASS: arrival-raised-press` | 180 seconds |
| `arrival-channel-small` (custody and blocked gap) | `--native-check-mode=arrival-channel-small --event-route-loose --resume-input=BROAD_CUT_WORKSITE --save-slot=FRESH_WORKSITE --native-check-output=FRESH_RESULT` | `CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small` | 300 seconds |
| `arrival-channel-small-resume` (fresh-process recovery) | `--native-check-mode=arrival-channel-small-resume --event-route-loose --resume-input=PREVIOUS_WORKSITE --save-slot=FRESH_WORKSITE --native-check-prior=PREVIOUS_RESULT --native-check-output=FRESH_RESULT` | `CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small-resume` | 180 seconds |

`BROAD_CUT_WORKSITE` is the retained passing output of
`arrival-broad-cut-resume` from the same native revision. Feed the narrow
channel result and save into the fresh-process recovery case; it checks exact
placed parts, dropped items, carried cargo and conserved mass before keyboard
pickup. The first three cases use pointer events for fitted placement and check
that a click while the Escape menu is open cannot place a part. The raised
starter checks three placements; the raised press checks five and forms a plate.
The channel case uses Ctrl+L, popup focus, arrow keys and Enter for three
custody attempts, including refusal across a missing rail. Its resume case
uses the same keyboard path to pick up the restored plate. Ordinary players point at material and press
E; the old material menu is available only with `--debug-material-tools`.
Scene tests still substitute scripted
actor movement and choices; they do not establish human play or desktop input.
