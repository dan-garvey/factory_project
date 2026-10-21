# Geometric transmission kernel

This unadopted C++ component prepares the individually placed cogwheel requirement.
It derives engagement from actual part geometry. It accepts no user-supplied edge
list and owns no world, stock, kit, request history, phase clock or save file.
The current ordinary opening still uses its original authority. This library is
not yet an ordinary construction or native-body witness.

## Geometry and signed motion

A part is a stable identifier, a hub/gear/shaft kind, an exact integer center and
a canonical positive X, Y or Z axis. Gears additionally have a tooth count;
shafts have an axial half-span. Other shape fields must be zero.

The pitch unit is an explicit profile unit, with pitch radius equal to tooth
count. Equivalently, one unit is half the selected module. The future authority
must record its physical unit scale and construction snapping before adoption;
the library does not round engine coordinates or choose a permanent game scale.

Parallel-axis gears engage only in the same axial plane and at exactly the sum
of their pitch radii. Their signed relation is minus the first tooth count
divided by the second. A 20-tooth source driving a 40-tooth gear yields -1/2;
an inserted idler changes parity to +1/2. Tooth counts here are fixture examples,
not a selected starter inventory.

For the experimental large-cog profile (tooth count 4, construction cell 4
grid units), two cogs on perpendicular axes also engage when their centers
are one cell apart along each cog's axis and share the third coordinate. They
transmit at equal speed; the signed rate is the same when the two axial offsets
have equal signs and reversed otherwise. This follows the corner relation in
[Create's rotation propagator](https://github.com/Creators-of-Create/Create/blob/mc1.21.1/dev/src/main/java/com/simibubi/create/content/kinetics/RotationPropagator.java).
This is a discrete gameplay connection, not a calculation of physical tooth
contact, and does not itself add large cogs to the opening's carried kit.

A shaft couples only coaxial parts whose axial spans touch or overlap. A hub or
gear has a point hub for this coupling. Two gears or hubs do not couple merely
because their centers or names match: an actual shaft must join their hubs.
Touching shaft endpoints couple; a gap does not. Different gear axes or planes
do not create an external spur mesh. Coplanar overlapping pitch disks refuse.

The kernel solves exact signed rational rates. An incompatible driven loop or
conflicting sources stall only the connected component, with zero derived rates.
A separate component can continue. Without a source the component is unpowered;
an explicitly zero source is stopped. This models kinematic consistency, not
torque distribution, native contact, inertia or a new damage rule.

## Authority and presentation interface

The future single authority owns placements and registered source rates, calls
evaluate, and retains its actual accepted geometry and derived result. It must
still perform finite-kit accounting, actor/reach admission, request replay and
atomic commit. Construction can validate a candidate without changing the live
world. No scene node or client can insert a transmission edge through this API.

Chapter's view can render the same centers, axes, tooth counts and shaft spans,
with engagement kind and exact signed rate from the authority. Assets must match
those facts. Rotation phase is deliberately absent here: the authority must own
and publish it before motion is claimed. Cosmetic interpolation cannot advance
material or decide whether a mechanism transmits.

The existing arbitrary drive-link representation remains historical input to
migration, not the requested new cogwheel authority. Native integration must
agree typed recovery, topology and part custody with the running-edit work.
This package does not silently migrate old saves or discard their links.

## Bounds and validation

This first adapter accepts at most 256 parts, identifiers of 1 to 128 bytes
without null bytes, coordinates within plus or minus 1,000,000 pitch units,
and tooth counts/shaft half-spans from 1 to 4,096. Shaft endpoints must also
remain in bounds. These keep squared geometry arithmetic exact in signed
64-bit integers. They are explicit fixture limits, not game-scale acceptance.

The same identifier policy applies to source hubs. Refusals retain a diagnostic
subject only when that identifier is valid and within the byte bound; malformed
or oversized identities are omitted rather than copied or truncated.

Source rates use signed 64-bit numerators and strictly positive denominators.
Cross-cancellation precedes checked multiplication; INT64_MIN is never negated.
An invalid shape, identity, source or unrepresentable rate returns an error
without publishing partial motion or engagement. Input values are unchanged.
Allocation exceptions can propagate before the authority commits anything.

Full collision clearance, arbitrary bevel gears, clutches, tooth phase/contact, load,
material feed direction, persisted phase and actual gameplay remain unfinished.
A solver result cannot establish physical clearance for perpendicular parts.

## Build and evidence

Bazel is canonical. The explicit targets are
`//native/factory-mechanics:mechanics` and
`//native/factory-mechanics:mechanics_test`, using the Ops-owned root/toolchain.
No competing root workspace or CMake entry point is added. Follow the existing
[admission contract](../../docs/engineering/local-resources.md) and
[native migration contract](../../docs/engineering/native-migration.md) while the
reviewed canonical workspace is available. Do not run this source with an
unreviewed toolchain/cache or bypass the current mandatory gates.

The tests are invented independent kinematic fixtures, not engine, ordinary
input, shared-play or save evidence. Source preparation grants no native run.
Exact source and any later declared original result belong in the owning Bead.
