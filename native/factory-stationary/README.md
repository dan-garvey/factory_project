# Pure stationary removal

This C++ package prepares uncommitted stationary removal and placement candidates.
It returns an eligible empty physical part and can rebuild from that exact carried
specification while preserving the explicit drive-enable setting. The existing
geometric kernel rederives the affected local transmission; another independently
connected source can keep its branch rotating.

Direct C++ compilation and all three native consumers have passed independent
source review and author execution. The package does not adopt a native World or
change the live GDScript demo. Model, Session and Store remain the sole current
authority.

## Exact custody and geometry

A placed part uses the shared `mechanics::Part` record, role and stable generation.
The finite kit uses a `PartSpec` keyed by machine role, gear tooth count or shaft
half-span. Removal refunds one exact physical part. Derived engagements and
deleted material links refund nothing: there are no hidden shaft-edge parts.

The initial profile supports at most one collector, belt and processor, matching
the canonical material slots. Its mechanical part and geometry bounds come from
the shared kernel. Material links are the two directed opening relationships.
The union of placed and carried part specifications is bounded to 512; counting
that union before planning ensures every valid world's refund fits the profile.
These are explicit adapter limits, not permanent game or carrying-capacity rules.
Coaxial shafts may meet at their ends, but two placed shafts cannot occupy a
positive length of the same axis. This check does not establish body clearance
for crossing shafts or for other part types.

The input is the one validated canonical Cargo/WorkLot State. Collector and belt
raw slots occupy their machine. Processor input, output or any processing lot
occupies its machine, including a ready lot with zero remaining ticks. Actor
Cargo is separate custody. The planner neither copies a material candidate nor
moves, converts, discards, resets or advances any quantity or work.

World must already have validated conservation, recipe, work serials, expected
roster and history for this same revision. This library checks machine membership
and occupancy without becoming a second complete material validator. Its source
successor explicitly drops the declaration proposal's unused Config and Path
arguments.

## One authority transaction

World binds the actor and their finite kit, resolves target identity/generation,
and returns any exact historical cached outcome before planning. The pure planner
validates bounded topology and source bindings, prepares the replacement topology
and kit, and returns the original target point as an interaction receipt.

World converts the declared pitch/grid scale to native interaction coordinates,
checks current readiness, reach and body restrictions, and revalidates revision
and generation before one atomic topology, kit and history commit. No caller can
authorize removal through a client pose or a stale plan.

A source removal unregisters only that source. A shaft removal changes derived
contact without deleting other physical shafts. The original enabled flag and
unaffected source rates remain exact. An enabled flag alone is not evidence that
an unrelated material branch continues production: local material-power adoption
remains a separate required World integration.

Placement consumes one exact carried specification. World supplies a fresh
resolved identity and, for a waterwheel, the matching registered source rate.
The planner checks current identity conflicts and finite parts, then derives the
new geometric contacts. It never supplies arbitrary transmission edges or alters
material. Source rates and identities are resolved authority facts, not client
permissions. Allocation exceptions propagate before a live commit.

Historical freshness, native placement/body admission, cached replay, shared
pending edits and checkpoint import/export remain World responsibilities. The
planner cannot prove a supplied absent identity has never existed in history.
The full task still requires real ordinary-input and continuation witnesses.

## Build and tests

The explicit Bazel targets are `//native/factory-stationary:stationary`,
`//native/factory-stationary:stationary_test`, and
`//native/factory-stationary:placement_test`, and
`//native/factory-stationary:recovery_rebuild_test`. The `:tests` suite selects
all three invented native consumers. Ops owns the root graph and the
header-only `//native/factory-core:material_types` target. That target must expose
the exact canonical material and recovery declarations without linking the old
incompatible quantity implementation. Its package agreement is a build prerequisite,
not a reason to stop independent source development.

The native tests are invented literal planner fixtures. They distinguish actual
local geometric disconnection from merely leaving a flag enabled; check exact
machine, gear and shaft refunds; refuse raw, output and zero/positive-progress
work; preserve carried Cargo; and challenge stale identities, invalid sources,
bad topology and checked refund overflow.
The rebuild consumer also uses the actual returned part to restore the removed
shaft or source, preserving a separate branch and consuming the exact kit item.
It challenges absent/wrong specifications, source identity, duplicate current
identity, incompatible geometry, overlapping gears and duplicate fixture machines.

The integration consumer calls the real canonical recovery, insertion, material
tick and stationary-planner functions. It round-trips trapped collector raw stock
through Cargo and a rebuilt collector without a press route. A separate partial
work case recovers combined input, output and whole work, rebuilds the processor,
reinserts the exact lot and raw stock, then checks its remaining ticks, later
blocked-ready work and literal individual final custody. The finite source keeps
its actual depletion and the independent geometric branch remains connected.
All three consumers passed direct GCC validation: 86 removal checks, 46 placement
checks and 60 cross-module recovery/rebuild checks. These logical fixtures are not
a live World, native actor, command history, checkpoint, ordinary-input or
shared-play witness. Canonical Bazel execution remains unverified. The material library's
single power flag still does not establish per-component production frequency.

Use ordinary resource admission and bounded external outputs for later builds.
Reuse passing checks and the single independent review when their relevant inputs
remain unchanged. Keep existing mandatory gates.
See the [native migration contract](../../docs/engineering/native-migration.md),
[design](../../DESIGN.md) and [resource admission](../../docs/engineering/local-resources.md).
