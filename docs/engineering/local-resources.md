# Cooperative local resource admission

Use the wrapper from any checkout of this repository:

```bash
python3 -B scripts/run_local.py check -- python3 -B scripts/check.py
python3 -B scripts/run_local.py heavy -- <build-or-test-command>
python3 -B scripts/run_local.py benchmark -- <measurement-command>
```

For commits, let the installed precommit hook invoke
`python3 -B scripts/check_commit.py` once. A manual coordinator run is optional
diagnostics, not an additional required check before the hook. It captures the staged tree
and takes one permit: check for non-GDScript changes, heavy for staged `.gd`
changes requiring the pinned compiler. It fails if staging changes before or
during validation. Do not wrap the coordinator or `git commit`, and do not call
another resource wrapper inside their checks. `check.py --staged` refuses game
changes without the explicit compiler path; it cannot silently run Godot under
a cheap permit. Runtime selection and retained compiler diagnostics are described
in [CONTRIBUTING](../../CONTRIBUTING.md#checks-and-local-hooks).

Cheap checks can coexist with each other and one heavy command. Heavy commands
share one lane. A benchmark excludes all wrapped checks, heavy commands, and
other benchmarks until its child exits. Locks live in the common Git directory,
so linked worktrees cooperate. Lock files are retained; never unlink them while
commands might be using them. Do not nest wrappers against the same repository.

Heavy and benchmark commands check the checkout filesystem's free disk and
Linux `MemAvailable` after admission. Initial settings are an eight-job budget,
20 GiB free-disk floor, and 8 GiB available-memory reserve. These are operational
settings for the current machine, not game targets or workload memory estimates.
Cheap checks remain available below the floors for diagnosis. Override settings
with `--jobs`, `--disk-floor-gib`, and `--memory-reserve-gib` before `--`.

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
