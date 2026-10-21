#include "factory/waterwheel.hpp"

#include <numeric>

namespace factory::waterwheel {

std::optional<bool> immersed(mechanics::Integer center_height,
                                   mechanics::Integer radius,
                                   mechanics::Axis axle,
                                   const Sample& sample) noexcept {
    constexpr auto limit = mechanics::maximum_coordinate;
    const auto in_range = [limit](mechanics::Integer value) { return value >= -limit && value <= limit; };
    if (!in_range(center_height) || radius <= 0 || radius > mechanics::maximum_coordinate ||
        !in_range(sample.surface) || !in_range(sample.bed) || sample.bed >= sample.surface ||
        !in_range(sample.velocity_x) || !in_range(sample.velocity_z) ||
        (axle != mechanics::Axis::x && axle != mechanics::Axis::z)) return std::nullopt;
    const auto bottom = center_height - radius;
    // A surface above the axle would drive the upper half too. This simple
    // undershot model intentionally makes no prediction for that geometry.
    return bottom < sample.surface && bottom > sample.bed && sample.surface <= center_height;
}

std::optional<mechanics::Rate> rate(mechanics::Integer center_height,
                                   mechanics::Integer radius,
                                   mechanics::Axis axle,
                                   const Sample& sample) noexcept {
    const auto contact = immersed(center_height, radius, axle, sample);
    if (!contact) return std::nullopt;
    if (!*contact) return mechanics::Rate{0, 1};
    // Positive rotation about X moves the bottom toward -Z; about Z it moves
    // toward +X. Axial flow cannot turn this ideal wheel.
    const auto tangent = axle == mechanics::Axis::x ? -sample.velocity_z : sample.velocity_x;
    if (tangent == 0) return mechanics::Rate{0, 1};
    const auto divisor = std::gcd(tangent, radius);
    return mechanics::Rate{tangent / divisor, radius / divisor};
}

}  // namespace factory::waterwheel
