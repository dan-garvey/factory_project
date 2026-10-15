# Basic stationary save continuation

`checkpoint_file.gd` is a small file adapter for the shared model's
`checkpoint()` and atomic `restore_checkpoint(snapshot)` methods. Chapter owns
the sole schema/rule validator. `write(model, path)` validates a capture through
that same validator, writes and verifies a sibling `.pending` file, then renames
it into place. Existing pending files cause refusal. `read_into(model, path)`
checks a bounded integrity envelope before calling the model's restore method.

The envelope holds plain Godot Variant bytes, preserving integer quantities;
object encoding/decoding is disabled. The checksum detects accidental corruption,
not authorization. There is a 1 MiB file cap and explicit prototype version.
There is no production cross-version format, migration, power-loss durability,
arbitrary hostile-input decoder or cross-authority timeline guarantee. Restoring
the saved world context is not a new network session epoch.

Run against an exact shared-model commit containing the checkpoint methods:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check_save_continuation.py \
  --godot /absolute/path/to/verified/Godot \
  --model-revision <exact-40-character-model-commit> \
  --artifacts /absolute/new/external/run-directory
```

The runner reuses the landed stationary runner's raw-Git source copier and
external-path validation. It overlays only these fixtures, then runs separate
producer and consumer Godot processes sequentially, with owned XDG/temp paths
and retained logs, source hashes, commands and assertion reports. No downloads,
live user saves, original tracker or source-model edits are involved. Each
engine process has a 60-second deadline; the first task envelope is 15 minutes
and 256 MiB total, under shared resource admission. The child is the trusted
verified engine; this runner is not arbitrary-process isolation.

The producer saves real opening-mode states with 16 feed and a 1:1 process:

- Paused power with one held input and one step of work left.
- Completed held work blocked behind an occupied output buffer.
- A retrieved-but-unacknowledged product and a replaced wheel whose old
  removal request is retained; the replacement has a different stable identity.

It then continues each original world as an uninterrupted reference. A fresh
consumer process loads each actual file through the model validator and applies
the same subsequent commands. Semantic projections, identities, request results,
parts, power and quantities must match; all 16 feed must become exactly 16 held
products in player inventories. This tests continuation, not serialized byte
equality. Byte equality is used only to prove a known good artifact survives a
rejected load or save.

Truncated, empty, corrupted, oversized, wrong-envelope and validly encoded but
invalid schema/state/reference/quantity/phase/request candidates must leave the
current authority and prior good file unchanged. A collision sentinel proves
pending data is not overwritten. The same prior authority must still finish
correctly afterward. Malformed logical candidates are test inputs, never a
second implementation of the core validator.

No live network world replacement, abandoned post-checkpoint request, moving
save/rejoin, UI save button, user play or performance result is established here.
The basic opening must reuse this adapter and rerun its actual save/load/input
path. A restored caller must allocate fresh new request identities while retries
retain the original identity; this fixture explicitly records its future caller
sequence rather than resetting a request counter into the saved cache.
