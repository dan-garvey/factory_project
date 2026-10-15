# Common prototype witness — proposal

Status: proposed evidence plan, not implemented or approved playable scope. No
runtime, engine, language, networking library, recipe, or performance target is
selected here. A paper procedure is not a completed test. Candidate trials need
their own bounded permission and resource budget; first-playable approval and
production-stack adoption remain separate decisions in [the roadmap](../../ROADMAP.md#convergence-and-decision-gates).

This witness gives candidate experiments a common set of observable questions.
It complements the authoritative-rule brief and the mechanics/network/save
workstreams; it does not prescribe their APIs or replace the first-chapter
challenge. A technically successful testbed does not establish invention,
teaching quality, progression, game-scale performance, or a satisfying game.

## Source contract

These links distinguish requirements from the proposals being tested:

| Source | What the witness carries forward |
| --- | --- |
| [Reference experiences](../../DESIGN.md#reference-experiences-supplied-by-the-user) | Directional gearing, exact quantities, and rotary/gantry scaling should have observable consequences. Original recipes and assets are unnecessary. |
| [Construction and movement](../../DESIGN.md#construction-and-movement) | Construction alignment, required motion families, operation/harvest/transfer/passengers in motion, and exclusion of edits during motion. Detailed docking and player-contact rules remain open. |
| [Complexity and automation](../../DESIGN.md#complexity-and-automation) | Invalid processing stalls; correction can be manual or designed; unintended obstruction stalls a connected drivetrain without machinery damage; couplings can isolate branches; fixed cycles precede required expressive controls. |
| [Inventory and acquisition](../../DESIGN.md#inventory-and-resource-acquisition) | Item location has logistical meaning. A repeatable test source must not settle depletion, lasting supply, or progression. |
| [Predictable motion](../../DESIGN.md#predictable-motion-and-physical-appearance) | Construction grid and operating transforms are distinct; intended tool contact differs from obstruction; independent pushing and detailed consequences remain deferred. |
| [Rules and presentation](../../DESIGN.md#separate-rules-from-their-presentation) | Proposed authoritative rules own quantities/sequence; headless and scene consumers need explicit observations; the actual character/collision join needs evidence. |
| [Multiplayer prototype](../../DESIGN.md#multiplayer-from-the-first-representative-prototype) | Proposed headless server/two-client setup, same authoritative rules in single player, simultaneous stationary edits, moving interactions, correction, reconnect, and persistent operation. No universal rewind or numeric network budget is selected. |
| [Candidate prototype](../../DESIGN.md#candidate-prototype--revised-proposal-not-a-commitment) | A neutral mechanical testbed, later-progression precision probe, early moving-world risks, and repeatable resource fixture are proposals rather than selected content. |
| [Independent design review](../../DESIGN_REVIEW.md#prioritized-findings) | Technical evidence must eventually join inventive layouts, meaningful verticality, construction/diagnosis, and actual player experience. |

## Repeatable fixture

Prepare a manifest and reset procedure before a trial. Keep the same manifest
and intent sequence when comparing candidates; record any necessary adaptation
and which comparison it invalidates. Initial setup/reset may inject test stock
outside the measured scenario. During a run, account for every material change;
do not replenish invisibly or use reset as recovery evidence.

Use neutral aliases such as `feed`, `supplement`, and `result`, with an explicit
symbolic bill of materials and selected exact quantities in the run manifest.
These are developer-test values, not proposed game recipes or chapter unlocks.
Specify permitted consumption, outputs, retained inputs, and transfer boundaries
before observing results. An independent accounting ledger must explain the
change, rather than deriving its expectations from the implementation's output.

The fixture has replaceable stations sharing one logical world:

- A stationary construction pad with a mechanical source, a direction-changing
  gear path, a feed/output route, and a complete functional process head.
- A precision cell with accessible input storage, a positive process condition,
  and an explicit way to remove surplus input or route it back. A developer-only
  metering/recovery probe may be separate from the fixed-cycle early-motion path.
- Comparable rotary and orthogonal gantry arrangements acting on the same
  neutral work opportunities. Record their swept/working spaces, gear direction,
  feed access, and an extension of the same arrangement. No unlock order is implied.
- A constrained train-like carrier with a deck and attached working apparatus,
  a stationary transfer station, and a marked intended tool/material encounter.
  It is one moving machine, not a test of one independent machine pushing another.
- A deliberately placed solid obstruction on a connected branch, a coupling that
  can isolate it, and an unaffected branch whose continued operation is observable.
- A chosen candidate's real playable character/controller and collision path,
  a headless authoritative world instance, and two clients with distinguishable
  command identities. The scene-backed single-player path must also be available
  for comparison. Test labels do not select team membership or progression ownership.

Give every station and relevant object a stable fixture label, and map that label
to the candidate's actual identity. Record construction alignment separately from
the operating frame. Capture geometric dimensions, fixed-cycle endpoints or
reversal conditions, permitted contacts and temporary transfer conditions in the
manifest. They are repeatability inputs to a bounded trial, not adopted world
units, docking rules, tooth physics, or production tolerances.

For a vertical variant, reserve a gravity/tool-face/clearance encounter whose
physical rule must first be explicitly chosen for the experiment. Record that
assumption. An attractive stack of machines alone is not evidence that height
changes operation; do not invent a material-decay rule to make the fixture pass.

## Cases and observable invariants

Case labels identify evidence, not an implementation order. Each case records
its starting manifest, submitted intents, actual accepted/rejected commands,
state before/after, and the failing observation if it cannot complete. Carry the
same objects through the combined run; isolated substitutes are diagnostic
coverage, not completion of the combined witness.

| Case | Exercise and observable invariant | Source |
| --- | --- | --- |
| W-build | Construct and edit the stationary mechanism through the actual command path, following the declared construction alignment. Both clients observe the accepted topology and item locations. Invalid/conflicting requests leave one coherent authoritative result and account for any stock change. Attempt an edit in motion separately; no moving edit is applied. This does not decide when a stopped assembly becomes editable. | Construction and movement; Multiplayer prototype |
| W-authority | Submit the same neutral rule case through the headless authority and the scene-backed single-player path. Compare authoritative quantities, processing decisions and topology outcomes. Presentation does not silently supply a second recipe or bypass a rejected command. This probes the proposed shared-rule boundary rather than requiring a particular engine abstraction. | Rules and presentation; Multiplayer prototype |
| W-direction | Run the gear path and compare observed direction/speed relationships with the declared topology. Change a relevant orientation or connection while stationary and repeat. The driven process/transport uses that result; a rotating decorative mesh alone does not qualify. Keep load/torque laws provisional. | Reference experiences; Rules and presentation |
| W-count | Submit the declared exact input condition, then a surplus-input variant. Only the valid condition completes the declared process. Surplus stalls without destructive cascades or unaccounted consumption/output; presentation cannot round the condition into success. Record process phase and every material location, not just the visible result. | Reference experiences; Complexity and automation; Rules and presentation |
| W-recovery | Preserve the stalled W-count state, correct it through the declared manual path, and observe continuation. Repeat with a separately declared designed recovery path. Track all routed/removed inputs and any accepted requests; reset, hidden replacement stock, and discarded failure state are not recovery. This late-control probe does not make expressive controls an early-game requirement. | Complexity and automation; Candidate prototype |
| W-geometry | Exercise rotary and gantry fixed-cycle motion with working tools/feed. Observe direction, reversal and working clearance through actual operation, including an operating pose away from construction alignment. Extend the same neutral work opportunity and record how each layout's swept space, access and feed path change. Do not infer the preferred layout, technology tier, or a throughput target from the fixture. The vertical variant additionally needs evidence that its declared physical constraint changes the outcome. | Reference experiences; Construction and movement; Predictable motion |
| W-obstruction | Introduce an unintended solid obstruction while connected machinery operates. The connected drivetrain stalls without machinery damage. Activate the declared isolating coupling; the unaffected branch can operate while the obstructed branch remains contained. Remove the obstacle and record recovery under the trial's stated re-engagement rule. Keep intended tool contact distinct from this obstruction. | Complexity and automation; Predictable motion |
| W-carrier | Run the constrained train-like assembly through its declared path while attached machinery operates. Construction alignment does not quantize every operating pose. Record attached topology, operation and contact state across movement/reversal. This is evidence about the moving-assembly join, not a complete train routing, docking or rigid-body system. | Construction and movement; Predictable motion; Candidate prototype |
| W-player | Board, move relative to the carrier, encounter a solid contact, and leave through the candidate's real controller, collision integration and authority/correction path. Observe the player body and authoritative result from both clients during motion/reversal. Parenting a dummy transform, camera motion, or a standalone collision mock cannot satisfy this case. Explicitly label provisional contact outcomes; do not adopt injury severity, pushing, respawn or docking rules. | Construction and movement; Rules and presentation; Multiplayer prototype |
| W-harvest | Let an operating moving tool encounter declared eligible material in its surroundings. Record the actual contact decision, source change and destination stock while motion continues. Repeat without eligible contact and verify no corresponding harvest. A temporary repeatable source proves neither infinite game resources nor a complete autonomous acquisition loop. | Construction and movement; Inventory and acquisition; Candidate prototype |
| W-transfer | Transfer between moving and stationary equipment under the manifest's declared temporary eligibility condition. Record source, in-flight ownership if any, acceptance and destination. Eligible transfer conserves the declared quantities; a noneligible/failed attempt creates no duplicate or disappearing material. Submit competing requests from the clients against the same available stock and explain the authoritative resolution without choosing production arbitration. | Construction and movement; Inventory and acquisition; Multiplayer prototype |
| W-clients | With both clients connected to one authoritative world, combine stationary edit conflicts, precision recovery and moving passenger/transfer actions. Deliver a repeatable delayed/reordered command schedule as an experiment. Observe accepted ordering and subsequent correction/convergence at a declared observation boundary; no client invents authoritative stock or topology. Record what is predicted, confirmed, interpolated or replayed rather than assuming whole-factory rollback. | Rules and presentation; Multiplayer prototype |
| W-save | Checkpoint at a declared safe stationary boundary and again during a meaningful moving/process/transfer state. Continue a reference branch, restore the checkpoint in a fresh authoritative instance, and submit the same subsequent intents, comparing their accepted/rejected outcomes too. Compare declared semantic state and outcomes: identities/relationships, stock locations, process/recovery phase, assembly motion and transfer ownership. Raw byte equality is not required; silently stopping or discarding in-flight state does not demonstrate it. Record unsupported checkpoint states rather than omitting them. | Rules and presentation; Multiplayer prototype; Candidate prototype |
| W-rejoin | Disconnect one client during combined operation; keep the authoritative world and other client running. Rejoin and inspect current topology, inventories, process and carrier/player state. Include an unresolved request at disconnect and establish its actual disposition without duplicate application or phantom stock. Repeat rejoin after the W-save restore. The run must declare its provisional player/request handling; this does not select offline production, team progression or reconnect placement policy. | Multiplayer prototype; Construction and movement |

"Conservation" includes the manifest's declared recipe transformations and sinks;
it does not mean every input must remain an unchanged output. Distinguish a
submitted intent from an accepted authoritative command, especially around save
and disconnect. A rejected, cancelled, pending or completed request needs an
observable disposition; retries alone must not make an accounting failure disappear.

## Combined run and evidence types

Start from the recorded reset, construct the stationary apparatus, verify the
direction path, then trigger a precision stall and recover it. Operate the rotary
and gantry variants and the train-like carrier with working machinery. Introduce
and isolate the obstruction, exercise actual player contact, and harvest/transfer
during motion. Keep both clients involved through conflicting requests,
correction, checkpoint/continuation and disconnect/rejoin. Restore and repeat the
relevant continuation in the same candidate build/configuration. This narrative
is a proposed run outline; its exact command schedule and checkpoints must be
written before execution rather than reconstructed from the successful attempt.

Record these evidence types separately for each case:

| Type | What it can establish | What it cannot establish |
| --- | --- | --- |
| Script/assertion | Reset and command replay, independent quantity accounting, state/phase/topology invariants, failed requests, declared continuation comparisons, and automated probes of the real candidate joins. Include input and failure logs. | Player understanding, comfort, enjoyment, or real character integration when the script uses a substitute. A headless-core pass does not validate a missing scene/controller consumer. |
| Visual inspection | The real scene shows tools, motion, contact, stock and both client views consistent with the recorded authoritative state; reviewers can inspect clearances and visible correction. Annotate cases and observations. | Exact accounting, correct authority, repeatability or performance from appearance alone. Video of a successful attempt cannot hide missing failed cases. |
| Actual user play | The user builds/edits, traces a drivetrain stall, repairs feeding/recovery, boards/operates the assembly and explains what they observed. Record confusion, assistance, attempted alternatives and the user's assessment. | A first-playable acceptance before agreed scope, or an automated technical result merely because the user watched it. An agent-operated demo, paper walkthrough or recording alone is not user play. |

Keep fields for each type as `not run`, `pass`, `fail`, or `unsupported`, with an
artifact reference and a narrow claim. A technical witness can be reviewed before
actual user play; its result must say user play is pending. First-playable work
must rerun the relevant combined cases in the integrated production candidate
and obtain the separately planned actual user session. Do not substitute this
neutral fixture for the chapter's new-product and inventive-layout challenge.

## Expected artifact packet

Keep an inspectable packet outside large checked-in payloads, referenced by the
task. A later implementation can choose filenames/formats without changing these
observation needs:

- Run identity: exact source revision, candidate/tool versions, invocation,
  build configuration, authority/client setup, machine/environment and resource
  admission. Mark adapted, unimplemented and manually assisted portions.
- Fixture manifest/reset: labelled layout and stock, symbolic process contract
  with instantiated test values, frames/contacts, fixed-cycle conditions, two
  client roles, any seed/randomness and all temporary rules. Verify reset state.
- Reproduction: ordered submitted intents plus actual acceptance/rejection and
  observation/checkpoint boundaries. Record how candidate time/update ordering
  is interpreted without prescribing a tick frequency or deterministic engine.
- Independent expectations and results: per-case assertions, material-location
  ledger, topology/phase/motion/contact/transfer observations, client corrections
  and semantic continuation comparison. Preserve the first failure and any fix.
- Save/rejoin material: checkpoint identity and integrity check, before/after
  state summaries, unresolved request dispositions, and failed/truncated-input
  experiments that demonstrate rejection without replacing a valid saved world.
- Visual record: both client views or clearly labelled captures around moving
  contact, obstruction/isolation, harvesting, transfer, correction and rejoin;
  correlate them with authoritative observations rather than editing only a reel.
- Review/play record: exact reviewed revision and cases, evidence type, reviewer
  findings, unsupported cases, user participation if any, known limits, follow-up
  owner and next decision. Do not describe tooling checks as runtime evidence.

## Deferred assumptions and decision handoff

Before execution, the bounded trial proposal must identify candidate-specific
fixture choices and obtain permission for the experiment. Unresolved choices do not become accepted
because a probe needs a value:

- Engine/language, scene/core boundary, character integration, command/event
  protocol, identifier representation, update order, randomness, prediction and
  replay scope, save format and transport remain candidates for the core brief.
- The exact tool vocabulary, recipes, ratios, resource types, extraction/recovery
  lifecycle, A/B/C content, unlocks and construction supply are not set by aliases
  or injected test stock. Infinite fixture supply is not a world rule.
- Construction units, operating geometry, intended contact eligibility, detailed
  coupling/re-engagement, stopped editing, docking and reattachment need declared
  provisional rules where exercised. Independent machine pushing stays excluded.
- Player injury severity, dropped-item contact, respawn, final camera/navigation,
  teaching UI and collision feedback remain open. Real player contact evidence
  is still required; deferring consequences does not justify a dummy passenger.
- Individual/team/world ownership and progression, joint credit, offline elapsed
  production and reconnect placement/request policy remain unresolved. Trial
  roles and continuation rules must not silently pick a shared progression track.
- No tick/frame/snapshot rate, player limit, factory scale, throughput threshold,
  latency target, download budget or production schedule is assigned here. The
  authorized trial must supply its bounded resource budget and report measured
  behavior without calling it a game-scale result.

The core brief owner should reconcile observation boundaries and the real
character/collision/authority join with this manifest before trial permission.
Mechanics, networking and save owners can refine the respective cases while
retaining source traces and visible unsupported states. Progenitor review checks
combined evidence and design fidelity; actual user decisions resolve playable
scope and remaining game rules. Writing this proposal completes neither gate.
