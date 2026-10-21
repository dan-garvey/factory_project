# Cooperative local resource admission

Use the wrapper from any checkout of this repository:

```bash
FACTORY_LOCAL="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources/factory-local"
"$FACTORY_LOCAL" --root "$PWD" check -- python3 -B scripts/check.py
"$FACTORY_LOCAL" --root "$PWD" heavy -- <build-or-test-command>
"$FACTORY_LOCAL" --root "$PWD" benchmark -- <measurement-command>
```

For commits, let the installed precommit hook select the locally pinned native
coordinator or `python3 -B scripts/check_commit.py` once. A manual run is optional
diagnostics, not an additional required check before the hook. It captures the staged tree
and takes one permit: check for non-GDScript changes, heavy for staged `.gd`
changes requiring the pinned compiler. It fails if staging changes before or
during validation. Do not wrap the coordinator or `git commit`, and do not call
another resource wrapper inside their checks. `check.py --staged` refuses game
changes without the explicit compiler path; it cannot silently run Godot under
a cheap permit. Runtime selection and retained compiler diagnostics are described
in [CONTRIBUTING](../../CONTRIBUTING.md#checks-and-local-hooks).

Cheap checks can coexist with each other and up to four heavy commands. Each
heavy command holds one of four slots. A benchmark excludes all wrapped checks, heavy commands, and
other benchmarks until its child exits. Locks live in the common Git directory,
so linked worktrees cooperate. Lock files are retained; never unlink them while
commands might be using them. Do not nest wrappers against the same repository.

Heavy and benchmark commands check the checkout filesystem's free disk and
Linux `MemAvailable` after admission. Initial settings are an eight-job budget,
20 GiB free-disk floor, and 8 GiB available-memory reserve. These are operational
settings for the current machine, not game targets or workload memory estimates.
The four-slot default is the user's operational choice for the current demo,
not a measured guarantee for every workload or GPU. Jobs remain eight per admitted
command; four commands can therefore request up to 32 supported tool jobs.
Foreground ownership and the suspension of agent desktop playtests still apply.
Cheap checks remain available below the floors for diagnosis. Override settings
with `--jobs`, `--disk-floor-gib`, and `--memory-reserve-gib` before `--`.

Choose separate compiler and engine resource profiles when a command includes
both. An optional compiler virtual-address-space cap must not carry into a
Godot import or startup unless that memory limit is itself under test. Shared
admission requires the disk and available-memory floors; it does not require a
per-process virtual-address-space cap. Retain the workload's deadlines,
artifact/log bounds and owned-process cleanup under either profile. If an
inherited cap prevents useful engine validation, preserve the first failure and
record the engine-profile correction in the owning task. Reuse passing
compilation for unchanged inputs; no new PM approval is required.

The child receives `CMAKE_BUILD_PARALLEL_LEVEL`, `CARGO_BUILD_JOBS`, and
`CTEST_PARALLEL_LEVEL` set to the selected jobs value, replacing inherited values.
Explicit tool flags and other tools can exceed that budget. Available memory
and disk can change after admission; the wrapper does not reserve bytes.

By default admission waits. Use `--no-wait` for a scheduler that should defer
instead of queueing work. Busy admission or a floor failure exits 75, without
starting the child. Other wrapper errors exit 1, argument errors exit 2, and
normal child exit codes pass through. A failed child releases admission. The immediate child inherits the
lock descriptors, but detached descendants are not a supported workload model.

This is cooperative coordination, not machine isolation. Unwrapped commands,
other repositories, background services, and host activity are unaffected.
Agree quiet periods before measurements and record the environment and observed
variation. The wrapper never deletes artifacts, kills unrelated processes,
changes host settings, or proves benchmark-quality isolation.

The native executable is installed at
`<common-git-dir>/factory-local-resources/factory-local`. Existing Python commands
retain exclusive legacy heavy admission. A locally pinned native commit
coordinator uses one native slot while preserving the same staged checks; an
unconfigured hook keeps its legacy coordinator. See
[hook configuration](../../CONTRIBUTING.md#checks-and-local-hooks).
Legacy and native commands coordinate on the same
retained `heavy.lock` and `activity.lock` inodes: native heavy jobs share the
legacy gate and hold distinct open-file-description byte locks on the heavy
descriptor. Both permits survive in the immediate child. No lock file is replaced
or unlinked during rollout. Older serial checkouts may reduce concurrency.
