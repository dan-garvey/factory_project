# Build, validate and publish

## Native builds

Use Bazel **8.4.2** from `.bazelversion`; the official Linux x86-64 binary's
SHA-256 is `4dc8e99dfa802e252dac176d08201fd15c542ae78c448c8a89974b6f387c282c`.
`MODULE.bazel`, its committed lock and `.bazelrc` own dependencies and options.
Normal builds require `--lockfile_mode=error`. The Linux toolchain uses
`/usr/bin/gcc-11` and `/usr/bin/g++-11`, host linker, libraries and headers;
it is not a hermetic SDK. Record their identities for acceptance and isolate
caches when that toolchain changes.

Use an owned external artifact/cache family, a verified Bazel executable and
the built [bounded runner](../../native/build-support/README.md).
The runner sanitizes the child environment and owns timeout/log/artifact limits.
Substitute existing absolute paths:

```bash
FACTORY_ADMISSION="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources"
FACTORY_BAZEL_ROOT=/absolute/owned/build-family
"$FACTORY_ADMISSION/factory-local" --root "$PWD" heavy --inherit-permits -- \
  /absolute/verified/factory-build-run \
  --artifacts "$FACTORY_BAZEL_ROOT" --log "$FACTORY_BAZEL_ROOT/fresh-build.log" \
  --admission-directory "$FACTORY_ADMISSION" --accounting-mode owned-user -- \
  /absolute/verified/bazel-8.4.2 --nosystem_rc --nohome_rc --batch \
  --host_jvm_args=-Xmx1024m --output_user_root="$FACTORY_BAZEL_ROOT/output" \
  test --repository_cache="$FACTORY_BAZEL_ROOT/repositories" \
  --disk_cache="$FACTORY_BAZEL_ROOT/actions" \
  --repository_disable_download --registry=https://bcr.bazel.build \
  --downloader_config="$PWD/native/build-support/offline-downloader.cfg" \
  --build_tests_only --test_tag_filters=-host //native/...
```

Provision verified dependency cache entries first; a miss must refuse, not fetch.
The registry selection, downloader configuration and download-disable flag work
together; they are not a whole-host network sandbox. Review pinned dependencies.
The owned-user accounting mode needs Linux user-namespace support and refuses
rather than omitting unreadable cache directories.

Use a relevant package target for focused work. Host-tagged tests need explicit
fixtures; for `//native/tooling:local_resources_test`, supply
`--test_arg=/absolute/checkout --test_arg=/absolute/owned/artifacts`.
The checkout may be direct or canonically linked; the test also creates its own
disposable linked worktree to check shared Git discovery. When the installed
hook selects this test without arguments, it uses Bazel's owned test directory
for a self-contained checkout fixture.
Run `//native/gameplay-build:launch_refresh_guard_test` explicitly with
`--test_tag_filters=host` in an admitted host lane to exercise the isolated
gameplay-library freshness guard; the documented
`--test_tag_filters=-host` suite excludes it. This test uses temporary Git repos
and fake build children, without starting Godot or a desktop.
The old `//:native_tests` alias covers only the bootstrap subset.

The repository's [native CI workflow](../../.github/workflows/native.yml) runs
on Ubuntu 22.04 with installed GCC 11 and OpenSSL headers. It downloads the
`.bazelversion` 8.4.2 binary only after checking the committed SHA-256 above,
prints the source revision and toolchain versions, and lets the Bazel module
lock govern `rules_cc`. Its first lane builds and runs all non-host
`//native/...` tests. Its host lane runs host tests separately, then the two
local commit-gate tests and `local_resources_test` with an owned temporary
fixture root. Those local tests are explicit because the resource test needs
two path arguments that the other tests must not receive. A failed compile,
nonzero selected test, or changed lock stops the job; GitHub retains the
selected target names and failing output in the job log. This CI lane is
not a Godot import, rendered scene, performance, or human-play result.

The same workflow runs ASAN and UBSAN over World transaction/checkpoint and
Host adapter/press/harvest consumers with debug symbols, frame pointers and
leak detection. It allows 180 seconds per sanitizer test rather than the
ordinary 30-second Bazel timeout. TSAN is excluded from this lane because
these production consumers do not create threads or share mutable state
between threads; the current native process supervisors use fork/wait, while
`std::this_thread::sleep_for` is only a wait. Revisit that exclusion if a native
consumer gains actual concurrent access. CI uses two Bazel jobs on its fresh
hosted runner; the local admission floors and bounded runner below still
govern developer-host checks.

Keep Bazel in `--batch` mode inside admission. Reuse caches within the verified
toolchain boundary; separate concurrent workspaces/output bases. Follow the
[artifact lifecycle](local-resources.md#artifact-lifecycle) when retiring inactive
outputs. Keep compact source/result records and any binaries, shared libraries
and runfiles still needed by installed tools or an active investigation/review;
completed build workspaces and duplicate caches need not be preserved.
Distinguish cached test success from executed tests and analysis from compilation.
Runner ceilings remain 300 seconds, 2 GiB artifacts, 8 MiB logs and eight jobs;
a specific case can require less.

Raw build-event/execution records may expose environment or arguments. Keep
them private with restrictive permissions; do not print or upload them.
Share only an allowlisted, hashed view of source identities, status, timings,
actions/cache counts and approved paths. Preserve the recorded failure outcomes
and source/toolchain provenance without recasting later hashes as earlier evidence.
Raw logs and bulky captures may expire under the artifact lifecycle.

## Gameplay installation

`./scripts/build-gameplay.sh` builds and installs the native gameplay library;
`--startup` selects the startup executable. See
[one-time configuration](../../native/gameplay-build/README.md).
The tracked Windows shortcut locates its own clean main checkout and prepares
stale components automatically; `--prepare-only` does so without launching,
and `--check` only checks installed pins. `--resume ABSOLUTE_SAVE` opens a
native save in a fresh session. `--prepare-session-only` runs capture, import
and startup without a desktop window and retains their exact records.
Branch builds do not install into the current-main human launcher.
A plain Bazel build only produces artifacts.
The committed `native/gameplay-build/production-paths.txt` is the shared
startup/gameplay freshness inventory. The installer checks Bazel's local source
and BUILD dependency labels against it before compiling; new transitive
packages must be declared there before installation.

### Native package roles

The product entrypoints are `//native/factory-launch:factory-project-capture`,
`//native/factory-launch:factory-opening-startup` and
`//native/factory-godot-world:factory-native-world.so`. Their Bazel dependency
closure identifies native product packages; the committed
`production-paths.txt` above owns the source inventory admitted for installation.
Check both when adding a production dependency.

The commit gate, gameplay installer, local tooling, Godot fixture runner,
validation manifest and asset/foliage preparation packages provide delivery,
test or offline art tools. The build-support runner also serves the product
startup. Other mechanics workbenches, repair scenarios and focused native
experiments remain selectable research and historical test consumers. Their
presence under `native/` does not put them in the captured game, and absence
from the product closure does not establish that their source is disposable.
Use the owning Beads when changing their lifecycle.

World, Host, opening-engineering and several delivery packages now default to
private Bazel visibility, with explicit grants for their actual external
consumers and public product entrypoints. Independent experiment packages
retain broader visibility where workbenches compose targets across packages;
check reverse dependencies before narrowing another target.

## Checks and local hooks

Run `./scripts/install-hooks.sh` once. The hook validates the exact staged
tree, rejects private tracker paths, checks source/compiler results and fails
if the index changes. Do not wrap `git commit` or either coordinator in another
admission command, auto-stage fixes, or bypass a failure. Run relevant consumer
checks; do not duplicate the hook's suite for unchanged inputs.

The same hooks path enables `commit-msg`, which rejects empty or whitespace-only
messages, including with `--allow-empty-message`. It checks the final message
after the editor without rewriting it; literal comment characters remain valid.

Optional repository-local `factory.commitGateExecutable` and
`factory.commitGateSHA256` select a retained verified native coordinator.
Both absent retain the existing Python coordinator; partial/invalid settings,
changed hashes or native failure refuse without fallback.

For native staged changes, configure the pinned offline Bazel executable and
an owned external mode-0700 artifact/cache family before installing the new
coordinator. Put verified dependency archives needed by Bazel in that family
for its local `--distdir`; download-disabled queries and builds refuse on a miss.
The native worker uses one inherited heavy permit and a bounded 300-second,
2-GiB-artifact, 8-MiB-log runner per query/build/test command:

```bash
git config --local factory.nativeBazelExecutable /absolute/verified/bazel-8.4.2
git config --local factory.nativeBazelSHA256 VERIFIED_LOWERCASE_BAZEL_SHA256
git config --local factory.nativeArtifacts /absolute/owned/native-gate-family
install -d -m 700 /absolute/owned/native-gate-family/output/native-gate-base
git config --local factory.nativeOutputBase /absolute/owned/native-gate-family/output/native-gate-base
# With extensions.worktreeConfig=true, a linked checkout may isolate its cache:
install -d -m 700 /absolute/owned/this-worktree/native-gate-family/output/native-gate-base
git config --worktree factory.nativeArtifacts /absolute/owned/this-worktree/native-gate-family
git config --worktree factory.nativeOutputBase /absolute/owned/this-worktree/native-gate-family/output/native-gate-base
```

The gate queries the staged Bazel graph for reverse dependencies of changed
native packages or root-package file data declared in the staged root BUILD,
builds every selected C++ target and requires a passing Bazel
event summary for every selected test, including cached and host-tagged tests.
A host test needing undeclared runtime arguments will fail this lane until its
target contract is repaired; it is not silently excluded.

Staged GDScript requires the pinned `4.7.2.stable.official.ed1daf0bf` engine:

```bash
git config --local factory.godotExecutable /absolute/verified/Godot_v4.7.2-stable_linux.x86_64
git config --local factory.godotSHA256 VERIFIED_LOWERCASE_EXECUTABLE_SHA256
git config --local factory.godotArtifacts /absolute/owned/compiler-artifacts
```

The native coordinator can use a per-worktree artifact destination:

```bash
git config --local extensions.worktreeConfig true
git config --worktree factory.godotArtifacts /absolute/owned/this-worktree/compiler-artifacts
```

Engine/digest pins remain shared. Import precedes `--check-only` for every staged
project script; import alone is insufficient. Error/parse/resource-loader lines
fail even with exit zero. Current limits: 64 MiB source, 512 files, 128 scripts,
128 MiB output family, five minutes and 8 MiB logs. Only the tracked Godot project
is supported; staged symlinks/submodules are refused. These are tool limits, not
game requirements. The gate does not prove runtime behavior or human play.

## Executable consumer lanes

Select the lane that exercises the changed consumer. Run local checks under
[resource admission](local-resources.md), with owned artifacts and the pinned
tools in the recipes above. Keep a source revision, exact selection, exit status
and completion log; a successful command alone does not prove a different lane.
The installed hook checks the staged tree as well as the relevant local runs.
For the tooling command below, set `FACTORY_LOCAL` as shown in the
[admission recipe](local-resources.md).

| Lane | Select | Require for a pass | Evidence limit |
| --- | --- | --- | --- |
| Tooling and source | `"$FACTORY_LOCAL" --root "$PWD" check -- python3 -B scripts/check.py`, or the installed hook on the staged tree | All selected tests pass, none skip, source parsing succeeds, and exit is zero; the staged hook also rejects index changes and private tracker paths. | Source and tooling only. |
| Native behavior | The admitted Bazel `//native/... --test_tag_filters=-host` recipe above, a focused affected target, or the installed hook's affected-target selection | Selected targets build and every selected test reports pass, including cached results; require the hook's Bazel event summary when it selects native tests. A query, build, test or changed lock failure refuses. | Native contracts; no scene or rendering. |
| Host installation | Under heavy admission, select `//native/gameplay-build:install_test` and `//native/gameplay-build:launch_refresh_guard_test` with the same bounded Bazel recipe, omitting `--test_tag_filters=-host`. CI also runs its separate `host,-local` lane. | Both local targets report pass and exit zero; a skipped target or incomplete install/refresh test is not a pass. | Installation and freshness guards without starting Godot or a desktop. |
| Headless scene | Build `//native/godot-fixture:factory-godot-fixture`, import the source-matched Godot project, then run a registered `--case`, such as `arrival-raised-starter-snap`, with its required arguments and fresh private output paths. See the [fixture guide](../../native/godot-fixture/README.md). | Require the case's complete revision-matched success line, zero exit, no engine/script/parse/load errors, and required native output; omitted or conflicting arguments refuse before launch. | Scripted scene events with substituted actor choices; no rendered quality or human play. |
| Rendered motion | Use the tracked `./scripts/launch-factory-latest.sh --agent-window --test-purpose="Machine motion check" --script res://opening/machine_visual_test.gd -- --batch-motion-check` on checked clean main. Other visual fixture modes and companion arguments are listed in the [fixture guide](../../native/godot-fixture/README.md). | Require zero exit, the complete `MACHINE_BATCH_MOTION_PASS 41` line, an actual renderer, and no engine/script/parse/load errors. Inspect relevant pixels for a visible change; keep the revision and view conditions. Benchmark metric lines prove only that their diagnostic route finished. | Passive GPU fixture evidence; no ordinary input or human-play acceptance. |

Run the Chapter 1 cog sequence as three named cases, each in a fresh process:

1. `arrival-first-plate`: pass `--native-check-mode=arrival-first-plate`,
   `--event-route-pointer` and `--native-check-output=FIRST_RESULT`. This writes
   `FIRST_RESULT.worksite`.
2. `arrival-cog-repair`: pass `--native-check-mode=arrival-cog-resume`,
   `--resume-input=FIRST_RESULT.worksite`, `--native-check-output=COG_RESULT`
   and `--save-slot=COG_SESSION`. This writes `COG_RESULT.final.worksite`.
3. `arrival-cog-reopen`: pass `--native-check-mode=arrival-cog-finish-resume`,
   `--resume-input=COG_RESULT.final.worksite`,
   `--native-check-output=REOPEN_RESULT` and `--save-slot=REOPEN_SESSION`.

Put those arguments after the runner's `--` separator. Use fresh absolute
result and save-slot paths inside the owned fixture artifact directory, and a
fresh log for each admitted run. `--list-cases` prints each script, argument
contract, deadline and exact completion marker. A passing cog log also reports
`status: pass` and a positive check count; the count can vary with physical
scene timing. These runs prove scripted scene and native save continuity only.

For the scene runner, use its bounded log and admission arguments rather than a
raw Godot invocation. For a graphical run, the tracked launcher prepares a
source-matched native library and labels the window. Neither fixture supplies
desktop interaction; keep ordinary use, performance and human-play findings in
their own records.

## Human visual review

Factory Proof Desk runs on Windows; its C++ WSL bridge owns immutable proof
bundles, Beads records and exact-thread feedback. No additional API key or hosted
review service is needed. The local Codex daemon must be running. Images, clips, annotations and
thread identifiers remain private in the configured Windows-local store.

Start with [the JSON example](../../native/proof-desk/example-proof.json). Each
required case declares its acceptance criteria, view conditions and media.
Use `stage: "direction"` for sketches or independent renders. A `final` bundle
requires a clean committed candidate, its approved `direction` proof ID, and
actual `after` evidence; existing elements also require `before` media. Keep all
required direction cases. `previous` links a replacement revision. A small
correction can reference a prior approved proof with `minor_correction: true`
and a `direction_reason`; this still requires final human approval.

`./scripts/proof.sh submit --manifest /absolute/proof.json` binds the proof to
`CODEX_THREAD_ID` and the owning Bead's assignee. End the turn immediately after
submission. The native bridge pauses an active goal under the user's review
policy; no model polling loop runs. The Windows review decision queues notes,
original images and marked frames as a user message to that exact thread, then
resumes only the goal it paused. Clip paths and timestamps accompany marked
frames. Budgets and unrelated goals remain unchanged. A delivery uncertainty
requires a matching user-message receipt before any retry can succeed.

The viewer keeps drafts until Send, and cannot approve a bundle with missing or
unapproved cases. A bundle allows 64 media items, including at most 32 images;
feedback allows 32 annotations. Split larger changes into bounded reviews.
Retain media while its approval is needed; missing or altered media invalidates
approval. Follow the existing artifact lifecycle after integration and review.

Build `//native/proof-desk:factory-proof` and run its two Bazel tests. On Windows,
configure `native/proof-desk/CMakeLists.txt` with MSVC 2022 and the Qt SDK pinned in
`qt-sdk.json`, build Release, and deploy dynamic dependencies with `windeployqt`.
The viewer reads `%LOCALAPPDATA%/FactoryProofDesk/config.json`: `store` is a local
Windows path, `distro` selects WSL, and `root`/`bridge` are absolute Linux paths.
Initialize the bridge with `factory-proof init --root REPO --store /mnt/c/...`.
Repository configuration pins `factory.proofExecutable`/`factory.proofSHA256`
and `factory.proofViewer`/`factory.proofViewerSHA256`. Agent viewer launches use
`scripts/launch-proof-desk.sh --test-purpose=TEXT`; `--fixture`, `--capture` and
`--self-test` provide passive, isolated checks, not human usability evidence.

After human acceptance of the installed tool, set `factory.proofRequired=true`.
The reference-transaction hook blocks unapproved changes before `main` moves;
pre-push is a second check. Approval is tied to the complete declared source
inputs, permitting unchanged disjoint joins. Native C++ changes require either
visual evidence or `declare-nonvisual --manifest FILE`, whose JSON declares the
owned `bead`, `actor`, exact `paths` and a concrete `reason`. Known visual files
cannot use that declaration. Existing compiler, test and code-review gates stay
in force. Never generate a human decision to satisfy a gate.

## Publish

Follow [AGENTS.md](../../AGENTS.md) for ownership and independent review.
Resolve current-main joins and validate affected behavior in your own worktree.
An uncommitted disjoint change can move to a fresh branch from current main after
verifying staged blobs; committed work normally merges main instead of rebasing.

Only the canonical main update and push hold the shared lock:

```bash
factory_common_git=$(git rev-parse --path-format=absolute --git-common-dir)
factory_tested_commit=$(git rev-parse HEAD)
flock --timeout 30 "$factory_common_git/factory-main-landing.lock" \
  bash -c '
    set -euo pipefail
    landing_checkout=$1
    landing_commit=$2
    test "$(git -C "$landing_checkout" branch --show-current)" = main
    test -z "$(git -C "$landing_checkout" status --porcelain)"
    git -C "$landing_checkout" merge --ff-only "$landing_commit"
    git -C "$landing_checkout" push origin main
  ' factory-land /home/dan/factory_project "$factory_tested_commit"
```

Do not build, test or wait for review under this lock. If main advances, is dirty,
or push refuses, reconcile in your own checkout; never force, reset or stash
someone else's changes. Open the required review request, record the landed
revision and limits in Beads, flush its export and inspect Git status.
