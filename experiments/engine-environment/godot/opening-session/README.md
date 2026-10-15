# Shared opening session adapter

This experimental loopback adapter gives one dedicated process the existing
opening Model and its 0.45-second clock. P and Q have shared fixture access;
these labels are not accounts, authentication or a permanent team policy.
Clients retain server projections, send intents and display actual outcomes.
They never create or advance a live worksite Model. The existing isolated Help
example is a separate teaching world. Offline input, saving and reopening use
the original files and behavior.

Every process uses the same RPC script at `/root/OpeningShared/Session`.
The server entry creates that root and Session child. The client scene owns
the same root/path and supplies `--session-port=N --session-role=P` (or Q).
ENet binds only `127.0.0.1`, accepts at most two peers, and admits ordinary
commands sequentially in actual RPC arrival order. No public fixture
admission, tick, restore, save or operator RPC is defined.
The adapter disables SceneMultiplayer peer relay before connecting: all traffic
uses the server/client path, without peer-to-peer lifecycle notifications.

The client API is `join_loopback(port, role)`, `is_ready()`, `projection()`,
`submit(action)`, `retry(request)` and `close()`. Metadata is `actor`, `context`,
`request_namespace`, `request_sequence` and `last_serial`. These client fields
are observations, not permission to choose a server identity. Signals are
`welcomed(actor, namespace, snapshot)`, `changed(snapshot)`,
`outcome(envelope)` and `disconnected(reason)`.

`projection()` returns a copy of the last server state, initially `{}`.
Disconnect retains it as stale read-only data; `is_ready()` becomes false and
mutations refuse. Joining again obtains a new server-generated caller
namespace and current projection. No connection failure starts a local world.
An initial connection or welcome attempt expires after ten real seconds and
reports `connection_timeout`. This bounds this loopback fixture's UI lifetime;
it is independent of the factory clock and is not a production latency policy.

`submit` and `retry` return `{queued, accepted: false, request, reason}`.
Queued work is not an authoritative success. An outcome flattens the unchanged
Model result and appends `snapshot` (the current server projection) and `serial`
(transport publication sequence). A retry can have an old result revision or
order; it must not roll the client projection back. Snapshot acceptance checks
context and monotonic transport sequence/revision/order. Retries reuse the exact
original intent within that connection. An old connection namespace refuses
after rejoin while the original Model request cache and work remain retained.

The server binds each role and namespace to its actual ENet peer. Claimed actor,
context and namespace mismatches refuse before reaching Model commands. The
ordinary Model remains the sole owner of validation, cached dispositions,
parts, quantities, topology and processing. This adds no serializer or second
material owner.

The initial network UI explicitly disables Save/Load and F5/F9. It does not
write a client worksite slot or roll back the live server. Full offline
save/reopen remains available separately. Server-owned persistence needs a
separate scope.

The server's optional initial `--frozen-clock` is for controlled observation;
it is not a client command. A separate ordinary-clock run must establish live
shared continuation. Local ready/status/stop/report paths only coordinate the
owned automated process lifecycle. Diagnostic JSON is not a compatible saved
worksite. `transport_check.gd` has private local file controls for transport
proofs; graphical input belongs to the actual shared-opening UI consumer.

This is trusted same-host loopback work, not public hosting, production netcode,
prediction, authentication, high-rate/scale evidence, moving-world networking,
network persistence, campaign policy or human play. Bounded orchestration and
actual two-UI evidence are required before accepting the integrated mode.

## Normal shared play

Use `scripts/run_shared_opening.py` for ordinary play on this computer:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_shared_opening.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 verified-lowercase-executable-sha256 \
  --artifacts /absolute/owned/shared-opening-sessions
```

The default opens two normal game windows, P and Q, and one headless server.
`--clients 1` opens only P. Clients enter `shared_opening.tscn` normally and
connect automatically. The ordinary mode has no input controller, copied
observer, delivery holds or frozen clock. The server keeps the existing live
clock and sole Model. Construction, material/drive links, retrieval, explicit
actor-owned confirmation and Help use the same controls as the offline opening.
Shared Save/Load remains unavailable. Each launch is a fresh finite16 fixture;
closing a session does not save it.

Closing **either** game window ends the entire session, including the server
and the other window. Ctrl-C also stops all owned processes. The launcher
records the actual reason and exit codes; a remaining window terminated during
cohort cleanup is not reported as a graceful user close. The default limit is
900 seconds after both requested participants join. `--duration-seconds` accepts
1 through1100, below the existing server lifetime. The whole launcher also has
an outer30-minute allowance. `--port` accepts one explicit port, or0 for one
kernel-selected candidate; a bind conflict fails without scanning or retrying.

The artifact root must be an owned absolute directory outside Git and without
symlinks. Each run retains original source hashes, captured runner hashes,
private projects/profiles, bounded logs, lifecycle PIDs/process groups and the
server's final report. `controller.json` identifies the launcher process;
atomic `cohort-state.json` records starting/ready/stopping/finished boundaries.
Ready means the actual server admitted all requested fixture roles. After
cleanup, `result.json` records the outcome and listener release. Ordinary play
is labelled `completed` or `interrupted`, rather than a gameplay test pass.
One outer resource permit and unchanged bounded helper own at most three
engines; the aggregate evidence root is capped at256MiB.

For a bounded automated normal-entry smoke check, add `--smoke`. This keeps the
ordinary scene entry and auto-connect, but appends the tracked
`launch_observer.gd` as an autoload **only in the copied client configuration
after import**. Its captured bytes and original/post-import/runtime configuration
hashes are disclosed. The default observer reads the real scene, waits for two
server revisions, captures its window and reports without game commands. It
closes/publishes its report before emitting the tagged completion marker; the
supervisor reads it once and releases the observers to exit only after all
participants were observed. This is startup/lifecycle evidence, not human play.

An independent test consumer may use `--smoke --observer /absolute/observer.gd`.
That explicit regular script is captured and limited to128KiB. It remains an
autoload observing/driving the normal scene, never a replacement client entry.
The exact report and finish protocol is implemented in the tracked default
observer and launcher validator. Extra ordinary-input stages can be retained
in its report. Normal mode refuses `--observer`; it never depends on diagnostic
controls. The separate transport and full UI checks below retain their own
coverage and attribution.

## Bounded transport proof

Run the diagnostic transport consumer through one outer resource permit:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check_opening_session.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 verified-lowercase-executable-sha256 \
  --artifacts /absolute/owned/shared-opening-evidence
```

This initial mode is explicitly **transport only**, with an initially frozen
server clock. It exercises real peers and Model commands, not graphical UI or
live production. It contests one carried collector, builds the shared path,
checks retry/reuse and actor/context refusals, disconnects/rejoins Q without
replacing the Model, attempts an occupied role and a command before joining,
rejects the old namespace and converges on one real state.
Independent item/part/shaft and final order/cache expectations face the actual
reports. Full two-UI/live-clock acceptance remains separate.

The launcher verifies the supplied executable hash and exact supported version,
copies/hashes sources into three separate projects/profiles and imports them
sequentially. One `execute_bounded` worker group then owns server and two client
engines. Those children inherit its group; none detaches or acquires a nested
resource permit. The controller limits live engines to three, per-actor logs to
8 MiB, the artifact root to 256 MiB and the whole session to 20 minutes. Timeout,
error text, early exit, port conflict or inconsistent reports refuse and retain
diagnostics; cleanup stops/reaps all children. The unchanged bounded helper
terminates the entire owned group, including remaining descendants.

`--port` selects a bounded loopback UDP port. Without it, one kernel-selected
candidate is used; a later bind conflict fails rather than scanning/retrying.
The private diagnostic client reads `--control-dir/control.json` with
`sequence/operation/payload` and atomically publishes `ack-N.json`/`final.json`.
Its JSON cell coordinates are explicitly reified as integer input before
submission; neither the wire adapter nor Model coerces malformed commands.
This protocol is separate from the real UI probe's actual-input controls.

## Actual two-client input

After the transport proof, add `--ui --clock frozen` or `--ui --clock live` to
the same launcher command. These are separately initialized sessions. The two
rendered clients use the real shared scene and input controller; no diagnostic
peer substitutes for input. The sealed `scripts/opening_ui_cases.py` module
owns the cases and independent expectations. An explicitly selected local pure
review driver can be captured with `--ui-driver /absolute/driver.py`; its bytes
and hash remain in the session evidence. The supervisor owns all processes,
input IDs, atomic control publication and completion. It waits for the matching
actor's `OPENING_UI_RESPONSE` marker before reading the closed response once.
Input completion alone is not server admission: cases inspect the real outcome
and current projection. UI readiness means controller startup, not welcome.

The case callback receives `exchange`, `wait_role_absent`, `observe_server` and
`transport_boundary`, plus the initial `frozen_clock` setting. `exchange` maps
P/Q to ordinary input controls, publishes all selected controls before waiting,
and returns complete responses. Read-only `observe_server` returns the actual
server checkpoint and diagnostics; it neither clones nor changes the Model.
Role absence is a real server lifecycle barrier.

The optional test-only server-local admission and outcome files are owned by
this supervisor. The seven boundary operations are `hold_admission`,
`wait_received`, `release_admission`, `hold_outcomes`, `wait_outcomes`,
`release_outcomes`, and `stop_server`. Held arrivals have not reached Model;
release preserves recorded arrival order. Holding an acknowledgement leaves the
actual Model decision and broadcast snapshots intact. Disconnect discards only
unadmitted transport data or undeliverable acknowledgements. Model stock,
requests and cached decisions remain. Default operation has no holds. These
files and read-only observation requests are never public or client RPCs, and
cannot freeze or advance the server clock after startup.
