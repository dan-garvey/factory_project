# Authoritative core and candidate trial proposal

Status: proposal for `factory-yau.3.1`, drafted against `01b929a`. This document
does not approve a trial or select an engine, language, simulation model,
determinism guarantee, networking library, or rollback strategy. Those choices
need evidence and the distinct decisions in [ROADMAP.md](../../ROADMAP.md).

[DESIGN.md](../../DESIGN.md) owns accepted requirements and open gameplay choices.
The relevant source sections are **Separate rules from their presentation**,
**Multiplayer from the first representative prototype**, **Engine evaluation**,
and **Construction and movement**. The proposed boundary below makes those
requirements testable without building a general engine abstraction.

## What the first trial would establish

One small authoritative mechanic should accept a command, change its owned state,
and expose the result to both a headless consumer and a 3D scene. The scene must
consume the result rather than implement a second version of the mechanic.
Exact item quantities belong to the authoritative rules. This is an integration
experiment, not evidence that the intended game is fun, scalable, or complete.

The common witness task, `factory-yau.6.1`, owns scenario identities, requirement
traceability, and assertions. This proposal owns the boundary exercised by those
scenarios. Motion, networking, and save authors can draft their fixtures in
parallel. Their specifications gate their own experiments; completing all of
them is unnecessary before collecting the first core/headless/scene evidence.

The first implementation remains blocked by bounded trial permission
(`factory-yau.3.2`). Production adoption (`factory-yau.3.5`) is a later decision.
A successful candidate must be reviewed and, where necessary, adapted under
`factory-yau.3.6`; prototype evidence does not automatically validate changed
production consumers.

## Proposed ownership at the boundary

Ownership means one authority decides a state transition. It does not require
one process, thread, source file, or final implementation language.

| Surface | Proposed authority | Consumer and evidence |
| --- | --- | --- |
| Factory entities, item locations/counts, processing phase, mechanical topology, and operating state | Authoritative rules | Headless assertions, scene views, server responses, and save/resume use the same owned state. |
| Requested changes | A caller submits intent; authoritative rules validate it against current state | A command identifies its subject and request, records acceptance/rejection or a defined duplicate outcome, and never grants the caller direct mutation access. |
| Accepted outcomes and observable events | Authoritative rules publish results derived from committed transitions | Presentation/network consumers can refresh from state; missing a cosmetic event cannot lose a product or repeat processing. An event log is not required as the persistence model. |
| Rendering, camera, input collection, UI, audio, and cosmetic interpolation | Presentation adapter | Visual state can lag or interpolate but cannot consume inventory, complete recipes, or decide a stall independently. |
| Player movement, collision geometry, and contact queries | An explicitly reviewed core/engine join; its authority is an experiment question | Record which side produces contacts, which side decides gameplay effects, and how the headless consumer obtains equivalent required information. |
| Admission/order of external requests | The authority hosting the rules, using a declared trial policy | Single-player and server paths exercise the same rule checks; no client-only success path or universal shared progression assumption. |
| Durable state and restoration | Persistence adapter reads/restores the state owned above through a defined boundary | Saving must include relevant pending work; loading does not reconstruct authoritative quantities from scene objects or replay cosmetic events. |

Command names and wire formats are deliberately absent. Semantic examples are
placing a stationary component, requesting a transfer, or supplying a declared
fixture input. They are not a settled API or permission to edit machinery in
motion. Stopped/docked editing conditions remain open.

For each command, the trial should expose the request identity, authoritative
subject identity, precondition result, accepted state transition, and resulting
observable revision or equivalent ordering evidence. A rejection/stall must be
distinguishable from an operation still progressing. Whether observers receive
snapshots, deltas, events, or a mixture remains a candidate decision.

The common witness's observation contract maps fixture labels to actual candidate
identities and distinguishes submitted intents from accepted commands/outcomes.
It records relevant before/after quantities, topology, process/motion phase,
contact and transfer state, client corrections, and save/rejoin checkpoints.
These are observation needs, not an API schema or transport choice. The two
proposal owners have reconciled this interface in the linked Beads tasks.

## Exact quantities and recoverable operations

Discrete item counts need exact authoritative accounting. This does not choose a
bit width, storage format, or representation for later fluid/gas quantities.
Define the accounting boundary across inventory, in-process material, moving
transfers, and outputs. Declared fixture sources/sinks must be explicit so a
repeatable test source cannot masquerade as a selected infinite-world source.

An accepted operation must have a coherent result: input material is retained
in a named owner or accounted for in the produced output. A failed precondition,
interrupted transfer, or stalled process cannot silently destroy or duplicate
it. For the exact-count witness, extra/wrong input stalls until manual or
designed recovery; testing that late-game mechanism early does not move its
player-facing unlock earlier.

The implementation must explain its commit boundary and any in-flight work.
This might be an atomic transition, explicitly owned work-in-progress state, or
another mechanism with the same observable accounting. The brief does not
mandate a transaction framework. Duplicate requests and restored pending work
need defined outcomes through the real consumers, not an assumed transport
guarantee or a second recipe calculation in the UI.

## Alternatives the evidence must distinguish

| Question | Alternatives to evaluate | Discriminating evidence |
| --- | --- | --- |
| Identity across consumers | Persistent world/entity identities with ephemeral adapter handles; other schemes with an explicit restore/remap boundary | References remain usable after save/rejoin and object replacement; a stale scene handle cannot mutate a different entity. No identifier format is selected. |
| Advancing authoritative time | Fixed logical steps, scheduled events, or a documented hybrid | Explain when commands/contacts enter the model, what advances without rendered frames, and what is retained on pause/save. Keep simulation advancement, snapshot sending, and rendering separate. |
| Concurrent command order | Explicit sequence/admission order, batched conflict resolution, or a bounded alternative | Two competing edits/transfers have inspectable accepted/rejected outcomes. Replay a recorded order where supported; do not infer ordering from callback arrival or UI frame order. |
| Randomness, if the witness needs any | No randomness for the initial fixture; controlled stateful streams; keyed draws | Record algorithm/state or draw identity and the restoration boundary. An uncontrolled global random source must not hide the cause of a differing outcome. Avoid introducing randomness solely to exercise infrastructure. |
| Reproducibility and correction | Deterministic rule regions, authoritative snapshots with correction, selective replay/prediction, or another measured combination | Name the tested equivalence and supported environment. Byte-identical whole-world state and whole-factory rewind are not assumed requirements. Exact quantities still must agree. |

Each trial record distinguishes an assumption needed to run a fixture from a
proposed reusable contract. A failed assumption is useful evidence; it is not
permission to quietly change the witness or the gameplay requirement.

## Engine, character, and collision joins

The difficult seam is a moving assembly affecting an actual character while
authoritative processing and transfers continue. A parented transform or video
of motion cannot establish the candidate's movement/collision/authority join.
Later motion evidence should use the candidate's real movement and collision
path, even with primitive visuals, and include a train-like constrained assembly
as well as the rotary/gantry fixture.

Two candidate boundaries are worth testing where relevant: core-owned motion
with engine geometry/contact queries, or engine-owned physical state admitted
through an explicit authoritative adapter. A third arrangement needs the same
ownership explanation. Neither route is selected here, and no freely simulated
rigid-body model is implied. A candidate that cannot provide its required
headless contact/movement information has an integration gap to report.

Record coordinate spaces, parent/assembly identity, when contact evidence is
sampled, which state revision it describes, and who resolves a conflicting
command. The broad accepted obstruction rule is connected-drivetrain stall
without machinery damage, with isolation through clutches/slipping couplings.
Intended tool/material contact needs to be distinguished from obstruction.
Independent-machine pushing, detailed player injury, final collision feedback,
and docking/editing rules remain deferred. Temporary contact assumptions must
be visible in the fixture and results.

Recorded contacts can isolate and reproduce a rule failure. They do not prove
that live engine contacts are correct. The combined witness must eventually
exercise live contacts, moving passengers, harvesting, moving/fixed transfers,
network correction, and save/rejoin through the actual joins.

## Bounded candidate comparisons

Godot and Unreal are candidates already named in DESIGN, not recommendations
made by this proposal. No version, installed availability, package size, or
binding capability has been verified by this task. The execution packet must
name and verify those facts before requesting a download or a build.

Compare an explicitly named engine/core integration route using the same first
mechanic and consumer assertions. Useful contrasts are:

| Route | Question answered | Scope and limitation |
| --- | --- | --- |
| Separate core with a thin in-process engine adapter | Can rules run headlessly and feed a real scene without duplicating state or rules? | Exercise one command, result/view transfer, build loop, and error path. Measure binding/ownership costs; do not build a cross-engine framework. |
| Engine-native rules with a headless consumer | How much iteration simplicity is gained, and which mechanics become engine-dependent? | A comparison baseline, not acceptance of reduced portability. State exactly what another host would have to replace. |
| Separate process/message boundary, if a concrete integration problem warrants it | Does isolation resolve that problem at an acceptable operational cost? | Conditional alternative; do not implement IPC, distributed services, or a generic protocol merely to complete a matrix. |

Run one approved candidate/route at a time on the sole test machine. A useful
comparison does not require implementing every route in every engine. The
permission packet names which paths receive executable evidence and which get
only feasibility inspection; incomplete comparisons must remain visible.

The initial scope is one declared mechanic, one headless consumer, one scene
consumer, one deliberate failure witness, and one edit/rebuild/run iteration.
Networking, moving-player, and persistence tasks then add their bounded
witnesses. Platform recommendation uses the combined evidence rather than
extrapolating from the initial successful command.

## Download, disk, and iteration budget

This proposal task has a zero-download/runtime-install allowance and adds only
this text. It authorizes no engine setup. The runbook's past free-space snapshot
is not an allocation: measure current capacity before preparing a trial.

The `factory-yau.3.2` packet must fill every field below with a bounded value and
owner before executable work. An unknown size is an unresolved budget, not an
unlimited allowance. Proposed counts above bound the first integration surface;
the approver still needs actual byte and wall-time caps for the named candidate.

| Budget field | Required approval record and stop condition |
| --- | --- |
| Downloads | Exact packages/versions/source, verified size estimate and maximum total new downloaded bytes. Count retries and prerequisites. Stop before an unlisted download or exceeding the cap. |
| Peak disk increase | Allowance for downloads plus simultaneous archive/unpacked files, toolchain, build cache, outputs and retained evidence, on each affected filesystem. Stop rather than delete unrelated artifacts or lower a floor. |
| Build/iteration work | Maximum setup/build wall time, allowed iteration count, and named commands. Record cold setup separately from incremental edit/build/play and headless runs. Stop at the cap or an unexplained repeated failure and report the bounded gap. |
| Retained artifacts | Owner, paths, retention allowance, and preservation of the reproducer/result before any separately scoped disposal. No blanket cleanup of another worktree or shared caches. |
| Expansion | Adding another candidate, integration route, source build, dependency, or larger witness needs a revised scoped budget; it is not automatic continuation of the first trial. |

Use the repository's cooperative admission policy: eight-job supported-tool
settings, a 20 GiB free-disk floor and 8 GiB available-memory reserve for heavy
work. These are operational settings, not game targets, hard quotas, or reserved
bytes. The planned peak increase must leave the floor plus agreed headroom;
admission checks alone cannot enforce the download/build allowance over time.
Use `heavy` for setup/build/test workloads and `benchmark` for controlled timing,
with an agreed quiet period. Do not nest wrappers or wrap `git commit` itself.
An unavailable budget is a resource limit to record, not proof an engine is
architecturally unsuitable.

## Evidence and failure witnesses

Each candidate result should retain the common witness identity/revision,
fixture assumptions and source/sink accounting, code revision, environment and
package versions, exact command trace/order policy, authoritative outcomes and
state assertions, actual headless/scene consumers, commands/results, resource
usage, and known unsupported cases. Keep correctness, emitted/architectural
evidence, physical timing, and eventual human play observations distinct.

Useful early falsifiers are a command accepted only in the graphical path;
quantity drift caused by scene updates; a rejected request or duplicate
application changing inventory; a stale identity targeting a replacement object;
frame/callback order becoming an undocumented rule; or headless execution requiring a scene's
hidden state. Later witnesses add live contact/character divergence, conflicting
client edits, and loss/duplication of in-flight work after save/rejoin. A scoped
unsupported case can be reported honestly; a green demo must not stand in for
the missing assertion.

Compare equivalent work when recording iteration costs and later timings. State
whether initialization, compilation, loading, rendering, and instrumentation
are included. Record variation rather than inventing a speed threshold, target
tick rate, factory size, player count, latency budget, or acceptable correction
model. No measurement in this task establishes a game-scale performance claim.

## Review and handoff

Before trial approval, the integration owner reconciles this boundary with the
common witness and names remaining experiment assumptions; unresolved chapter
content, full campaign rules, and final progression schemas need not block
neutral technical evidence. Before production adoption, independently review
the combined candidate and its actual state owners, engine/character joins,
network and persistence consumers, costs, failures, and portability limits.

Record the proposal revision, witness revision, accepted trial scope/budget,
open decisions, exact experiment evidence, and next owner in Beads. Preserve a
small reproducer for a failed boundary instead of repairing a different
subsystem inside an unbounded spike. The prose/checks for this proposal prove
only a reviewable experiment plan; they do not prove executable mechanics or
authorize implementation.
