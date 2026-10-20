# Native World in the Godot opening

`FactoryNativeWorld` is a scene-level `RefCounted` extension that owns one C++
World. The normal offline scene uses `opening/native_model.gd` to forward
commands, natural ticks, ActorWorld observations and checkpoint values. The
bridge has no file, network connection, clock or second quantity map. Store
retains the existing binary envelope, verified write and atomic publication.
Missing native resources fail startup; only an explicit `--legacy-fixture`
selects the historical scripted fixture. The existing shared server can explicitly
select this same native owner with `--native-world`; clients remain read-only
Session facades and never instantiate a native World.

The current opening adapter is a revisable profile: sixteen raw units, one-unit
buffers, a two-tick press, four-world-unit reach and the existing site/capsule
geometry. It preserves the original wire intent in World's history. Exact retry
lookup precedes current target translation, so removal, rebuilding and a fresh
process cannot retarget an old receipt. Checkpoint import validates the original
action and typed payload against that historical translation without using
present poses or generations. Malformed adapter refusals retain their exact wire.

Ordinary collector, belt and press placement also attaches their directly mating
material ports. The existing +X, one-cell, same-row layout still applies; nearby
unrelated machines do not connect. Every affected endpoint must be in the same
admitted reach cut. Placement, links and the carried part commit atomically,
without creating a shaft or advancing material. The exact optional mechanical
axis stays in the original wire and typed history. Adjacent material machines
therefore need no separate Connect request; old manual links and receipts remain
supported by the sole native World, Session and Store.

Drive connections consume independent finite shaft parts and derive motion from
their actual geometry. The projection includes those parts, rational motion,
engagements, typed cargo and per-actor kits. It is a detached view, never authority.
The ordinary offline and native shared views mount thin individual-cog controls
and a confirmed transmission presenter; see the [opening controls](../../experiments/engine-environment/godot/opening/README.md).
Mechanical parts do not yet have precise actor colliders;
ActorWorld keeps its existing uniform machine boxes and floor.

The physical checkpoint has schema 3 and format `factory-native-physical`. Its
logical World checkpoint has schema 2, including the trusted interaction offset.
It retains typed material, kits, topology, issued identities, original history and
actor seed positions. Native readiness, epochs, object identifiers and velocity
are process-local and are not saved. Restore requires a fresh unobserved Host;
there is no old scripted-save migration or safe-spawn fallback.

## Build and consume

After the pinned build, prepare an immutable captured runtime with the actual
absolute launcher/library outputs and the already verified engine hash. The
installed admission tool is in the canonical Git directory:

```sh
native_admission="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources"
"$native_admission/factory-local" --root "$PWD" heavy -- \
  /absolute/factory-opening-startup \
  --repo "$PWD" --tree "$(git rev-parse 'HEAD^{tree}')" \
  --output /absolute/owned/fresh-native-opening \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --engine-sha256 verified-lowercase-executable-sha256 \
  --admission "$native_admission" \
  --native-descriptor "$PWD/native/factory-godot-world/native-world.gdextension" \
  --native-descriptor-sha256 "$(sha256sum native/factory-godot-world/native-world.gdextension | cut -d ' ' -f1)" \
  --native-descriptor-relative native-world.gdextension \
  --native-library /absolute/factory-native-world.so \
  --native-library-sha256 "$(sha256sum /absolute/factory-native-world.so | cut -d ' ' -f1)" \
  --native-library-relative factory-native-world.so
```

This checks a headless import and ordinary scene startup. A human with a graphical
display can then open the captured runtime directly, using a fresh save path
whose parent already exists:

```sh
"$native_admission/factory-local" --root "$PWD" heavy -- timeout 1800 \
  /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --path /absolute/owned/fresh-native-opening/runtime/project \
  res://opening/opening.tscn -- --save-slot=/absolute/owned/player.factory
```

For a saved worksite, prepare another fresh output using `--resume` and the
original Store file. Add `--resume-input` pointing at that new output's
`incoming.factory` when manually opening its runtime. Use a separate fresh
`--save-slot`; do not reuse the launcher's existing `worksite.factory`.
The automated headless consumer is not a rendered or human-play result.

The focused `opening/native_material_attachment_check.gd` consumer uses ordinary
construction callbacks and actual native walking to test an atomic unreachable
endpoint refusal, a fresh connected belt, removal and reconstruction. It retains
typed facts and tests the existing confirmed-link guidance. Its fresh-process
mode checks the original Store binary and history before new material input.
This is headless adapter coverage, not desktop input or human play. The first
Store continuation and the later axis-bearing current-main construction keep
their own source revisions rather than being reported as one unchanged case.

The separate `opening-session/native_shared_cog_check.gd` consumer exercises the
ordinary shared view through menu, key, button and projected click callbacks in
independent P and Q processes. Clients retain their raw initial projections
before validation and use separate passed markers before releasing material
input. `native_shared_cog_server_check.gd` inherits the ordinary server without
changing its commands, clock, body producer or Store lifecycle; it retains the
original ready/final dictionaries and native observations in typed binary files.
The selected continuation loads the original host save before fresh client input,
then inspects, removes and reconstructs a real cog with confirmed actor-specific
custody. These scripts are bounded automated consumers, not desktop control,
human usability, tooth-contact physics or rate-scaled production evidence.

Bazel targets are `//native/factory-godot-world:factory-native-world.so`,
`//native/factory-godot-world:host_test` and
`//native/factory-godot-world:gear_host_test`. The separate
`factory-native-world-abi-test.so` runs invented ABI controls at extension
initialization and must never be supplied as the gameplay library. Use the
existing [native build profile](../../docs/engineering/native-builds.md).

Supply the production library and `native-world.gdextension` as the six paired
resource options to [factory-opening-startup](../factory-launch/README.md).
Their project-relative paths are `factory-native-world.so` and
`native-world.gdextension`. The launcher captures the immutable Git project,
copies both pinned resources, imports and starts the ordinary offline scene.
It does not download a library or select a script fallback. The older Python
fixed-roster launchers do not deliver this extension.

`opening/native_adapter_check.gd` is a bounded headless scene consumer. It loads
the ordinary opening, uses actual registered ActorWorld observations and natural
scene ticks, then exercises recovery, running removal/rebuilding and exact retry.
Its fresh-process mode verifies the original typed Store load and native seeds
before a new material command. It retains binary observations before reporting
failure. This is automated integration evidence, not desktop input, usability,
human play, shared-world adoption or a performance result.

The independent API converter's supported engine and limits are documented in
[factory-godot-values](../factory-godot-values/README.md). Calls run synchronously
on the engine-owning thread. Engine exceptions fail delivery; the thin facade
stops the session rather than interpreting uncertainty as a material refusal.

The extension implements Variant calls and marks its method metadata `VARARG` so
the VM cannot select an absent typed callback. The callback still enforces exact
argument counts and scalar types. `native_dispatch_check.gd` guards that metadata
before compiling and invoking a typed native receiver. The old library is rejected
before that previously unsafe path; this is distinct from physical-body coverage.

## Shared native profile

The server's explicit `--native-world` option uses the same fixed native profile
with P/Q actors. Session keeps its peer, actor, context and request-namespace
checks and passes the authenticated actor to the native command call. The Host
also requires the original wire client to match. Local startup rejects a missing
library or a legacy/native combination; it does not select the scripted owner.
The historical shared profile remains separate when this option is absent.

Use the complete captured runtime for the existing `opening-session/server.gd`
entry with `--native-world`, and connect the ordinary `shared_opening.tscn` clients
with their existing port/role arguments. All tracked adapter scripts and the
exact descriptor/library must be present. The legacy fixed-roster Python shared
launcher does not prepare this native profile.

The original headless shared consumer ran that real server and ordinary P/Q client scenes
in distinct processes. It tests natural collection into a buffer, authenticated
Q recovery, an actual native host save, and fresh-host P/Q restoration before
either client submits material input. Q then reinserts its original raw unit and
P recovers it once. Six old requests, per-actor custody and the sixteen-unit total
survive. This is a raw-unit recovery witness, not press/product continuation,
walking, desktop input, actor contact, crash recovery or human play.

The current `opening-session/native_shared_check.gd` consumer extends the existing
shared-cog client's typed records, initial barriers and RPC assertions. It uses
the same `--cog-phase`, `--cog-directory` and `--cog-previous` arguments. Its separate
production case collects a real product into Q, pauses and recovers a positively
progressed workpiece into Q's Cargo, and rejects P's attempt to insert that lot.
A fresh server must load the original host save before either client submits a
material request. Q then reinserts the same lot and P collects three more products.
The fixture asserts individual custody, exact progress and sixteen-unit accounting;
its source is not a claim that this new case has passed or that humans tested it.

The original consumer explicitly predeclared the runtime extension catalogue
before import. Two first cold imports without it failed; debugger captures show
a native importer fault. A fresh early-catalogue control passed. Keep that
instrumentation boundary and the original failures separate from acceptance of
the launcher correction. No unique symbolic engine cause is asserted.

## Oriented transmission API

Commands retain the same context, client and request identity. They enter the
existing World planner, finite kit and two-endpoint reach checks.

| Command | Additional fields | Meaning |
| --- | --- | --- |
| `place_gear` | `center: [int, int, int]`, `axis: "x"`, `"y"` or `"z"`, `teeth: int` | Place one carried gear at an exact grid center. |
| `place` | Existing `kind` and `cell`, optional `axis` string | Orient a machine while retaining the existing cell wire. Omitted axis remains `"x"`. |
| `connect_drive` | Existing `from` and `to` identifiers | Consume a carried shaft that actually spans the two endpoints. |
| `disconnect_drive` | Existing `from` and `to` identifiers | Return the matching shaft through the same World removal planner. |
| `remove` | Existing `entity` identifier | Remove a selected individual gear or machine, preserving custody rules. |

One grid unit is `pitch / 4`, currently 0.4125 world units. Map a center to
`center * pitch / 4 + [0, anchor_height, 0]`. The axis is the rotation axis,
normal to the gear plane. This fixture accepts integer X/Z coordinates from -8
through 16 and integer Y from 0 through 16. These are revisable adapter bounds,
not requirements for the eventual world scale. Placement uses a conservative
disc bounding box against registered actor capsules; precise tooth or part
colliders are not implemented.

The read-only `part_specifications` projection maps each actor to entries with
`kind`, `teeth`, `half_span` and remaining `count`. The finite profile is unchanged:
P starts with two equal two-tooth gears and three shafts of half-span two; Q has
no parts. Uncarried specifications refuse without changing that kit. Gears and
shafts appear in `transmission_parts`, with integer `axis` values 0, 1 and 2 for
X, Y and Z. Use `engagements` and exact signed `motion` for transmission facts;
the historical `drive_links` shortcut describes machine-to-machine shafts only.

A first horizontal train places a Y-axis wheel at cell `[-1, 1]`, a Y-axis
collector at `[0, 1]`, and Y-axis gears at `[-4, 4, 4]` and `[0, 4, 4]`. Join each
machine to the gear above it using a real vertical shaft. The equal gears mesh
and reverse rotation. Moving the second gear by one grid unit breaks engagement.
The focused native unit verifies this geometry, running removal/rebuilding,
finite kit, historical retries and exact typed checkpoint restore. Its actor
observations and tick are synthetic unit inputs, not physical gameplay evidence.

Current material stepping treats either rotating direction as powered and does
not scale production by angular rate. The signed motion is real kinematic output,
but directional transport and rate-dependent throughput remain separate work.
The same checkpoint formats and finite profile remain in use. Old cell commands
retain their default orientation, and old receipts replay before present geometry
or pose checks. No second material owner, fallback or checkpoint migration is added.

`opening/native_cog_check.gd` adds a headless integration consumer of the ordinary
scene's command boundary, using real ActorWorld cuts and a fresh Store reopen.
It retains exact typed observations on failure and independently checks scalar
three-dimensional reach. Its scope is native-body cog admission, geometry and
custody. It does not operate desktop controls or establish the separate cog UI's
discoverability, shared construction, human play or direction-sensitive throughput.
