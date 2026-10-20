# Finite material core foundation

This C++20 library extracts the existing collector, belt and press material rules
from the experimental Model. It has no engine dependency or downloaded package.
It is not yet used by the playable demo. The current Model, Session and Store
remain the live owners of their existing boundaries.

`State` contains literal raw holdings, completed products in named inventories and
the remaining held-work ticks. `Config` supplies recipe input, collector capacity
and cycle duration. `Path` supplies already resolved component, connection and power
facts. One step finishes held work, starts eligible work, moves belt stock, moves
collector stock and extracts finite feed, in that order. A full output preserves
completed held work with zero remaining ticks. Stopped power leaves material state
unchanged. Quantities use signed 64-bit integers with checked conservation sums.

The validator rejects negative counts, invalid capacities and held batches, missing
holders, invalid edges, overflow and conservation disagreement. Step and retrieval
validate before committing a replacement state, so a refused transition is atomic.
Products count as their recipe's input units for conservation. Raw material cannot
be collected through the product retrieval operation.

These functions are not a command-admission API. The caller must first establish
actor identity, actual reach and request identity, and return historical cached
outcomes without invoking the material transition again. Revisions, topology
editing, kit ownership, native body registration, projections and disk import are
explicit adapter work, tracked in `factory-yau.3.17.7`. The current scalar product
inventory is not a recovery container for raw or partly processed material.

## Historical foundation build

The original standalone campaign passed 206 logical native checks and the separate
four-product consumer. Its final source, material and operational bindings are
complete; this does not establish live adoption or measured performance.

Bazel is the canonical build system required by the user. The [current graph and
build instructions](../../docs/engineering/native-builds.md) cover this foundation
and have passed bounded build/cache validation. Ops owns further package integration
and commit-turnaround measurements in `factory-yau.3.17.8`. See the
[migration contract](../../docs/engineering/native-migration.md). The CMake files
and commands below are retained to explain or reproduce the historical fixture,
not as the default for new native work or a competing build-system commitment.

That fixture used the installed C++ compiler, CMake and Ninja in an owned external
directory. The command has one cooperating heavy admission, not nested wrappers.
Any declared reproduction still needs the agreed bounded supervisor and retained
source, compiler, command and result provenance; no additional run is requested here.

```bash
factory_core_build=/absolute/owned/external/build
python3 -B scripts/run_local.py heavy -- sh -eu -c '
  cmake -S native/factory-core -B "$1" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
  cmake --build "$1" --parallel 2
  ctest --test-dir "$1" --output-on-failure --no-tests=error --parallel 1
  "$1/factory-material-case"
' sh "$factory_core_build"
```

The native tests exercise complete literal snapshots, one- and two-input recipes,
output backpressure, stopped and disconnected paths, named product custody, atomic
refusals and integer boundaries. The separate headless consumer completes the
existing eight-input/two-input-recipe fixture as four products. Neither program
claims ordinary input, Godot character physics, request replay, Store restoration,
human play, portability or performance. Existing mandatory repository gates remain
in force and do not yet compile this separate C++ project automatically.
