#pragma once

#include "factory/pulley_pair.hpp"

namespace factory::pulley_loop {
using Integer = mechanics::Integer;
struct Profile {
    pulley_pair::Profile transmission;
    Integer half_thickness{1}, half_width{1};
    bool operator==(const Profile&) const = default;
};
struct Contact {
    std::uint64_t obstacle{};
    Integer minimum_squared{}, maximum_squared{};
    // Distance-to-centre-segment interval of the OPEN obstacle rectangle.
    // It intersects the open finite belt band; this is not an impact time.
    bool operator==(const Contact&) const = default;
};
struct Geometry {
    Profile profile;
    clearance::Box bounds;
    Integer inner_squared{}, outer_squared{};
    std::optional<Contact> contact;
    [[nodiscard]] bool clear() const noexcept { return !contact; }
};
enum class Error { invalid_loop, unsupported_layout, parent_refused, representation_limit, query_refused };
struct Refusal {
    Error reason;
    std::optional<pulley_pair::Refusal> parent_error{};
    std::optional<clearance::Error> geometry_error{};
};
using Inspection = std::variant<Refusal, Geometry>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Complete finite path volume for EQUAL-radius OPEN pulleys. In the proper
// shaft/span plane, inner² < distance(point, centre segment)² < outer², with
// strict overlap of the open axial slab. This is two straight straps and two
// OUTWARD semicircular caps. Empty loop interior is available, never filled by
// the enclosing box. Geometry is independent of an observed material position.
//
// Reuse parent setup/grid bounds and validate ALL native obstacle observations
// before selecting the lowest obstructing identity. Its enclosing-AABB hit is
// discarded. Tangency at either band boundary or axial face is clear under the
// existing experimental strict-interior policy. No impact phase or partial move.
// Belt half-width must fit both declared pulley widths and thickness must leave
// a nonempty inner opening. Crossed/unequal paths are explicitly unsupported.
//
// This declared corridor is not a manufactured belt/groove/housing or physical
// contact/force model. No length/stock, tension, traction, slip/sag/creep, phase,
// graph/clock, material or World is adopted. All results are owned observations.
[[nodiscard]] Inspection inspect(const Profile&, std::span<const clearance::Obstacle>);
}  // namespace factory::pulley_loop
