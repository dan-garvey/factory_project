#pragma once

#include "factory/mechanics.hpp"
#include "factory/recovery.hpp"

#include <compare>
#include <cstddef>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace factory::stationary {

// Pure stationary removal. World owns admission and the atomic live commit.
// This package never edits a moving assembly or creates a second authority.
enum class Role { collector, belt, processor, waterwheel, gear, shaft };

// This is the finite inventory specification, independent of identity, location
// and orientation. A gear's tooth count or shaft's length cannot change on refund.
// Machine roles use zero teeth and half_span; gear and shaft match mechanics::Part.
struct PartSpec {
    Role role{Role::collector};
    mechanics::Integer teeth{};
    mechanics::Integer half_span{};
    auto operator<=>(const PartSpec&) const = default;
};

// Bounded adapter profile, not a carrying-capacity game rule. Count the union
// of kit and placed specifications so every valid world's refund fits this bound.
inline constexpr std::size_t maximum_specifications = 512;
using Kit = std::map<PartSpec, materials::Quantity>;

struct PlacedPart {
    // The shared mechanical Part is the one geometry record. Its id is the
    // entity id, not a second alias. Machine roles expose Kind::hub geometry;
    // individual gears and shafts expose their corresponding mechanical kind.
    mechanics::Part geometry;
    std::int64_t generation{};
    Role role{Role::collector};
    // Diameter of a complete waterwheel in world grid squares. Other parts use 1.
    mechanics::Integer wheel_tiles{1};
    bool operator==(const PlacedPart&) const = default;
};

struct MaterialLink {
    materials::EntityRef from;
    materials::EntityRef to;
    bool operator==(const MaterialLink&) const = default;
};

struct Topology {
    std::vector<PlacedPart> parts;
    std::vector<MaterialLink> material_links;
    // Registered waterwheel sources and their exact configured rates. These are
    // World facts, never arbitrary client links. Engagements remain derived.
    std::vector<mechanics::Drive> sources;
    bool drive_enabled{};
    bool operator==(const Topology&) const = default;
};

struct PowerView {
    bool drive_enabled{};
    // Uses the existing geometric kernel. Disabling a source yields zero-rate
    // drive inputs without overwriting its configured source rate in Topology.
    // Stalls remain local to the connected component; phase/load are not modeled.
    mechanics::Result mechanical;
};

struct RemovalSelection {
    // World resolves and validates this identity/generation before planning,
    // then revalidates it and current admission immediately before one commit.
    materials::EntityRef target;
};

enum class RemovalError {
    invalid_topology,
    invalid_kit,
    invalid_material_state,
    unknown_target,
    stale_generation,
    occupied_target,
    quantity_overflow,
    invalid_mechanics,
};

struct RemovalRefusal {
    RemovalError reason{RemovalError::invalid_topology};
    materials::Error material_error{materials::Error::none};
    mechanics::Error mechanical_error{mechanics::Error::none};
};

struct RemovalFacts {
    materials::EntityRef target;
    // A retained pre-edit grid point. World converts the explicit grid scale to
    // its native interaction anchor; this is not a trusted client/body pose.
    mechanics::Point interaction_point{};
    PartSpec refunded_part;
    std::vector<MaterialLink> removed_material_links;
    bool removed_source{};
};

struct PreparedRemoval {
    Topology candidate;
    Kit candidate_kit;
    RemovalFacts facts;
    PowerView power;
};

using RemovalPlan = std::variant<RemovalRefusal, PreparedRemoval>;

[[nodiscard]] const char* removal_error_name(RemovalError) noexcept;

// Pure derivation only. Validate the geometry and source bindings; use zero
// source rates when disabled. Never accept an input engagement/drive-edge graph.
[[nodiscard]] PowerView power_view(const Topology&);

// World supplies its fully validated canonical material State and the already
// bound actor's Kit for the same admitted revision. It retains complete quantity,
// recipe, serial, roster and history validation; this is an occupancy consumer.
// This first material profile has at most one collector, belt and processor.
// The planner validates that topology/material membership and Kit are coherent;
// full actor roster, history and body admission remain World responsibilities.
//
// Collector/belt raw slots, processor input/output or ANY processing lot occupy
// their machine. A zero-remaining lot is still occupied. Actor Cargo is separate.
// No refusal or plan moves, converts, discards, resets or advances any material.
//
// A successful plan removes only the resolved part, its incident material links
// and its own source registration, and refunds exactly one matching PartSpec.
// Geometric engagements are rederived and refund nothing. Preserve every other
// part/source/link, the explicit drive setting, and the original caller values.
// Failure returns no partial candidate. There is no drive-off prerequisite.
//
// World returns cached outcomes before planning and owns one atomic commit of
// admitted topology, the actor's Kit and original command outcome. It allocates
// fresh rebuild identities, retains generations/history and persists the single
// checkpoint. This library owns no live world, requests, clock, file or actor.
[[nodiscard]] RemovalPlan prepare_removal(const Topology&, const Kit&,
                                          const materials::State&,
                                          const RemovalSelection&);


struct PlacementSelection {
    // These are resolved World inputs, not trusted client identity or rates.
    // World allocates a fresh identity only as part of its admitted commit and
    // rejects reuse of any historical identity before calling this planner.
    PlacedPart part;
    std::optional<mechanics::Drive> source;
};

enum class PlacementError {
    invalid_topology,
    invalid_kit,
    invalid_material_state,
    invalid_part,
    identity_conflict,
    part_limit,
    unavailable_part,
    incompatible_source,
    overlapping_shafts,
    invalid_mechanics,
};

struct PlacementRefusal {
    PlacementError reason{PlacementError::invalid_topology};
    materials::Error material_error{materials::Error::none};
    mechanics::Error mechanical_error{mechanics::Error::none};
};

struct PlacementFacts {
    materials::EntityRef target;
    mechanics::Point interaction_point{};
    PartSpec consumed_part;
};

struct PreparedPlacement {
    Topology candidate;
    Kit candidate_kit;
    PlacementFacts facts;
    PowerView power;
};

using PlacementPlan = std::variant<PlacementRefusal, PreparedPlacement>;

[[nodiscard]] const char* placement_error_name(PlacementError) noexcept;

// Prepare one stationary physical placement, consuming one exact carried part.
// Waterwheels require their World-supplied source registration; other roles may
// not carry a source. Existing parts, links, sources, drive setting and material
// stay unchanged. Engagements are rederived from actual geometry, not supplied.
//
// The same World validation/admission/atomic-commit preconditions as removal
// apply. The planner proves only absence in CURRENT topology, not historical
// freshness, actor reach, body clearance or permission to edit moving assemblies.
[[nodiscard]] PlacementPlan prepare_placement(const Topology&, const Kit&,
                                              const materials::State&,
                                              const PlacementSelection&);

}  // namespace factory::stationary
