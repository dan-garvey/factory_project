#pragma once

#include "factory/mechanics.hpp"

#include <optional>

namespace factory::waterwheel {

// All positions and velocities use the same caller-owned integer grid. The
// flow sample is trusted site data, not a player command or a fluid simulation.
struct Sample {
    mechanics::Integer surface{};
    mechanics::Integer bed{};
    mechanics::Integer velocity_x{};
    mechanics::Integer velocity_z{};
    bool operator==(const Sample&) const = default;
};

[[nodiscard]] std::optional<bool> immersed(
    mechanics::Integer center_height, mechanics::Integer radius,
    mechanics::Axis axle, const Sample& sample) noexcept;

// Ideal undershot wheel. The axle is horizontal and the lower rim must cross
// the water surface above the bed. The result is angular rate per time unit,
// signed around the positive axle; zero means no tangential current.
// Invalid dimensions or values return no result, not a rounded drive.
[[nodiscard]] std::optional<mechanics::Rate> rate(
    mechanics::Integer center_height, mechanics::Integer radius,
    mechanics::Axis axle, const Sample& sample) noexcept;

}  // namespace factory::waterwheel
