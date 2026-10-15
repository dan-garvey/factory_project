# Interrupted plate retrieval in the shared opening

This is a focused additional consumer case for the experimental same-host shared
opening. Existing transport and UI checks already cover retry/cache identity,
wheel placement interrupted before admission or after decision, power commands
with an undelivered acknowledgement, disconnect/rejoin and orderly host
checkpoint/reopen. Those results remain attributed to their original consumers.
This case adds an item-changing retrieval while the other participant competes
for the same one-slot output.

Run through the existing supervised actual-input harness:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check_opening_session.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 verified-lowercase-executable-sha256 \
  --artifacts /absolute/owned/shared-recovery-evidence \
  --ui --clock live \
  --ui-driver /absolute/checkout/scripts/opening_recovery_cases.py
```

The pure driver creates no Model, transport, files or processes. The unchanged
harness owns one headless authority and two rendered clients, local delivery
barriers, real input, reports and teardown under one outer heavy permit. It
captures the case driver and hashes the game/runner inputs. The clients load the
real shared scene through the existing diagnostic input entry. This is ordinary
keyboard/mouse/button behavior in that scene, with explicit test instrumentation;
it is not the uninstrumented normal launcher's positional entry or human play.
The existing twenty-minute, three-engine, 256 MiB and per-log allowances remain.

Q builds and powers the actual collector/belt/press/waterwheel line with finite
stock and parts. After one output exists, Q stops the drive. The authority's
revision clock continues while every material location, held work, remaining
phase, machine identity and topology stay fixed. This produces controlled cuts
without changing the server's clock implementation or inventing stock.

The same authority then exercises two distinct output boundaries:

| Boundary | Actual server result | Other participant | Returning participant |
| --- | --- | --- | --- |
| P's retrieval arrives but admission is held; P disconnects | No Model command or cached disposition, output retained | Q receives that one plate | P rejoins with fresh namespace, Q's current credit and no replay |
| P's retrieval is admitted, but its acknowledgement is held; P disconnects | Exactly one cached P retrieval and P-owned plate, output empty | Q's explicit keyboard R gets `unavailable_output` | P rejoins with fresh namespace and its actual plate; the old acknowledgement remains unknown |

Current authoritative stock does not establish which historical request was
acknowledged. Both clients retain honest uncertainty while the server records
whether the original command was absent or applied once. Rejoin itself issues
no game command. The driver checks the actual request cache, full stopped
checkpoint, current client projections and separate P/Q inventories, rather
than inferring authority from a UI counter. Final actor credit is P1/Q1 and all
sixteen material units remain accounted for. Viewport captures supplement those
records; they do not prove the accounting themselves.

The source-only oracle tests discriminate wrong actor credit, balanced duplicate
transfers, changed phase/identity/topology, hidden automatic replay, malformed
quantities and mismatched cached dispositions. They do not simulate a game or
replace actual engine evidence. This is additional coverage unless an actual
failure is reproduced and retained; source tests alone are not a regression
claim. Native execution and independent review receipts establish which exact
revision passed.

No new gameplay, persistence or network implementation is selected here. The
existing sole Model/Session/Store boundaries remain. Moving-world networking,
remote security, crash durability, rollback, throughput targets and human
play/enjoyment remain outside this case.
