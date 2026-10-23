# Native local admission

The C++ admission tool implements the user's four-heavy-job default. Cheap checks
can run alongside heavy work, while a benchmark excludes both. Every heavy job
retains the 20 GiB free-disk floor, 8 GiB available-memory floor and eight-job tool
setting. This is a cooperative operating policy, not a GPU capacity measurement,
a memory reservation or permission to control a user desktop.

## Build and test

Bazel is the canonical build interface. Keep its output and cache under an owned
bounded family and use ordinary resource admission:

```bash
bazel build //native/tooling:factory-local
bazel test //native/tooling:local_resources_test \
  --test_arg=/absolute/canonical/linked-checkout \
  --test_arg=/absolute/owned/admission-results
```

The test is marked local because it observes host process descriptors and creates
disposable Git repositories in the explicit fixture directory. It starts no game
and never acquires the real checkout's permits. The first argument comes from the
built CLI runfile; the two explicit arguments supply the read-only source checkout
and fixture root. Existing relevant passing tests and one independent review
suffice; there is no additional approval chain.

## Existing entry points

The Python entry point and commit coordinator remain unchanged and retain their
legacy serial behavior. New heavy jobs use the native executable installed at
`<common-git-dir>/factory-local-resources/factory-local`. No Python forwarding
implementation is added. Legacy jobs coordinate with all native slots through
the same retained exclusive gate.

The standalone CLI accepts an explicit checkout:

```bash
/absolute/owned/factory-local --root /absolute/checkout heavy -- command argument
```

Its default root is the caller's current directory. Options before `--` include
`--jobs`, `--disk-floor-gib`, `--memory-reserve-gib`, `--no-wait` and
`--inherit-permits`. Use the latter only for a command that verifies inherited
permit identity and keeps any Bazel invocation bounded with `--batch`.
Floor changes require a documented resource decision. Busy nonwaiting admission
or insufficient capacity exits 75 before the command starts. Argument errors exit
2, wrapper/exec failures exit 1, and real command exits pass through, including
127. Signals map to `128 + signal`.

## Lock compatibility and lifetime

Every linked checkout uses the common Git directory's retained `heavy.lock` and
`activity.lock` inodes. Native heavy jobs take a shared legacy gate, one of four
one-byte Linux open-file-description locks on that same heavy descriptor, and
shared activity. Older wrappers take the exclusive legacy gate, so they cannot
overlap a native heavy job. They may temporarily reduce concurrency but cannot
bypass the four-slot bound. Checks take shared activity; benchmarks take exclusive
activity. A heavy waiter takes no activity permit until a slot is available.
All native entrants take one retained admission-order gate while acquiring
their activity locks. Heavy commands first wait for the legacy gate and a free
slot without holding the order gate or activity. A benchmark keeps the gate
while waiting for exclusive activity, preventing later native shared arrivals
from overtaking it. The gate
is released before child execution, so it does not serialize admitted work.
The legacy Python wrapper still coordinates on the heavy and activity locks but
does not use the order gate.

Both admission descriptors survive in the immediate supervisor, including its
slot if the outer wrapper exits. The command and any persistent server it starts
receive no admission descriptors by default. An explicit `--inherit-permits`
passes them to a verified direct command. Unrelated descriptors close before Git
discovery or command execution. Linux `close_range` and `F_OFD_SETLK` are
required; unsupported calls fail closed. Lock files are never replaced or
unlinked during rollout.

Capacity is checked after admission. It can change later and is not reserved.
Detached services still require their owning workload's timeout, process
cleanup and aggregate artifact/log limits. Permit isolation does not supply those.

## Validation and remaining scope

The native suite covers four live children, fifth-job refusal, slot reuse, queued
waiters, benchmark exclusivity, both directions of legacy compatibility, the
capacity refusals, command exits, literal arguments,
job settings, hook-variable isolation, closed standard streams and unrelated
descriptor closure. Wrapper-loss and deliberate assertion controls require the
owned inherited child to be reaped and its permits released. An ordered queue
control holds a benchmark behind active heavy work, starts later heavy entrants,
and proves the benchmark enters before them. A synthetic
persistent server control verifies that a completed direct client releases both
permits while its server stays alive, with later legacy heavy, native heavy and
benchmark entry.

These operational tests do not establish safe rendering of four games, actual
OS-focus behavior or gameplay acceptance. Agent-controlled desktop playtests
remain suspended until the user re-enables them. Other Python-backed launch,
gate and evidence implementations remain in force until their relevant native
replacements are tested and reviewed.
