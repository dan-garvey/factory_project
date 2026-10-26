# Native World in the Godot opening

The production GDExtension exposes one native World through Host commands,
projections and typed checkpoints. Godot supplies input/presentation and confirmed
actor observations. It does not keep a fallback material authority. Missing native
resources or failed Store loads stop startup.

Build `//native/factory-godot-world:factory-native-world.so` through
[native builds](../../docs/engineering/native-builds.md). The separately named
ABI-test library is an invented test fixture and must never be installed as the
gameplay library.
The Bazel production extension is public. Only the opening-engineering package
may depend on the Host library and test-site helper; local tests, ABI fixture
and runtime configuration target are private to this package.

## Build and consume

After the pinned build, prepare an immutable captured runtime with the actual
absolute launcher/library outputs and the already verified engine hash. The
installed admission tool is in the canonical Git directory:
Normal startup captures the native opening product dependency closure; explicit
fixture captures keep the complete tracked Godot project.

```sh
native_admission="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources"
"$native_admission/factory-local" --root "$PWD" heavy --inherit-permits -- \
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

## Adapter contract

Calls are synchronous on the engine-owning thread. Session binds the caller;
Host checks the authenticated actor against the command's client identity.
The [value adapter](../factory-godot-values/README.md) preserves exact types
and owned data. Engine delivery failure is not a gameplay refusal.

Methods advertise VARARG metadata because the extension implements Variant calls;
callbacks still enforce exact argument counts and scalar types. Do not expose an
absent typed callback through misleading method metadata.

After a complete view, `advance_delta` returns either `full` or top-level
`changes` and `removed` fields. Merge them before scene readers run. Authority
mutations and actor samples invalidate the comparison base. Every field changed
by World ticking must remain equivalent to full projection, for arrival and
nonarrival profiles. Public `advance` and `projection` return full snapshots.

Construction uses quarter-grid integer centers and declared axes; public
commands, current fields and validation live in Host headers/source and tests.
A gear/shaft's world center and native occupancy must match its presenter and
actor collision. Geometry-derived engagement, signed motion, source flow and
physical endpoints determine operation.

## Shared native profile

Use the complete captured runtime with `opening-session/server.gd --native-world`
and ordinary `shared_opening.tscn` clients, providing the server/client port and
role arguments defined by those scripts. The historical shared scripted profile
is separate when the native option is absent. Its fixed-roster Python launcher
does not prepare the extension.

The native adapter, shared and continuation scripts retain their own typed
observations and exact sources. They exercise different scopes; none alone
proves human usability, internet networking or every moving-world/save case.
Record results and remaining consumer gaps in Beads.
