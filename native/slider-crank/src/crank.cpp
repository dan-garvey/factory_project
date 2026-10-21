#include "factory/slider_crank.hpp"

#include <algorithm>
#include <limits>
#include <numeric>

namespace factory::slider_crank {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
constexpr Integer scale_bound = scotch_yoke::maximum_direction_scale;
constexpr Integer root_bound = g::maximum_dimension * scale_bound;
constexpr Integer radicand_bound = root_bound * root_bound;
constexpr Integer base_bound = (g::maximum_coordinate + 2 * g::maximum_dimension) * scale_bound;
constexpr Integer comparison_bound = g::maximum_coordinate * scale_bound + base_bound;
static_assert(g::maximum_coordinate <= 1000000 && g::maximum_dimension <= 4096 && scale_bound > 0 && scale_bound <= 256);
static_assert(comparison_bound <= std::numeric_limits<Integer>::max() / comparison_bound);
// Raw guards precede every product. A grid comparison square is <=2.65e17;
// derivative numerators are <=2.2e12. Never multiply by the native crank rate.
std::uint64_t magnitude(Integer value) noexcept {
    const auto bits = static_cast<std::uint64_t>(value);
    return value < 0 ? std::uint64_t{0} - bits : bits;
}
Fraction fraction(Integer n, Integer d = 1) {
    const auto divisor = static_cast<Integer>(std::gcd(magnitude(n), static_cast<std::uint64_t>(d)));
    return {n / divisor, d / divisor};
}
bool branch(Branch b) { return b == Branch::positive || b == Branch::negative; }
bool grid(Integer v) { return v >= -g::maximum_coordinate && v <= g::maximum_coordinate; }
bool valid(const Coordinate& c) {
    return c.base >= -base_bound && c.base <= base_bound && c.radicand >= 0 && c.radicand <= radicand_bound &&
        c.denominator >= 1 && c.denominator <= scale_bound && branch(c.branch);
}
Order order(Integer a, Integer b) { return a < b ? Order::less : a > b ? Order::greater : Order::equal; }
Order compare(const Coordinate& c, Integer target) {
    const auto d = target * c.denominator - c.base;
    if (c.branch == Branch::positive) return d < 0 ? Order::greater : order(c.radicand, d * d);
    return d > 0 ? Order::less : order(d * d, c.radicand);
}
bool inside(const Coordinate& c, Integer lo, Integer hi) { return compare(c, lo) != Order::less && compare(c, hi) != Order::greater; }
std::optional<Integer> exact_root(Integer squared) {
    Integer low{}, high = root_bound;
    while (low <= high) {
        const auto middle = low + (high - low) / 2, value = middle * middle;
        if (value == squared) return middle;
        if (value < squared) low = middle + 1; else high = middle - 1;
    }
    return {};
}
std::optional<Refusal> validate(const Profile& p) {
    if (!p.crank_id || !p.slider_id || p.crank_id == p.slider_id || !branch(p.branch) ||
        !std::all_of(p.origin.begin(), p.origin.end(), grid) || !grid(p.lower) || !grid(p.upper) || p.lower >= p.upper ||
        p.radius < 1 || p.radius > g::maximum_dimension || p.rod_length < 1 || p.rod_length > g::maximum_dimension ||
        p.guide_offset < -g::maximum_dimension || p.guide_offset > g::maximum_dimension) return Refusal{Error::invalid_profile};
    if (static_cast<std::size_t>(p.shaft) >= 3 || static_cast<std::size_t>(p.travel) >= 3 || p.shaft == p.travel) return Refusal{Error::invalid_axes};
    return {};
}
g::Point guide(const Profile& p) {
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.travel), v = 3 - a - u;
    auto point = p.origin;
    point[v] += ((a + 1) % 3 == u ? 1 : -1) * p.guide_offset;
    return point;
}
}  // namespace

Comparison compare_to_grid(const Coordinate& c, Integer target) {
    if (!valid(c)) return Error::invalid_coordinate;
    if (!grid(target)) return Error::invalid_grid;
    return compare(c, target);
}
RationalView rational_view(const Coordinate& c) {
    if (!valid(c)) return Error::invalid_coordinate;
    const auto root = exact_root(c.radicand);
    if (!root) return std::optional<Fraction>{};
    return std::optional<Fraction>{fraction(c.base + (c.branch == Branch::positive ? *root : -*root), c.denominator)};
}
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_axes: return "invalid_axes";
        case Error::invalid_direction: return "invalid_direction";
        case Error::invalid_motion: return "invalid_motion";
        case Error::invalid_rate: return "invalid_rate";
        case Error::invalid_coordinate: return "invalid_coordinate";
        case Error::invalid_grid: return "invalid_grid";
        case Error::unreachable: return "unreachable";
        case Error::representation_limit: return "representation_limit";
    }
    return "unknown";
}

Reading sample(const Profile& p, Direction direction, g::Motion input) {
    if (const auto error = validate(p)) return *error;
    const auto x = direction.cosine, y = direction.sine, q = direction.scale;
    if (x < -scale_bound || x > scale_bound || y < -scale_bound || y > scale_bound || q < 1 || q > scale_bound ||
        x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1) return Refusal{Error::invalid_direction};
    if (input.state != g::MotionState::unpowered && input.state != g::MotionState::stopped && input.state != g::MotionState::rotating && input.state != g::MotionState::stalled)
        return Refusal{Error::invalid_motion};
    const auto admitted = k::prepare(k::maximum_teeth, {}, input.rate, false);
    if (const auto* error = std::get_if<k::Error>(&admitted)) return Refusal{Error::invalid_rate, *error};
    input.rate = fraction(input.rate.numerator, input.rate.denominator);
    if ((input.state == g::MotionState::rotating) != (input.rate.numerator != 0)) return Refusal{Error::invalid_motion};
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.travel), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    const auto d = p.guide_offset * q - p.radius * y, lq = p.rod_length * q, radicand = lq * lq - d * d;
    if (radicand < 0) return Refusal{Error::unreachable};
    Sample result{p, direction, input, {}, guide(p), {p.origin[u] * q + p.radius * x, radicand, q, p.branch}, {}, false};
    for (std::size_t i = 0; i < 3; ++i) result.pin[i] = fraction(p.origin[i]);
    result.pin[u] = fraction(p.origin[u] * q + p.radius * x, q);
    result.pin[v] = fraction(p.origin[v] * q + handed * p.radius * y, q);
    for (std::size_t i = 0; i < 3; ++i)
        if (!grid(result.guide_anchor[i]) || result.pin[i].numerator < -g::maximum_coordinate * result.pin[i].denominator ||
            result.pin[i].numerator > g::maximum_coordinate * result.pin[i].denominator) return Refusal{Error::representation_limit};
    if (!inside(result.slider, -g::maximum_coordinate, g::maximum_coordinate)) return Refusal{Error::representation_limit};
    result.guide_fits = inside(result.slider, p.lower, p.upper);
    if (radicand) result.per_radian = Derivative{fraction(-p.radius * y, q), fraction((p.branch == Branch::positive ? 1 : -1) * d * p.radius * x, q), radicand};
    return result;
}

Inspection inspect(const Profile& p) {
    if (const auto error = validate(p)) return *error;
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.travel), v = 3 - a - u;
    const auto anchor = guide(p);
    if (!std::all_of(anchor.begin(), anchor.end(), grid)) return Refusal{Error::representation_limit};
    for (const auto i : {u, v}) if (!grid(p.origin[i] - p.radius) || !grid(p.origin[i] + p.radius)) return Refusal{Error::representation_limit};
    const auto reach = p.radius + static_cast<Integer>(magnitude(p.guide_offset));
    Cycle result{p, p.rod_length * p.rod_length - reach * reach, {}, false};
    if (!result.closed()) return result;
    const auto short_arm = p.rod_length - p.radius, long_arm = p.rod_length + p.radius;
    Coordinate near{p.origin[u], short_arm * short_arm - p.guide_offset * p.guide_offset, 1, p.branch};
    Coordinate far{p.origin[u], long_arm * long_arm - p.guide_offset * p.guide_offset, 1, p.branch};
    result.extrema = p.branch == Branch::positive ? std::array{near, far} : std::array{far, near};
    if (!inside((*result.extrema)[0], -g::maximum_coordinate, g::maximum_coordinate) ||
        !inside((*result.extrema)[1], -g::maximum_coordinate, g::maximum_coordinate)) return Refusal{Error::representation_limit};
    result.guide_fits = inside((*result.extrema)[0], p.lower, p.upper) && inside((*result.extrema)[1], p.lower, p.upper);
    return result;
}
}  // namespace factory::slider_crank
