# Construction supply without remote withdrawal

Status: paper proposal for `factory-yau.2.4`, based on `cdc4d5c`. No cache range,
storage unlock, access policy, delivery component or playable scope is selected.
There is no implementation or play evidence. The alternatives below are trial
assumptions, not additions to accepted game rules.

## Source requirements

[Inventory and resource acquisition](../../DESIGN.md#inventory-and-resource-acquisition)
requires relief from forgotten parts/repeated chest trips while preserving item
location. Unlimited-range reference toolboxes do not grant global withdrawal.
[Construction convenience](../../DESIGN.md#construction-convenience-and-logistics-progression)
proposes remembered requirements, location search, bounded caches and later
physical delivery. Bulk production inputs still need handling infrastructure.
[Multiplayer](../../DESIGN.md#multiplayer-and-progression-ownership) requires
multiple teams and independent learning; sharing/credit/access remain open.
The [chapter challenge](first-chapter-challenge.md) needs construction stock but
grants no remote withdrawal. Its parts/recipes and source bootstrap are provisional.

## Compare four kinds of help

These can coexist; knowing, requesting and possessing a part are distinct.

| Candidate | What it relieves | Where stock remains; remaining friction |
| --- | --- | --- |
| Remembered bill of materials (BOM) attached to a plan | Remembering a shopping list and forgetting a final part | No stock moves. Separate unbuilt demand, carried stock and known supply; still fetch what is missing. A ghost is an intention, not a free component or reservation. |
| Searchable location catalogue | Remembering which container holds a part | Show a named physical location and observation/access status. A search result supplies neither possession nor a transport connection; stock may be stale or already taken. |
| Nearby physical cache/toolbox | Repeated long trips during work in one area | Stage stock near the job, or physically carry the toolbox there. For one demo, take stock through its actual access face into carried inventory before placing; replenish or move the cache as the job moves. No distance-based invisible withdrawal. |
| Later physically fulfilled request | Repeated fetching and replenishment after logistics are built | A request waits for authorized source stock and a working transport route. Parts travel by an explicitly tested belt/cart/train or other physical carrier to the worksite; mere catalogue or network membership is insufficient. |

A BOM should distinguish **needed**, **held here**, **known elsewhere** and
**requested/in transit**. Do not add these as if they were disjoint piles of
available stock: one known stack may already be requested. Reservation and
allocation policies remain alternatives to compare, not a selected subsystem.

## Trace the actual items

"Holder" below means physical custody, not entitlement or team ownership.
The demo must declare who may inspect, withdraw, request, receive and build;
neither an owner label nor knowing a location grants all five permissions.

| Step | Physical custody and checks for the paper walkthrough |
| --- | --- |
| Plan/search | Stock stays in its container. The plan records demand; catalogue results identify locations and distinguish knowledge from permitted access. Showing a count does not authorize taking it. |
| Retrieve/load | At the actual source, recheck stock and the declared withdrawal permission. Transfer accepted quantities to player inventory or a physical carrier; the source no longer holds those same items. A stale result cannot create supply. |
| Carry/transit | The player, toolbox or carrier holds the items at its real location. A queued order is not a second stack; in-transit stock cannot also fund a build at the source. |
| Receive/cache | Actual arrival transfers custody to the worksite cache or carried toolbox. Check the declared receiving/access rule. A blocked or disconnected route leaves stock at its last real holder, not at the destination. |
| Place | Recheck stationary construction permission and actual accessible stock. Transfer the required parts into the placed component exactly once; a rejected placement leaves quantities accounted for. Catalogue/request totals cannot pay for it. |
| Cancel/recover | Cancelling a queued request moves no stock. Loaded/shipped goods stay with their physical holder pending a declared return or acceptance action; cancellation cannot recreate them at the source. Dismantling/refund rules need their own choice. |

For this walkthrough, the sum of stock in containers, inventories, carriers and
placed components changes only through a declared source, sink or conversion.
Record reservation separately if tested; it changes availability, not location.
Do not infer a production transaction, wire protocol, save format or ownership
framework from that accounting check. Pending/in-flight work must eventually
join the [common witness](prototype-witness.md)'s conflict and save/rejoin cases.

## Multiplayer and failure walkthrough

Use two stationary build plans competing for one explicitly stocked shaft;
the shaft/count are fixture values, not a selected chapter requirement.

1. Both players can know the source location under a declared trial visibility
   rule. Their two BOMs express two demands, not two owned shafts. Compare a
   last-observed count with a refreshed count; neither makes a promise of stock.
2. One authorized retrieval takes the shaft. The other retrieval rechecks and
   reports missing/unavailable stock without silently sourcing other stock or
   funding a ghost. If testing reservations, declare priority/release separately.
3. Move the stocked cache to another worksite, or disconnect a delivery route.
   The old plan retains its demand; its old location result grants no access.
   Actual custody explains whether goods are still at source or in transit.
4. Change a participant's team/access while a request is in flight. Recheck the
   declared receiving/build permissions; hold or physically return goods under
   the trial's explicit recovery assumption. Do not silently confiscate, discard
   or duplicate them. The real access-revocation policy stays open.
5. Disconnect/rejoin with an outstanding request. Reconcile its actual custody
   and accepted placement outcome before submitting again; a duplicate request
   must not duplicate stock. This is a later witness, not tested by this paper.

A novice using an advanced team's cache raises separate visibility, permission,
recipe-learning and progression-credit choices. Shared physical goods do not
settle those choices. Delivery alone neither confirms a quest nor proves that
its goods were produced autonomously.

## Small demo alternatives and their limits

| Alternative to put before the user | Explicit trial assumptions; useful observation |
| --- | --- |
| A: remembered BOM + location list; carried-inventory placement | Fixture names a reachable source and permitted stock. One planned fetch replaces memory/retracing; observe forgotten parts, stale counts and the cost of repeated journeys. Cheap to scope, but only diagnoses the remaining supply chore. |
| B: A + a physically stocked worksite cache/toolbox | Fixture supplies or physically relocates the cache beside the job; access is by actual interaction, not a chosen radius. Compare building the same arrangement at two work areas, including moving/replenishing the cache. This tests fewer long trips while retaining handling. |
| C: later request/delivery probe extending B | Declare one physical source-to-cache route and carrier, source/recipient permissions and a blocked-route recovery. Observe loading, travel, arrival and rejection. This is a separate later logistics experiment, not an early unlock or compulsory chapter project. |

Measure trips, handling actions, forgotten parts and understood failure causes
on the same arrangement; invent no acceptable trip count, time or range target.
Paper comparison cannot establish that B is comfortable or that C is reliable.
Automatic delivery/replenishment should eventually remove recurring supply trips;
manual item-by-item collection must not be the only eventual receiving method.
That future method still needs actual local transfer, not remote stock deduction.
Bulk recipe inputs stay on their physical production routes in every alternative.

## Decisions and next review

- Which demonstration should be scoped first: A, B, or another physical-access
  approach? Neither a local cache nor delivery is an adopted chapter unlock.
- What makes local access valid: direct interaction, a carried toolbox, or a
  physically serviced worksite connection? Range, capacity and coverage stay open.
- Who may discover/count/withdraw/request/build from personal, team and shared
  stock, and what happens to permission changes or competing requests?
- When should delivery expand capability, and which transport/receiving actions
  should it automate? Confirm source stock/bootstrap with `factory-yau.2.5`;
  resolve learning/credit with `.2.1`–`.2.3` before adopting a shared model.

`factory-yau.1.5` reviews this alongside layouts and the build/diagnose storyboard:
trace one missing part from source to accepted placement and an interrupted
delivery back to an accounted holder. A convenient UI is insufficient if either
trace silently withdraws distant stock or hides an unavoidable replenishment loop.
