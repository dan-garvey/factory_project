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
`--test_arg=/absolute/linked/checkout --test_arg=/absolute/owned/artifacts`.
Run `//native/gameplay-build:launch_refresh_guard_test` explicitly with
`--test_tag_filters=host` in an admitted host lane to exercise the isolated
gameplay-library freshness guard; the documented
`--test_tag_filters=-host` suite excludes it. This test uses temporary Git repos
and fake build children, without starting Godot or a desktop.
The old `//:native_tests` alias covers only the bootstrap subset.

Keep Bazel in `--batch` mode inside admission. Reuse caches within the verified
toolchain boundary; separate concurrent workspaces/output bases. Never clean
another owner's outputs or evidence. Before replacing a sequential build
workspace, retain needed source, seals, results, binaries and runtime libraries.
Distinguish cached test success from executed tests and analysis from compilation.
Runner ceilings remain 300 seconds, 2 GiB artifacts, 8 MiB logs and eight jobs;
a specific case can require less.

Raw build-event/execution records may expose environment or arguments. Keep
them private with restrictive permissions; do not print or upload them.
Share only an allowlisted, hashed view of source identities, status, timings,
actions/cache counts and approved paths. Preserve original failures and exact
source/toolchain provenance without recasting later hashes as earlier evidence.

## Gameplay installation

`./scripts/build-gameplay.sh` builds and installs the native gameplay library;
`--startup` selects the startup executable. See
[one-time configuration](../../native/gameplay-build/README.md).
The Windows shortcut prepares stale components automatically; `--prepare-only`
does so without launching, and `--check` only checks installed pins.
Branch builds do not install into the current-main human launcher.
A plain Bazel build only produces artifacts.

## Checks and local hooks

Run `./scripts/install-hooks.sh` once. The hook validates the exact staged
tree, rejects private tracker paths, checks source/compiler results and fails
if the index changes. Do not wrap `git commit` or either coordinator in another
admission command, auto-stage fixes, or bypass a failure. Run relevant consumer
checks; do not duplicate the hook's suite for unchanged inputs.

Optional repository-local `factory.commitGateExecutable` and
`factory.commitGateSHA256` select a retained verified native coordinator.
Both absent retain the existing Python coordinator; partial/invalid settings,
changed hashes or native failure refuse without fallback.

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
