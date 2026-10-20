#include "factory/clearance.hpp"

#include <algorithm>

namespace factory::clearance {
namespace {
constexpr auto bound = mechanics::maximum_coordinate;
// Each radial difference is at most 2*bound. A sum of two squares is at most
// 8*bound^2, which fits int64 under this explicit grid contract.
static_assert(bound > 0 && bound <= 1000000000);

bool valid_box(const Box& box) noexcept {
    for (std::size_t axis = 0; axis < 3; ++axis) {
        if (box.minimum[axis] < -bound || box.maximum[axis] > bound ||
            box.minimum[axis] >= box.maximum[axis]) return false;
    }
    return true;
}

std::size_t axis_index(mechanics::Axis axis) noexcept {
    switch (axis) {
        case mechanics::Axis::x: return 0;
        case mechanics::Axis::y: return 1;
        case mechanics::Axis::z: return 2;
    }
    return 3;
}

struct RadialRange { Coordinate lower{}, upper{}; };

RadialRange radial_range(const Box& box, const Point& pivot, std::size_t axis) noexcept {
    RadialRange result;
    for (const auto coordinate : {(axis + 1) % 3, (axis + 2) % 3}) {
        const auto low = box.minimum[coordinate] - pivot[coordinate];
        const auto high = box.maximum[coordinate] - pivot[coordinate];
        const auto near = low > 0 ? low : high < 0 ? -high : 0;
        const auto far = std::max(low < 0 ? -low : low, high < 0 ? -high : high);
        result.lower += near * near;
        result.upper += far * far;
    }
    return result;
}
}  // namespace

FullTurnResult full_turn(const Rotor& rotor, std::span<const Obstacle> obstacles) noexcept {
    if (!valid_box(rotor.box)) return {Error::invalid_box};
    const auto axis = axis_index(rotor.axis);
    if (axis == 3) return {Error::invalid_motion};
    for (const auto coordinate : rotor.pivot) {
        if (coordinate < -bound || coordinate > bound) return {Error::invalid_motion};
    }
    const auto body = radial_range(rotor.box, rotor.pivot, axis);
    auto room = bound;
    for (const auto coordinate : {(axis + 1) % 3, (axis + 2) % 3}) {
        room = std::min({room, bound - rotor.pivot[coordinate], bound + rotor.pivot[coordinate]});
    }
    if (body.upper > room * room) return {Error::invalid_motion};
    if (obstacles.size() > mechanics::maximum_parts) return {Error::too_many_obstacles};
    for (std::size_t i = 0; i < obstacles.size(); ++i) {
        if (obstacles[i].id == 0) return {Error::invalid_id};
        if (!valid_box(obstacles[i].box)) return {Error::invalid_box};
        for (std::size_t j = 0; j < i; ++j) {
            if (obstacles[j].id == obstacles[i].id) return {Error::duplicate_id};
        }
    }
    FullTurnResult result;
    for (const auto& obstacle : obstacles) {
        if (rotor.box.maximum[axis] <= obstacle.box.minimum[axis] ||
            rotor.box.minimum[axis] >= obstacle.box.maximum[axis]) continue;
        const auto other = radial_range(obstacle.box, rotor.pivot, axis);
        const auto lower = std::max(body.lower, other.lower);
        const auto upper = std::min(body.upper, other.upper);
        // A rectangle's radii form one connected interval. A complete rotation
        // therefore sweeps its annulus; axial overlap plus a strict radial
        // interval overlap is necessary and sufficient for interior collision.
        if (lower >= upper) continue;
        if (!result.hit || obstacle.id < result.hit->obstacle) {
            result.hit = FullTurnHit{obstacle.id, lower, upper};
        }
    }
    return result;
}
}  // namespace factory::clearance
