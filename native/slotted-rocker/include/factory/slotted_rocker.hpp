#pragma once

#include "factory/slider_crank.hpp"

namespace factory::slotted_rocker {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Direction = slider_crank::Direction;
using Point = slider_crank::Point;
using Ray = std::array<slider_crank::Coordinate, 3>;
inline constexpr Integer maximum_radius = mechanics::maximum_dimension / 3;
struct Profile {
    std::uint32_t crank_id{7}, lever_id{11};
    mechanics::Point origin{0, 0, 8};
    mechanics::Axis shaft{mechanics::Axis::z}, span{mechanics::Axis::x};
    Integer radius{10}, slot_inner{8}, slot_outer{31};
    bool operator==(const Profile&) const = default;
};
enum class Stroke { short_arc, long_arc };
struct Constraint { Fraction per_input_radian; mechanics::Motion output; };
struct Sample {
    Profile profile;
    Direction direction;
    mechanics::Motion input;
    mechanics::Point pivot;
    Point pin, lever_ray;
    Fraction distance_squared;
    Stroke stroke;
    bool slot_fits{};
    std::optional<Constraint> constraint;
};
struct Reversal { Ray pin_from_crank, lever_from_pivot; };
struct Cycle {
    Profile profile;
    mechanics::Point pivot;
    Integer minimum_distance{}, maximum_distance{};
    bool slot_covers{};
    std::array<Reversal, 2> reversals;  // Negative, positive transverse crank position.
    Fraction short_input_fraction{1, 3}, long_input_fraction{2, 3};
};
enum class Error { invalid_profile, invalid_axes, invalid_direction, invalid_motion, invalid_rate,
                   representation_limit, unsupported_result };
struct Refusal { Error reason; std::optional<geared_cycle::Error> rate_error{}; };
using Reading = std::variant<Refusal, Sample>;
using Inspection = std::variant<Refusal, Cycle>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Continuously engaged crank/slotted lever, with reversible experimental pivot
// spacing 2R. The lever rocks through both strokes; no withdrawn pin, held dwell,
// implicit slot counter or new phase authority exists. ONE caller circle gives
// the current pin and actual pivot-relative ray. Missing finite slot contact
// supplies no output constraint. Retain raw/native unavailable states and refuse
// unsupported inferred output rates without partial output.
//
// Ratio is per physical input radian. Conditional equal-angular-unit native
// readouts are observations, not a live time-varying graph prescription or tick
// conversion. Bounds on the declared circular slot envelope are arithmetic
// admission, not full solid collision. No pin width, ram, forces/contact,
// tooth/body clearance, clock, World/material or construction rule is adopted.
[[nodiscard]] Reading sample(const Profile&, Direction, mechanics::Motion);

// Full radial range R..3R, with exact irrational reversal rays at crank cosine
// 1/2. These endpoints are not rounded into the rational physical-circle chart.
// Constant physical input speed divides the strokes into 1/3 and 2/3 of a turn;
// it gives nonuniform output speed, without a positive-duration dwell.
[[nodiscard]] Inspection inspect(const Profile&);
}  // namespace factory::slotted_rocker
