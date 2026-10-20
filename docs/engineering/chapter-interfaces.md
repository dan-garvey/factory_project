# Chapter progression, logistics and source boundaries

This documentation contract covers `factory-yau.2.6`. It maps accepted design
requirements and the reversible [ownership experiment](progression-ownership-trial.md)
to responsibilities for a later chapter implementation. It adds no server API,
checkpoint schema, progression code or requirement to the current opening.

The requirement sources are [progression and teaching](../../DESIGN.md#progression-and-teaching),
[inventory and acquisition](../../DESIGN.md#inventory-and-resource-acquisition),
[multiplayer ownership](../../DESIGN.md#multiplayer-and-progression-ownership),
[quest completion](../../DESIGN.md#quest-completion) and
[lasting supply](../../DESIGN.md#resource-pressure-without-recurring-manual-replacement).
The ownership experiment selects defaults for a bounded trial; its choices do
not settle permanent campaign policy.

## Keep the owners distinct

The existing native World remains the single material authority. Session binds
authenticated requests to actors, and Store retains the authoritative checkpoint.
Future learning and campaign records need explicit owners, but that distinction
must not create another quantity map, client simulation or stock fallback.

| Concern | Required boundary | Status |
| --- | --- | --- |
| Physical items, machines, deposits and terrain | One shared authoritative world; learning or campaign credit cannot duplicate or move physical goods. | Accepted requirements. |
| Learning pace | People can retain their own pace while cooperating. A server-wide completion flag is insufficient to represent that choice. | Accepted requirement; exact permanent sharing remains open. |
| Lessons and recipe entitlement | Keep the learner's records separate from work-team membership and campaign credit. Campaign opt-in does not complete lessons or grant recipes. | Ownership-trial choice. |
| Campaign credit | An explicitly selected solo or shared campaign receives its allocated commission credit. Joining a work team does not silently select a campaign. | Ownership-trial choice. |
| Access | Knowledge of an item or recipe does not supply physical delivery or permission to withdraw another holder's stock. | Accepted location requirement; detailed permission policy remains open. |
| Ordinary completion | The player confirms possession of requested products; this does not prove manufacturing or sustained automation. The trial's inventory check consumes nothing. | Accepted starting preference and reversible nonconsuming default. |
| Off-site delivery | Credit and terminal material use occur together at the recipient, using the declared allocation. Loading or transit alone grants no credit. | Ownership-trial choice; transport remains unimplemented. |
| Throughput completion | The true ending measures specified end-game production rates separately from ordinary checks. | Accepted direction; products, rates and measurement are open. |

The trial's personal recipe entitlement must not be presented as a permanent
unlock model. It also does not make all recipes available to a new player or
guarantee access to an experienced team's equipment.

## Conceptual records

These are information boundaries, not wire messages or a selected persistent
layout. Identifiers distinguish their owners even if a future implementation
stores them in one checkpoint. Identifier encoding, count bounds, migration and
versioning still need a concrete implementation decision.

| Record | Information a later adapter must preserve | Meaning it must not imply |
| --- | --- | --- |
| Learner record | Learner identity, offered and completed checks, applicable recipe entitlement, and seen or deferred explanations. | Every campaign member completed the same lesson. |
| Work-team access | Actor, affected holder or machine, and the permission being exercised. | Membership owns all nearby goods or selects a campaign. |
| Campaign participation | Campaign identity, explicit opt-in or departure, and its credited orders. | A copied personal learning record or a quantity holder. |
| Physical holder | Stable holder identity, actual location or containing machine/cargo, typed contents, and applicable access and capacity. | A globally withdrawable inventory because a catalogue can find it. |
| Inventory confirmation | Learner, offered objective and observed eligible inventory at authoritative admission, plus its historical outcome. | A debit, remote stock reservation or proof of automation. |
| Cargo and allocation | Cargo holder, typed contents, source, recipient, offered order identities and fixed beneficiary quantities. | Credit before receipt or more allocated goods than the cargo contains. |
| Recipient disposition | Original request identity, accepted or refused result, terminal project use and the corresponding credit. | A second available copy of consumed cargo. |
| Resource source | Source identity and location, its route kind, finite remainder where applicable, and the conditions for actual extraction. | A universal infinite-resource flag or an unlock caused by exhaustion. |
| Supply capability | The relevant technology milestone and route eligibility. | Replenishment of an exhausted node or guaranteed transport capacity. |

Contents retain their material kind, exact quantity and any required work state.
An ore count is not interchangeable with a plate count; transformation accounting
belongs to the selected recipe. The six-plate example below conserves plates
because it contains no further processing. A future codec must reject malformed,
overflowing or incompatible counts rather than rounding them into valid custody.

## Command and observation responsibilities

The following operations name responsibilities rather than public function names.
They must consume the existing authority and request-history boundaries when
implemented; this document introduces no competing service or second ledger.

| Operation | Admission and committed result |
| --- | --- |
| Observe stock or an explanation | Publish only permitted information. Discovery does not debit a remote holder, grant access or mark learning complete. |
| Confirm an offered inventory check | Bind the learner and objective to the actual eligible inventory. Under the trial, record completion once without consuming or reserving those items. |
| Build or operate | Retain the applicable physical reach, parts, recipe and permission checks. Operating permitted machinery does not itself grant its recipe. |
| Load or unload cargo | Transfer actual typed contents between the authorized source and cargo holders. Loading creates neither recipient credit nor terminal use. A return requires a real transfer route. |
| Hand cargo to its recipient | Check the frozen allocation, remaining order demand and current authority. Refuse the whole handoff if it no longer qualifies; otherwise commit terminal use and the declared credit together. |
| Look up an uncertain outcome | Reconcile the original identity before retrying or replacing its use of the same cargo. Return the historical disposition without retargeting its beneficiary or recreating goods. |
| Change team or campaign | Preserve physical goods, personal trial learning and accepted historical allocations. New operations use current permission; old credit does not migrate to the new campaign. |
| Extract from a source | Apply the selected physical source rule and transfer its actual yield to an authorized holder. A capability unlock is not an extraction result. |

Membership can change while a handoff is unresolved. Reconciliation is required
before retrying that handoff or reusing its cargo, not before changing membership.
The original actor may retrieve their own receipt after departure without gaining
general access to the former team's stock, machinery or other actors' receipts.
An accepted outcome is historical even if current permission would refuse a new
operation. A genuinely unadmitted operation still checks current permission and
its original allocation. A replacement allocation needs a new explicit request
after the old disposition is resolved.

Client observations must distinguish confirmed disposition from a pending or
unresolved delivery. A missing response proves neither acceptance nor refusal.
Identity retains the original authority context, actor and complete caller-scoped
request key; a bare sequence number is insufficient. Keep the original intent,
allocation and outcome together rather than reconstructing them from current
membership or poses.
The existing [uncertain-request contract](../proposals/stationary-authority-contract.md#uncertain-requests-at-disconnect-and-restore)
supplies that boundary; no blind automatic retry is selected here.

## Source lifecycle and supply access

Keep source state separate from learning and campaign state. An early finite
deposit remains exhausted after extraction. Rejoining, receiving a recipe,
changing campaign or unlocking a lasting-supply route does not refill it.

| Route | Required distinction | Still open |
| --- | --- | --- |
| Find and exhaust finite nodes | Extraction permanently reduces the actual node. Repeating discovery remains a valid simpler route. | Deposit sizes, travel burden and survey mechanics. |
| Qualifying infinite source | Supply depends on the selected physical source and its extraction conditions. Stored inventory alone is not an infinite source. | Eligible materials, thresholds, geometry and machinery. |
| Autonomous finite-source acquisition | Surveying, acquisition, extraction and delivery must all be covered by the engineered route. Automating only a final transfer is insufficient. | Vehicles, route handling, access and replenishment implementation. |
| Active recovery cycle | A later route requires meaningful designed operations and coordination, rather than passive waiting at a lower average rate. | Process phases, dependencies, yield and unlock. |

Lasting-supply availability follows a technology milestone after initial
extraction is established. Exhaustion supplies a reason to build that route,
not its unlock trigger or timer. Which actor or campaign owns a permanent
milestone remains open; the ownership trial cannot silently settle it for all
future source systems.

Required capabilities need an exploration route and a more demanding in-base
route in the same world. A reachable, permitted source, safe access, starter
parts and the complete feedstock and transport path must actually exist. A
personal uncompleted lesson alone does not provide that opportunity. A trial
without such access must report the case as unsupported instead of refilling
nodes, teleporting inputs or granting technology because a deposit emptied.

## Bounded scenarios for later implementation

These are paper acceptance scenarios. They are not retained runtime results,
new item recipes or new requirements for the existing four-plate opening.

| Scenario | Expected boundary |
| --- | --- |
| A newcomer joins an advanced team but keeps a solo campaign | Team membership does not finish personal learning. Existing machinery and stock remain in the shared world, subject to actual access. |
| A learner receives two plates as an explicit gift and confirms an offered two-plate check | Custody moves once. The nonconsuming trial check leaves two plates and grants no proof that the learner manufactured or automated them. |
| A catalogue lists two plates in an inaccessible chest | The observation does not make them eligible carried inventory or permit withdrawal at a distance. The exact future construction-cache coverage rule remains open. |
| Six plates are loaded for three declared two-unit allocations | Carried plates decrease by six and cargo gains six. Credit and terminal use remain zero until the recipient accepts. |
| That six-plate handoff succeeds but its response is lost | Cargo becomes zero and terminal project use becomes six. Reconciliation returns the original three allocations; no second shipment or available copy appears. |
| The caller changes campaign before that reconciliation | Membership may change. The old request still credits its original beneficiaries, and its cargo cannot be retried or reused before disposition is known. |
| Permission is revoked before an unadmitted recipient handoff | The whole handoff may refuse, leaving the six plates in their actual holder. A lost response alone cannot choose this outcome instead of the accepted case. |
| A node empties before a supply milestone | The node stays empty. Do not unlock technology, start a regeneration timer or reset stock. The implementation must identify another viable route or report the unsupported access case. |
| A lasting-supply milestone is later earned | It enables its specified route, not all materials or all source kinds. An exhausted original node remains exhausted. |
| A player reconnects after terrain and factory changes | Restore the actual world and historical dispositions. Offer the learner's retained explanations without restoring old terrain or inventing practice inputs. |

## Persistence and unresolved interfaces

A later checkpoint must consistently preserve the identities needed to reconcile
physical custody and accepted credit. It cannot restore available cargo without
its accepted terminal-use disposition, rename a referenced campaign on departure,
or discard a receipt merely because membership changed. Permission to retrieve an
own receipt remains distinct from permission to inspect another team's world data.

This does not select an account service, permission system, world streaming
scheme, save migration, transport object, network ordering algorithm or database
transaction layout. Source thresholds, starter access, unlock rewards, chapter
content and permanent learning/campaign sharing also remain open. End-game rate
measurement needs a separate contract with selected products and timing rules.

The current native opening remains its existing finite fixture. Its inventory
goal and Store evidence do not establish these later delivery, source or learning
systems. Implement each selected increment against the same authority, with
relevant tests and honest scope, rather than adopting every conceptual record at
once or making this document a new opening dependency.
