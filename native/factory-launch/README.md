# Native opening tools

The capture tool copies the complete tracked Godot project from an immutable Git
tree or commit. The startup tool imports a separate runtime copy and starts the
ordinary offline scene in a bounded headless session. Both use the existing
resource admission; neither introduces another game-state authority.

Direct GCC builds and the native capture/copy consumers have passed. Complete
capture, import and ordinary headless startup have also passed with the worker
assets present. The startup CLI has also built and linked through canonical
Bazel. The resume increment passed 62 native controls and an ordinary Store-load
case, preserving the original, incoming and newly published save bytes. Compiled
resource delivery passed 44 native controls. Rendered interaction, actual bridge
ABI loading and shared launcher parity remain unverified; existing mandatory
commands stay active.

## Build and verify

The first supported host is Linux. Bazel is the canonical build interface; the
package composes against the canonical graph owned by `factory-yau.3.17.8`.
Its root configuration and bounded runner remain separately owned.
Use the installed C++ compiler and OpenSSL 3 Crypto headers/runtime, with their
prospective identity seal. There is no dependency download or network operation
in the capture program.

The package exports these explicit targets:

```sh
//native/factory-launch:capture
//native/factory-launch:factory-project-capture
//native/factory-launch:factory-opening-startup
//native/factory-launch:capture_test
//native/factory-launch:opening_test
//native/factory-launch:extension_test
//native/factory-launch:source_budget_test
//native/factory-launch:tests
```

Build the CLI and run the named test through the current
[native build contract](../../docs/engineering/native-builds.md), using one owned
external output base and the reviewed cache-safe supervisor. Declare the exact
commands, applicable host inputs, safe environment and cumulative cache/artifact/
log bounds before admission. Keep source, toolchain and test results associated
with the tested revision. The project-budget update passed the canonical capture
target and focused source-budget target. Earlier direct GCC results retain their
original scope; they are not relabelled as Bazel runs.

The Bazel test finds its declared CLI runfile with `rootpath` and stores its
disposable repositories and intentional alias fixtures under `TEST_TMPDIR`;
the original test result remains in Bazel's retained test log. It refuses a
missing test directory rather than writing into the runfiles tree.
A legacy explicit artifact-parent argument remains available for the
preserved CMake fixture; that plan was never executed and is not a second default
build path. See the [Bazel test contract](https://bazel.build/reference/test-encyclopedia)
and [runfile path variables](https://bazel.build/reference/be/make-variables).

The repository source gate does not compile this C++ implementation.
Native tests create disposable Git repositories and utility children; they do not
invoke a game, engine, live tracker or network socket. Root test-suite integration
and shared build configuration remain the Bazel owner's responsibility.

`source_budget_test` covers 3 MiB and exact 4 MiB captures and runtime copies,
one-byte aggregate overflow, and the unchanged 2 MiB resume-file boundary. Its C++
fixture also invokes the existing staged parser with a disclosed fake executable
to check input admission and byte preservation. That utility does not import
resources or establish actual Godot compilation.

## Capture

Invoke the built program through ordinary resource admission:

```sh
/absolute/owned/build/factory-project-capture \
  --repo /absolute/repository \
  --tree FULL_LOWERCASE_COMMIT_OR_TREE_OBJECT_ID \
  --output /absolute/owned/fresh-capture
```

The repository root and output parent must be canonical existing directories.
The output must be new and external to Git worktrees and administration. Git
discovers ownership at the canonical destination parent, including
bare repositories and separately named administration. Discovery errors refuse
before creating output. Only the pinned Git's ordinary non-repository diagnostic
permits a destination; an unfamiliar diagnostic fails closed.
The tool does not read the private tracker or export ignored/untracked files. It selects
`experiments/engine-environment/godot/` from raw Git objects without checkout
filters, archive exclusions or replacement objects. Working-file changes and
deletions do not change the selected snapshot.

The new directory contains `project/` and a final `capture.json` with the resolved
tree, source modes, blob identities, per-file SHA256 values, byte/script totals and
the actual Git executable hash. Modes are preserved for regular source files.
The manifest is written only after every captured byte is rehashed. A failed write
can leave an owned partial directory for diagnosis; it must not be reused or
represented as a complete capture. Existing outputs are never replaced.

## Bounds and limits

- The current small-project limits are 4 MiB of source, 512 files and 128 `.gd`
  scripts, matching the existing staged project allowance. All tracked resources
  are captured, including scenes and binary assets; this is not a dependency
  parser or permission to load untracked resources.
  The source allowance covers the complete authored project and is separate
  from the unchanged 2 MiB opaque resume-input bound. The staged compiler retains
  its 128 MiB output-family bound, deadline and log limits.
- Symlinks, submodules, private metadata and generated `.godot` caches are refused.
  This first adapter accepts printable ASCII paths. That is a tool limitation,
  not a game-world or permanent asset-naming requirement.
- The explicit `/usr/bin/git` utility is hashed before and after source reads.
  Commands use argument arrays and filtered Git environment overrides, with no
  shell. Raw blob output remains binary. Utility stderr is normally suppressed;
  destination discovery briefly captures bounded combined diagnostics to distinguish
  a non-repository from a discovery error. Those diagnostics are not copied into
  the capture manifest or error message. Refusals
  identify the failed Git operation and exit rather than capturing configuration
  or unrelated diagnostic data.
- Each utility read has at most ten seconds and bounded output. The complete
  capture has a sixty-second deadline checked between operations. Utility failure
  or timeout terminates its owned group and reaps the leader. These cooperative
  deadlines do not promise interruption of blocked filesystem calls or isolation
  from other host activity.
- Closed caller standard streams do not change utility output capture. Pipe
  descriptors are moved above the standard stream targets before child redirects.
- The standalone CLI handles `SIGINT` and `SIGTERM` as cancellation, unwinds its
  current utility child and returns the corresponding signal exit. The library
  accepts a caller-owned cancellation flag and does not replace another caller's
  handlers. Partial output is retained and is never a completed manifest.
- The manifest says `engine_runs: 0`. No import, compiler, renderer, input event,
  native physics, material decision, checkpoint load or save occurs here.

## Headless normal entry

The additive `factory-opening-startup` source composes the capture library and the
unchanged Ops bounded process runner. It retains the raw capture under `project/`
and makes a separate `runtime/project/` copy with the same original bytes and
modes. The worker scene and every other tracked asset are included automatically.
Generated import files may be added only to the runtime tree. Rewriting an original
input during import or startup refuses continuation and preserves the evidence.

The entry requires an explicit repository, immutable object, fresh external
output, engine path, engine SHA256 and existing admission directory. For example:

```sh
python3 -B scripts/run_local.py heavy -- \
  env -i PATH=/usr/bin:/bin LANG=C.UTF-8 \
  /absolute/owned/build/factory-opening-startup \
  --repo /absolute/repository --tree FULL_OBJECT_ID \
  --output /absolute/owned/fresh-startup \
  --godot /absolute/verified/Godot --engine-sha256 FULL_SHA256 \
  --admission /absolute/repository/.git/factory-local-resources
```

The admission directory belongs to the canonical main checkout. The tool writes
`launch-plan.json` before either engine stage, pins the engine before and after
each stage, and invokes only these two commands:

1. Import the captured project with `--headless --editor --import --quit`.
2. Start `res://opening/opening.tscn` with `--headless --quit-after 60` and a
   private save-slot path. No custom script, observer, state fixture or legacy
   profile is injected.

For an existing worksite, add `--resume /absolute/previous.factory`. The launcher
copies that opaque Store binary to a separate read-only `incoming.factory` and
passes the existing `--resume-input` argument to the same ordinary scene. Only
Store decodes and validates the saved state. The original and incoming bytes and
modes are checked before and after both stages. Empty, aliased, changed or
oversized inputs refuse; the current adapter input allowance is 2 MiB. The scene
must publish a fresh `worksite.factory` in the new session before the launcher
reports success. The result records both binary hashes without claiming material
continuation or inspecting game quantities. An invalid Store load fails without
falling back to a fresh world.

The native World bridge may supply a compiled Linux library and its GDExtension
descriptor using these paired options:

```sh
--native-descriptor /absolute/bridge.gdextension \
--native-descriptor-sha256 FULL_SHA256 \
--native-descriptor-relative native/bridge.gdextension \
--native-library /absolute/libfactory_world.so \
--native-library-sha256 FULL_SHA256 \
--native-library-relative native/libfactory_world.so
```

All six options are required together. Platform owns the descriptor contents,
ABI and exact relative paths; these names are illustrative. The launcher preserves
the pristine capture and copies only those two pinned resources into the runtime
tree before import. A descriptor already captured from Git is reused only when
its bytes match. Libraries cannot replace tracked sources, and existing runtime
outputs, aliases, metadata/cache destinations and changed pins refuse. The current
input bounds are 64 KiB for the descriptor and 64 MiB for the library, inside the
existing 256 MiB session limit. Both original inputs and runtime resources are
rechecked around each engine stage. The plan records their paths and hashes.
Before the first import, the launcher also creates a fresh runtime-only
`.godot/extension_list.cfg` containing exactly the pinned descriptor's `res://`
path. Early declaration avoids relying on first-scan discovery for class
registration. Existing caches and aliased generated paths refuse; the catalogue
and its owner-only mode are verified around each stage. Its hash is recorded as
a generated resource, separately from captured sources and external inputs.
The pristine project is unchanged. This is the current single-extension startup
profile, not a game rule or a claim that the underlying importer fault is fixed.
This is resource delivery, without a second World, automatic authority adoption
or evidence that an arbitrary library has the expected ABI. The focused extension
consumer uses invented file bytes and invokes no engine.

The existing runner requires the original heavy/activity permit descriptors and
owns each child group, bounded output, timeout, cancellation and reaping. This is
not another admission layer. Its fixed private environment is reused unchanged
only because this phase is explicitly headless; a rendered desktop route needs an
environment contract. Ops retains its runner source and package ownership; the
library visibility is limited to the native launcher package.

The whole operation has a cooperative 300-second deadline, at most 120 seconds
per engine stage, a 256 MiB owned family and two 4 MiB logs. The caps are adapter
limits, not game requirements or a fresh launch allowance. Any failed stage stops
later execution. Original logs, the pristine capture, runtime copy and final
`startup-result.json` remain. `startup_exited` describes only normal bounded
process exit without strict-error log lines. It establishes neither a native
body observation nor readable visuals, input, gameplay, material, save/resume or
human play.

The new `opening_test` source exercises complete resource copies, binary bytes,
exact modes, generated-cache separation, altered-source refusal, path and metadata
guards, and literal normal-entry commands. It invokes no engine. Both native
consumers have passed, followed by a separate successful two-stage engine startup.
The later resume case separately exercised ordinary Store loading and preserved
the opaque save bytes; it did not test resumed material production. These checks
do not exercise rendered input or multiplayer. Resource limits and the current
desktop-playtesting suspension still govern later tests.

Rendered offline/shared supervision, broader interruption/continuation coverage
and live bridge loading remain unfinished. The single Model, Session and
Store remain unchanged. The normal workflow uses the relevant automated tests and
one independent reviewer; the integrator serializes landing and publication.
Existing mandatory commands stay active.
