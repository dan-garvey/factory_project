# Stationary two-client experiment

The rule owner is the exact sandbox `model.gd`; clients send intents and consume
confirmed projections. `peer.gd` supplies a reusable loopback ENet adapter.
`probe.gd` drives controlled phases and a primitive diagnostic view. It does not
implement recipes, construction costs or a second client authority.

From a checkout containing this runner, under the shared heavy lane:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check_stationary_authority.py \
  --godot /absolute/path/to/verified/Godot \
  --model-revision <exact-40-character-shared-model-commit> \
  --artifacts /absolute/new/external/run-directory
```

Add `--render` to render both actual client consumers and save their final PNGs.
The parent artifact directory must already exist. Existing destinations and
paths inside any registered checkout are refused. There are no downloads or
automatic retries. The runner copies dependency sources from raw Git blobs at
the supplied immutable commit and overlays these probe scripts; it never copies
a mutable model from another worktree or modifies that checkout.

The first trial uses 16 feed and a 1:1 recipe through the same three-argument
model constructor. Source capacities and advancement order belong to that
model. This fixture does not exercise wheel/power, stopped edits, save, story,
progression, actual player input or the four-plate opening objective.

The server waits for the required intents before admitting each controlled
schedule. Cases include missing-before/present-after dependencies, conflicting
and independent placements, a contested product, and two valid retrievals with
explicit production advancement between them because output capacity is one.
No random latency, sleep or retry decides a conflict winner.

P disconnects after its retrieval is applied with the acknowledgement withheld.
While it is gone, the server advances and Q receives stale views, including a
same-revision older-order observation after a refusal. The runner waits for both
P's actual exit and the server's explicit rejoin barrier before starting a fresh
P process. The duplicate request must retain its result without another effect;
changed-payload reuse is refused. Three engines are live at most; reconnect
requires four launches in total. Client labels P/Q are trusted fixture roles,
not a production authentication policy.

Assertions inspect real client reports, authoritative quantities and independent
expected final inventories P=2/Q=1 with conserved 16 units in this 1:1 fixture.
A single-player control replays the actual command/advance trace through the
same model. Final client snapshots and diagnostic view consumption are checked.
Both final reports arrive before explicit sequential peer shutdown; concurrent
client shutdown and arbitrary network faults are not covered.

Each run retains process logs, commands/PIDs, source hashes, exact dependency
revision, trace, authoritative/client reports and optional rendered captures.
Engine/script errors fail even if a pass marker appeared. Headless/rendered
watchdogs are 90/150 seconds; owned disk is capped at 256 MiB. These are probe
limits, not game performance targets or host quotas. Keep the task's aggregate
15-minute execution window and shared disk/memory floors independently.

This is evidence for the exercised stationary adapter, not full `.5.3`, save or
opening acceptance. The integrated gameplay scene must reuse the same authority
and rerun its applicable consumers. There is no prediction, rollback, Internet
hosting, fairness, whole-world replay or final-scale guarantee here.
