#include "factory/four_bar.hpp"

#include <algorithm>
#include <numeric>

namespace factory::four_bar {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
constexpr Integer dimension = 2 * maximum_length;
constexpr Integer distance_bound = dimension * dimension * maximum_scale * maximum_scale;
constexpr Integer denominator_bound = 2 * maximum_scale * distance_bound;
constexpr Integer root_bound = 2 * maximum_length * maximum_scale * dimension * maximum_scale;
constexpr Integer radicand_bound = root_bound * root_bound;
constexpr Integer base_bound = (g::maximum_coordinate + dimension) * denominator_bound;
constexpr Integer coefficient_bound = dimension * maximum_scale;
static_assert(maximum_scale == 256 && g::maximum_coordinate <= 1000000);
// After raw guards: squared distance <=2^30, radical <=2^60, denominator
// <=2^39, base <2^60 and derivative numerator <2^59. All geometry arithmetic
// below is signed int64. Comparison alone needs a portable unsigned 128-bit
// product; its two limbs never perform overflowing signed arithmetic.
std::uint64_t magnitude(Integer v) {
    const auto bits = static_cast<std::uint64_t>(v);
    return v < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction fraction(Integer n, Integer d = 1) {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(n), static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
using Product = std::array<std::uint64_t, 2>;  // Most significant limb first.
Product product(std::uint64_t a, std::uint64_t b) {
    constexpr auto mask = std::uint64_t{0xffffffff};
    const auto a0 = a & mask, a1 = a >> 32, b0 = b & mask, b1 = b >> 32;
    auto t = a0 * b0;
    const auto w0 = t & mask;
    t = a1 * b0 + (t >> 32);
    const auto w1 = t & mask, w2 = t >> 32;
    t = a0 * b1 + w1;
    return {a1 * b1 + w2 + (t >> 32), (t << 32) + w0};
}
bool grid(Integer v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; }
bool branch(Branch b) { return b == Branch::positive || b == Branch::negative; }
bool valid(const Coordinate& c) {
    return c.base >= -base_bound && c.base <= base_bound && c.coefficient >= -coefficient_bound &&
        c.coefficient <= coefficient_bound && c.radicand >= 0 && c.radicand <= radicand_bound &&
        c.denominator >= 1 && c.denominator <= denominator_bound;
}
slider_crank::Order order(const Product& a, const Product& b) {
    return a < b ? slider_crank::Order::less : a > b ? slider_crank::Order::greater : slider_crank::Order::equal;
}
slider_crank::Order compare(const Coordinate& c, Integer target) {
    const auto delta = target * c.denominator - c.base;
    if (!c.coefficient || !c.radicand)
        return delta > 0 ? slider_crank::Order::less : delta < 0 ? slider_crank::Order::greater : slider_crank::Order::equal;
    if (c.coefficient > 0 && delta < 0) return slider_crank::Order::greater;
    if (c.coefficient < 0 && delta > 0) return slider_crank::Order::less;
    const auto coefficient = magnitude(c.coefficient), d = magnitude(delta);
    const auto lhs = product(coefficient * coefficient, static_cast<std::uint64_t>(c.radicand)), rhs = product(d, d);
    return c.coefficient > 0 ? order(lhs, rhs) : order(rhs, lhs);
}
bool inside(const Coordinate& c) {
    return compare(c, -g::maximum_coordinate) != slider_crank::Order::less &&
        compare(c, g::maximum_coordinate) != slider_crank::Order::greater;
}
std::optional<Refusal> validate(const Profile& p) {
    if (!p.crank_id || !p.coupler_id || !p.rocker_id || p.crank_id == p.coupler_id || p.crank_id == p.rocker_id ||
        p.coupler_id == p.rocker_id || !branch(p.branch) || !std::all_of(p.origin.begin(), p.origin.end(), grid) ||
        p.ground < 1 || p.ground > maximum_length || p.crank < 1 || p.crank > maximum_length ||
        p.coupler < 1 || p.coupler > maximum_length || p.rocker < 1 || p.rocker > maximum_length) return Refusal{Error::invalid_profile};
    if (static_cast<std::size_t>(p.shaft) >= 3 || static_cast<std::size_t>(p.span) >= 3 || p.shaft == p.span) return Refusal{Error::invalid_axes};
    if (!grid(p.origin[static_cast<std::size_t>(p.span)] + p.ground)) return Refusal{Error::representation_limit};
    return {};
}
}  // namespace

Comparison compare_to_grid(const Coordinate& c, Integer target) {
    if (!valid(c)) return Error::invalid_coordinate;
    if (!grid(target)) return Error::invalid_grid;
    return compare(c, target);
}
RationalView rational_view(const Coordinate& c) {
    if (!valid(c)) return Error::invalid_coordinate;
    if (!c.coefficient || !c.radicand) return std::optional<Fraction>{fraction(c.base, c.denominator)};
    Integer lo{}, hi = root_bound;
    while (lo <= hi) {
        const auto mid = lo + (hi - lo) / 2, square = mid * mid;
        if (square == c.radicand) return std::optional<Fraction>{fraction(c.base + c.coefficient * mid, c.denominator)};
        if (square < c.radicand) lo = mid + 1; else hi = mid - 1;
    }
    return std::optional<Fraction>{};
}
const char* error_name(Error e) noexcept {
    switch (e) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_axes: return "invalid_axes";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::invalid_coordinate: return "invalid_coordinate";
        case Error::invalid_grid: return "invalid_grid";
        case Error::unreachable: return "unreachable";
        case Error::underconstrained: return "underconstrained";
        case Error::representation_limit: return "representation_limit";
    }
    return "unknown";
}
Reading sample(const Profile& p, Direction d, g::Motion input) {
    if (const auto error = validate(p)) return *error;
    const auto x = d.cosine, y = d.sine, q = d.scale;
    if (x < -maximum_scale || x > maximum_scale || y < -maximum_scale || y > maximum_scale || q < 1 || q > maximum_scale ||
        x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1) return Refusal{Error::invalid_direction};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating &&
        input.state != g::MotionState::stalled) return Refusal{Error::invalid_motion};
    const auto admitted = k::prepare(k::maximum_teeth, {}, input.rate, false);
    if (const auto* error = std::get_if<k::Error>(&admitted)) return Refusal{Error::invalid_rate, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    const auto u = static_cast<std::size_t>(p.span), a = static_cast<std::size_t>(p.shaft), v = 3 - u - a;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1, sign = p.branch == Branch::positive ? 1 : -1;
    const auto wx = p.ground * q - p.crank * x, wy = -p.crank * y, s = wx * wx + wy * wy;
    if (!s) return Refusal{p.coupler == p.rocker ? Error::underconstrained : Error::unreachable};
    const auto q2 = q * q, h = (p.coupler * p.coupler - p.rocker * p.rocker) * q2 + s;
    const auto radical = 4 * p.coupler * p.coupler * q2 * s - h * h;
    if (radical < 0) return Refusal{Error::unreachable};
    const auto den = 2 * q * s;
    Sample result{p, d, input, {}, p.origin, {}, radical == 0, {}};
    result.anchor[u] += p.ground;
    for (std::size_t i = 0; i < 3; ++i) {
        result.pin[i] = fraction(p.origin[i]); result.joint[i] = {p.origin[i], 0, 0, 1};
    }
    result.pin[u] = fraction(p.origin[u] * q + p.crank * x, q);
    result.pin[v] = fraction(p.origin[v] * q + handed * p.crank * y, q);
    result.joint[u] = {p.origin[u] * den + 2 * s * p.crank * x + h * wx, -sign * wy, radical, den};
    result.joint[v] = {p.origin[v] * den + handed * (2 * s * p.crank * y + h * wy), handed * sign * wx, radical, den};
    for (std::size_t i = 0; i < 3; ++i) {
        if (!valid(result.joint[i]) || !inside(result.joint[i]) || result.pin[i].numerator < -g::maximum_coordinate * result.pin[i].denominator ||
            result.pin[i].numerator > g::maximum_coordinate * result.pin[i].denominator) return Refusal{Error::representation_limit};
    }
    if (radical) result.per_input_radian = Derivative{
        fraction(p.crank * p.crank * q2 - p.ground * p.crank * x * q, s),
        fraction(sign * h * p.ground * p.crank * y * q, s), radical};
    return result;
}
Inspection inspect(const Profile& p) {
    if (const auto error = validate(p)) return *error;
    const auto near = p.ground > p.crank ? p.ground - p.crank : p.crank - p.ground;
    const auto inner = p.coupler > p.rocker ? p.coupler - p.rocker : p.rocker - p.coupler;
    const auto far = p.ground + p.crank, outer = p.coupler + p.rocker;
    const bool closed = near >= inner && far <= outer;
    const auto u = static_cast<std::size_t>(p.span), a = static_cast<std::size_t>(p.shaft), v = 3 - u - a;
    const auto reach = p.crank + p.coupler;
    bool envelope = true;
    for (const auto i : {u, v}) envelope = envelope && grid(p.origin[i] - reach) && grid(p.origin[i] + reach);
    return Cycle{p, near, far, closed, closed && near > inner && far < outer && near > 0, envelope};
}
}  // namespace factory::four_bar
