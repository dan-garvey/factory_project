# Native commit coordinator

`factory-commit-check --root CHECKOUT` captures the exact staged tree and obtains
one native check/heavy permit. The existing immutable staged checker still owns
source tests, raw-blob export, index guards and required Godot parsing. For a
native, shared Bazel or root-package Bazel data change, the admitted worker then exports raw Git
objects into a private bounded snapshot and runs offline Bazel reverse-dependency
queries, affected builds and tests from that snapshot. It requires one passing
Build Event Protocol summary per selected test. A temporary `GIT_INDEX_FILE`
remains effective throughout.

The coordinator reads the root `BUILD.bazel` from the staged tree before
admission. A changed file named as a root-package Bazel input seeds its exact
label, so the launcher guard scripts reach their native host consumers.
Unreferenced scripts and ordinary prose do not select the native lane.

[Configuration and limits](../../docs/engineering/native-builds.md#checks-and-local-hooks)
are shared with the legacy coordinator. Optional repository-local
`factory.commitGateExecutable` and `factory.commitGateSHA256` must both be valid;
both absent preserve the existing coordinator. Invalid pins or native failure
never fall back to another checker.

The native coordinator prefers worktree-specific `factory.godotArtifacts`,
then the common local setting. An empty value or read error refuses.
Engine/executable hashes remain shared. Do not wrap the hook in another
admission command.

Native validation similarly prefers worktree-specific `factory.nativeArtifacts`
and `factory.nativeOutputBase`, then their common local settings. One fixed
output base is reused across temporary staged paths in a checkout; separate
concurrent checkouts should use separate families and bases. The Bazel executable
and SHA256 pin are common repository-local settings. The artifact family is
external, owned and mode 0700;
it holds the offline dependency distdir, bounded cache, private logs and only
temporary staged snapshots. A cache or dependency miss refuses. The worker
records compiler/linker hashes and installed toolchain package versions and
uses that key in C++ action flags. The host SDK is still not hermetic; package
identity is the supported cache boundary, not a proof of arbitrary untracked
header bytes.

The executable fixes `/usr/bin/git` and `/usr/bin/python3` and exposes no
public command, interpreter or resource-floor override. Git metadata reads have
a five-second deadline and 2 MiB bound. The worker uses bounded raw-blob reads
for the staged snapshot. Host fixtures and scripted checks do not establish
human gameplay acceptance.
