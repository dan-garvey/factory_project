#pragma once

#include "factory/slider_crank.hpp"

namespace factory::tusi_stroke {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Direction = slider_crank::Direction;
using Point = slider_crank::Point;
using Coordinate = slider_crank::Coordinate;
inline constexpr Integer maximum_radius = 2048;
struct Profile {
    std::uint32_t ring_id{7}, carrier_id{9}, planet_id{11}, pin_id{13};
    mechanics::Point origin{0, 0, 8};
    mechanics::Axis shaft{mechanics::Axis::z}, span{mechanics::Axis::x};
    Integer radius{4};  // Moving circle R; stationary internal pitch circle is 2R.
    Direction clocking;  // Initial pin direction on the moving circle at carrier angle zero.
    bool ring_locked{true};
    mechanics::Point lower{-10, -1, 8}, upper{10, 1, 8};  // Finite guide window, not a construction area.
    bool operator==(const Profile&) const = default;
};
struct Sample {
    Profile profile;
    Direction direction;
    mechanics::Motion carrier, planet;  // Conditional ideal rates, not graph prescriptions.
    Point center, contact, pin, pin_per_input_radian;
    bool guide_fits{};
};
struct Cycle {
    Profile profile;
    std::array<std::array<Coordinate, 2>, 3> bounds;
    bool guide_fits{};
};
enum class Error { invalid_profile, invalid_axes, invalid_direction, invalid_clocking, invalid_motion,
                   invalid_rate, unconstrained_ring, representation_limit };
struct Refusal { Error reason; std::optional<geared_cycle::Error> rate_error{}; };
using Reading = std::variant<Refusal, Sample>;
using Inspection = std::variant<Refusal, Cycle>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Ideal fixed ring of pitch radius 2R and an internally rolling circle of R.
// ONE caller phase and the initial clocking derive both opposed circular motions.
// Absolute planet spin is -carrier, while its carrier-relative spin is -2carrier.
// The material contact velocity is zero; the changing contact LOCATION need not
// be stationary. A free ring cannot supply this phase or rate relationship.
// Validate raw native state/rate even when the ring is free or power is absent.
//
// Every clocking traces a diameter, generally oblique to span. Keep exact
// rational samples and per-input-radian derivatives, not a new phase clock or
// implicit native per-tick translation. The complete pitch-circle grid envelope
// validates before observations. Radius 2048 is an inherited arithmetic bound.
// Complete tooth/solid clearance, friction/force/contact, actual ring fixture,
// graph, construction, World/material and persistence remain unestablished.
[[nodiscard]] Reading sample(const Profile&, Direction, mechanics::Motion);

// Exact whole-axis extrema for the entire line stroke, including irrational
// oblique extrema. Compare these with the finite guide; a fitting pose is not
// a whole-stroke certificate. Guide bounds do not establish body clearance.
[[nodiscard]] Inspection inspect(const Profile&);
}  // namespace factory::tusi_stroke
