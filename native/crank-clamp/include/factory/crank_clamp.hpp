#pragma once

#include "factory/slider_crank.hpp"

namespace factory::crank_clamp {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Point = slider_crank::Point;
using Direction = slider_crank::Direction;
using Coordinate = slider_crank::Coordinate;
inline constexpr Integer maximum_arm = 2048;
enum class Clocking { opposed, same_reference };
struct Profile {
    std::array<std::uint32_t, 4> ids{7, 11, 13, 17};  // Left crank/jaw, right crank/jaw.
    mechanics::Point origin{0, 0, 8};
    mechanics::Axis shaft{mechanics::Axis::z}, travel{mechanics::Axis::x};
    Integer spacing{20}, radius{3}, rod_length{5};
    Clocking clocking{Clocking::opposed};
    bool operator==(const Profile&) const = default;
};
struct Centre {
    Point reference;
    Integer cosine_coefficient{};  // Additional travel coordinate is coefficient*cos(theta).
    [[nodiscard]] bool fixed() const noexcept { return cosine_coefficient == 0; }
};
struct Sample {
    Profile profile;
    Direction direction;
    std::array<slider_crank::Sample, 2> jaws;
    Point centre;
    Coordinate gap;  // Right working plane minus left; negative diagnoses reversed order.
    bool powered{};
};
struct Cycle {
    Profile profile;
    std::array<slider_crank::Cycle, 2> jaws;
    Centre centre;
    std::optional<std::array<Coordinate, 2>> gap_extrema;
    [[nodiscard]] bool closed() const noexcept { return jaws[0].closed() && jaws[1].closed(); }
    [[nodiscard]] bool regular() const noexcept { return jaws[0].regular() && jaws[1].regular(); }
};
enum class Error { invalid_profile, invalid_axes, invalid_direction, invalid_motion, invalid_rate,
                   drive_mismatch, parent_refused, representation_limit };
struct Refusal {
    Error reason;
    std::uint32_t subject{};
    std::optional<slider_crank::Error> parent_error{};
    std::optional<geared_cycle::Error> rate_error{};
};
using Reading = std::variant<Refusal, Sample>;
using Inspection = std::variant<Refusal, Cycle>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Matched zero-offset rods, explicit mounting, ONE physical caller direction.
// Correct clocking gives theta_right=pi-theta_left; the wrong reference gives
// -theta_left. Both need actual equal/opposite native rates when rotating.
// The two parent derivative terms keep their OWN local crank-angle units.
// Native gearing has no phase authority here: mounting is a declared setup,
// and all angles/centres are owned observations, not a second live jaw state.
// Validate both observed source motions before useful geometry, even if the
// first rod cannot reach. Unavailable native sources do not invent pair power.
//
// The 2048 arm limit propagates the parent's radical bound after multiplying K
// by four; it is a representation limit of this adapter, not a game-scale law.
// No new root solver, collision/contact/grip, force, material, graph, clock or
// World is adopted; negative gap has no automatic overlap/loss response.
[[nodiscard]] Reading sample(const Profile&, Direction, std::array<mechanics::Motion, 2>);

// Exact whole-cycle centre certificate and ordered gap bounds, independent of
// source availability. One accidentally centred pose cannot establish a fixed
// work centre. Reuse parent closure/regularity; impossible gaps remain absent.
[[nodiscard]] Inspection inspect(const Profile&);
}  // namespace factory::crank_clamp
