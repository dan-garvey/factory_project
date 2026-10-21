#include "factory/geneva_drive.hpp"

#include <algorithm>
#include <numeric>

namespace factory::geneva_drive {
namespace g = mechanics;
namespace s = slider_crank;
namespace k = geared_cycle;
namespace {
static_assert(g::maximum_coordinate <= 1000000 && maximum_radius <= g::maximum_dimension / 2);
static_assert(scotch_yoke::maximum_direction_scale <= 256 && k::maximum_denominator <= 1000000 && k::maximum_intervals <= 256);
// Raw guards precede products: squared radial numerators <=9.7e9; native
// derivative products <=6.6e10 and denominators <=2.4e9, inside int64.
std::uint64_t magnitude(Integer n) { const auto bits = static_cast<std::uint64_t>(n); return n < 0 ? std::uint64_t{0} - bits : bits; }
Fraction fraction(Integer n, Integer d = 1) {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(n), static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
std::optional<k::Error> rate_error(Fraction rate) {
    const auto checked = k::prepare(k::maximum_teeth, {}, rate, false);
    if (const auto* error = std::get_if<k::Error>(&checked)) return *error;
    return {};
}
bool grid(Integer n) { return n >= -g::maximum_coordinate && n <= g::maximum_coordinate; }
std::optional<Refusal> raw(const Profile& p) {
    if (!p.driver_id || !p.wheel_id || p.driver_id == p.wheel_id || !std::all_of(p.origin.begin(), p.origin.end(), grid) ||
        p.radius < 1 || p.radius > maximum_radius || p.slot_inner < 1 || p.slot_outer > g::maximum_dimension || p.slot_inner >= p.slot_outer)
        return Refusal{Error::invalid_profile};
    if (static_cast<std::size_t>(p.shaft) >= 3 || static_cast<std::size_t>(p.span) >= 3 || p.shaft == p.span) return Refusal{Error::invalid_axes};
    return {};
}
g::Point wheel(const Profile& p) { auto at = p.origin; at[static_cast<std::size_t>(p.span)] += 2 * p.radius; return at; }
std::optional<Refusal> bounds(const Profile& p) {
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u;
    const auto at = wheel(p);
    for (const auto i : {u, v}) if (!grid(p.origin[i] - p.radius) || !grid(p.origin[i] + p.radius) || !grid(at[i] - p.slot_outer) || !grid(at[i] + p.slot_outer))
        return Refusal{Error::representation_limit};
    return {};
}
Ray boundary(const Profile& p, bool incoming) {
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    Ray result{};
    result[u] = {-3 * p.radius, 0, 2};
    result[v] = {0, 3 * p.radius * p.radius, 2, handed * (incoming ? -1 : 1) > 0 ? s::Branch::positive : s::Branch::negative};
    return result;
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_axes: return "invalid_axes";
        case Error::invalid_frame: return "invalid_frame";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::representation_limit: return "representation_limit";
        case Error::unsupported_result: return "unsupported_result";
    }
    return "unknown";
}

Reading sample(const Profile& p, Frame frame, g::Motion input) {
    if (const auto error = raw(p)) return *error;
    if (frame.slot >= 6) return Refusal{Error::invalid_frame};
    const auto x = frame.input.cosine, y = frame.input.sine, q = frame.input.scale;
    constexpr auto limit = scotch_yoke::maximum_direction_scale;
    if (x < -limit || x > limit || y < -limit || y > limit || q < 1 || q > limit || x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1)
        return Refusal{Error::invalid_direction};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating && input.state != g::MotionState::stalled)
        return Refusal{Error::invalid_motion};
    if (const auto error = rate_error(input.rate)) return Refusal{Error::invalid_rate, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    if (const auto error = bounds(p)) return *error;
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    const auto radial_n = p.radius * p.radius * (5 * q - 4 * x);
    const bool fits = p.slot_inner * p.slot_inner * q <= radial_n && radial_n <= p.slot_outer * p.slot_outer * q;
    const auto stage = 2 * x > q ? Stage::indexing : y < 0 || (y == 0 && x < 0) ? Stage::incoming_dwell : Stage::outgoing_dwell;
    Sample result{p, frame, input, wheel(p), {}, fraction(radial_n, q), stage, fits, {}};
    for (std::size_t i = 0; i < 3; ++i) result.pin[i] = fraction(p.origin[i]);
    result.pin[u] = fraction(p.origin[u] * q + p.radius * x, q);
    result.pin[v] = fraction(p.origin[v] * q + handed * p.radius * y, q);
    if (stage == Stage::indexing && !fits) return result;
    if (stage != Stage::indexing && !p.dwell_lock) return result;
    Constraint constraint{};
    if (stage == Stage::indexing) {
        constraint.slot_ray[u] = {p.radius * x - 2 * p.radius * q, 0, q};
        constraint.slot_ray[v] = {handed * p.radius * y, 0, q};
        constraint.per_input_radian = fraction(q - 2 * x, 5 * q - 4 * x);
    } else constraint.slot_ray = boundary(p, stage == Stage::incoming_dwell);
    const auto rate = fraction(input.rate.numerator * constraint.per_input_radian.numerator, input.rate.denominator * constraint.per_input_radian.denominator);
    if (const auto error = rate_error(rate)) return Refusal{Error::unsupported_result, *error};
    auto state = input.state;
    if (state == g::MotionState::rotating && !rate.numerator) state = g::MotionState::stopped;
    constraint.output = {state, rate};
    result.constraint = constraint;
    return result;
}

Inspection inspect(const Profile& p) {
    if (const auto error = raw(p)) return *error;
    if (const auto error = bounds(p)) return *error;
    const auto small = p.radius * p.radius, large = 3 * small;
    return Cycle{p, wheel(p), {boundary(p, true), boundary(p, false)}, small, large,
        p.slot_inner * p.slot_inner <= small && p.slot_outer * p.slot_outer >= large};
}
}  // namespace factory::geneva_drive
