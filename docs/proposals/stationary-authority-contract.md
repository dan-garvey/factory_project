# Stationary authority and two-client experiment

Status: bounded experiment specification for `factory-yau.5.1`, drafted against
`b0bf95c`. No executable networking, selected engine, transport, arbitration
algorithm or gameplay content follows from this document. It prepares `.5.3`
on the basic-opening path to `.6.10` and actual feedback `.6.11`.
[DESIGN.md](../../DESIGN.md#first-chapter-basics-before-elaborate-machinery)
owns the accepted collector → machine → product shape and open choices.

## Fixture boundary

Use one authority, two clients P/Q and stationary equipment. Name one input
kind, one processor transformation and physical input/output locations only
after the candidate scope supplies them. Neutral technical stock may be a
declared fixture; it must not masquerade as accepted chapter content or an
infinite world source. No custom carrier, passengers or moving transfer is
needed. The processor can have work in progress while its structure stays fixed.

Declare provisional P/Q access to the test stock and construction sites; shared
fixture access grants no personal/team/world unlock or completion credit. State
what placement, connection, stock interaction and blocked-output actions the
candidate actually supports. Its real commands must exercise these cases;
editing database values or a disconnected mock scene is diagnostic evidence only.

Single-player uses the same authoritative validation and transition path as the
server. The headless consumer, both scene clients and later save adapter observe
that owned state. Rendering an item or an apparent successful placement cannot
debit stock, finish a process or authorize another command independently.

## Record before running

For each intent, identify client/request, current world/authority context, actual
target identity, relevant preconditions and authoritative result/order evidence.
These are observation requirements, not field names or a wire format. Distinguish
intent submission, admission, application and client acknowledgement. Record
accepted pending work and its material owner where those stages are separate.

Declare the candidate's conflict/ordering policy before observing outcomes:
sequential admission, a resolved batch or another bounded policy can qualify.
Document dependent-command handling and stale/duplicate-request recognition.
Do not derive an unexplained winner from render callback order, or label client
send order as the authority's accepted order. No particular winner, fairness,
latency, exactly-once delivery or whole-factory rewind guarantee is selected.

Expose an independently inspectable projection: entity/reference identities,
topology, item kind/count/location, process-held work/output and request outcomes.
For each material kind, initial stock + declared sources + transformation outputs
− transformation inputs − declared sinks must equal all current locations,
including owned work in flight. Recipe changes are explicit transformations;
adding unlike material counts into a single conserved total is insufficient.

## Bounded cases for the actual consumers

The labels below refine the stationary portion of W-clients/W-rejoin in the
[common witness](prototype-witness.md#cases-and-observable-invariants). Passing
them does not pass those witnesses' broader moving/precision cases.

| Case and controlled setup | Required observations and discriminating failure |
| --- | --- |
| S1 — Baseline path | Run the same supported place/connect/input/process/retrieve intents through single-player and server/headless paths. Compare logical outcomes at equivalent advancement, then view the actual server result on P/Q. A UI-only success or second recipe calculation is a failure. |
| S2 — Conflicting placement | P/Q both request a site for which the declared fixture placement rule admits only one structure. Hold both intents before authoritative admission, then release under the declared policy. At most one conflicting structure and its associated cost can commit; refusals cannot consume parts. Also place at nonconflicting sites as a control. This fixture precondition does not select final dimensions/collision UI. |
| S3 — Contested quantity | Put one unit in a location P/Q may both access; issue competing requests whose combined cost exceeds it. No outcome can overdraw or credit the same unit to two owners. Record winner/refusal/pending states under the declared policy, then repeat with sufficient stock as a positive control. Never assert a named client must win unless the declared schedule establishes it. |
| S4 — Dependent/stale intent | Delay placement acknowledgement or delivery of a dependent connection/interaction. Deliver the dependent intent before its precondition exists, then after it exists. Reject, defer with owned pending state, or require resubmission as declared; never silently create a target or connect another entity. If target replacement is supported, reuse its old visual position and show an old reference cannot mutate the replacement. |
| S5 — Reordered observations | Hold a response/view update while another accepted transition advances the authority. Release the older observation afterward. P/Q must converge to current authoritative stock/topology; stale presentation cannot fund another transfer or undo committed state. Record what corrects/replays/interpolates and which state is confirmed. No prediction is required merely to demonstrate this case. |
| S6 — Disconnect while authority continues | Pause at a declared request boundary, disconnect P, let Q and the processor continue, then rejoin P through the real client/server path. P obtains current stock, topology, held work and request disposition before retrying uncertain work. Disconnect itself creates no stock debit/credit; returning client inventory is not authoritative. |
| S7 — Integrated continuation | In the later `.5.4`/`.6.10` candidate, repeat the uncertain-request observation around a coherent partial-production save and fresh-authority restore. Verify actual subsequent processing and client convergence, not merely a successful load or matching first frame. Carry the same ownership/request facts across the save boundary. |

Exercise deliberate delivery/order control using explicit barriers, a supported
transport seam or another documented mechanism. Log release and accepted order;
do not rely on sleeps, repeated retries or unrecorded latency to obtain a race.
At least one controlled order change must distinguish the contested cases from
two unrelated serial commands. Preserve the failing schedule when a case fails.
An unsupported command/stage is reported as such, not replaced by direct state
mutation and called a pass. S7 belongs to combined continuation; its execution
does not block writing or reviewing this stationary specification.

## Uncertain requests at disconnect and restore

Preserve the distinctions requested in `.5.1` comment 50 and the
[save/resume contract](save-resume-contract.md#client-and-request-continuation):

| Authoritative disposition | Rejoin/restore obligation |
| --- | --- |
| Submitted but not accepted | A queued intent/animation is not committed work. Establish whether it remains unaccepted and whether a new submission is allowed under current preconditions. |
| Accepted and pending | Retain the owned work and quantities, or demonstrate the coherent boundary resolved it before capture. Expose pending/completed/accounted failure; admission cannot disappear on disconnect. |
| Applied, acknowledgement absent | Keep its applied effect. Releasing/repeating the old request must not unknowingly apply that effect again; a retained outcome, duplicate/stale refusal or another evidenced mechanism can establish this. |
| Rejected/cancelled/terminal | Preserve the meaning and any retained/routed stock. Reconnection cannot turn a refusal into an unnoticed success; a newly intended request is assessed against current state. |

Exercise each boundary the candidate represents. If admission/application is
atomic, document that and test both observable sides rather than inventing a
pending stage. Hold an acknowledgement separately to expose the applied-but-
uncertain case. A transport receipt is not the authority's commit boundary.

After restoration, establish current world/authority context before admitting
client work. Test an old queued request against changed current facts; it cannot
retarget an unrelated restored/replacement entity or unknowingly repeat prior
effects. This does not select an epoch encoding, durable request log, deduplication
window, account system or production retry protocol. Unknown disposition must be
visible and prevent blind retry; it cannot be disguised as a confirmed failure.

## Evidence and handoff to implementation

Before claiming `.5.3`, record approved environment/scope, candidate/rule/fixture
revision, provisional access and supported commands, conflict/dependency policy,
context/request recognition and exact build/run commands. Obtain named trial
permission `.3.2`; this document grants no install or executable budget.

Keep initial/final and checkpoint projections, submitted/released/admitted
orders, outcomes, P/Q correction observations and the first divergence. For
every supported schedule, assertions must inspect actual authoritative owners
and actual clients after declared convergence; a screenshot alone proves no
quantity or request invariant. A headless-only adapter test cannot establish
that the real graphical correction/rejoin path works.

Mark each case not run, pass, fail or unsupported, with evidence and a narrow
claim. **Every runtime case here is currently not run.** Record automated results
separately from visual inspection and eventual user play. `.6.10` must rerun the
relevant stationary/concurrency and partial-production continuation cases in the
integrated basic demo; separate green core/network/save spikes are insufficient.

This specification selects no networking library, prediction model, tick/player/
latency target, final progression/access policy, offline production rule,
reconnect placement or disconnect-player-presence behavior. Declare any such
fixture assumption before execution without treating it as game canon.

Moving-passenger/transfer authority, delayed-command correction and persistence
joins are explicitly `.5.5` specification work before that moving probe; `.5.6`
adds moving save/rejoin. Those later cases and `.6.2`'s broader combined witness
remain unproved. Do not require their specification or implementation to pass
this stationary outcome, and do not claim stationary evidence solves them.
