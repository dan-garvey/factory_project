#include "factory/crank_clamp.hpp"

#include <algorithm>
#include <numeric>

namespace factory::crank_clamp {
namespace g = mechanics;
namespace s = slider_crank;
namespace k = geared_cycle;
namespace {
static_assert(g::maximum_coordinate <= 1000000 && maximum_arm <= g::maximum_dimension / 2);
static_assert(scotch_yoke::maximum_direction_scale > 0 && scotch_yoke::maximum_direction_scale <= 256);
// Raw guards precede products. 4*K <= (4096*q)^2 fits the parent's coordinate
// representation. Gap numerators are <=2.1e6; centre numerators are <5.2e8.
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction fraction(Integer n, Integer d = 1) {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(n), static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
bool grid(Integer v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; }
std::optional<Refusal> validate(const Profile& p) {
    auto ids = p.ids;
    std::sort(ids.begin(), ids.end());
    if (!ids[0] || std::adjacent_find(ids.begin(), ids.end()) != ids.end() ||
        !std::all_of(p.origin.begin(), p.origin.end(), grid) || p.spacing < 1 || p.spacing > g::maximum_dimension ||
        p.radius < 1 || p.radius > maximum_arm || p.rod_length < 1 || p.rod_length > maximum_arm ||
        (p.clocking != Clocking::opposed && p.clocking != Clocking::same_reference)) return Refusal{Error::invalid_profile};
    if (static_cast<std::size_t>(p.shaft) >= 3 || static_cast<std::size_t>(p.travel) >= 3 || p.shaft == p.travel) return Refusal{Error::invalid_axes};
    if (!grid(p.origin[static_cast<std::size_t>(p.travel)] + p.spacing)) return Refusal{Error::representation_limit};
    return {};
}
s::Profile parent(const Profile& p, std::size_t side) {
    s::Profile result;
    result.crank_id = p.ids[side * 2]; result.slider_id = p.ids[side * 2 + 1];
    result.origin = p.origin;
    if (side) result.origin[static_cast<std::size_t>(p.travel)] += p.spacing;
    result.shaft = p.shaft; result.travel = p.travel; result.radius = p.radius; result.rod_length = p.rod_length;
    result.lower = -g::maximum_coordinate; result.upper = g::maximum_coordinate;
    result.branch = side ? s::Branch::negative : s::Branch::positive;
    return result;
}
std::optional<Refusal> motion(g::Motion& input, std::uint32_t id) {
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating && input.state != g::MotionState::stalled)
        return Refusal{Error::invalid_motion, id};
    const auto checked = k::prepare(k::maximum_teeth, {}, input.rate, false);
    if (const auto* error = std::get_if<k::Error>(&checked)) return Refusal{Error::invalid_rate, id, {}, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion, id};
    return {};
}
Centre certificate(const Profile& p) {
    Centre result{};
    for (std::size_t i = 0; i < 3; ++i) result.reference[i] = fraction(p.origin[i]);
    const auto u = static_cast<std::size_t>(p.travel);
    result.reference[u] = fraction(2 * p.origin[u] + p.spacing, 2);
    result.cosine_coefficient = p.clocking == Clocking::opposed ? 0 : p.radius;
    return result;
}
bool representable(const Coordinate& c) { return std::holds_alternative<s::Order>(s::compare_to_grid(c, 0)); }
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_axes: return "invalid_axes";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::drive_mismatch: return "drive_mismatch";
        case Error::parent_refused: return "parent_refused";
        case Error::representation_limit: return "representation_limit";
    }
    return "unknown";
}

Reading sample(const Profile& p, Direction direction, std::array<g::Motion, 2> sources) {
    if (const auto error = validate(p)) return *error;
    constexpr auto bound = scotch_yoke::maximum_direction_scale;
    const auto x = direction.cosine, y = direction.sine, q = direction.scale;
    if (x < -bound || x > bound || y < -bound || y > bound || q < 1 || q > bound ||
        x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1) return Refusal{Error::invalid_direction};
    // Both sources validate BEFORE a mechanically unreachable parent can return.
    for (std::size_t i = 0; i < 2; ++i) if (const auto error = motion(sources[i], p.ids[i * 2])) return *error;
    const bool powered = sources[0].state == g::MotionState::rotating && sources[1].state == g::MotionState::rotating;
    if (powered && (sources[0].rate.denominator != sources[1].rate.denominator || sources[0].rate.numerator != -sources[1].rate.numerator))
        return Refusal{Error::drive_mismatch};
    const Direction right = p.clocking == Clocking::opposed ? Direction{-x, y, q} : Direction{x, -y, q};
    const auto left_reading = s::sample(parent(p, 0), direction, sources[0]), right_reading = s::sample(parent(p, 1), right, sources[1]);
    if (const auto* error = std::get_if<s::Refusal>(&left_reading)) return Refusal{Error::parent_refused, p.ids[0], error->reason, error->rate_error};
    if (const auto* error = std::get_if<s::Refusal>(&right_reading)) return Refusal{Error::parent_refused, p.ids[2], error->reason, error->rate_error};
    const auto& left = std::get<s::Sample>(left_reading);
    const auto& other = std::get<s::Sample>(right_reading);
    const auto d = p.radius * y, lq = p.rod_length * q, radical = lq * lq - d * d;
    const Coordinate gap{p.spacing * q - (p.clocking == Clocking::opposed ? 2 * p.radius * x : 0), 4 * radical, q, s::Branch::negative};
    if (!representable(gap)) return Refusal{Error::representation_limit};
    const auto centre = certificate(p);
    auto at = centre.reference;
    const auto u = static_cast<std::size_t>(p.travel);
    at[u] = fraction((2 * p.origin[u] + p.spacing) * q + 2 * centre.cosine_coefficient * x, 2 * q);
    return Sample{p, direction, {left, other}, at, gap, powered};
}

Inspection inspect(const Profile& p) {
    if (const auto error = validate(p)) return *error;
    const auto left = s::inspect(parent(p, 0)), right = s::inspect(parent(p, 1));
    if (const auto* error = std::get_if<s::Refusal>(&left)) return Refusal{Error::parent_refused, p.ids[0], error->reason, error->rate_error};
    if (const auto* error = std::get_if<s::Refusal>(&right)) return Refusal{Error::parent_refused, p.ids[2], error->reason, error->rate_error};
    Cycle result{p, {std::get<s::Cycle>(left), std::get<s::Cycle>(right)}, certificate(p), {}};
    if (!result.closed()) return result;
    if (p.clocking == Clocking::opposed) {
        result.gap_extrema = std::array{Coordinate{p.spacing - 2 * (p.rod_length + p.radius), 0, 1},
                                      Coordinate{p.spacing - 2 * (p.rod_length - p.radius), 0, 1}};
    } else {
        result.gap_extrema = std::array{Coordinate{p.spacing - 2 * p.rod_length, 0, 1},
                                      Coordinate{p.spacing, 4 * (p.rod_length * p.rod_length - p.radius * p.radius), 1, s::Branch::negative}};
    }
    for (const auto& c : *result.gap_extrema) if (!representable(c)) return Refusal{Error::representation_limit};
    return result;
}
}  // namespace factory::crank_clamp
