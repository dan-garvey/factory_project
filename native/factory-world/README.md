# Native World and transactions

World owns material, components, topology, actor custody, foundations, issued
identities, request history and checkpoints. Host/Session admit authenticated
requests and project results; scene nodes do not own a second simulation.

## Transactions

`TransactionOwner<State>` prepares a complete deeply owned State, history,
revision and delivery before one nonthrowing pointer swap. Domain validation
checks conservation, roster, generations, topology and historical references.
Calls are serialized on the authority thread; the owner is not thread-safe.

Exact history lookup precedes current admission. A retry returns its original
owned receipt/revision and a delivery-only duplicate flag. Reusing an identity
with changed intent is an error. Refusals retain State and cache their original
outcome. Preparation/validation/allocation failure is not a gameplay refusal:
it commits and caches nothing. Reentrant writes refuse.

Trusted stepping uses the same complete validation and commit boundary without
creating request receipts. An unchanged step changes no revision. Snapshots and
results own their values; no public mutable borrow or history reset exists.

## Custody and geometry

Placement/reclaim, construction stock, source depletion and loose/held work
share the transaction. Resolve actual entity generations, native actor/reach
observations and physical interaction anchors. Client coordinates alone grant
no authority. Reclaim cannot erase occupied contents or mint parts.

Mechanical power derives from placed geometry and physical source rates.
Disconnected branches stop independently. Partial/ready work retains recipe,
serial, remaining work and form through pauses, recovery and reinsertion.
Assembly recognition and current tuning live in source; the intended component
boundary is in [DESIGN](../../DESIGN.md).

Material attachment resolves compatible physical endpoints and validates both
ends, finite custody, direction and capacity atomically. A blocked outlet
retains the same item/work rather than consuming another input.

## Checkpoints and consumers

Typed checkpoint validation covers complete current state and request history.
Session binds actors/request namespaces; Store owns files; Host restores native
bodies from validated facts. Invalid loads refuse without a fresh-world fallback.
Component tests do not prove every shared or moving-world continuation.

Use `//native/factory-world:all` through
[native builds](../../docs/engineering/native-builds.md). The
[Godot bridge](../factory-godot-world/README.md) is the ordinary scene consumer.
Headers and tests define current APIs and schemas; dated results belong in Beads.
