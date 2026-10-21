#pragma once

#include "factory/slider_crank.hpp"

namespace factory::geneva_drive {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Point = slider_crank::Point;
using Direction = slider_crank::Direction;
using Ray = std::array<slider_crank::Coordinate, 3>;
inline constexpr Integer maximum_radius = 2048;
struct Profile {
    std::uint32_t driver_id{7}, wheel_id{11};
    mechanics::Point origin{0, 0, 8};
    mechanics::Axis shaft{mechanics::Axis::z}, span{mechanics::Axis::x};
    Integer radius{10}, slot_inner{8}, slot_outer{18};
    bool dwell_lock{true};  // Declared ideal cam constraint, not inferred from a withdrawn pin.
    bool operator==(const Profile&) const = default;
};
struct Frame {
    Direction input;
    std::uint32_t slot{};  // Supplied slot identity 0..5 for this input revolution.
    bool operator==(const Frame&) const = default;
};
enum class Stage { incoming_dwell, indexing, outgoing_dwell };
struct Constraint {
    Ray slot_ray;  // World-axis components RELATIVE to wheel centre; not a unit vector.
    Fraction per_input_radian;
    mechanics::Motion output;  // Conditional ideal kinematics; not a live graph prescription.
};
struct Sample {
    Profile profile;
    Frame frame;
    mechanics::Motion input;
    mechanics::Point wheel;
    Point pin;
    Fraction pin_distance_squared;
    Stage stage;
    bool radial_fits{};
    std::optional<Constraint> constraint;
};
struct Cycle {
    Profile profile;
    mechanics::Point wheel;
    std::array<Ray, 2> boundary_rays;  // Incoming and outgoing tangential directions.
    Integer minimum_radius_squared{}, maximum_radius_squared{};
    bool slot_covers{};
    Fraction index_fraction{1, 3}, dwell_fraction{2, 3}, step_per_positive_turn{-1, 6};
    [[nodiscard]] bool complete() const noexcept { return slot_covers && profile.dwell_lock; }
};
enum class Error { invalid_profile, invalid_axes, invalid_frame, invalid_direction, invalid_motion,
                   invalid_rate, representation_limit, unsupported_result };
struct Refusal { Error reason; std::optional<geared_cycle::Error> rate_error{}; };
using Reading = std::variant<Refusal, Sample>;
using Inspection = std::variant<Refusal, Cycle>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Six-slot external Geneva, axis spacing exactly 2R. ONE caller owns its input
// phase frame AND the corresponding slot identity; no winding/counter is inferred.
// Canonical angle is [-pi,pi): negative-X with sine zero is incoming dwell.
// Advancing the supplied slot at that seam permutes the six identical rays by
// +60 degrees and preserves wheel orientation. This API does not advance phase.
//
// Active pin closure requires cos(theta)>1/2 AND finite radial slot fit. A
// withdrawn pin supplies no wheel constraint unless the ideal dwell lock is
// explicitly declared. Its fixed slot ray uses the exact tangential boundary
// direction, not an invented continuing attachment to the actual pin.
//
// Per-input-radian derivative is geometric, never a native per-tick conversion.
// Retain native source states: unavailable/stopped/stalled do not become power;
// a rotating input under a declared locked dwell has zero stopped output.
// Validate both raw and inferred native rates before useful constrained output.
// No actual graph prescription, bodies/roller/locking-cam clearance, forces,
// impact/acceleration/contact admission, material, clock or World is established.
[[nodiscard]] Reading sample(const Profile&, Frame, mechanics::Motion);

// Exact whole-slot range and explicit lock-qualified dwell. Irrational entry
// directions live in Coordinate boundary rays; never round them into the bounded
// rational physical-circle chart. Constant angular input gives 1/3 index and 2/3
// dwell, not constant output velocity. A fitting current pose is insufficient.
[[nodiscard]] Inspection inspect(const Profile&);
}  // namespace factory::geneva_drive
