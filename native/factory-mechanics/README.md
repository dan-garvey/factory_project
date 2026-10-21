# Geometric transmission kernel

This C++ component derives engagement from actual part geometry. The native
stationary topology evaluates it for the World used by the opening. The kernel
accepts no user-supplied edge list and owns no world, stock, kit, request history,
phase clock or save file. Its tests alone are not a native-body witness.

## Geometry and signed motion

A part is a stable identifier, a hub/gear/shaft kind, an exact integer center and
a canonical positive X, Y or Z axis. Gears additionally have a tooth count;
shafts have an axial half-span. Other shape fields must be zero.

The pitch unit is an explicit profile unit, with pitch radius equal to tooth
count. Equivalently, one unit is half the selected module. The World supplies
its construction geometry; the library does not round engine coordinates or
choose a permanent game scale.

Parallel-axis gears engage only in the same axial plane and at exactly the sum
of their pitch radii. Their signed relation is minus the first tooth count
divided by the second. A 20-tooth source driving a 40-tooth gear yields -1/2;
an inserted idler changes parity to +1/2. Tooth counts here are fixture examples,
not a selected starter inventory.

The experimental small/large pair (tooth counts 2 and 4) is an exception to
the generic pitch-distance rule: on matching axes and in one axial plane, its
centers can differ by one four-unit construction cell in both radial
directions or occupy adjacent cells in one radial direction. Its signed ratio
is -1/2 from small to large and -2 in reverse. Equal large starter cogs also
mesh in adjacent cells. The old six-unit pitch-radius spacing does not connect
the mixed pair. This discrete
placement follows Create's large-to-small cog connection; it is not a claim
that pitch circles physically touch at that distance.

For the experimental large-cog profile (tooth count 4, construction cell 4
grid units), two cogs on perpendicular axes also engage when their centers
are one cell apart along each cog's axis and share the third coordinate. They
transmit at equal speed; the signed rate is the same when the two axial offsets
have equal signs and reversed otherwise. This follows the corner relation in
[Create's rotation propagator](https://github.com/Creators-of-Create/Create/blob/mc1.21.1/dev/src/main/java/com/simibubi/create/content/kinetics/RotationPropagator.java).
This is a discrete gameplay connection, not a calculation of physical tooth
contact. The opening's finite kit and construction rules are owned by the World
and Host, not by this kernel.

A shaft couples only coaxial parts whose axial spans touch or overlap. Two
coaxial hubs or cogs also connect through their facing axle ends when their
centers are exactly one construction cell (four grid units) apart along their
shared axis. A one-cell shaft also connects to an adjacent hub or cog at its
facing tile boundary. These connections carry the same signed rate; the direct
hub-to-hub or cog-to-hub contact consumes no separate shaft. A greater gap or lateral offset does not connect them. Touching
shaft endpoints couple; a gap does not. Different gear axes or planes do not
create an external spur mesh. Coplanar overlapping pitch disks refuse.

The kernel solves exact signed rational rates. An incompatible driven loop or
conflicting sources stall only the connected component, with zero derived rates.
A separate component can continue. Without a source the component is unpowered;
an explicitly zero source is stopped. This models kinematic consistency, not
torque distribution, native contact, inertia or a new damage rule.

## Authority and presentation interface

The native World owns placements and registered source rates; stationary
topology evaluates their geometry through this kernel. World and Host perform
finite-kit accounting, actor/reach admission, request replay and atomic commit.
Construction can validate a candidate without changing the live world. No scene
node or client can insert a transmission edge through this API.

The view can render the same centers, axes, tooth counts and shaft spans,
with engagement kind and exact signed rate from the authority. Assets must match
those facts. Rotation phase is deliberately absent here: the authority must own
and publish it before motion is claimed. Cosmetic interpolation cannot advance
material or decide whether a mechanism transmits.

This package does not own recovery, topology or part custody and does not
silently migrate old saves or discard their links.

## Bounds and validation

This kernel accepts at most 256 parts, identifiers of 1 to 128 bytes
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

The pure solver accepts explicit belt spans between parallel one-tile shafts,
including horizontal, vertical, 45-degree inclined and sideways paths. Each
span validates aligned grid centers, a maximum of twenty
tiles, unobstructed tile centers and exclusive belt occupancy. Aligned shafts
within the span are pulleys; their signed angular rates match, including when
the drive enters at either end. Incompatible sources stall the connected
component. Stationary plans account for a carried belt, the World stores spans
and cargo lanes, and ordinary controls can place and remove spans. This geometry
check is not full terrain or body collision clearance.

The separate `belt_path` primitive derives ordered global tile centers for
horizontal, vertical, 45-degree inclined and sideways paths. It rejects paths
along the axle, unequal diagonal steps, off-grid endpoints and paths longer
than twenty tiles. The World and playable consumers still admit only horizontal
paths; the other geometries are groundwork, not placeable belts. See Create's
[belt connector](https://github.com/Creators-of-Create/Create/blob/mc1.21.1/dev/src/main/java/com/simibubi/create/content/kinetics/belt/item/BeltConnectorItem.java)
for the referenced axle and path constraints.

Full collision clearance, arbitrary bevel gears, clutches, tooth phase/contact, load,
material feed direction, persisted phase and actual gameplay remain unfinished.
A solver result cannot establish physical clearance for perpendicular parts.

## Build and evidence

Bazel is canonical. The explicit targets are
`//native/factory-mechanics:mechanics` and
`//native/factory-mechanics:mechanics_test`, using the Ops-owned root/toolchain.
No competing root workspace or CMake entry point is added. Follow the existing
[admission contract](../../docs/engineering/local-resources.md) and
[native migration contract](../../docs/engineering/native-migration.md), including
the current mandatory checks.

The kernel tests use invented kinematic fixtures; they are not engine, ordinary
input, shared-play or save evidence. Those consumers require their own checks.
