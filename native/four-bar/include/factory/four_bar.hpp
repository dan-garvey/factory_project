#pragma once

#include "factory/slider_crank.hpp"

namespace factory::four_bar {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Direction = slider_crank::Direction;
using Point = slider_crank::Point;
using Branch = slider_crank::Branch;
inline constexpr Integer maximum_length = 64;
inline constexpr Integer maximum_scale = scotch_yoke::maximum_direction_scale;

// Exact factored value (base + coefficient*sqrt(radicand))/denominator.
// This is a geometry value, not a rounded live position or native rate.
struct Coordinate {
    Integer base{}, coefficient{}, radicand{}, denominator{1};
    bool operator==(const Coordinate&) const = default;
};
using Joint = std::array<Coordinate, 3>;
struct Profile {
    std::uint32_t crank_id{7}, coupler_id{9}, rocker_id{11};
    mechanics::Point origin{0, 0, 8};
    mechanics::Axis shaft{mechanics::Axis::z}, span{mechanics::Axis::x};
    Integer ground{8}, crank{2}, coupler{7}, rocker{5};
    Branch branch{Branch::positive};
    bool operator==(const Profile&) const = default;
};
struct Derivative {
    Fraction direct, inverse_root;  // direct + inverse_root/sqrt(radicand).
    Integer radicand{};
};
struct Sample {
    Profile profile;
    Direction direction;
    mechanics::Motion input;
    Point pin;
    mechanics::Point anchor;
    Joint joint;
    bool tangent{};
    std::optional<Derivative> per_input_radian;
};
struct Cycle {
    Profile profile;
    Integer minimum_distance{}, maximum_distance{};
    bool closed{}, regular{};
    bool envelope_within_grid{};  // Sufficient enclosing-disc bound, not a tight path bound.
};
enum class Error { invalid_profile, invalid_axes, invalid_direction, invalid_motion, invalid_rate,
                   invalid_coordinate, invalid_grid, unreachable, underconstrained, representation_limit };
struct Refusal { Error reason; std::optional<geared_cycle::Error> rate_error{}; };
using Reading = std::variant<Refusal, Sample>;
using Inspection = std::variant<Refusal, Cycle>;
using Comparison = std::variant<Error, slider_crank::Order>;
using RationalView = std::variant<Error, std::optional<Fraction>>;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] Comparison compare_to_grid(const Coordinate&, Integer);
[[nodiscard]] RationalView rational_view(const Coordinate&);

// Both finite-circle intersections of an ordinary planar four-bar, with ONE
// caller-owned physical input direction and explicit assembly branch. The span
// points to the fixed rocker anchor; shaft cross span supplies the proper second
// axis. Tangency has one joint but no regular derivative. Coincident equal
// circles are underconstrained, never a manufactured joint or divided-by-zero.
// Validate raw source state/rate even at unreachable or unpowered poses.
//
// Derivatives are geometric per input radian. An irrational ratio is not a
// rational native graph prescription; no native rate conversion is performed.
// Length <=64 and direction denominator <=256 are arithmetic adapter limits.
// No branch retention, complete solids/clearance, force/contact, clock, mutable
// phase, graph, World/material authority or construction grid is established.
[[nodiscard]] Reading sample(const Profile&, Direction, mechanics::Motion);

// Whole selected-input-turn reach uses abs(D-R)..D+R within abs(L-H)..L+H.
// A fitting current pose or a general Grashof inequality is insufficient.
// Strict containment and nonzero centre distance certify regular centreline
// closure only. A conservative enclosing-disc grid flag is reported separately.
[[nodiscard]] Inspection inspect(const Profile&);
}  // namespace factory::four_bar
