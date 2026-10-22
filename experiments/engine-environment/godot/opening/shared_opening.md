# Shared opening client

This separate experimental scene presents the existing opening through the
[loopback session adapter](../opening-session/README.md). The offline opening,
its save/reopen launcher and its worked example remain unchanged. The neutral
project startup also remains unchanged. Use the session runner's explicit,
bounded server/two-client mode; this document does not start a service.

The two provisional participants P and Q share the finite starter kit and worksite.
One server Model owns all items, parts, identities, topology, process phase,
request outcomes and live time. The client owns its camera, selection, pending
message and local objective acknowledgement. It does not construct a live Model,
advance a local factory or predict stock. The normal Help example retains its
own isolated Model and physics world for teaching.

## What the client shows

A sent command first reads **Waiting for the server's decision**. A transport
queue receipt is explicitly not accepted work. The client allows one outstanding
command; it applies the outcome only when a matching server result and current
context/revision/order projection are available. A refusal displays the server's
reason and current worksite. Placement selects an entity only after actual
acceptance; a pending placement creates no machine or part debit locally.
Refused collector or waterwheel placement points to the ore deposit or
stream bank; correcting the location submits a fresh intent using the same part.

The participant label identifies whose inventory supplies the four-plate goal.
P's plates do not satisfy Q's inventory check, even though both may use the same
fixture machinery. Confirmation is explicit, local and non-consuming. This
fixture access rule selects no campaign, team, learning or shared progression
model.

Before readiness, no state is invented. After disconnect, the last confirmed
worksite remains visible and read-only. Uncertain actions remain explicitly
uncertain and never retry automatically. Connection failures show their cause
alongside that warning; a failed reconnect does not decide the earlier action.
Reconnecting obtains a server-generated
fresh namespace and current projection and resets selection, link selection and
local objective acknowledgement. Camera and Help remain local presentation.

Save and Load buttons are disabled in this mode. F5/F9 explicitly report that
network saving/loading is unavailable and perform no Store operation. Supplying
a local slot through the view API also leaves saving unavailable. Offline
`--save-slot` and `--resume` startup arguments are explicitly refused here. Existing
offline saves and compatible reopen are separate supported paths, not evidence
of server persistence or permission to roll back a live session.

Normal build, connect, inspect, retrieve, power, dismantle, camera and Help
controls are inherited from the offline view. Reconnect/Disconnect apply only
to this loopback session. Help navigation issues no game request or save, and
the live server/other participant can continue while an example is open. Full
checkpoint isolation observations use an explicitly frozen server test clock;
powering off alone does not stop the Model's revision clock.

If the first machine chosen for a connection is dismantled before the second
point is chosen, its confirmed removal clears that local choice. A replacement
at the same square needs an explicit new choice; unrelated updates keep a valid one.
Other actions still wait for their own server result; only the unsubmitted local
choice is cleared.

## Scene and adapter seam

`shared_opening.tscn` has root `OpeningShared` and child `Session`, giving both
server and client the exact RPC path `/root/OpeningShared/Session` without an
autoload or changed project settings. The existing `opening.gd` supplies geometry,
ordinary input and Help; `shared_opening.gd` overrides startup, asynchronous command
submission, readiness guards and unavailable network save/load. It never calls
the offline startup that creates a Model or accepts a local resume slot.

The explicit normal client arguments are `--session-port=N` and
`--session-role=P` or `Q`. Only an explicit loopback port is used. The adapter owns
role binding, context, namespace/sequence, cached retry recognition and transport
freshness. Its `welcomed`, `changed`, `outcome` and `disconnected` signals drive
the view; `projection()` returns a deep copy, not a mutable authority.

## Actual-input test controller

`shared_check.gd` is a separate automated SceneTree script used by the bounded
session supervisor. It loads the real scene, sets it as `current_scene`, and
uses actual Input events and visible buttons. It introduces no admin, admit,
clock or test RPC in the client protocol. Normal `shared_opening.tscn` never
reads its diagnostic control files.

The supervisor creates a fresh owned external directory per client and supplies
`--ui-control-root=PATH` in addition to the normal session arguments.
The test-only `--ui-defer-connect` starts at an explicit not-ready boundary;
actual Reconnect button input then joins the session. It publishes
`control.json` atomically, one monotonic integer id at a time, then awaits
`response-ID.json` or a retained `failure.json`. Each response includes the exact
input and actual scene/session projection, identity, pending/outcome status,
actor-specific goal, save availability and Help isolation facts. Output markers
are `OPENING_UI_READY` and `OPENING_UI_RESPONSE`; exits, diagnostics and a
`OPENING_UI_FAIL` are meaningful, not a substitute for these facts.

| Control action | Fields / actual consumer |
| --- | --- |
| `observe` | Read current facts without a game request |
| `key` | `key`: 1–8, B, F, G, I, R, H, SPACE, F5, F9, ESCAPE, LEFT, RIGHT, HOME |
| `cell` | `x`, optional `z`: project the real world square to a mouse click |
| `button` | `button`: an explicit view button name, clicked through GUI input |
| `barrier` | `condition`: ready, settled, disconnected, output, inventory, revision; optional `minimum` |
| `view_delta` | `seconds` in 0–600: advance presentation only, to test absence of a client clock |
| `capture` | Save the real rendered viewport to `capture-ID.png` |
| `quit` | Retain final facts and exit the automated client |

Only known controls/keys/buttons are accepted. Controls are at most64KiB,512
sequential requests,30seconds per observation barrier and four minutes total
per automated client. The outer supervisor owns the stricter cohort timeout,
artifact/log allowance, three-engine limit and teardown. It must use one heavy
permit, not wrap individual peers or create detached engines. A barrier observes
actual readiness/state; it never changes world state or retries a failed action.

The intended evidence covers real contested input/refusal and convergence,
actor-owned retrieval and goal, read-only Help with separate live-clock proof,
disconnect/rejoin, missing-server/not-ready behavior and unavailable F5/F9.
The session's structured run receipt, exact source/runtime hashes and independent
combined review establish which cases were actually run; this description alone
is not a pass result. Existing exact-hash offline checks and save/reopen evidence
remain attributed to their original consumers.

Trusted loopback fixture access is not authentication, remote hosting, production
netcode, prediction, high-rate/scale acceptance, moving-world support, server
persistence or a human playtest. No permanent gameplay, camera or stack decision
is selected by this client.
