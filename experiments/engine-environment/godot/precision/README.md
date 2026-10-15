# Exact-count processing bench

This optional later-control fixture exercises the
[exact-material and recovery witness](../../../../docs/proposals/prototype-witness.md#cases-and-observable-invariants).
It uses the accepted experimental engine, with one authority shared by its
headless and 3D consumers. The normal opening and its recipes stay separate.
The letters, quantities, process duration and circuit setpoints below are small
test values, not chapter content or an early control unlock.

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_precision.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 verified-lowercase-executable-sha256 \
  --artifacts /absolute/owned/precision-evidence
```

This opens `precision/main.tscn` normally. Close the window to finish; the
default limit is 900 seconds. `--duration-seconds` accepts 1 through 900.
Right-drag orbits the camera and the wheel changes zoom.

| Action | Key |
| --- | --- |
| Move one A, B or wrong X from the finite source into the chamber | A, B, X |
| Return one A or B to its actual return bin; route one X to the reject bin | 1, 2, 3 |
| Collect the actual output C into the finished bin | C |
| Pause/resume machinery power; one authority step | Space; N |
| Toggle the three meter/output rows; toggle the three recovery rows | M; R |
| Start/stop the caller clock | T |
| Begin a fresh finite experiment | Backspace |

The clock starts stopped. Each source contains **8 A, 4 B and 1 X**, for at most
four products C. The chamber starts only with **exactly 2 A + 1 B and no X**.
Missing, insufficient, surplus and wrong-kind inputs stay in place until
corrected; equal total quantity is insufficient when the material is wrong.
Capturing a valid chamber moves its whole contents into a named held job. It
runs for two more steps, retaining that job if paused or if the one-product
output is full. Input is closed during a captured job; a busy insertion leaves
the source unchanged. Collecting an empty output cannot create another C.

The six editable sensor/actuator rows read actual owner locations and propose
one normal transfer per powered step, in displayed priority order. The board
has fixed example predicates: collect output; reject X; return surplus A/B;
feed A/B up to their targets, using returned stock first. The recipe predicate
lives in the authority. The board can be incomplete: metering alone cannot
repair surplus or wrong stock. It owns wiring bits and never owns quantities.
This is a bounded prewired board, rather than a complete programmable circuit
editor.

For a concrete repair, insert A three times, B once and X once before stepping.
The invalid batch stays put. Return one A with 1 and route X with 3, then step
to process the exact remainder. Alternatively enable M and R, then T: the
designed circuit moves the surplus into the return bin, preserves X in the
reject bin, reuses the returned A and finishes four C from the original stock.
The correction uses the same owner and admitted transfers throughout.
Backspace is an explicit new experiment; resetting is never recovery.

The boxes and labelled bins are symbolic stationary ports and quantities, not
item-body collision or moving-transfer evidence. C represents 2 A + 1 B in the
per-material ledger. Raw, returned, rejected and held stock remain accounted
alongside output and finished product identities. This mode has no network or
checkpoint interface; retained JSON is diagnostic evidence.

## Bounded checks

Add `--check` for the real headless authority cases. Add `--check --render` for
those cases plus real keyboard/checkbox input through the ordinary 3D scene.
Both cover exact input, missing material, positive insufficient quantity,
required-kind surplus, an extra unlisted material and equal-total substitution.
Each invalid state is retained before manual repair, and separately before
the designed meter/recovery path. Power pause, closed input and output
backpressure preserve actual captured work and job identity.

The rendered check appends the tracked `observer.gd` as an autoload only to
its private copied configuration after import. Its original/post-import/runtime
configuration hashes are retained. It supplies actual input and observes the
one existing scene authority; it never creates a second authority or writes
quantities. Reports retain each command/step's raw before and after states,
case boundaries and owner identities. Read-only literal oracles independently
account for material and product equivalents. Three actual viewport captures
also record visible token counts against the owner at stable cuts. These are
technical checks, not human play or proof of learning comfort.

Original source, captured runners, pinned executable, private profiles, logs,
actual PIDs/groups/exits and reports are retained outside Git. One outer heavy
permit and the unchanged bounded helpers own at most one live engine; the
family is limited to 30 minutes and 256 MiB, with existing admission floors.
No production engine, game performance target, moving-world join, persistence
format or final recipe/control progression follows from this experiment.
