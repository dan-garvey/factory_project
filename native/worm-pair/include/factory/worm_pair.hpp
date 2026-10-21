#pragma once

#include "factory/clearance.hpp"
#include "factory/geared_cycle.hpp"

#include <array>
#include <optional>
#include <span>
#include <variant>

namespace factory::worm_pair {
using Integer = mechanics::Integer;
using Id = std::uint32_t;

// Direction of observed axial thread-pattern travel for positive rotation
// about the positive world axis. These are NOT manufacturer thread-hand labels.
enum class Pattern { positive = 1, negative = -1 };
struct Worm {
    Id id{};
    mechanics::Point center{};
    mechanics::Axis axis{mechanics::Axis::x};
    Integer radius{4}, half_span{16}, starts{1};
    Pattern pattern{Pattern::positive};
    bool operator==(const Worm&) const = default;
};
struct Wheel {
    Id id{};
    mechanics::Point center{};
    mechanics::Axis axis{mechanics::Axis::y};
    Integer teeth{24}, half_width{2};  // Existing pitch radius = tooth count.
    bool operator==(const Wheel&) const = default;
};
struct Drive { Id part{}; mechanics::Rate rate; };
struct Geometry {
    Worm worm;
    Wheel wheel;
    mechanics::Point contact{};
    std::array<clearance::Box, 2> pitch_bounds;
    mechanics::Rate wheel_from_worm;
};
struct Evaluation {
    Geometry geometry;
    std::array<mechanics::Motion, 2> motion;  // Worm, wheel; positive global axes.
    std::array<std::optional<mechanics::Rate>, 2> prescribed;
};
enum class Error {
    invalid_worm, invalid_wheel, duplicate_id, not_perpendicular, pitch_gap,
    outside_worm_face, outside_wheel_face, representation_limit, too_many_drives,
    unknown_part, duplicate_drive, invalid_rate, native_refused, unsupported_result,
};
struct Refusal {
    Error reason;
    Id subject{};
    std::optional<geared_cycle::Error> rate_error{};
    std::optional<mechanics::Error> native_error{};
    std::optional<clearance::Error> envelope_error{};
};
using Result = std::variant<Refusal, Evaluation>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure declared ideal cylindrical worm mesh on skew perpendicular axes. Axial
// lead per revolution is 2*pi*starts in existing pitch units. Thread-pattern
// axial travel equals wheel tangential travel; contact also lies strictly
// inside both finite axial faces. Magnitude is starts/teeth, NOT radius/teeth.
// The local native spur representation supplies power/conflict arithmetic only.
//
// Missing observations are unpowered, not brakes. A supplied wheel drive is an
// ideal source constraint, not evidence of real backdrive eligibility. The
// authority owns friction/brakes, torque, tooth-profile/module/hand matching,
// contact and actual construction admission. Pitch-cylinder boxes are setup
// proxies, not full teeth/housing geometry. No automatic self-lock, phase,
// clock, World, material or persistent state is introduced. Outputs are owned.
[[nodiscard]] Result evaluate(const Worm&, const Wheel&, std::span<const Drive>);
}  // namespace factory::worm_pair
