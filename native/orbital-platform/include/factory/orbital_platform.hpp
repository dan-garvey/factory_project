#pragma once

#include "factory/scotch_yoke.hpp"

namespace factory::orbital_platform {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Point = std::array<Fraction, 3>;
using Direction = scotch_yoke::Direction;
struct Profile {
    std::uint32_t input_id{7}, output_id{11}, tray_id{19};
    mechanics::Point origin{0, 0, 8};
    mechanics::Axis shaft{mechanics::Axis::z}, span{mechanics::Axis::x};
    Integer spacing{12}, radius{4}, half_width{1}, half_thickness{1};
    bool operator==(const Profile&) const = default;
};
struct Geometry {
    Profile profile;
    mechanics::Point remote_axis;
    clearance::Box reference;  // UNTRANSLATED box, not the theta=0 posed body.
};
struct Contact {
    std::uint64_t obstacle{};
    Integer minimum_squared{}, maximum_squared{};
    // Squared-distance interval of the OPEN displacement rectangle. The
    // supplied orbit radius squared lies strictly inside it. No impact time.
    bool operator==(const Contact&) const = default;
};
struct Orbit {
    clearance::Box reference;
    mechanics::Axis shaft;
    Integer radius{};
    std::optional<Contact> contact;
    [[nodiscard]] bool clear() const noexcept { return !contact; }
};
struct Sample {
    Geometry geometry;
    Direction direction;
    std::array<Point, 2> pins;
    Point displacement, per_radian;
    std::array<mechanics::Motion, 2> shafts;
    bool change_point{};  // The declared branch is collinear with its base.
};
struct Setup {
    Geometry geometry;
    Orbit tray;
};
enum class Error { invalid_profile, invalid_axes, invalid_direction, invalid_motion, invalid_rate,
                   invalid_body, representation_limit, query_refused };
struct Refusal {
    Error reason;
    std::optional<geared_cycle::Error> rate_error{};
    std::optional<clearance::Error> geometry_error{};
};
using Reading = std::variant<Refusal, Sample>;
using OrbitQuery = std::variant<Refusal, Orbit>;
using Inspection = std::variant<Refusal, Setup>;
[[nodiscard]] const char* error_name(Error) noexcept;

// COMPLETE circular TRANSLATION of a fixed-orientation box. In the plane
// perpendicular to shaft, add (R*cos(theta),R*sin(theta)) to every point.
// The zero-displacement reference is not itself an actual orbit pose for R>0.
// Strict-interior policy and complete-set validation reuse the native box query.
// The circle must meet the open obstacle-minus-body rectangle: min²<R²<max².
// Native bounds cover the entire actual orbit. Return the lowest obstructing
// identity independent of observation order, never a partial move/impact phase.
[[nodiscard]] OrbitQuery orbit(const clearance::Box& reference, mechanics::Axis shaft,
                               Integer radius, std::span<const clearance::Obstacle>);

// Pure observations for a DECLARED guided same-phase parallel-crank branch.
// Equal crank pins and a constant separation translate the tray without spin.
// One caller owns its physical circle direction; the other pin and output
// motion follow it 1:1. The per-radian derivative is geometric, not a native
// per-tick displacement or an implicit angular-unit conversion.
//
// Bare four-bars can change assembly branch at collinear poses. The exposed
// change-point flag and a clear tray sweep do NOT establish guide/branch
// retention, full crank/guide solids, forces or unique mechanical admission.
// World owns those constraints, actual graph/phase/clock and material adoption.
// These APIs store no live state; geometry-only setup is separate from power.
[[nodiscard]] Reading sample(const Profile&, Direction, mechanics::Motion);
[[nodiscard]] Inspection inspect(const Profile&, std::span<const clearance::Obstacle>);
}  // namespace factory::orbital_platform
