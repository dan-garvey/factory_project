# Native builds with Bazel

Bazel is the user-directed build system for migrated native code. This first
graph began with the reviewed finite material foundation and now also exposes
typed values, authority, geometric mechanics, stationary edits, logical
World/checkpoints and native project/compiled-resource capture. It does not replace installed commit gates or activate
a native game authority. Further package/gate integration belongs to the
continuing migration in `factory-yau.3.17.8`.

The corrected local validation completed on 2026-10-20 using the reviewed graph
and bounded runner. It exercised a cold build, a no-action cache hit, relevant
source/header/test/option invalidation, visible compile/test failures and cache
reuse from a separate worktree. The runner passed 40 native controls. These are
component results, not game activation or a measured end-to-end commit speedup.
The earlier incomplete bootstrap and failed setups retain their original limits.

## Pinned inputs and host boundary

Use Bazel **8.4.2**, as recorded in `.bazelversion`. The official Linux x86-64
executable is available from
[the Bazel release host](https://releases.bazel.build/8.4.2/release/bazel-8.4.2-linux-x86_64).
Verify its SHA-256 before executing it:

```text
4dc8e99dfa802e252dac176d08201fd15c542ae78c448c8a89974b6f387c282c
```

`MODULE.bazel` selects the C++ rules. Commit the generated `MODULE.bazel.lock`;
normal commands use `--lockfile_mode=error`, so dependency-resolution changes
need an explicit reviewed lock update. Do not use an unpinned rolling tool or
download dependencies inside a test.

This increment uses the existing Linux GCC 11 toolchain at `/usr/bin/gcc-11`
and `/usr/bin/g++-11`, with the host linker, runtime libraries and system
headers. It is an explicitly **host-dependent** toolchain, not a hermetic SDK or
a portability result. Accepted evidence must record their actual hashes and
versions. Do not reuse results after changing the host toolchain or its headers
without a new toolchain seal and an isolated output/cache namespace. Automatic
host-fingerprint enforcement belongs to the native validation integration;
these BUILD files do not implement it.

## Commands and ownership

Set `FACTORY_BAZEL` to the absolute verified executable and
`FACTORY_BAZEL_ROOT` to an absolute, owned external build directory. Keep
outputs outside every source checkout and the private Beads directory.

```bash
python3 -B scripts/run_local.py heavy -- \
  env -i PATH=/usr/bin:/bin HOME="$FACTORY_BAZEL_ROOT/home" LANG=C.UTF-8 \
  "$FACTORY_BAZEL" --nosystem_rc --nohome_rc --batch \
  --host_jvm_args=-Xmx1024m \
  --output_user_root="$FACTORY_BAZEL_ROOT/output" \
  test --repository_cache="$FACTORY_BAZEL_ROOT/repositories" \
  --disk_cache="$FACTORY_BAZEL_ROOT/actions" \
  --build_tests_only --test_tag_filters=-host //native/...
```

The existing Python admission command remains in use until its independently
reviewed native successor takes over. This adds no Python implementation.
Do not wrap `check_commit.py` or `git commit` in another admission command.
The installed hook remains the single mandatory staged check. Run relevant
behavior tests as needed, without repeating passing checks for unchanged inputs.

Create the private, empty child home inside the owned family before launch. The
environment above is an explicit allowlist, rather than the parent shell's
environment. Keep required tool and cache paths in the sealed command. Do not
forward account tokens, passwords, credentials or unrelated environment values
to Bazel, its repository rules or its actions. Add a required variable only after
reviewing its purpose and capture behavior; never print its value as a probe.
This prospective command guidance is not evidence that the original bootstrap
used an allowlisted environment.

`--batch` keeps the Bazel JVM in the admitted process lifetime instead of
starting a detached server. Local repository and action caches persist between
invocations. The output root contains separate Bazel output bases derived from
each canonical workspace path, so linked worktrees do not share a mutable
execution directory. A cache shared across worktrees must stay within the same
verified toolchain boundary. Never point two concurrent workspaces at an
explicitly identical `--output_base`.

For sequential tasks, prefer one owned canonical build workspace. This can be a
clean Git worktree on a fresh current-main branch or a private source staging
directory. A new staged-copy path also creates another output base, even when
the authoring worktree and caches are reused. Keep concurrent writers in
separate workspaces.

Before reuse, retain the prior raw-Git archive, seals, results and any binaries,
required project shared libraries or runfiles outside mutable build outputs;
keep their runtime layout and consumer references valid. A copied executable
alone may still depend on libraries in the old output base. On Linux, the ELF
loader's `--list` mode checks dependency resolution without executing test main;
reuse the original passing tests when only verifying the retained copy.
Finish prior operations and readers before replacing staged source. If a
consumer still needs an output in place, preserve that workspace. Seal and verify
each new candidate before and after its invocation as usual. Reuse preserves
dependency invalidation, toolchain isolation and resource limits.

The first targets are:

| Target | Purpose |
| --- | --- |
| `//native/factory-core:materials` | Typed finite material library |
| `//native/factory-core:materials_test` | Original logical material tests |
| `//native/factory-core:material_case` | Separate finite headless consumer |
| `//:native_tests` | Focused bootstrap suite: materials and tree metadata |
| `//:material_demo` | Alias for the material consumer binary |

The canonical native test command selects `//native/...` with
`--build_tests_only --test_tag_filters=-host`. New package tests join this
selection automatically. It covers the migrated material/recovery, authority,
mechanics, World, value-adapter, terminal-fixture and asset tests. Use a relevant
package target for focused iteration; Bazel can reuse unchanged actions. The
older `//:native_tests` label retains its bootstrap scope and reports a
deprecation warning directing callers to the complete command.

Linux host integration tests retain their separate fixture requirements:
`//native/build-support:runner_test`, `//native/factory-launch:tests` and
`//native/tooling:local_resources_test`. These six tests exercise host processes,
namespaces, filesystem capture or admission. The admission test takes an actual
canonically linked checkout and an owned external artifact root after its
declared CLI argument; supply them as
`--test_arg=/absolute/linked/checkout --test_arg=/absolute/owned/artifacts`.
Select these host tests explicitly for their relevant changes.
Mark new tests that require host integration fixtures with the `host` tag.

The C++ sources retain their independently reviewed component bytes. Their
historical CMake files remain attributable; those old builds do not establish
the new Bazel graph or its cache behavior.

## Incremental results and acceptance

Do not clean the output tree for every change. Bazel uses declared source,
header, dependency and command inputs to decide which actions to repeat.
Public headers are explicit library inputs, and test sources are separate from
the production library. Compiler options belong to the action configuration.
The immutable module lock and configuration are review inputs too.

Build Event Protocol and execution records can contain the complete client
environment, command-line representations and action environments. Treat raw
records as restricted evidence: create the owned evidence directory with mode
0700 and new evidence files with a restrictive umask before launch. Never print,
search into shared output, attach or upload raw records. File permissions do not
isolate agents sharing the same operating-system user and cannot retract output
that has already been displayed.

Before review, produce a separately hashed, allowlisted view containing only
the invocation identity, start and finish times, original exit and test status,
action/cache counts, approved source paths and input digests. Omit all environment
and command-line representations, free-form progress, option dumps and unknown
fields. Bind each view to its original file hash and retain the originals without
changing their bytes. Check the view and intended handoffs for the known captured
values without printing them. This narrow check is not a general secret audit.
The single independent reviewer uses the safe views and checks this capture and
reader boundary; no separate privacy or receipt approval is added. Reviewers do
not inspect raw records to locate a matching line. Existing raw evidence does not become safe merely because a
later launch uses an allowlist.

Distinguish a cached successful test from a test that actually executed, and a
build that completed analysis from a build that compiled anything. A failing
compile or test remains a failure even when unchanged prerequisites came from
the cache. Cache reuse is evidence about the exact actions, not permission to
skip the installed gates or validate different mutable source.

For review, seal the exact raw-Git source and toolchain before the build, retain
the original command and status, and verify that the source is unchanged after
it. Normal mutable development commands are not an immutable staged acceptance
gate. The native gate replacement in `factory-yau.3.17.4` must preserve that
boundary through its relevant tests before replacing the installed checks.
Authors own checked current-main joins and publication; independent review
follows merge under [AGENTS.md](../../AGENTS.md).

The first bootstrap retained source, Bazel, flags and action results but omitted
the original host compiler, linker, runtime and header identity seal. That is an
unresolved evidence limitation, not proof of toolchain drift or incorrect output.
A later readback cannot establish which toolchain bytes the earlier actions used.
Keep the original outcomes and this limitation explicit for independent review;
do not replay the consumed campaign or label a later hash as a prelaunch pin.

## Resource and cache limits

The first bootstrap campaign uses one cumulative **2 GiB** external family for
the pinned tool, repository archives, output bases, action cache and evidence,
with **8 MiB** stage logs. The original one-heavy admission, eight-job limit,
20 GiB free-disk floor and 8 GiB available-memory floor remain in force. The
existing bounded child helper monitors the complete family during acceptance
campaigns and retains first failures. These limits are operational settings.

A later metadata-component invocation stopped when that helper's directory scan
encountered a concurrently removed Bazel cache directory. Its outer result remains
a failure. The existing scanner is not a proven race-safe Bazel cache supervisor;
resolve that native supervision boundary before another campaign that mutates the
same monitored cache. Do not bypass monitoring or retry to obtain a passing run.

The [native build runner](../../native/build-support/README.md) supplied the
reviewed correction used by the completed follow-up validation. It does not
replace installed admission or commit checks. Native campaigns bind applicable
compiler, linker, runtime and header identities before execution and check those
identities before trusting cache reuse. The old incomplete campaign and restricted
records stay unchanged. The ordinary relevant-tests/one-reviewer rule applies;
declaring a bounded command is resource planning, not a separate plan approval.

The first prospective setup compiled that runner successfully, then failed during
Bazel package loading before any configuration case ran. An all-host URL block
removed an archive's original basename; the pinned downloader returned a valid
cache hit under an extensionless synthetic name, which archive extraction refused.
The separately preserved source correction retains ordinary archive URLs, combines
`--repository_disable_download` with a block on `bcr.bazel.build`, and explicitly
pins `--registry=https://bcr.bazel.build`. The registry path ignores the repository
download-disable flag, so the flag alone does not preserve the offline contract.
Alternative registries and mirror overrides are excluded by the sealed command
and dependency/source review. A checksum-cache miss must refuse; this is not a
whole-host network sandbox. The correction does not turn the failed setup into a
pass or authorize reuse of the stopped campaign's remaining cases.

Batch mode has no idle server to perform background cache collection. Check
the complete family before a new command; a full cache is a resource decision,
not permission to delete another worktree's output or evidence. Do not silently
start a fresh family to escape a limit. A future shared development-cache
manager must pass the relevant tests and preserve these resource and evidence
contracts before replacing this bounded arrangement. Independent review follows
the same post-merge policy.

This increment uses local execution and local caches. Remote execution, remote
caches, paid services, performance claims and automatic retirement of the old
gates are outside its scope. Report cold and warm timings from the same machine
and workload, including the unchanged mandatory checks when discussing the
whole validation cycle. Compilation reuse alone is not a measured reduction
in end-to-end commit latency.

References: [Bazel dependencies](https://bazel.build/external/overview),
[cache action inputs](https://bazel.build/remote/caching) and
[output directory ownership](https://bazel.build/remote/output-directories).
