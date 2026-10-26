# Local resource admission

```bash
FACTORY_LOCAL="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources/factory-local"
"$FACTORY_LOCAL" --root "$PWD" check -- python3 -B scripts/check.py
"$FACTORY_LOCAL" --root "$PWD" heavy -- BUILD_OR_TEST_COMMAND
"$FACTORY_LOCAL" --root "$PWD" benchmark -- MEASUREMENT_COMMAND
```

Shared cheap checks may coexist with **four heavy slots**. Benchmarks exclude
both. Supported-tool parallelism is **eight jobs per admitted command**.
Heavy/measurement admission requires **20 GiB free disk and 8 GiB available
memory**. These are cooperative operating limits, not reserved capacity or game
targets. Floor changes need a documented resource decision.

The native tool is installed under the common Git directory; all worktrees
share its retained lock files. Legacy Python wrappers retain exclusive heavy
admission and can reduce concurrency. Never unlink live locks or nest wrappers.
The installed commit hook acquires its own permit; do not wrap it or duplicate
its full checks. [Hook configuration](native-builds.md#checks-and-local-hooks).

Ordinary command descendants receive no permit descriptors; the supervisor keeps
admission until the command exits. `--inherit-permits` is only for a verified
consumer such as the bounded native build/fixture/startup runner. Such consumers
must keep Bazel in `--batch` mode so a detached server cannot retain admission.
This does not supervise unrelated detached services.

Options before `--` include `--jobs`, `--disk-floor-gib`,
`--memory-reserve-gib`, `--no-wait` and `--inherit-permits`.
Busy nonwaiting admission or insufficient capacity exits 75 before launch;
argument errors exit 2, wrapper failures 1, child exits pass through, and
signals return `128 + signal`. Cheap checks remain available below the floors.

Keep build outputs, caches and evidence in owned external families with their
declared bounds. Separate compiler and engine resource profiles: a compiler
address-space cap must not accidentally carry into Godot import/startup.
Admission does not require a per-process cap.

## Artifact lifecycle

Beads retains conclusions, revisions and evidence limits; it does not require
permanent copies of every referenced file. Keep only the logs, reproductions and
selected images needed for an active investigation or review. Retire generated
build trees, imported projects, duplicate caches and routine captures when the
run is inactive and its result is recorded. Completed work needs no permanent
failed-run directory or screenshot archive. Preserve the historical failure
outcome rather than relabeling it as a later success. Record retired paths in
the owning Bead or a linked cleanup record so historical references remain clear.

Check running processes, current main/worktree configuration and installed
executable, library and runfile dependencies before cleanup. Never remove live
files or locks. Owners clean their inactive outputs at task completion; coordinate
shared cleanup through Beads. Explicit user-directed cleanup authorizes retiring
obsolete shared artifacts without collecting fresh permission from every former
owner. Current useful playtesting saves may be kept; incompatible development
saves need no migration or retention unless an active bug specifically needs one.

Reuse a bounded cache rather than opening new families whenever one fills.
The default aggregate targets across families are 20 GiB of regenerable outputs
and caches and 5 GiB of diagnostic captures, excluding installed tools and useful
current saves. These are cleanup targets, not weaker admission floors. Retire
unneeded material before allocating another family. Review remaining diagnostic
captures after seven days; an exception must name its owner, active need and
expiry condition in Beads. Keep compact source/result records instead of entire
runtime bundles, and record any necessary temporary budget exception.

Build the tool with `//native/tooling:factory-local`. The host test
`//native/tooling:local_resources_test` accepts a direct or canonically linked
checkout and an owned fixture directory as optional test arguments. Without
them, Bazel's test temporary directory holds a self-contained checkout. Both
routes create a disposable linked worktree and use synthetic permits, not the
real checkout's lanes. Follow [native builds](native-builds.md).

This wrapper does not isolate the whole machine. Record workload/environment
and variation for measurements, and coordinate quiet periods in Beads. It never
authorizes desktop input, kills unrelated processes or proves performance.
