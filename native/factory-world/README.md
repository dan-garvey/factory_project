# Atomic native transactions

`TransactionOwner<State>` keeps one owned complete State, request history and
revision in a single snapshot. A successful new command prepares and validates
all three before replacing the snapshot with one nonthrowing pointer swap.
Refused new commands retain the same State while caching their original outcome.

This is unadopted native transaction machinery. It does not create a running World
beside Model, Session or Store, change their implementation, or define another
material schema. Its native tests use an invented marker State to test ownership
and commit behavior; they are not game, quantity or physical evidence.

## Caller contract

The real instantiation must use a complete, deeply owned value containing the
canonical material State, actor kits, topology and identity metadata. Copies must
not share mutable world objects. Destruction must not throw. The trusted complete
validator must check conservation, expected actors, generations, topology and
operation-specific history consistency. Generic history validation alone does
not establish those domain facts.

Session binds the caller before dispatch. For a fresh request, a trusted native
handler receives const current facts and derives canonical targets, current
native-body/reach admission and the pure rule candidate. Client coordinates,
supplied handlers and validator callbacks are not public gameplay inputs. Calls
are serialized on the authority thread; this component is not thread-safe and
does not sandbox malicious native code or mutable external aliases.

## Transaction behavior

Exact history lookup precedes the handler and current admission. A retry returns
an owned copy of the original result, including its original revision and facts,
with the delivery-only duplicate flag set. It invokes no handler, validator or
current rule. The separately returned current revision identifies the current
snapshot without retargeting the cached receipt. Changed intent under the same
identity is a history error and cannot invoke the handler.

For a new request, accepted decisions require a complete replacement State;
refused decisions require no replacement State. The reviewed history helper
prepares the original result and next order/revision. The owner builds a complete
candidate snapshot, validates it and prepares the owned delivery before its
single commit. Invalid decisions, invalid candidates, allocation/copy exceptions,
handler exceptions and validator exceptions leave the original snapshot intact.
Failed preparation is not a cached gameplay refusal; it returns no outcome.
Reentrant writes are refused without a partial or nested commit.

Snapshots and outcomes are independent owned copies. There is no public mutable
borrow, setter, cache reset or context replacement. Fresh creation starts at
revision and order zero after full validation. Validated restore preserves a
complete logical checkpoint rather than resetting its history. Trusted
stepping prepares one complete candidate and increments revision without creating
or modifying a request receipt. An unchanged step increments nothing. The same
validation, reentrancy guard and atomic commit apply to both paths. Complete
Store-file integration, body registration/lifetimes and live adoption remain
subsequent integration work. This API must not be used
to manufacture a fresh world when a real checkpoint import fails.

## Native stationary World

`World` instantiates the owner with the canonical material State, stationary
topology, each actor's finite part kit and an issued-entity ledger. Immutable
startup profile facts define the finite source, complete part budget, recipe,
actor roster, source rate, grid scale and reach. Validation checks material and
physical-part conservation, exact roster agreement, current generations, issued
identities, canonical topology and historical work references before every commit.
There is no mutable compatibility inventory or separately authoritative projection.

Foundations share this same transaction owner, identity sequence and request
history. Their finite per-actor custody and grid-aligned placed blocks are part
of the complete State and checkpoint, outside the mechanical topology. Removal
cannot orphan a supported machine or stacked block. The trusted site adapter
validates terrain support; the World retains exact reach, conservation, overlap,
generation and history checks. There is no old-save migration for this feature.

Session supplies the authenticated actor and request namespace. Fresh commands
use exact integer fields and known keys. They resolve current entity generations,
derive native interaction anchors and obtain an observation from the host's
registered actor producer. Both endpoints of a material link require reach.
Placement allocates a fresh identity only with its successful finite-part commit;
removal retains the old identity for historical receipt lookup. Recovery, whole
work insertion and product collection call the existing material functions.
Stationary removal and rebuilding call the existing pure planners.

The trusted host tick derives each machine's power from geometric shaft and gear
engagements. A disconnected machine stops while unrelated rotating branches keep
working. Carried work pauses; its original recipe, serial and remaining time
survive recovery and reinsertion. A ready lot with zero remaining time still
occupies its processor. Material links are the two permitted transport edges,
not arbitrary power-transmission edges.

This first profile limits the roster to 16 actors, current work to 256 lots and
issued entity identities to 4096. Other inherited component bounds still apply.
These are adapter limits, not permanent game requirements. Calls are serialized
on the authority thread. The native host observation callback is trusted code;
the domain does not prove registration, collision clearance or process lifetime.
Native body integration and the switch from the current scripted authority are
unfinished. This native format does not decode the old scripted save format.

## Material construction attachment

The opening's Host translates ordinary collector, belt and press placement into
`place_connected`. This internal native operation derives only compatible ports
involving the new part. It uses the opening's directed port layout: collector
to belt and belt to press, one cell along +X for a Z-axis belt or along +Z for
an X-axis belt, at the same height. A cell is four integer quarter-pitch units. Gaps, reverse layouts,
diagonals, other heights and nearby power components do not attach. This is a
revisable adapter layout, not a general material-routing rule.

The logical checkpoint uses schema 4 and retains identified horizontal, inclined,
vertical and sideways belt spans and their shaft endpoints. A span counts against the same finite belt
part inventory as a conveyor. `place_belt_span` consumes a belt and checks
reach to both shaft identities; `remove_belt_span` refunds it. Both retain
generation and retry history. The native Host checks actor and site clearance.
World owns canonical multi-slot lane custody; vertical and sideways power-only
spans require empty lanes. The Godot Host still permits only horizontal spans.
A powered collector adjacent to
either outer endpoint can feed raw material into an empty endpoint, even while
the span is stopped. Rotation carries raw material to an adjacent processor at
the outgoing endpoint, subject to its input capacity. Attachment follows grid
geometry regardless of construction order. Other items and unconnected or full
ends remain on the lane. The Host projects confirmed lane slots and the shared
presenter shows those confirmed items at their confirmed slot and phase positions.
Manual recovery uses the selected slot's current confirmed cargo. Earlier logical
schema payloads are refused.

The planner checks reach to the new part and every existing endpoint before
preparing one replacement state. Placement, finite kit and the added links
commit together, or none do. Material attachment creates no shaft, mechanical
engagement, power or material tick. Placing the belt first, last or between the
other two placements produces the same directed path without separate link
requests. Existing removal still removes the affected links and refunds the
exact carried specification.

The original internal `place` operation remains unchanged for historical
receipts and other construction. Its accepted history still requires exactly
one reach target. `place_connected` retains the new part first, followed by its
actual attached endpoints; historical validation permits only the corresponding
distinct input and output anchors. Restoration and exact retry preserve the
original identities and targets, including a removed belt, rather than deriving
new attachments from the current worksite.

## Typed logical checkpoints

The checkpoint codec composes Recovery's canonical material subrecord with the
stationary topology, actor part kits, all issued entity identities, request
history and current revision. The exact trusted startup profile is included for
comparison. Decoding cannot select another recipe, roster, finite budget, source
rate, grid scale or reach. Integer authority fields stay integers; unknown and
missing fields refuse. Input depth, text, node and collection bounds apply before
material decoding and its current-work serial checks.

`World::restore` validates a complete decoded snapshot and expected world context
before creating an owner. It preserves every historical intent, outcome and
revision, including receipts for removed parts and earlier actor observations.
Accepted historical facts must retain their exact scalar/container schema,
generation, moved material and valid original reach calculation. They are never
compared against a new actor pose or retargeted to the current topology. Invalid
input returns a refusal or no owner; there is no fresh-seed fallback.

This is a logical native checkpoint value. Store still owns encoding, file
publication and the original file. The codec owns no file descriptor or network
operation. Physical poses, body registration and process lifetimes remain host
adapter responsibilities and are not supplied by this checkpoint. Logical
round-trip and resumed work tests do not establish fresh-process game restoration.

## Build and evidence

Bazel targets include `//native/factory-world:transactions`,
`//native/factory-world:transactions_test`, `//native/factory-world:world` and
`//native/factory-world:world_test`, `//native/factory-world:checkpoint` and
`//native/factory-world:checkpoint_test`. The World consumes the existing material,
recovery and stationary packages; the generic owner depends only on authority.

The literal test source covers atomic accepted/refused commands, exact retry,
strict request reuse, detached reads/delivery, invalid decisions/candidates,
preparation exceptions and nested writes. Source checks do not compile or execute
these controls. The new World tests use the real component implementations with
invented finite state and actor observations. They check literal custody, partial
and ready work, running removal/rebuild, independent local power, two-endpoint
reach, authenticated binding and immutable historical outcomes. They do not run
Godot, a real actor or ordinary gameplay. The root suite remains material-only;
select the relevant package target explicitly. Use ordinary resource admission
and the installed commit hook once. One independent reviewer covers the change;
unchanged dependencies do not need repeated checks or reviews. See the
[migration contract](../../docs/engineering/native-migration.md) and
[resource rules](../../docs/engineering/local-resources.md).

The original native World and logical-checkpoint consumers passed 124 and 126
checks respectively, and the composed package built and linked through canonical
Bazel. These results are retained component evidence, not a live game or physical
restoration result. Recovery supplied the single independent source review.
