# Shared opening session adapter

The explicit `--native-world` server option uses one C++ World with the existing
Session and ActorWorld producer. Its [native guide](../../../../native/factory-godot-world/README.md#shared-native-profile)
records complete-payload requirements and the bounded headless P/Q raw-recovery
and fresh-host continuation. Clients create no live World. The historical
scripted profile and Python launcher below remain distinct; a missing native
payload never silently selects them when the native option was requested.

This experimental loopback adapter gives one dedicated process the existing
opening Model and its 0.45-second clock. P and Q have shared fixture access;
these labels are not accounts, authentication or a permanent team policy.
Clients retain server projections, send intents and display actual outcomes.
They never create or advance a live worksite Model. The existing isolated Help
example is a separate teaching world. The normal offline and shared opening use
the same physical actor producer; on shared play only the dedicated host runs
it. Clients render confirmed actor proxies, not a second authority or a
caller-reported pose. The historical unrestricted consumers name their legacy
fixture explicitly.

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

Native actor samples carry both current actors in a compact replaceable packet
on ordered unreliable channel 1. Only changed native World revisions or request
orders send a full state, reliably on independent channel 2. The older scripted
Model still sends its full replaceable states on channel 1. Received full states
are coalesced within a poll before rebuilding the view; actor samples are also
coalesced. A joined peer acknowledges its welcome before native full-state
delivery; the server keeps at most one full state in flight per peer and replaces
any waiting full state with the newest one. Welcome, commands, controls and
every original outcome remain reliable on channel 0. A lost actor sample is
replaced by the next one. A material change arrives as a full reliable state.
Outcomes immediately publish their snapshots and preserve every original result.
Serial, revision
and order checks prevent either channel from rolling the client view back.
Disconnect clears pending delivery while preserving the last confirmed
read-only projection.

The server binds each role and namespace to its actual ENet peer. Claimed actor,
context and namespace mismatches refuse before reaching Model commands. The
ordinary Model remains the sole owner of validation, cached dispositions,
parts, quantities, topology and processing. This adds no serializer or second
material owner.

The initial network UI explicitly disables Save/Load and F5/F9. It does not
write a client worksite slot or roll back the live server. Full offline
save/reopen remains available separately. Optional host checkpoints capture
the authoritative worksite at an orderly stop, as described below.

The server's optional initial `--frozen-clock` is for controlled observation;
it is not a client command. A separate ordinary-clock run must establish live
shared continuation. Local ready/status/stop/report paths coordinate the
owned host process lifecycle. Diagnostic JSON is not a compatible saved
worksite. `transport_check.gd` has private local file controls for transport
proofs; graphical input belongs to the actual shared-opening UI consumer.

This is trusted same-host loopback work, not public hosting, production netcode,
prediction, authentication, high-rate/scale evidence, moving-world networking,
campaign policy or human play. Bounded orchestration and
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
WASD moves the bound physical character, Space jumps, and P operates the nearby
waterwheel. Right-drag orbits and the mouse wheel zooms the following camera; neither
changes construction authority. Building, dismantling, retrieval, power control
and both link endpoints require the current native body origin within the
provisional four-unit 3D reach. Move closer and deliberately retry a refusal.
Help releases held movement without pausing the server's production. The
current planar grid, capsule/motor values, fixed boxes and excluded actor-actor
contact are adapter/fixture limits; see the
[physical contract](../../../../docs/engineering/physical-construction-contract.md)
and [constraint register](../../../../docs/engineering/godot-constraints.md).

Client Save/Load remains unavailable. By default each launch is a fresh
finite16 fixture and closing it does not save. Add `--save-on-close` to publish
the actual host's checkpoint at an orderly session end. Its new
`worksite.factory` path is printed and retained in the run directory. Reopen
that compatible opening with `--resume /absolute/previous/worksite.factory`.
Resume implies save-on-close into a **new** output slot. The input is captured
read only and preserved, and no client can load over a running world.

The host retains quantities and their locations, per-actor inventories,
construction identities and topology, held work/remaining phase, power and
cached command dispositions/order, plus physical actor poses and capabilities.
The declared roster must match the saved profile: use `--clients 1` for a P-only
shared save or the default two clients for P/Q. Cross-roster migration and
schema-1/unrestricted saves refuse in the normal physical profile; a missing
actor never grants unrestricted construction. P's pocket remains P's and Q's
remains Q's within that declared roster. Logical Core context survives; transport
serial, socket bindings and caller namespaces are fresh. Old connection
requests refuse rather than automatically replay. Selection and the local
non-consuming goal confirmation start fresh; a qualified actor can confirm
again. The factory does not catch up elapsed real time while stopped.
Native registration/readiness is rebuilt from saved positions, with controls
and velocity released; momentum and jump-phase continuation are not promised.
Unsupported contact aborts before admission without a safe-spawn fallback.
An explicit `--legacy-fixture` retains the historical unrestricted launcher
profile for regression work, not physical-character evidence.

Only the existing bounded Model/Store format is supported, with the opening's
16 blanks, one-blank recipe and P/Q roles. A bad or incompatible input fails
before server readiness or client admission, without creating a fresh fallback.
Existing output or `.pending` collisions refuse without overwriting an earlier
file. Checkpoint paths also reserve the lifecycle/control paths and their
temporary `.writing` buffers. If an error report would itself overwrite a
checkpoint path, the server retains its refusal in stderr and suppresses that
JSON report. A refused/failed publication makes the launcher fail, never a saved or
completed result. Ctrl-C after readiness asks for an orderly host stop/save
before cleanup; an interrupted preparation can have no checkpoint. This is not
crash/power-loss durability, autosave retention, cross-version migration or a
moving-factory persistence claim.

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
hashes are disclosed. The default observer reads the real scene, records its
connected revision, waits for two **additional** server revisions, captures its
window and reports without game commands. A large restored revision alone
cannot satisfy that clock check. It
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

Physical movement/reach and same-server rejoin have bounded two-client input
evidence, separate from actual human play. Offline P fresh-process restoration
does not prove normal shared P/Q host-file reopening. The independently reviewed
`scripts/check_physical_shared_resume.py` source defines that separate consumer:
ordinary Q refusal/P placement and movement produce the first real host save,
then a second normal host reopens the unchanged input with read-only clients.
It uses the existing launcher twice under one heavy admission and one retained
artifact family; it adds no replacement game entry, process supervisor or
state authority.
Source or compiler acceptance alone is not its runtime verdict.

`native_shared_rejoin_check.gd` also has separate `--cog-phase=chapter-ui` and
`--cog-phase=chapter-ui-resume` modes for the native arrival. Run its P and Q
roles as separate ordinary `shared_opening.tscn` clients against one
`server.gd --native-world` host. The first phase walks the host-owned actor
through the shared control callback, aims the ordinary E picker at a finite
tree trunk, uses the multitool button to shape a wooden frame, and places it
with the common-grid component tool. Q observes the exact debit and part. Stop
the host with `--save-file`, then start a fresh host with that unchanged Store
input and run both resume roles: P uses the ordinary deconstruct control to
reclaim the same part, and Q observes its returned cargo. Both phases require
their separate P/Q result files and the host's accepted save report. These
callbacks are automated client input, not a desktop or human playtest. They
do not yet cover the complete collector and press controls.

The same consumer has `--cog-phase=collector-ui` and
`--cog-phase=collector-ui-resume` modes. With a native server and separate P/Q
ordinary scenes, P walks to a finite tree and ore deposit, shapes four wooden
components, crafts a cutting edge at the pod, takes the single crank, and fits
five issued pieces on a raised foundation. It selects the fitted shaft and
presses the visible collector cut button. Q checks the original resource debits
and one receiver blank. The resumed mode opens the server's unchanged Store
save with both clients; P picks up that blank, then uses the same button to cut
one more, while Q checks separate carried, receiver and source custody. The
fixture retains each wire command and settled native outcome. Its walking and
button callbacks are automated scene input, not desktop or human play. The
separate `tile_transport_check.gd --chapter-product` fixture covers the press
and first plate with synthetic actor observations; this collector UI mode does
not establish an ordinary player-controlled first plate.

The subsequent `--cog-phase=collector-plate` and
`--cog-phase=collector-plate-resume` modes carry that first collector save
through the press with the same normal P/Q scenes. P picks up five blanks made
with the collector's cut button, harvests the second finite tree through the
ordinary E ray, shapes five wood pieces and two metal fittings, and fits seven
separate press parts beside the collector. P selects the press frame and uses
the actual Feed, Turn crank, and Pick up exit product panel buttons. Q checks
the raw blank under the press head, a retained WorkLot during turning, the
finished plate at the exit, and final P cargo. A third fresh native host opens
the unchanged plate save, and both clients compare placed identities, source
stock, dropped material and cargo to the prior P result. This phase issues
component placements through the ordinary scene's Session helper; its panel
button callbacks and walking are automated input, not human play or a claim
that every press part was placed through the pointer interface.

The low-level dedicated entry accepts optional `--resume-input` and
`--save-file` paths in the same owned directory as its lifecycle files. These
are host process options, never RPCs. Input is decoded into the one actual
server Model through the existing Store before readiness/welcome; output uses
that same Store once at the completed stop boundary. No-option entry does not
load the Store, preserving the accepted minimal transport consumer. Ready and
final reports distinguish the loaded checkpoint, original input hash and
actual publication/refusal. Their JSON remains diagnostics, not a saved game.

For controlled authority restart evidence, `scripts/check_shared_checkpoint.py`
uses explicit accepted producer fixtures and the real diagnostic peers. It
labels that seed reuse, verifies original Model/Store pins and file hashes,
then runs new actual hosts through Store capture and restart. The same two
peer processes reconnect to successive authorities with fresh namespaces;
old applied requests refuse and a new live clock completes retained work.
Add `--negative` to run the separate pre-admission refusal controls: corrupt or
truncated input, valid Core files outside the opening/P/Q contract, occupied
output/pending paths and invalid host paths. The tracked
`checkpoint_controls.gd` creates the valid incompatible files through the real
Core and Store. Expected host failures retain their original `fail` reports;
the checker separately records whether each refusal and preservation matched
its expectation. This is separate from normal-scene smoke/input evidence and
human play.

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
