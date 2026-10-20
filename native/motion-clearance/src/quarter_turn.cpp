#include "factory/clearance.hpp"
#include "native/motion-clearance/src/arc_math.hpp"

#include <algorithm>

namespace factory::clearance {
namespace {
constexpr auto bound = mechanics::maximum_coordinate;
// Plane coordinates are at most 2*bound, quadratic coefficients at most 4*bound.
// The private isolator's proof and squared 64-bit plane bounds use this cap.
static_assert(bound > 0 && bound <= 1000000);
bool valid_box(const Box& b) noexcept {
    for (std::size_t axis = 0; axis < 3; ++axis) {
        if (b.minimum[axis] < -bound || b.maximum[axis] > bound || b.minimum[axis] >= b.maximum[axis]) return false;
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
struct Rectangle { Coordinate low_u{}, high_u{}, low_v{}, high_v{}; };
Rectangle plane(const Box& b, const Point& pivot, std::size_t axis, TurnDirection direction) noexcept {
    const auto u = (axis + 1) % 3, v = (axis + 2) % 3;
    Rectangle r{b.minimum[u] - pivot[u], b.maximum[u] - pivot[u], b.minimum[v] - pivot[v], b.maximum[v] - pivot[v]};
    if (direction == TurnDirection::negative) {
        const auto low = r.low_v; r.low_v = -r.high_v; r.high_v = -low;
    }
    return r;
}
bool upper_bound(Coordinate cosine, Coordinate sine, Coordinate limit) noexcept {
    if (cosine > 0 && sine > 0) return limit >= 0 && cosine * cosine + sine * sine <= limit * limit;
    return std::max(cosine, sine) <= limit;
}
bool fits(const Rectangle& r, const Rectangle& grid) noexcept {
    return upper_bound(r.high_u, -r.low_v, grid.high_u) && upper_bound(-r.low_u, r.high_v, -grid.low_u) &&
           upper_bound(r.high_v, r.high_u, grid.high_v) && upper_bound(-r.low_v, -r.low_u, -grid.low_v);
}
detail::Polynomial inequality(Coordinate cosine, Coordinate sine, Coordinate constant) noexcept {
    // cos=(1-t^2)/(1+t^2), sin=2t/(1+t^2), t in [0,1].
    return {constant - cosine, 2 * sine, cosine + constant};
}
bool collides(const Rectangle& r, const Rectangle& o) {
    // Strict overlap on the two fixed axes and the two rotated body axes.
    return detail::positive_somewhere({{
        inequality(r.high_u, -r.low_v, -o.low_u), inequality(-r.low_u, r.high_v, o.high_u),
        inequality(r.high_v, r.high_u, -o.low_v), inequality(-r.low_v, -r.low_u, o.high_v),
        inequality(o.high_u, o.high_v, -r.low_u), inequality(-o.low_u, -o.low_v, r.high_u),
        inequality(o.high_v, -o.low_u, -r.low_v), inequality(-o.low_v, o.high_u, r.high_v),
    }});
}
}  // namespace

QuarterTurnResult quarter_turn(const Rotor& rotor, TurnDirection direction, std::span<const Obstacle> obstacles) noexcept {
    try {
        if (!valid_box(rotor.box)) return {Error::invalid_box};
        const auto axis = axis_index(rotor.axis);
        if (axis == 3 || (direction != TurnDirection::positive && direction != TurnDirection::negative)) return {Error::invalid_motion};
        for (const auto coordinate : rotor.pivot) if (coordinate < -bound || coordinate > bound) return {Error::invalid_motion};
        const auto body = plane(rotor.box, rotor.pivot, axis, direction);
        const auto grid = plane({{-bound, -bound, -bound}, {bound, bound, bound}}, rotor.pivot, axis, direction);
        if (!fits(body, grid)) return {Error::invalid_motion};
        if (obstacles.size() > mechanics::maximum_parts) return {Error::too_many_obstacles};
        for (std::size_t i = 0; i < obstacles.size(); ++i) {
            if (!obstacles[i].id) return {Error::invalid_id};
            if (!valid_box(obstacles[i].box)) return {Error::invalid_box};
            for (std::size_t j = 0; j < i; ++j) if (obstacles[i].id == obstacles[j].id) return {Error::duplicate_id};
        }
        QuarterTurnResult result;
        for (const auto& obstacle : obstacles) {
            if (rotor.box.maximum[axis] <= obstacle.box.minimum[axis] || rotor.box.minimum[axis] >= obstacle.box.maximum[axis]) continue;
            if (collides(body, plane(obstacle.box, rotor.pivot, axis, direction)) &&
                (!result.obstacle || obstacle.id < *result.obstacle)) result.obstacle = obstacle.id;
        }
        return result;
    } catch (const detail::Limit&) {
        return {Error::arithmetic_limit};
    }
}
}  // namespace factory::clearance
