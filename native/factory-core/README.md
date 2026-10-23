# Finite material and recovery core

This unadopted C++20 fixture evolves the reviewed finite material foundation with
typed actor cargo and pure recovery/insertion plans. It is not connected to the
playable demo. The existing Model, Session and Store retain their live authority,
connection and file boundaries until the separately reviewed native World joins
them. No GDScript recovery mirror or fallback world is introduced.

## Canonical custody

One State contains raw source, collector, belt and processor-input stock, completed
processor output, one optional processing WorkLot, and one Cargo per admitted
actor. Cargo distinguishes raw units, completed products and whole work lots.
The old mutable product inventories and held-plus-timer representation are
replaced rather than kept as parallel owners.

A WorkLot owns its original recipe input exactly once. It carries a positive
world-local serial, original recipe signature and remaining ticks. Zero remaining
ticks means ready work, including the valid boundary after output retrieval and
before the next tick. Carried work pauses. Moving or reinserting a lot neither
allocates a new identity nor resets or advances its timer.

Processor work retains a fraction of a subtick on the WorkLot itself, so a
fractional shaft rate accumulates without a minimum-speed floor and the exact
progress follows recovery, carried cargo and checkpoints. Rate changes retain
exact fractions when their common denominator fits; larger combinations use
bounded integer rounding. The earlier machine fixture uses material checkpoint
schema 6. The experimental arrival profile uses schema 9: named finite timber
balances and carried timber live beside the existing ore source and raw cargo
in this same material State. Hand mining ore and the collector debit that same
source. Strict conservation rejects missing, duplicated or refilled tree stock
on decode. Eleven provisional component recipes each consume only carried
timber or ore and retain those ingredient weights in actor cargo or installed
component custody and checkpoints.
The experimental World/Host now admits crafting at one physically reached pod
bench. The World can place and reclaim typed parts on the shared quarter-grid;
machine assembly and timber/component belt transport remain separate slices.

This first profile still has one raw material, one product recipe, and one
collector/belt/processor fixture. Config supplies recipe weight, cycle duration
and collector capacity. Path supplies already resolved component, edge and power
facts; it is not another transmission solver. Per-component mechanical operation
and general multi-recipe cargo remain separate work.

Validation checks signed 64-bit counts, capacities, exact recipe-weighted
conservation, valid progress, unique current work ownership and next_work_id above
every present serial. It allocates no memory, preserving its noexcept contract.
The duplicate check is quadratic in simultaneous lots; this small finite fixture
does not establish factory-scale performance. World must also validate the
expected roster, World context and every work serial in retained history.

## Tick and product retrieval

`advance_belt_lane` is a pure proposal for a shaft-connected belt span.
It moves individual raw units, products or whole work lots through bounded slots
using signed fixed-point distance, preserves fractional phase across reversal,
and propagates a full receiver's backpressure. It returns the candidate and
delivered items without changing the input. World owns and validates each lane,
persists it, and advances occupied lanes from confirmed shaft motion. The World
connects adjacent collectors and processor inputs at span endpoints. A press
accepts a compatible carried work lot into its empty processing slot, preserving
its identity and fractional progress; a busy press blocks it on the belt.
Actors can also place one carried blank, plate or selected work lot into an
empty reachable horizontal or inclined belt slot; power-only belts refuse cargo.
An item travelling toward a collector remains on the lane rather than ejecting into
the machine; open ends still eject. Confirmed item slots are projected to the presenter;
manual span recovery removes individual items through the World.

`advance_belt_lane_rate` also retains the fractional part of a fixed-point
subtick in the authoritative lane. An unchanged rational shaft rate accumulates
exactly across ticks and checkpoints. When the rate changes, the lane retains
both fractions exactly if their common denominator fits the saved integer;
larger combinations use deterministic rounding with error below one part in
the maximum signed 64-bit denominator per change. Finite lane
occupancy bounds the work at extreme rates. Inclined travel retains its
fixed-point approximation to diagonal distance.

The fixed order remains: advance or finish existing machine work; start eligible
new work; move belt input; move collector stock; extract finite source feed.
New work receives its full original duration and one checked fresh serial. A full
output retains the same ready lot. Stopped power preserves the complete State,
and ordinary powered ticks never visit carried work.

The additive MachinePower overload accepts already resolved local drive facts.
The existing Path.powered flag remains the coarse fixture enable; the old
three-argument call retains its behavior. Collector power gates collection and
collector dispatch, belt power gates belt dispatch, and processor power gates
work advancement/start. Receiving raw buffers may accept input while stopped.
For example, stopping a processor need not stop an independently driven sender.
Positive partial work and blocked ready work remain paused under that machine's
local stop. An active absent machine is refused before a candidate is published.
These are explicit fixture choices, not permanent energy or mechanical rules.
World still derives component motion and performs one trusted step/commit; the
material library adds no solver, source, timer or second live authority.

World maps the magnitude of the press's signed rational rotation rate to work
per step, using 4,096 subticks per baseline work tick. The experimental mapping
retains fractional subticks and saturates only at the integer representation
limit. Opposite directions work equally; an unpowered or
stalled press does no work. This makes gear ratios affect processing but does
not claim Create's exact press timing, load, or stress behavior. Fractional
progress belongs to the WorkLot and follows it through recovery and insertion.
The modular arrival press uses the same WorkLot advance arithmetic. Its manual
crank starts work on the first turn, advances one baseline work tick on each
later turn and retains a ready lot at the physical work point when the selected
exit is full. Multiple work points remain independent inside one material State.
The nonresource material checkpoint schema is 6. The arrival resource payload
uses schema 10 and includes belt-lane and typed loose-material custody plus
timber and ore embodied in fabricated stationary kits. Earlier schemas are
refused rather than inventing a compatibility migration.

Product retrieval credits only an already admitted actor's Cargo.products.
It cannot create a new actor, collect raw material as a plate or consume a work
lot. Every tick and retrieval validates a complete candidate before replacing the
input State. Serial or quantity overflow leaves the original State unchanged.

## Pure recovery and insertion

prepare_recovery evacuates the selected machine's contents into the bound actor's
existing Cargo. A processor contributes input raw, its whole processing lot and
completed output together. No viable press route or global drive shutdown is
required. Source stock is never recoverable or refillable through this interface.

prepare_insertion moves a positive explicit raw amount into an eligible raw slot,
or selects one existing carried WorkLot by serial for a compatible empty
processing slot. The processor's input and output are separate buffers: existing
raw input or a full product output does not replace or split the inserted lot.
A full output can still block a reinserted ready lot. Products remain products.

Both functions return either a refusal or a complete uncommitted State with
typed transfer facts and the affected entity identity. Receipt Cargo is an owned
description of the move, not another live holder. Insufficient cargo/capacity,
occupied processing, incompatible work acceptance, malformed state, invalid
target shape and arithmetic failure publish no partial candidate.

These are authority-internal planners, not command-admission APIs. World must
bind the actor through Session, resolve stable entity/generation to the fixture
holder, and supply current Path and compatible-recipe facts. The planner cannot
prove that a nonempty target identity is current topology. World rejects unknown
or stale targets before planning and revalidates identity, reach, revision and
native admission before commit.

The sole World must resolve historical requests before evaluating new rules and
commit its complete material/topology candidate with exactly one cached outcome.
Old transfers return their original receipt rather than being repeated against
moved actors or a rebuilt machine. Store remains the file owner; complete typed
logical checkpoint composition lives in the native World package, while Store
publication and native registration remain separate Platform work.
No legacy save is silently reinterpreted by these functions.

## Validation and build status

The new literal C++ tests preserve the original one- and two-input material
snapshots and four-product consumer. Additional source controls cover raw
recovery without a processor, combined processor contents, positive partial-cycle
pause/resume, blocked ready work, selected lot identity, actor custody, atomic
refusals, serial exhaustion and exact signed-integer limits. These are pure
logical fixtures, not ordinary input or human play.

The separate recovery_transaction_test.cpp consumer composes these real transfer
functions with the reviewed single-snapshot transaction owner. Its fixed invented
domain checks individual raw custody on an incomplete route, accepted and refused
historical retries after later transfers, strict typed request reuse, whole partial
work and atomic rejection of a nonconserving candidate. It does not implement the
game command adapter, Session authentication, target admission or checkpoint codec.
The later five-consumer direct-compiler campaign passed these material,
recovery/history and local-power fixtures, including the four-product consumer.

The separate material_power_test.cpp consumer has literal per-holder snapshots
for independent senders and passive buffers, paused partial/ready work, finite
backpressure, global fixture disable and serial exhaustion. The earlier material,
recovery and request-consumer test sources remain unchanged. These logical
controls do not establish ordinary running edits or live authority adoption.

Bazel is the canonical build system. Ops owns native/factory-core/BUILD.bazel,
root configuration, toolchain/cache provenance and bounded supervision. The
package exposes `materials_test`, `recovery_test`, `recovery_transaction_test`,
`material_power_test` and `material_state_codec_test`. These logical tests are
included by the recursive [native test command](../../docs/engineering/native-builds.md);
use their explicit package targets for focused iteration. The strict material
codec passed its original 129-check native
campaign. Earlier material-only suite results retain that narrower coverage.
Existing source checks do not execute C++.

The original foundation campaign at c51bd28 passed 206 logical checks and the
separate four-product consumer. Its CMake/Ninja definition, results and first
failures remain historical component evidence. They are not a validation of this
representation successor, the current build interface or permission for another
campaign. Existing mandatory repository gates remain enforced.

Actual bad-line reproduction, ordinary same-worksite recovery, shared request
behavior, complete saved custody/progress and fresh-process continuation remain
required under factory-yau.6.42 and factory-yau.3.17.7. This library alone does not
satisfy those gameplay or adoption outcomes.
