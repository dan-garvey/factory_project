#include "factory/orbital_platform.hpp"

#include <algorithm>
#include <numeric>

namespace factory::orbital_platform {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
static_assert(g::maximum_coordinate <= 1000000 && g::maximum_dimension <= 4096 && scotch_yoke::maximum_direction_scale <= 256);
// Every validated obstacle/body coordinate difference is <=2e6; a two-axis
// squared distance is <=8e12. Profile offsets and rational pose numerators are
// separately bounded below 1.1e6 and 2.7e8, safely inside native int64.
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction fraction(Integer n, Integer d = 1) {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(n), static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
bool inside(Fraction v) { return v.numerator >= -g::maximum_coordinate * v.denominator && v.numerator <= g::maximum_coordinate * v.denominator; }
std::optional<Refusal> validate(const Profile& p) {
    if (!p.input_id || !p.output_id || !p.tray_id || p.input_id == p.output_id || p.input_id == p.tray_id || p.output_id == p.tray_id ||
        !std::all_of(p.origin.begin(), p.origin.end(), [](auto v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; }))
        return Refusal{Error::invalid_profile};
    if (static_cast<std::size_t>(p.shaft) >= 3 || static_cast<std::size_t>(p.span) >= 3 || p.shaft == p.span) return Refusal{Error::invalid_axes};
    for (auto v : {p.spacing, p.radius, p.half_width, p.half_thickness})
        if (v < 1 || v > g::maximum_dimension) return Refusal{Error::invalid_profile};
    return {};
}
Geometry geometry(const Profile& p) {
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span);
    auto remote = p.origin; remote[u] += p.spacing;
    c::Box box{p.origin, remote};
    for (std::size_t i = 0; i < 3; ++i) {
        const auto extent = i == a ? p.half_thickness : p.half_width;
        box.minimum[i] -= extent; box.maximum[i] += extent;
    }
    return {p, remote, box};
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_axes: return "invalid_axes";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::invalid_body: return "invalid_body";
        case Error::representation_limit: return "representation_limit";
        case Error::query_refused: return "query_refused";
    }
    return "unknown";
}

OrbitQuery orbit(const c::Box& reference, g::Axis shaft, Integer radius, std::span<const c::Obstacle> obstacles) {
    if (static_cast<std::size_t>(shaft) >= 3) return Refusal{Error::invalid_axes};
    if (radius < 1 || radius > g::maximum_dimension) return Refusal{Error::invalid_profile};
    const auto body = c::sweep(reference, {}, {});
    if (body.error != c::Error::none) return Refusal{Error::invalid_body, {}, body.error};
    const auto a = static_cast<std::size_t>(shaft), u = (a + 1) % 3, v = (a + 2) % 3;
    auto envelope = reference;
    for (const auto i : {u, v}) { envelope.minimum[i] -= radius; envelope.maximum[i] += radius; }
    if (c::sweep(envelope, {}, {}).error != c::Error::none) return Refusal{Error::representation_limit};
    // This query is validation only: overlap at the untranslated reference can
    // be irrelevant to a positive-radius circle. Never turn its hit into ours.
    const auto complete = c::sweep(reference, {}, obstacles);
    if (complete.error != c::Error::none) return Refusal{Error::query_refused, {}, complete.error};
    Orbit result{reference, shaft, radius, {}};
    for (const auto& obstacle : obstacles) {
        if (reference.maximum[a] <= obstacle.box.minimum[a] || reference.minimum[a] >= obstacle.box.maximum[a]) continue;
        Integer lower{}, upper{};
        for (const auto i : {u, v}) {
            const auto lo = obstacle.box.minimum[i] - reference.maximum[i], hi = obstacle.box.maximum[i] - reference.minimum[i];
            const auto near = std::max({Integer{0}, lo, -hi});
            const auto far = std::max(magnitude(lo), magnitude(hi));
            lower += near * near;
            upper += static_cast<Integer>(far * far);
        }
        if (lower < radius * radius && radius * radius < upper && (!result.contact || obstacle.id < result.contact->obstacle))
            result.contact = Contact{obstacle.id, lower, upper};
    }
    return result;
}

Reading sample(const Profile& p, Direction direction, g::Motion input) {
    if (const auto error = validate(p)) return *error;
    constexpr auto bound = scotch_yoke::maximum_direction_scale;
    const auto x = direction.cosine, y = direction.sine, q = direction.scale;
    if (x < -bound || x > bound || y < -bound || y > bound || q < 1 || q > bound ||
        x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1) return Refusal{Error::invalid_direction};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating && input.state != g::MotionState::stalled)
        return Refusal{Error::invalid_motion};
    const auto admitted = k::prepare(k::maximum_teeth, {}, input.rate, false);
    if (const auto* error = std::get_if<k::Error>(&admitted)) return Refusal{Error::invalid_rate, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    Sample result{geometry(p), direction, {}, {}, {}, {input, input}, y == 0};
    result.displacement[u] = fraction(p.radius * x, q);
    result.displacement[v] = fraction(handed * p.radius * y, q);
    result.per_radian[u] = fraction(-p.radius * y, q);
    result.per_radian[v] = fraction(handed * p.radius * x, q);
    for (std::size_t i = 0; i < 3; ++i) {
        const auto d = result.displacement[i];
        result.pins[0][i] = fraction(p.origin[i] * d.denominator + d.numerator, d.denominator);
        result.pins[1][i] = fraction(result.geometry.remote_axis[i] * d.denominator + d.numerator, d.denominator);
        if (!inside(fraction(result.geometry.remote_axis[i])) ||
            !inside(fraction(result.geometry.reference.minimum[i] * d.denominator + d.numerator, d.denominator)) ||
            !inside(fraction(result.geometry.reference.maximum[i] * d.denominator + d.numerator, d.denominator)))
            return Refusal{Error::representation_limit};
    }
    return result;
}

Inspection inspect(const Profile& p, std::span<const c::Obstacle> obstacles) {
    if (const auto error = validate(p)) return *error;
    const auto body = geometry(p);
    const auto result = orbit(body.reference, p.shaft, p.radius, obstacles);
    if (const auto* error = std::get_if<Refusal>(&result)) return *error;
    return Setup{body, std::get<Orbit>(result)};
}
}  // namespace factory::orbital_platform
