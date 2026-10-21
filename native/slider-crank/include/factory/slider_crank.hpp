#pragma once

#include "factory/scotch_yoke.hpp"

namespace factory::slider_crank {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Point = std::array<Fraction, 3>;
using Direction = scotch_yoke::Direction;
enum class Branch { positive, negative };

// One exact coordinate: (base + sign(branch)*sqrt(radicand))/denominator.
// No rounded/rational live mirror is stored. Public helpers validate raw fields
// before arithmetic; only an exact square gets a rational view.
struct Coordinate {
    Integer base{}, radicand{}, denominator{1};
    Branch branch{Branch::positive};
    bool operator==(const Coordinate&) const = default;
};
enum class Order { less, equal, greater };
enum class Error { invalid_profile, invalid_axes, invalid_direction, invalid_motion, invalid_rate,
                   invalid_coordinate, invalid_grid, unreachable, representation_limit };
using Comparison = std::variant<Error, Order>;
using RationalView = std::variant<Error, std::optional<Fraction>>;
[[nodiscard]] Comparison compare_to_grid(const Coordinate&, Integer);
[[nodiscard]] RationalView rational_view(const Coordinate&);
[[nodiscard]] const char* error_name(Error) noexcept;

struct Profile {
    std::uint32_t crank_id{7}, slider_id{11};
    mechanics::Point origin{0, 0, 8};
    mechanics::Axis shaft{mechanics::Axis::z}, travel{mechanics::Axis::x};
    Integer radius{3}, rod_length{5}, guide_offset{};
    Integer lower{2}, upper{8};  // World coordinates along the positive travel axis.
    Branch branch{Branch::positive};
    bool operator==(const Profile&) const = default;
};
struct Derivative {
    Fraction direct, inverse_root;  // direct + inverse_root/sqrt(radicand).
    Integer radicand{};            // Strictly positive whenever this exists.
};
struct Sample {
    Profile profile;
    Direction direction;
    mechanics::Motion crank;
    Point pin;
    mechanics::Point guide_anchor;  // Static point on the declared guide line.
    Coordinate slider;
    std::optional<Derivative> per_radian;
    bool guide_fits{};
};
struct Cycle {
    Profile profile;
    Integer minimum_projection_squared{};
    std::optional<std::array<Coordinate, 2>> extrema;  // Ordered; absent if not closed.
    bool guide_fits{};
    [[nodiscard]] bool closed() const noexcept { return minimum_projection_squared >= 0; }
    [[nodiscard]] bool regular() const noexcept { return minimum_projection_squared > 0; }
};
struct Refusal {
    Error reason;
    std::optional<geared_cycle::Error> rate_error{};
};
using Reading = std::variant<Refusal, Sample>;
using Inspection = std::variant<Refusal, Cycle>;

// Current centreline closure, from ONE physical circle direction. The logical
// transverse guide offset runs along shaft cross travel, in a proper 3D frame.
// A finite rod can miss the guide. Valid coordinates can have a nonsquare root;
// retain that exact value and compare integer guide/grid limits without rounding.
// Raw/native source validation applies even while unpowered. At zero longitudinal
// rod projection the derivative is absent; a normal zero slider speed at stroke
// reversal is a different, finite derivative. Per-radian terms are geometric,
// never an implicit native-angular-unit conversion or a per-tick displacement.
[[nodiscard]] Reading sample(const Profile&, Direction, mechanics::Motion);

// Whole-cycle centreline/finite-guide inspection. Current fit cannot establish
// full closure: L >= R+abs(offset); strict inequality keeps rod projection nonzero.
// Extrema come from the inner/outer tangent circles, signed for the explicit
// branch. Keep singular limiting cases visible and impossible extrema absent.
// No complete rod/crank/slider/guide solids, body collision, unique force/branch
// admission, live clock, graph, material or World adoption is established.
[[nodiscard]] Inspection inspect(const Profile&);
}  // namespace factory::slider_crank
