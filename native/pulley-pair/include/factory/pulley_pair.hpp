#pragma once

#include "factory/clearance.hpp"
#include "factory/slider_crank.hpp"

#include <span>

namespace factory::pulley_pair {
using Integer = mechanics::Integer;
using Id = std::uint32_t;
using Coordinate = slider_crank::Coordinate;
using Point = std::array<Coordinate, 3>;
inline constexpr Integer maximum_radius = 128, maximum_separation = 256, maximum_half_width = 64;
enum class Layout { open, crossed };
struct Pulley {
    Id id{};
    mechanics::Point center{};
    mechanics::Axis axis{mechanics::Axis::z};
    Integer radius{2}, half_width{1};
    bool operator==(const Pulley&) const = default;
};
struct Profile {
    std::array<Pulley, 2> pulleys{Pulley{7, {0, 0, 8}}, Pulley{11, {20, 0, 8}}};
    mechanics::Axis span{mechanics::Axis::x};
    Layout layout{Layout::open};
    bool operator==(const Profile&) const = default;
};
struct Drive { Id pulley{}; mechanics::Rate rate; };
struct Geometry {
    Profile profile;
    // Two straight pitch strands, each with endpoints in pulley argument order.
    // These are exact tangent centreline points, not belt surface/body contacts.
    std::array<std::array<Point, 2>, 2> strands;
    Integer separation{}, straight_span_squared{};
    mechanics::Rate second_from_first;
    std::array<clearance::Box, 2> pitch_bounds;
    clearance::Box loop_bounds;  // Encloses the loop, including its EMPTY interior.
};
struct Evaluation {
    Geometry geometry;
    std::array<mechanics::Motion, 2> motion;
    std::array<std::optional<mechanics::Rate>, 2> prescribed;
};
enum class Error { invalid_pulley, duplicate_id, invalid_layout, invalid_span, nonparallel,
                   skew, spacing_limit, pitch_overlap, too_many_drives, unknown_pulley,
                   duplicate_drive, invalid_rate, representation_limit, native_refused, unsupported_result };
struct Refusal {
    Error reason;
    Id subject{};
    std::optional<geared_cycle::Error> rate_error{};
    std::optional<mechanics::Error> native_error{};
};
using Result = std::variant<Refusal, Evaluation>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Ideal taut no-slip pitch kinematics. Parallel coplanar shafts, one signed
// perpendicular coordinate span and explicit open/crossed routing. All raw
// descriptors/prescriptions validate before useful output. The existing native
// virtual-spur representation supplies ratio, power and conflicting-drive rules;
// ordinary separated gears do not acquire engagement. Missing drives, explicit
// zero and contradictory prescriptions remain unpowered, stopped and stalled.
//
// Reuse the published exact Coordinate for both tangent strands; no rounded
// root mirror. The 256 separation and 128 radius limits propagate that adapter's
// denominator/arithmetic limits, not game-scale or feasible-belt requirements.
// Pitch/loop boxes are conservative bounds, never filled-belt collision shapes.
// Crossed strand intersection is NOT physical crossing/twist/contact admission.
// No belt length/stock, tension, traction, slip/sag/creep, solids, torque, phase,
// live graph/clock, material or World adoption is established.
[[nodiscard]] Result evaluate(const Profile&, std::span<const Drive>);
}  // namespace factory::pulley_pair
