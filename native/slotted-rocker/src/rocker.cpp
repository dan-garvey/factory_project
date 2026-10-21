#include "factory/slotted_rocker.hpp"

#include <algorithm>
#include <numeric>

namespace factory::slotted_rocker {
namespace g = mechanics;
namespace k = geared_cycle;
namespace s = slider_crank;
namespace {
constexpr Integer scale = scotch_yoke::maximum_direction_scale;
static_assert(maximum_radius * 3 <= g::maximum_dimension && scale <= 256 && g::maximum_coordinate <= 1000000);
// Raw guards precede products. Radial numerator <4.4e9; admitted native rate
// numerator <=256e6, geometric ratio numerator <=768 and denominator <=2304.
// Infer only after normalization; all intermediate products fit signed int64.
Fraction fraction(Integer n, Integer d = 1) {
    const auto bits = static_cast<std::uint64_t>(n), magnitude = n < 0 ? std::uint64_t{0} - bits : bits;
    const auto divisor = static_cast<Integer>(std::gcd(magnitude, static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
bool grid(Integer v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; }
std::optional<k::Error> rate_error(Fraction f) {
    const auto r = k::prepare(k::maximum_teeth, {}, f, false);
    if (const auto* e = std::get_if<k::Error>(&r)) return *e;
    return {};
}
std::optional<Refusal> validate(const Profile& p) {
    if (!p.crank_id || !p.lever_id || p.crank_id == p.lever_id || !std::all_of(p.origin.begin(), p.origin.end(), grid) ||
        p.radius < 1 || p.radius > maximum_radius || p.slot_inner < 1 || p.slot_outer > g::maximum_dimension || p.slot_inner >= p.slot_outer)
        return Refusal{Error::invalid_profile};
    if (static_cast<std::size_t>(p.shaft) >= 3 || static_cast<std::size_t>(p.span) >= 3 || p.shaft == p.span) return Refusal{Error::invalid_axes};
    return {};
}
g::Point pivot(const Profile& p) { auto r = p.origin; r[static_cast<std::size_t>(p.span)] += 2 * p.radius; return r; }
std::optional<Refusal> bounds(const Profile& p) {
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u; const auto at = pivot(p);
    for (const auto i : {u, v}) if (!grid(p.origin[i] - p.radius) || !grid(p.origin[i] + p.radius) ||
        !grid(at[i] - p.slot_outer) || !grid(at[i] + p.slot_outer)) return Refusal{Error::representation_limit};
    return {};
}
Reversal reversal(const Profile& p, int sense) {
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    Reversal r{};
    r.pin_from_crank[u] = {p.radius, 0, 2};
    r.lever_from_pivot[u] = {-3 * p.radius, 0, 2};
    r.pin_from_crank[v] = r.lever_from_pivot[v] = {0, 3 * p.radius * p.radius, 2,
        handed * sense > 0 ? s::Branch::positive : s::Branch::negative};
    return r;
}
}  // namespace

const char* error_name(Error e) noexcept {
    switch (e) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_axes: return "invalid_axes";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::representation_limit: return "representation_limit";
        case Error::unsupported_result: return "unsupported_result";
    }
    return "unknown";
}
Reading sample(const Profile& p, Direction d, g::Motion input) {
    if (const auto error = validate(p)) return *error;
    const auto x = d.cosine, y = d.sine, q = d.scale;
    if (x < -scale || x > scale || y < -scale || y > scale || q < 1 || q > scale || x * x + y * y != q * q ||
        std::gcd(std::gcd(x, y), q) != 1) return Refusal{Error::invalid_direction};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating &&
        input.state != g::MotionState::stalled) return Refusal{Error::invalid_motion};
    if (const auto error = rate_error(input.rate)) return Refusal{Error::invalid_rate, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    if (const auto error = bounds(p)) return *error;
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1, radial = p.radius * p.radius * (5 * q - 4 * x);
    const bool fits = p.slot_inner * p.slot_inner * q <= radial && radial <= p.slot_outer * p.slot_outer * q;
    Sample result{p, d, input, pivot(p), {}, {}, fraction(radial, q), 2 * x > q ? Stroke::short_arc : Stroke::long_arc, fits, {}};
    for (std::size_t i = 0; i < 3; ++i) { result.pin[i] = fraction(p.origin[i]); result.lever_ray[i] = {}; }
    result.pin[u] = fraction(p.origin[u] * q + p.radius * x, q);
    result.pin[v] = fraction(p.origin[v] * q + handed * p.radius * y, q);
    result.lever_ray[u] = fraction(p.radius * x - 2 * p.radius * q, q);
    result.lever_ray[v] = fraction(handed * p.radius * y, q);
    if (!fits) return result;
    const auto ratio = fraction(q - 2 * x, 5 * q - 4 * x);
    const auto rate = fraction(input.rate.numerator * ratio.numerator, input.rate.denominator * ratio.denominator);
    if (const auto error = rate_error(rate)) return Refusal{Error::unsupported_result, *error};
    auto state = input.state; if (state == g::MotionState::rotating && !rate.numerator) state = g::MotionState::stopped;
    result.constraint = Constraint{ratio, {state, rate}};
    return result;
}
Inspection inspect(const Profile& p) {
    if (const auto error = validate(p)) return *error;
    if (const auto error = bounds(p)) return *error;
    return Cycle{p, pivot(p), p.radius, 3 * p.radius, p.slot_inner <= p.radius && p.slot_outer >= 3 * p.radius,
        {reversal(p, -1), reversal(p, 1)}};
}
}  // namespace factory::slotted_rocker
