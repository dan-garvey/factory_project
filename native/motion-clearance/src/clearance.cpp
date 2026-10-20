#include "factory/clearance.hpp"

#include <numeric>
#include <utility>

namespace factory::clearance {
namespace {
constexpr auto bound = mechanics::maximum_coordinate;
// All plane differences and motion denominators are at most 2*bound. Their
// comparison cross-products fit signed 64-bit under this explicit proof bound.
static_assert(bound > 0 && bound <= 1000000000);

bool valid(const Box& box) noexcept {
    for (std::size_t axis = 0; axis < 3; ++axis) {
        if (box.minimum[axis] < -bound || box.maximum[axis] > bound ||
            box.minimum[axis] >= box.maximum[axis]) return false;
    }
    return true;
}

bool valid_motion(const Box& box, const Point& move) noexcept {
    for (std::size_t axis = 0; axis < 3; ++axis) {
        if (move[axis] < -2 * bound || move[axis] > 2 * bound) return false;
        if (box.minimum[axis] + move[axis] < -bound || box.maximum[axis] + move[axis] > bound) return false;
    }
    return true;
}

Fraction fraction(Coordinate numerator, Coordinate denominator) noexcept {
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    const auto divisor = std::gcd(numerator, denominator);
    return {numerator / divisor, denominator / divisor};
}

int compare(Fraction a, Fraction b) noexcept {
    const auto left = a.numerator * b.denominator;
    const auto right = b.numerator * a.denominator;
    return left < right ? -1 : left > right ? 1 : 0;
}

bool overlaps(const Box& a, const Box& b) noexcept {
    for (std::size_t axis = 0; axis < 3; ++axis) {
        if (a.maximum[axis] <= b.minimum[axis] || a.minimum[axis] >= b.maximum[axis]) return false;
    }
    return true;
}

std::optional<Hit> contact(const Box& box, const Point& move, const Obstacle& obstacle) noexcept {
    Fraction entry{0, 1}, exit{1, 1};
    for (std::size_t axis = 0; axis < 3; ++axis) {
        const auto delta = move[axis];
        if (delta == 0) {
            if (box.maximum[axis] <= obstacle.box.minimum[axis] ||
                box.minimum[axis] >= obstacle.box.maximum[axis]) return std::nullopt;
            continue;
        }
        auto low = fraction(obstacle.box.minimum[axis] - box.maximum[axis], delta);
        auto high = fraction(obstacle.box.maximum[axis] - box.minimum[axis], delta);
        if (compare(low, high) > 0) std::swap(low, high);
        if (compare(low, entry) > 0) entry = low;
        if (compare(high, exit) < 0) exit = high;
        // Plane inequalities are strict. An empty interval is only grazing or
        // endpoint contact, not interior overlap during the proposed movement.
        if (compare(entry, exit) >= 0) return std::nullopt;
    }
    return Hit{obstacle.id, entry, overlaps(box, obstacle.box)};
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "none";
        case Error::invalid_box: return "invalid_box";
        case Error::invalid_motion: return "invalid_motion";
        case Error::too_many_obstacles: return "too_many_obstacles";
        case Error::invalid_id: return "invalid_id";
        case Error::duplicate_id: return "duplicate_id";
        case Error::arithmetic_limit: return "arithmetic_limit";
    }
    return "unknown";
}

Result sweep(const Box& box, const Point& move, std::span<const Obstacle> obstacles) noexcept {
    if (!valid(box)) return {Error::invalid_box};
    if (!valid_motion(box, move)) return {Error::invalid_motion};
    if (obstacles.size() > mechanics::maximum_parts) return {Error::too_many_obstacles};
    for (std::size_t i = 0; i < obstacles.size(); ++i) {
        if (obstacles[i].id == 0) return {Error::invalid_id};
        if (!valid(obstacles[i].box)) return {Error::invalid_box};
        for (std::size_t j = 0; j < i; ++j) if (obstacles[j].id == obstacles[i].id) return {Error::duplicate_id};
    }
    Result result;
    for (const auto& obstacle : obstacles) {
        const auto hit = contact(box, move, obstacle);
        if (!hit) continue;
        if (!result.hit || compare(hit->time, result.hit->time) < 0 ||
            (compare(hit->time, result.hit->time) == 0 && hit->obstacle < result.hit->obstacle)) result.hit = hit;
    }
    return result;
}
}  // namespace factory::clearance
