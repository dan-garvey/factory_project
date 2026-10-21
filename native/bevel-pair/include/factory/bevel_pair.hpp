#pragma once

#include "factory/clearance.hpp"
#include "factory/geared_cycle.hpp"

#include <array>
#include <optional>
#include <span>
#include <variant>

namespace factory::bevel_pair {
using Id = std::uint32_t;
using Integer = mechanics::Integer;

// Explicit bevel descriptors, separate from ordinary native spur Parts. A pitch
// radius equals its tooth count in this adapter's existing integer pitch units.
struct Gear {
    Id id{};
    mechanics::Point center{};  // Center of the outer pitch circle.
    mechanics::Axis axis{mechanics::Axis::x};
    Integer teeth{};
    bool operator==(const Gear&) const = default;
};
struct Drive {
    Id gear{};
    mechanics::Rate rate;  // About the POSITIVE world coordinate axis.
};
struct Geometry {
    std::array<Gear, 2> gears;
    mechanics::Point apex{}, contact{};
    std::array<clearance::Box, 2> pitch_bounds;
    mechanics::Rate second_from_first;
};
struct Evaluation {
    Geometry geometry;
    std::array<mechanics::Motion, 2> motion;  // In descriptor argument order.
    std::array<std::optional<mechanics::Rate>, 2> prescribed;
};
enum class Error {
    invalid_gear, duplicate_id, not_right_angle, skew_axes, pitch_mismatch,
    representation_limit, too_many_drives, unknown_gear, duplicate_drive,
    invalid_rate, native_refused, unsupported_result,
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

// Pure right-angle pitch-cone kinematics with a shared apex and outer generator.
// Validate ALL raw descriptors/drives before returning owned results. The local
// outward-axis spur representation reuses native connected-component semantics;
// it does not make perpendicular ordinary spur gears mesh. Missing drives are
// unpowered, explicit zero is stopped, and incompatible drives stall both gears.
//
// Pitch bounds enclose ideal full cones, not teeth, face widths or housings.
// The caller must perform actual construction/contact admission. This neither
// proves tooth-profile compatibility nor owns torque, phase, a clock or World.
[[nodiscard]] Result evaluate(const Gear&, const Gear&, std::span<const Drive>);
}  // namespace factory::bevel_pair
