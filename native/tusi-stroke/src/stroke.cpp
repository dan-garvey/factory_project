#include "factory/tusi_stroke.hpp"

#include <algorithm>
#include <numeric>

namespace factory::tusi_stroke {
namespace g = mechanics;
namespace k = geared_cycle;
namespace s = slider_crank;
namespace {
constexpr Integer scale = scotch_yoke::maximum_direction_scale;
static_assert(scale == 256 && maximum_radius * 2 <= g::maximum_dimension && g::maximum_coordinate <= 1000000);
// Primitive raw directions validate before products. Phase/clocking denominator
// product <=65536; sample numerators <6.7e10; extrema roots <=(4096*256)^2.
bool grid(Integer v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; }
bool valid(Direction d) {
    return d.cosine >= -scale && d.cosine <= scale && d.sine >= -scale && d.sine <= scale &&
        d.scale >= 1 && d.scale <= scale && d.cosine * d.cosine + d.sine * d.sine == d.scale * d.scale &&
        std::gcd(std::gcd(d.cosine, d.sine), d.scale) == 1;
}
Fraction fraction(Integer n, Integer d = 1) {
    const auto bits = static_cast<std::uint64_t>(n), magnitude = n < 0 ? std::uint64_t{0} - bits : bits;
    const auto divisor = static_cast<Integer>(std::gcd(magnitude, static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
std::optional<Refusal> validate(const Profile& p) {
    const std::array<std::uint32_t, 4> ids{p.ring_id, p.carrier_id, p.planet_id, p.pin_id};
    for (std::size_t i = 0; i < ids.size(); ++i) {
        if (!ids[i]) return Refusal{Error::invalid_profile};
        for (std::size_t j = i + 1; j < ids.size(); ++j) if (ids[i] == ids[j]) return Refusal{Error::invalid_profile};
    }
    if (!std::all_of(p.origin.begin(), p.origin.end(), grid) || !std::all_of(p.lower.begin(), p.lower.end(), grid) ||
        !std::all_of(p.upper.begin(), p.upper.end(), grid) || p.radius < 1 || p.radius > maximum_radius) return Refusal{Error::invalid_profile};
    for (std::size_t i = 0; i < 3; ++i) if (p.lower[i] > p.upper[i]) return Refusal{Error::invalid_profile};
    if (static_cast<std::size_t>(p.shaft) >= 3 || static_cast<std::size_t>(p.span) >= 3 || p.shaft == p.span) return Refusal{Error::invalid_axes};
    if (!valid(p.clocking)) return Refusal{Error::invalid_clocking};
    const auto u = static_cast<std::size_t>(p.span), a = static_cast<std::size_t>(p.shaft), v = 3 - u - a;
    for (const auto i : {u, v}) if (!grid(p.origin[i] - 2 * p.radius) || !grid(p.origin[i] + 2 * p.radius)) return Refusal{Error::representation_limit};
    return {};
}
bool inside(Fraction f, Integer lo, Integer hi) { return f.numerator >= lo * f.denominator && f.numerator <= hi * f.denominator; }
bool inside(const Coordinate& c, Integer lo, Integer hi) {
    return std::get<s::Order>(s::compare_to_grid(c, lo)) != s::Order::less && std::get<s::Order>(s::compare_to_grid(c, hi)) != s::Order::greater;
}
}  // namespace

const char* error_name(Error e) noexcept {
    switch (e) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_axes: return "invalid_axes";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_clocking: return "invalid_clocking";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::unconstrained_ring: return "unconstrained_ring";
        case Error::representation_limit: return "representation_limit";
    }
    return "unknown";
}
Reading sample(const Profile& p, Direction d, g::Motion input) {
    if (const auto error = validate(p)) return *error;
    if (!valid(d)) return Refusal{Error::invalid_direction};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating &&
        input.state != g::MotionState::stalled) return Refusal{Error::invalid_motion};
    const auto admitted = k::prepare(k::maximum_teeth, {}, input.rate, false);
    if (const auto* error = std::get_if<k::Error>(&admitted)) return Refusal{Error::invalid_rate, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    if (!p.ring_locked) return Refusal{Error::unconstrained_ring};
    const auto u = static_cast<std::size_t>(p.span), a = static_cast<std::size_t>(p.shaft), v = 3 - u - a;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    const auto x = d.cosine, y = d.sine, q = d.scale, c = p.clocking.cosine, z = p.clocking.sine, h = p.clocking.scale, den = q * h;
    Sample result{p, d, input, {input.state, {-input.rate.numerator, input.rate.denominator}}, {}, {}, {}, {}, true};
    for (std::size_t i = 0; i < 3; ++i) {
        result.center[i] = result.contact[i] = result.pin[i] = fraction(p.origin[i]); result.pin_per_input_radian[i] = {};
    }
    result.center[u] = fraction(p.origin[u] * q + p.radius * x, q);
    result.center[v] = fraction(p.origin[v] * q + handed * p.radius * y, q);
    result.contact[u] = fraction(p.origin[u] * q + 2 * p.radius * x, q);
    result.contact[v] = fraction(p.origin[v] * q + handed * 2 * p.radius * y, q);
    result.pin[u] = fraction(p.origin[u] * den + p.radius * ((h + c) * x + z * y), den);
    result.pin[v] = fraction(p.origin[v] * den + handed * p.radius * (z * x + (h - c) * y), den);
    result.pin_per_input_radian[u] = fraction(p.radius * (-(h + c) * y + z * x), den);
    result.pin_per_input_radian[v] = fraction(handed * p.radius * (-z * y + (h - c) * x), den);
    for (std::size_t i = 0; i < 3; ++i) result.guide_fits = result.guide_fits && inside(result.pin[i], p.lower[i], p.upper[i]);
    return result;
}
Inspection inspect(const Profile& p) {
    if (const auto error = validate(p)) return *error;
    if (!p.ring_locked) return Refusal{Error::unconstrained_ring};
    const auto u = static_cast<std::size_t>(p.span), a = static_cast<std::size_t>(p.shaft), v = 3 - u - a;
    const auto c = p.clocking.cosine, h = p.clocking.scale;
    Cycle result{p, {}, true};
    for (std::size_t i = 0; i < 3; ++i) result.bounds[i] = {Coordinate{p.origin[i], 0, 1, s::Branch::negative}, Coordinate{p.origin[i], 0, 1, s::Branch::positive}};
    for (const auto i : {u, v}) {
        const auto radical = 2 * p.radius * p.radius * h * (h + (i == u ? c : -c));
        result.bounds[i] = {Coordinate{p.origin[i] * h, radical, h, s::Branch::negative}, Coordinate{p.origin[i] * h, radical, h, s::Branch::positive}};
    }
    for (std::size_t i = 0; i < 3; ++i) for (const auto& endpoint : result.bounds[i])
        result.guide_fits = result.guide_fits && inside(endpoint, p.lower[i], p.upper[i]);
    return result;
}
}  // namespace factory::tusi_stroke
