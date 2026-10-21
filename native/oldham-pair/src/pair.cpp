#include "factory/oldham_pair.hpp"

#include <algorithm>
#include <limits>
#include <numeric>

namespace factory::oldham_pair {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
constexpr Integer dial_bound = cardan_pair::maximum_dial_component;
static_assert(dial_bound > 0 && dial_bound <= 64);
static_assert(g::maximum_coordinate > 0 && g::maximum_coordinate <= 1000000);
static_assert(g::maximum_dimension > 0 && g::maximum_dimension <= 4096);
constexpr Integer dot_bound = 4 * g::maximum_coordinate * dial_bound;
static_assert(dot_bound <= std::numeric_limits<Integer>::max() / dot_bound);
// A transverse dot is <= 4*10^6*64; its square fits int64. Every centre
// numerator is <= 6*10^6*64^2 and every derivative numerator is <= that bound.
// All raw centres/dimensions/dials are bounded BEFORE products or differences.
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction fraction(Integer n, Integer d = 1) {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(n), static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
bool dimension(Integer value) { return value > 0 && value <= g::maximum_dimension; }
std::optional<Refusal> validate(const Profile& profile) {
    for (const auto* port : {&profile.input, &profile.output}) {
        if (!port->id || static_cast<std::size_t>(port->axis) >= 3 ||
            !std::all_of(port->center.begin(), port->center.end(), [](auto v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; }))
            return Refusal{Error::invalid_port, port->id};
    }
    if (profile.input.id == profile.output.id) return Refusal{Error::duplicate_id, profile.output.id};
    if (profile.input.axis != profile.output.axis) return Refusal{Error::not_parallel, profile.output.id};
    if (!dimension(profile.input_travel) || !dimension(profile.output_travel) || !dimension(profile.disc_radius) || !dimension(profile.half_thickness))
        return Refusal{Error::invalid_profile};
    const auto axis = static_cast<std::size_t>(profile.input.axis);
    const auto gap = profile.output.center[axis] - profile.input.center[axis];
    if (gap > -2 * profile.half_thickness && gap < 2 * profile.half_thickness) return Refusal{Error::axial_gap, profile.output.id};
    return {};
}
bool inside(Fraction value) { return value.numerator >= -g::maximum_coordinate * value.denominator && value.numerator <= g::maximum_coordinate * value.denominator; }
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_port: return "invalid_port";
        case Error::duplicate_id: return "duplicate_id";
        case Error::not_parallel: return "not_parallel";
        case Error::invalid_profile: return "invalid_profile";
        case Error::axial_gap: return "axial_gap";
        case Error::invalid_dial: return "invalid_dial";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::outside_input_slot: return "outside_input_slot";
        case Error::outside_output_slot: return "outside_output_slot";
        case Error::representation_limit: return "representation_limit";
        case Error::query_refused: return "query_refused";
    }
    return "unknown";
}

Reading sample(const Profile& profile, Dial dial, g::Motion input) {
    if (const auto error = validate(profile)) return *error;
    if (dial.x < -dial_bound || dial.x > dial_bound || dial.y < -dial_bound || dial.y > dial_bound ||
        (dial.x == 0 && dial.y == 0) || std::gcd(dial.x, dial.y) != 1) return Refusal{Error::invalid_dial};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating && input.state != g::MotionState::stalled)
        return Refusal{Error::invalid_motion};
    const auto admitted = k::prepare(k::maximum_teeth, {}, input.rate, false);
    if (const auto* error = std::get_if<k::Error>(&admitted)) return Refusal{Error::invalid_rate, profile.input.id, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    const auto axis = static_cast<std::size_t>(profile.input.axis), u = (axis + 1) % 3, v = (axis + 2) % 3;
    const auto dx = profile.output.center[u] - profile.input.center[u], dy = profile.output.center[v] - profile.input.center[v];
    const auto x = dial.x, y = dial.y, n = x * x + y * y;
    const auto along = dx * x + dy * y, across = -dx * y + dy * x;
    if (along * along > profile.input_travel * profile.input_travel * n) return Refusal{Error::outside_input_slot, profile.input.id};
    if (across * across > profile.output_travel * profile.output_travel * n) return Refusal{Error::outside_output_slot, profile.output.id};
    Sample result{profile, dial, {}, {}, {fraction(along * along, n), fraction(across * across, n)}, {input, input, input}};
    result.centre[axis] = fraction(profile.input.center[axis] + profile.output.center[axis], 2);
    result.centre[u] = fraction(profile.input.center[u] * n + dx * x * x + dy * x * y, n);
    result.centre[v] = fraction(profile.input.center[v] * n + dx * x * y + dy * y * y, n);
    result.centre_per_radian[u] = fraction(-2 * dx * x * y + dy * (x * x - y * y), n);
    result.centre_per_radian[v] = fraction(dx * (x * x - y * y) + 2 * dy * x * y, n);
    if (!std::all_of(result.centre.begin(), result.centre.end(), inside)) return Refusal{Error::representation_limit};
    return result;
}

TurnPlan prepare_turn(const Profile& profile, std::span<const c::Obstacle> obstacles) {
    if (const auto error = validate(profile)) return *error;
    const auto axis = static_cast<std::size_t>(profile.input.axis), u = (axis + 1) % 3, v = (axis + 2) % 3;
    g::Point pivot{};
    for (std::size_t coordinate = 0; coordinate < 3; ++coordinate) {
        const auto sum = profile.input.center[coordinate] + profile.output.center[coordinate];
        if (sum % 2) return Refusal{Error::representation_limit};
        pivot[coordinate] = sum / 2;
    }
    auto centre = profile.input.center;
    centre[axis] = pivot[axis];
    centre[u] = profile.output.center[u];
    c::Box box{centre, centre};
    for (std::size_t coordinate = 0; coordinate < 3; ++coordinate) {
        const auto extent = coordinate == axis ? profile.half_thickness : profile.disc_radius;
        box.minimum[coordinate] -= extent;
        box.maximum[coordinate] += extent;
    }
    const auto checked_box = c::sweep(box, {}, {});
    if (checked_box.error != c::Error::none) return Refusal{Error::representation_limit, 0, {}, checked_box.error};
    const c::Rotor proxy{box, pivot, profile.input.axis};
    const auto clearance = c::full_turn(proxy, obstacles);
    if (clearance.error == c::Error::invalid_motion) return Refusal{Error::representation_limit, 0, {}, clearance.error};
    if (clearance.error != c::Error::none) return Refusal{Error::query_refused, 0, {}, clearance.error};
    const auto dx = profile.output.center[u] - profile.input.center[u], dy = profile.output.center[v] - profile.input.center[v];
    const auto squared = dx * dx + dy * dy;
    return Turn{profile, proxy, {squared <= profile.input_travel * profile.input_travel, squared <= profile.output_travel * profile.output_travel}, clearance};
}
}  // namespace factory::oldham_pair
