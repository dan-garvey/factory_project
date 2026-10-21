#include "factory/scotch_yoke.hpp"

#include <algorithm>
#include <numeric>

namespace factory::scotch_yoke {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
static_assert(g::maximum_coordinate <= 1000000 && g::maximum_dimension <= 4096 && maximum_direction_scale <= 256);
// After raw validation, position numerators are below 2.6e8 and body offsets
// below 1.1e6. No supplied native rate is multiplied into a geometric derivative.
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction fraction(Integer n, Integer d = 1) {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(n), static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
std::optional<Refusal> validate(const Profile& p) {
    if (!p.crank_id || !p.yoke_id || p.crank_id == p.yoke_id ||
        !std::all_of(p.origin.begin(), p.origin.end(), [](auto v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; }))
        return Refusal{Error::invalid_profile};
    if (static_cast<std::size_t>(p.shaft) >= 3 || static_cast<std::size_t>(p.travel) >= 3 || p.shaft == p.travel)
        return Refusal{Error::invalid_axes};
    for (auto v : {p.radius, p.pin_radius, p.slot_half_width, p.slot_half_length, p.wall, p.half_thickness})
        if (v < 1 || v > g::maximum_dimension) return Refusal{Error::invalid_profile};
    return {};
}
bool inside(Fraction value) {
    return value.numerator >= -g::maximum_coordinate * value.denominator && value.numerator <= g::maximum_coordinate * value.denominator;
}
c::Box wall_box(const Profile& p, std::size_t index) {
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.travel), v = 3 - a - u;
    c::Box box{p.origin, p.origin};
    box.minimum[a] -= p.half_thickness; box.maximum[a] += p.half_thickness;
    box.minimum[u] -= p.radius + p.slot_half_width; box.maximum[u] += -p.radius + p.slot_half_width;
    box.minimum[v] -= p.slot_half_length; box.maximum[v] += p.slot_half_length;
    if (index < 2) {
        box.minimum[v] -= p.wall; box.maximum[v] += p.wall;
        if (index == 0) { box.maximum[u] = box.minimum[u]; box.minimum[u] -= p.wall; }
        else { box.minimum[u] = box.maximum[u]; box.maximum[u] += p.wall; }
    } else if (index == 2) { box.maximum[v] = box.minimum[v]; box.minimum[v] -= p.wall; }
    else { box.minimum[v] = box.maximum[v]; box.maximum[v] += p.wall; }
    return box;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_axes: return "invalid_axes";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::outside_slot_width: return "outside_slot_width";
        case Error::outside_slot_length: return "outside_slot_length";
        case Error::representation_limit: return "representation_limit";
        case Error::query_refused: return "query_refused";
    }
    return "unknown";
}

Reading sample(const Profile& p, Direction direction, g::Motion input) {
    if (const auto refusal = validate(p)) return *refusal;
    const auto x = direction.cosine, y = direction.sine, q = direction.scale;
    if (x < -maximum_direction_scale || x > maximum_direction_scale || y < -maximum_direction_scale || y > maximum_direction_scale ||
        q < 1 || q > maximum_direction_scale || x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1)
        return Refusal{Error::invalid_direction};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating && input.state != g::MotionState::stalled)
        return Refusal{Error::invalid_motion};
    const auto admitted = k::prepare(k::maximum_teeth, {}, input.rate, false);
    if (const auto* error = std::get_if<k::Error>(&admitted)) return Refusal{Error::invalid_rate, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    if (p.slot_half_width < p.pin_radius) return Refusal{Error::outside_slot_width};
    if (p.slot_half_length < p.pin_radius || p.radius * static_cast<Integer>(magnitude(y)) > (p.slot_half_length - p.pin_radius) * q)
        return Refusal{Error::outside_slot_length};
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.travel), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    Sample result{p, direction, input, {}, {}, {}};
    for (std::size_t i = 0; i < 3; ++i) result.pin[i] = result.yoke[i] = fraction(p.origin[i]);
    result.yoke[u] = result.pin[u] = fraction(p.origin[u] * q + p.radius * x, q);
    result.pin[v] = fraction(p.origin[v] * q + handed * p.radius * y, q);
    result.yoke_per_radian[u] = fraction(-p.radius * y, q);
    if (!std::all_of(result.pin.begin(), result.pin.end(), inside) || !std::all_of(result.yoke.begin(), result.yoke.end(), inside))
        return Refusal{Error::representation_limit};
    return result;
}

TurnPlan prepare_turn(const Profile& p, std::span<const c::Obstacle> obstacles) {
    if (const auto refusal = validate(p)) return *refusal;
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.travel);
    auto centre = p.origin; centre[u] += p.radius;
    c::Box pin{centre, centre};
    for (std::size_t i = 0; i < 3; ++i) {
        const auto extent = i == a ? p.half_thickness : p.pin_radius;
        pin.minimum[i] -= extent; pin.maximum[i] += extent;
    }
    const auto checked = c::sweep(pin, {}, {});
    if (!checked.clear()) return Refusal{Error::representation_limit, {}, checked.error};
    Turn result{p, {p.slot_half_width >= p.pin_radius, p.slot_half_length >= p.radius + p.pin_radius}, {pin, p.origin, p.shaft}, {}, {}, {}, {}};
    result.pin_clearance = c::full_turn(result.pin_proxy, obstacles);
    if (result.pin_clearance.error == c::Error::invalid_motion) return Refusal{Error::representation_limit, {}, result.pin_clearance.error};
    if (result.pin_clearance.error != c::Error::none) return Refusal{Error::query_refused, {}, result.pin_clearance.error};
    result.wall_traverse[u] = 2 * p.radius;
    for (std::size_t i = 0; i < 4; ++i) {
        result.wall_start[i] = wall_box(p, i);
        const auto bounded = c::sweep(result.wall_start[i], result.wall_traverse, {});
        if (bounded.error != c::Error::none) return Refusal{Error::representation_limit, {}, bounded.error};
        result.walls[i] = obstacles.empty() ? bounded : c::sweep(result.wall_start[i], result.wall_traverse, obstacles);
        if (result.walls[i].error != c::Error::none) return Refusal{Error::query_refused, {}, result.walls[i].error};
    }
    return result;
}
}  // namespace factory::scotch_yoke
