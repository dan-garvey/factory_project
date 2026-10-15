# Save/resume ownership and equivalence — proposal

Status: persistence evidence contract, drafted against `f06ffaa`. This text
implements no save system and authorizes no runtime work. It selects no schema,
serialization library, migration framework, simulation model, lockstep or
rollback guarantee. Candidate experiments still need bounded trial permission;
proposal acceptance is not production or playable acceptance.

## Sources and witness links

[DESIGN: rules and presentation](../../DESIGN.md#separate-rules-from-their-presentation)
proposes authoritative quantities, sequence, topology and engine adapters.
[DESIGN: multiplayer](../../DESIGN.md#multiplayer-from-the-first-representative-prototype)
calls for persistent factory operation, moving interactions, reconnect and the
same authoritative rules in single-player/server paths. [Construction and
movement](../../DESIGN.md#construction-and-movement) and [complexity and
automation](../../DESIGN.md#complexity-and-automation) supply the accepted broad
motion, invalid-process stall, non-destructive drivetrain stall and isolation
requirements. Detailed contact and progression rules remain open.

The [authoritative-core proposal](authoritative-core-trial.md#proposed-ownership-at-the-boundary)
assigns one owner per transition and distinguishes state from cosmetic events.
This proposal refines its persistence seam rather than creating a second owner.
The [common witness matrix](prototype-witness.md#cases-and-observable-invariants)
owns case identities. Relevant cases are W-authority, W-count, W-recovery,
W-geometry, W-obstruction, W-carrier, W-player, W-harvest, W-transfer,
W-clients, W-save and W-rejoin. Its
exact-material variants and distinction between submitted intents and accepted
outcomes apply unchanged.

## Proposed ownership inventory

These are logical facts needed to explain continuation, not serialized fields
or a requirement to dump every runtime object. For each candidate, identify the
single owner, the coherent observation boundary and whether a fact is retained
or safely reconstructed. Reconstructed information must be determined from
retained authoritative facts and declared rules; it cannot depend on a vanished
scene, client or socket. Prove any omitted-state claim through continuation.

| State family | Facts the candidate must account for | Omission/reconstruction failure to expose |
| --- | --- | --- |
| World and identities | The fixture/world being restored; identity and lifetime of existing entities; topology/containment and references; the mapping from fixture labels to real entities. Rebuild ephemeral adapter handles without retargeting an old reference to a replacement entity. | A belt, request or passenger references a missing object, or a stale identity now targets a different machine. |
| Item kind, quantity and location | Exact stock by material identity and owner/location, including inventories, buffers, machine-held inputs, output awaiting delivery and any owned in-flight material. Record declared source/sink transformations. | Total counts appear unchanged while wrong material, location, duplicate ownership or lost process-held stock changes the next result. |
| Precision and recovery | Current process contract/configuration, accepted phase, partial work where relevant, stall condition, held inputs, recovery route/configuration and the disposition of requests that can advance it. Recompute a reason only if retained facts establish it. | Restore resets a stalled batch to valid, reconsumes inputs, forgets missing/wrong-kind stock, restarts completed work, or bypasses designed recovery. |
| Mechanical operation | Connected topology, direction/gearing, operating/stall/isolation state, coupling state, and the fixed-cycle phase/reversal condition needed for the next transition. | The blocked branch silently reconnects, an isolated branch stalls, or a cycle restarts from its construction pose. |
| Moving assembly | Assembly membership, construction frame versus operating transform, path/constraint identity, direction and phase, plus velocity or other integrator state if it affects future behavior in that candidate. | A carrier snaps to the grid, loses attached machinery, reverses incorrectly, or resumes with a different working encounter. |
| Harvest and transfer | Eligible encounter/target identity, actual accepted work, source effect, process/transfer phase, and who owns each material quantity before, during and after acceptance. Preserve or explicitly reconstruct pending decisions at the declared boundary. | A harvested source is charged twice, stock exists at both ends, a pending handoff disappears, or a scene event creates another delivery. |
| Actual player/collision join | Which authority owns the character's persisted facts; player identity and presence under the trial policy; world/assembly-relative state, movement/contact state affecting continuation, and relationship to the moving assembly. Identify core-owned versus engine-owned facts. | A dummy transform looks correct while the real controller falls through, acquires a different contact, duplicates a body, or receives an obsolete correction. |
| Accepted requests and external work | Subject/request identity and world context; admitted order or equivalent evidence; whether accepted work is pending, applied, rejected or otherwise terminal; enough disposition information to handle uncertain acknowledgements. | Rejoin or load reapplies a completed input, silently drops admitted work, or treats a merely submitted request as committed. |
| Time, ordering and randomness | The candidate's advancement boundary, pending scheduled work or remaining phase, order facts that affect competing outcomes, and random state/draw identity only where actually used. | A timer uses unrelated host elapsed time, callback order changes admission, or uncontrolled randomness changes which stock is consumed. |
| Provisional access/ownership | Fixture player roles, access decisions or ownership references actually used by saved requests/state, labelled as provisional. Preserve their meaning within the trial. | Restore grants different access, attributes a request to the other client, or silently substitutes a universal team/progression model. |

Rendered interpolation, camera/audio, transient UI, scene lookup handles,
network sockets and acceleration caches are not authoritative substitutes.
They may be rebuilt, but a purported cache that changes contact, inventory or
the next accepted transition must be included in the ownership explanation.
Do not serialize process pointers or assume an engine object graph alone is a
complete durable world. This does not decide which side owns physical state.

## Coherent save and restore boundary

The checkpoint must describe one explainable cut across its participating
owners. For example, source removal cannot come from before a transfer while
destination credit comes from after it, with no owner of the difference. Record
the accepted command boundary and relevant machine/contact observations rather
than equating a rendered frame with an authoritative checkpoint.

A candidate can coordinate capture, retain explicit work in progress, or use
another bounded mechanism. Waiting for a declared safe transition is an option
to evaluate, not proof it supports every requested in-flight checkpoint. If it
can save only an idle factory, report moving/partial-work cases as unsupported;
do not silently stop machinery, drain buffers or complete requests to pass them.
No global transaction framework or continuously running save thread is selected.

Restore into a fresh authoritative instance, with no live objects borrowed from
the reference run. Establish references, quantities and process/motion owners
before allowing new commands or clients to mutate them. Rebuild adapters through
the actual candidate join and expose a coherent state to consumers. A candidate
must report when initialization or live-contact reconstruction cannot reproduce
the declared checkpoint semantics; a snapshot of an attractive scene is not a fix.

Describe the save operation's completion and failure boundary separately from
loading. A failed export/publication or rejected load must preserve the previous
valid fixture artifact and must not partly replace an already running world.
Keep generated negative inputs in disposable copies. This is a proposed failure
safety criterion, not a claim of crash/power-loss durability, autosave retention
or a selected filesystem publication/backup strategy. Those guarantees need
separate explicit scope and evidence.

## Client and request continuation

Transport reconnection and a restored world are different events. W-rejoin first
lets one client leave while the server and other client continue; W-save starts
a restored reference branch. Exercise rejoin after restoration as a separate
join, establishing the current world/authority context before new requests.
No production session/epoch encoding, account system or reconnect placement rule
is chosen here.

| Disposition at the checkpoint | Required observation after restore/rejoin |
| --- | --- |
| Submitted but not accepted | Do not infer a committed transition from a client queue or animation. The trial declares whether that intent can be submitted again and under which current preconditions. |
| Accepted and still pending | Preserve the owned work and its material/state obligations, or show the declared boundary resolved it before capture. Report completion, continued pending state or an explicitly accounted failure; do not silently forget it. |
| Applied but acknowledgement absent | The authoritative result remains applied in that branch. A repeat request cannot unknowingly apply the effect again. A recorded result, explicit duplicate/stale refusal or another measured mechanism may establish this; no exactly-once transport is assumed. |
| Rejected, cancelled or otherwise terminal | Preserve enough meaning to explain the outcome and any retained/routed material. A reconnect is not permission to turn a prior refusal into an unnoticed success. A newly intended request can be evaluated against current state. |

Capture these distinctions for competing precision-input or transfer requests
from the two clients. A network acknowledgement is not the authority's commit
boundary, and disconnect must not itself cause an invented stock debit/credit.
Requests from a different restored/continued world context must not mutate the
current world through accidental identity reuse. The trial names how such
requests are recognized and handled rather than silently replaying an old queue.

Discarded client predictions and rebuilt views must converge from the restored
authority through the real correction path. Durable facts must not be recovered
from untrusted client inventories or cosmetic completion events. Preserve the
actual player movement/collision/authority join for W-player and W-rejoin;
parenting a replacement camera or dummy passenger cannot establish restoration.
Provisional disconnected-player presence and pending-request rules remain
declared experiment assumptions, not chosen offline progression or injury rules.

## Semantic continuation equivalence

A save is not validated merely by loading successfully or comparing an initial
state hash. Define an independent projection of the ownership inventory and
expected observations before execution. Use fixture-to-real identity mapping to
compare relationships without requiring equal memory addresses, serialized
bytes or adapter handles. Never equate a removed object with a new one merely
because their visible position/material is the same.

For each checkpoint, retain an uninterrupted reference branch and a restored
branch of the same candidate/rules/fixture revision. Compare their initial
logical projection, then advance them through the same declared logical
conditions and submitted intents, comparing accepted/rejected outcomes as well
as subsequent state. Keep every material kind/location exact, including owned
in-flight stock and the declared recipe transformations. Compare process phase,
stall/isolation, topology, motion and request consequences at named boundaries.

Where live contact or concurrent admission can vary, the trial must name the
controlled input/order and comparison it can support. Distinguish reproducing a
recorded authoritative order from repeating unconstrained network arrival.
Declare any justified physical comparison policy before observing results;
never use a tolerance to excuse changed material counts, duplicated requests,
different contact eligibility or a different recipe outcome. Unsupported
comparisons remain visible. No whole-world bitwise determinism, lockstep,
universal factory rewind or fixed timestep follows from this criterion.

Use equivalent logical advancement, not time spent with the application closed.
The trial must specify how its process clock and pending work are represented.
It must not silently manufacture production for wall-clock downtime or reset
the phase to hide missing time state. Offline elapsed production and offline
player progression remain outside this proposal.

## Discriminating checkpoint and failure witnesses

All rows refine the existing witness, not a new catalogue of game mechanics.
Keep failed states intact for inspection and subsequent recovery. A separate
isolated probe is diagnostic coverage until rerun in the combined candidate.

| Probe | Existing cases and checkpoint | Failure the comparison must catch |
| --- | --- | --- |
| P-count | W-count/W-recovery: missing and positive-but-insufficient inputs, required-kind and unlisted-kind surplus, equal-total wrong-kind substitution; checkpoint before correction and during declared recovery work. | A loader stores only total units, drops the wrong kind, loses buffered stock, restarts a phase, or makes an invalid batch complete. Each restored variant must still need the appropriate accounted correction and must complete without duplicate output afterward. |
| P-operation | W-geometry/W-obstruction/W-carrier: blocked connected drivetrain, isolated branch still working, and moving rotary/gantry/train-like phase with attached work in progress. | Load clears a stall/coupling, resets direction or operating pose, loses attached topology, or changes the next process/working encounter. Do not impose a new docking/re-engagement rule to repair the comparison. |
| P-harvest-transfer | W-harvest/W-transfer: source eligibility before acceptance, accepted work with a declared owner of in-flight material, and applied delivery before client acknowledgement. | Source depletion or output repeats; a transfer is present at both ends/neither; restoring or rejoining commits the same accepted work again. An atomic candidate instead documents and tests both sides of its actual transition boundary. |
| P-player | W-player/W-clients/W-rejoin: real character moving relative to the carrier while machinery/transfer operates; restore and correct through the real engine/authority join. | A pose-only save loses motion/contact ownership, a client creates another character, or a stale correction silently moves the restored body into a different interaction. Temporary player-contact outcomes remain declared, not canon. |
| P-request | W-clients/W-save/W-rejoin: competing stock requests and an uncertain response at disconnect, with each disposition above represented where the candidate supports it. | Merely submitted work appears committed, admitted work disappears, a result is applied twice, or a stale subject/world context affects a replacement. Replay a preserved request to test its disposition explicitly. |
| P-rebuild | W-authority/W-save: restore without reference scene objects or client caches, then run the same authoritative rule and real scene consumer. | Hidden scene state, cosmetic events, sockets or stale adapter handles are necessary to reconstruct authoritative stock or sequence. |
| P-invalid | W-save: truncated/failed input and validly decoded but semantically invalid disposable checkpoint variants. | A loader reports success after dropping, repairing or partially publishing required state, or damages the previous valid artifact/world on failure. |

For P-invalid, include missing required state, duplicate identities, dangling
topology/containment/assembly references, invalid material quantities, conflicting
owners of the same transfer stock, and incompatible process phase/input facts.
An unmet W-count precondition is a valid stalled world, not corrupt save data:
missing, insufficient, surplus and wrong-kind batches must remain loadable for
recovery. The malformed cases concern contradictory ownership/references or
phase facts under the declared rules, not merely an invalid production input.
These are malformed logical cases, not a prescribed file grammar. Also name
unsupported rules/format versions if the candidate introduces them; reject
unknown behavior-affecting state rather than silently inventing defaults.
Optional diagnostic metadata can follow an explicitly declared compatibility
rule. No migration or recovery framework is required by this probe.

Corruption rejection and continuation are separate claims: a parser that rejects
a truncated input proves neither exact-material restoration nor moving-player
equivalence. Conversely, a successful happy-path continuation does not prove a
malformed load leaves the running world intact. Record the reason, unchanged
pre-load authority/artifact and ability to continue the prior valid world after
each rejected input; use copies rather than destructive tests on user saves.

## Evidence packet and remaining decisions

Extend the [common artifact packet](prototype-witness.md#expected-artifact-packet)
with the checkpoint's exact candidate/witness/rule revision, coherent capture
boundary, owner inventory, original artifact identity/integrity evidence,
request dispositions, client/world context and fixture reset. Retain the
reference and restored intent/outcome traces, independent expected projection,
first divergence report, negative-input construction and rejection evidence.
Record which facts were reconstructed and the tested reason omission was safe.

Separate automated accounting/continuation assertions from visual inspection of
the actual character/contact/correction join. Actual user play remains its own
evidence type; this document and passing repository checks prove none of those
runtime results. Mark every probe not run, pass, fail or unsupported with its
artifact and narrow claim. State limits on supported checkpoint phases and
environments; do not report only the convenient idle checkpoint.

Still open: production serialization and schema/versioning, migration/backup and
crash durability, save scheduling and performance budgets, authority/time/order
implementation, networking/session protocol and duplicate handling mechanism,
engine-owned physical-state representation, team/world progression, offline
production, player reconnect placement/presence, stopped/docked editing, injury
and other detailed contact consequences. Fixture assumptions must remain
labelled until the appropriate decision accepts them.

The persistence owner and network/mechanics owners should reconcile the capture
and request boundaries before their executable trial; root review checks the
combined witness and its actual consumers. No main landing, tracker repair,
download or executable persistence work is authorized by this proposal.
