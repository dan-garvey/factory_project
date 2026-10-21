#include "factory/four_bar.hpp"
#include "factory/four_bar_workbench.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace n = factory::four_bar;
namespace g = factory::mechanics;
namespace s = factory::slider_crank;
using I = n::Integer;
using F = n::Fraction;
// Test-only compiler integer, independent of production's portable limb product.
__extension__ using Wide = __int128;
std::size_t checks{}, profiles{}, observations{}, unreachable{}, comparisons{}, traces{};
void require(bool pass, const char* reason) {
    ++checks;
    if (!pass) { std::cerr << "FAIL " << reason << '\n'; std::exit(1); }
}
g::Motion moving(F rate = {1, 2}) { return {g::MotionState::rotating, rate}; }
long double value(const n::Coordinate& c) {
    return (c.base + static_cast<long double>(c.coefficient) * std::sqrt(static_cast<long double>(c.radicand))) / c.denominator;
}
long double value(F f) { return static_cast<long double>(f.numerator) / f.denominator; }
bool refused(const n::Reading& result, n::Error error) {
    const auto* r = std::get_if<n::Refusal>(&result); return r && r->reason == error;
}
std::vector<n::Direction> directions() {
    std::vector<n::Direction> result;
    for (I q = 1; q <= 65; ++q) for (I x = -q; x <= q; ++x) for (I y = -q; y <= q; ++y)
        if (x * x + y * y == q * q && std::gcd(std::gcd(x, y), q) == 1) result.push_back({x, y, q});
    for (const auto d : {n::Direction{95, 168, 193}, {95, -168, 193}, {-209, 120, 241}, {209, -120, 241}}) result.push_back(d);
    return result;
}

void link_and_velocity(const n::Sample& r) {
    const auto& p = r.profile;
    const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u;
    const I handed = (a + 1) % 3 == u ? 1 : -1;
    const auto& cx = r.joint[u]; const auto& cy = r.joint[v];
    const I den = cx.denominator, radical = cx.radicand, q = r.direction.scale;
    require(cy.denominator == den && cy.radicand == radical, "both planar coordinates share their factored field");
    std::array<Wide, 2> t{}, b{}, rocker{};
    const std::array<std::size_t, 2> axes{u, v};
    Wide pin_squared{};
    for (std::size_t j = 0; j < 2; ++j) {
        const auto i = axes[j];
        const auto& c = r.joint[i];
        require(den % r.pin[i].denominator == 0, "pin denominator divides exact joint denominator");
        t[j] = c.base - Wide{r.pin[i].numerator} * (den / r.pin[i].denominator);
        b[j] = c.coefficient;
        rocker[j] = c.base - Wide{r.anchor[i]} * den;
        const auto pin = (r.pin[i].numerator - p.origin[i] * r.pin[i].denominator) * (q / r.pin[i].denominator);
        pin_squared += Wide{pin} * pin;
    }
    require(pin_squared == Wide{p.crank} * p.crank * q * q, "actual world pin lies on the crank circle");
    require(r.pin[a] == F{p.origin[a], 1} && std::get<std::optional<F>>(n::rational_view(r.joint[a])) == std::optional<F>{F{p.origin[a], 1}}, "all joints retain the proper shaft plane");
    for (const auto link : {0, 1}) {
        const auto& base = link == 0 ? t : rocker;
        const I length = link == 0 ? p.coupler : p.rocker;
        require(base[0] * base[0] + base[1] * base[1] + (b[0] * b[0] + b[1] * b[1]) * radical == Wide{length} * length * den * den,
            "independent exact algebraic squared length has the declared finite link length");
        require(base[0] * b[0] + base[1] * b[1] == 0, "independent link length has zero irrational coefficient");
    }
    const auto wx = Wide{r.anchor[u]} * q - Wide{r.pin[u].numerator} * (q / r.pin[u].denominator);
    const auto wy = Wide{r.anchor[v]} * q - Wide{r.pin[v].numerator} * (q / r.pin[v].denominator);
    const auto branch_cross = handed * (wx * b[1] - wy * b[0]);
    require(radical == 0 || (p.branch == n::Branch::positive ? branch_cross > 0 : branch_cross < 0), "world cross product independently distinguishes both assembly branches");
    require(r.tangent == (radical == 0) && r.per_input_radian.has_value() == !r.tangent, "tangent and regular derivative are distinct");
    if (!r.per_input_radian) return;
    const auto& d = *r.per_input_radian;
    require(d.radicand == radical, "derivative preserves the actual joint's radical");
    const Wide vx = -p.crank * r.direction.sine, vy = handed * p.crank * r.direction.cosine;
    const auto dot_base = vx * t[0] + vy * t[1], dot_root = vx * b[0] + vy * b[1];
    const auto cross_base = handed * (rocker[0] * t[1] - rocker[1] * t[0] + (b[0] * b[1] - b[1] * b[0]) * radical);
    const auto cross_root = handed * (rocker[0] * b[1] + b[0] * t[1] - rocker[1] * b[0] - b[1] * t[0]);
    require(cross_base == 0 && cross_root != 0, "actual joint velocity constraint has a nonzero pure-root denominator");
    require(Wide{d.inverse_root.numerator} * cross_root * q == dot_base * d.inverse_root.denominator * den,
        "independent exact dot/cross velocity constraint matches inverse-root derivative term");
    require(Wide{d.direct.numerator} * cross_root * q == dot_root * d.direct.denominator * den,
        "independent exact dot/cross velocity constraint matches rational derivative term");
    const auto rx = value(cx) - r.anchor[u], ry = value(cy) - r.anchor[v];
    const auto tx = value(cx) - value(r.pin[u]), ty = value(cy) - value(r.pin[v]);
    const auto omega = value(d.direct) + value(d.inverse_root) / std::sqrt(static_cast<long double>(radical));
    const auto residual = (-handed * ry * omega - static_cast<long double>(vx) / q) * tx +
        (handed * rx * omega - static_cast<long double>(vy) / q) * ty;
    require(std::abs(residual) < 1e-8L, "independent Cartesian velocity preserves coupler length");
}

void branches_and_frames() {
    const auto rays = directions();
    const std::array<g::Motion, 6> sources{{moving(), moving({-1, 2}), moving({7, 11}), {}, {g::MotionState::stopped, {}}, {g::MotionState::stalled, {}}}};
    const std::array<std::array<I, 4>, 9> dimensions{{{8, 2, 7, 5}, {8, 3, 8, 5}, {8, 2, 6, 3}, {8, 2, 6, 4},
        {6, 4, 2, 5}, {3, 5, 6, 7}, {2, 2, 5, 5}, {17, 3, 14, 12}, {64, 63, 64, 64}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        for (const auto origin : {g::Point{0, 0, 8}, {-23, 17, 31}}) for (const auto& dim : dimensions) for (const auto branch : {n::Branch::positive, n::Branch::negative}) {
            n::Profile p; p.origin = origin; p.shaft = static_cast<g::Axis>(a); p.span = static_cast<g::Axis>(u);
            p.ground = dim[0]; p.crank = dim[1]; p.coupler = dim[2]; p.rocker = dim[3]; p.branch = branch;
            const auto cycle = std::get<n::Cycle>(n::inspect(p));
            const I near = std::abs(p.ground - p.crank), far = p.ground + p.crank, inner = std::abs(p.coupler - p.rocker), outer = p.coupler + p.rocker;
            require(cycle.profile == p && cycle.minimum_distance == near && cycle.maximum_distance == far && cycle.closed == (near >= inner && far <= outer), "whole input distance range independently supplies complete closure");
            require(cycle.regular == (near > inner && far < outer && near != 0), "strict full-turn regularity rejects both tangent and coincident limits");
            for (const auto ray : rays) for (const auto source : sources) {
                const auto result = n::sample(p, ray, source);
                const I square = (p.ground * p.ground + p.crank * p.crank) * ray.scale - 2 * p.ground * p.crank * ray.cosine;
                const bool reach = square >= inner * inner * ray.scale && square <= outer * outer * ray.scale;
                if (!square && p.coupler == p.rocker) { require(refused(result, n::Error::underconstrained), "coincident equal circles have no unique joint"); ++unreachable; continue; }
                if (!reach) { require(refused(result, n::Error::unreachable), "independent circle-distance bounds reject missing finite intersections"); ++unreachable; continue; }
                require(std::holds_alternative<n::Sample>(result), "reachable finite circles return an owned sample");
                const auto& current = std::get<n::Sample>(result);
                require(current.profile == p && current.direction == ray && current.input == source, "source state, caller direction and branch stay explicit and owned");
                link_and_velocity(current);
                for (const auto& coordinate : current.joint) {
                    for (const auto grid : {-1000, -24, 0, 8, 32, 1000}) {
                        const auto approximate = value(coordinate) - grid;
                        const auto actual = std::get<s::Order>(n::compare_to_grid(coordinate, grid));
                        if (std::abs(approximate) > 1e-10L) require(actual == (approximate < 0 ? s::Order::less : s::Order::greater), "exact grid comparison agrees with independent separated numerical value");
                    }
                }
                ++observations;
            }
            ++profiles;
        }
    }
}

void limits_and_discriminators() {
    n::Profile p;
    p.coupler = 6; p.rocker = 3;
    require(std::holds_alternative<n::Sample>(n::sample(p, {}, moving())) && !std::get<n::Cycle>(n::inspect(p)).closed, "current fit cannot prove full turn: later input locks");
    p = {}; p.ground = 6; p.crank = 4; p.coupler = 2;
    std::array<I, 4> lengths{p.ground, p.crank, p.coupler, p.rocker}; std::sort(lengths.begin(), lengths.end());
    require(lengths[0] + lengths[3] < lengths[1] + lengths[2] && !std::get<n::Cycle>(n::inspect(p)).closed && std::holds_alternative<n::Sample>(n::sample(p, {3, 4, 5}, moving())), "general Grashof success does not make this chosen input a full crank");
    p = {}; p.coupler = 6; p.rocker = 4;
    const auto tangent = std::get<n::Sample>(n::sample(p, {-1, 0, 1}, moving()));
    require(tangent.tangent && !tangent.per_input_radian && std::get<n::Cycle>(n::inspect(p)).closed && !std::get<n::Cycle>(n::inspect(p)).regular, "tangent closure remains visible without an invented derivative");
    p.branch = n::Branch::negative; const auto same = std::get<n::Sample>(n::sample(p, {-1, 0, 1}, moving()));
    for (std::size_t i = 0; i < 3; ++i) require(n::rational_view(tangent.joint[i]) == n::rational_view(same.joint[i]), "both branches meet at exact tangency");
    p = {}; p.ground = 6; p.crank = 3; p.coupler = 5; p.rocker = 10;
    const auto stop = std::get<n::Sample>(n::sample(p, {0, 1, 1}, moving()));
    require(!stop.tangent && stop.per_input_radian && std::abs(value(stop.per_input_radian->direct) + value(stop.per_input_radian->inverse_root) / std::sqrt(static_cast<long double>(stop.per_input_radian->radicand))) < 1e-18L, "regular zero rocker speed at reversal is not a tangent singularity");
    for (const auto rate : {F{std::numeric_limits<I>::max(), std::numeric_limits<I>::max()}, F{-4, 8}}) {
        const auto normalized = std::get<n::Sample>(n::sample({}, {}, moving(rate)));
        require(normalized.input.rate == (rate.numerator > 0 ? F{1, 1} : F{-1, 2}), "raw rates normalize before any useful geometry");
    }
    for (const auto bad : {n::Direction{0, 0, 1}, {2, 0, 2}, {1, 1, 1}, {1, 0, 0}, {1, 0, 257}, {std::numeric_limits<I>::min(), 0, 1}})
        require(refused(n::sample({}, bad, {}), n::Error::invalid_direction), "malformed physical directions reject before products even unpowered");
    for (const auto rate : {F{1, 0}, {1, -1}, {std::numeric_limits<I>::min(), 1}, {1, 1000001}, {std::numeric_limits<I>::max(), 1}}) {
        p = {}; p.coupler = 1; p.rocker = 1;
        require(refused(n::sample(p, {}, moving(rate)), n::Error::invalid_rate), "invalid rate cannot hide behind unreachable closure");
    }
    for (const auto input : {g::Motion{g::MotionState::rotating, {}}, {g::MotionState::stopped, {1, 2}}, {g::MotionState::stalled, {-1, 2}}, {static_cast<g::MotionState>(99), {}}})
        require(refused(n::sample({}, {}, input), n::Error::invalid_motion), "native state/rate inconsistencies are never turned into power");
    for (int i = 0; i < 9; ++i) {
        p = {};
        if (i == 0) p.crank = 0;
        if (i == 1) p.ground = 65;
        if (i == 2) p.coupler = std::numeric_limits<I>::min();
        if (i == 3) p.rocker = 65;
        if (i == 4) p.coupler_id = p.crank_id;
        if (i == 5) p.rocker_id = 0;
        if (i == 6) p.branch = static_cast<n::Branch>(99);
        if (i == 7) p.origin[1] = std::numeric_limits<I>::max();
        if (i == 8) p.crank_id = p.rocker_id;
        require(refused(n::sample(p, {}, {}), n::Error::invalid_profile) && std::get<n::Refusal>(n::inspect(p)).reason == n::Error::invalid_profile, "raw profile extrema and identities reject before arithmetic");
    }
    p = {}; p.span = p.shaft; require(refused(n::sample(p, {}, {}), n::Error::invalid_axes), "equal axes reject");
    p.span = static_cast<g::Axis>(99); require(refused(n::sample(p, {}, {}), n::Error::invalid_axes), "invalid axis enum rejects");
    p = {}; p.origin[0] = g::maximum_coordinate - 8;
    require(std::holds_alternative<n::Sample>(n::sample(p, {}, moving())) && !std::get<n::Cycle>(n::inspect(p)).envelope_within_grid, "conservative full-envelope flag does not reject a fitting actual pose");
    p = {}; p.origin[1] = g::maximum_coordinate - 2;
    require(refused(n::sample(p, {}, moving()), n::Error::representation_limit), "actual irrational joint outside the grid refuses without rounding");
    p.origin[0] = g::maximum_coordinate; require(refused(n::sample(p, {}, moving()), n::Error::representation_limit), "out-of-grid fixed anchor rejects");
    auto owned = std::get<n::Sample>(n::sample({}, {}, moving())); owned.profile.crank = 64; owned.joint[0].base = 123;
    const auto again = std::get<n::Sample>(n::sample({}, {}, moving()));
    require(again.profile.crank == 2 && again.joint[0].base != 123, "samples own their data without mutable shared assembly state");
}

void raw_comparisons() {
    constexpr I den_bound = I{1} << 39, coefficient_bound = I{1} << 15, rad_bound = I{1} << 60;
    constexpr I base_bound = (g::maximum_coordinate + 128) * den_bound;
    std::uint64_t state = 0x13bacf6123;
    const auto random = [&state]() { state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state; };
    for (int i = 0; i < 12000; ++i) {
        n::Coordinate c{static_cast<I>(random() % static_cast<std::uint64_t>(2 * base_bound + 1)) - base_bound,
            static_cast<I>(random() % (2 * coefficient_bound + 1)) - coefficient_bound,
            static_cast<I>(random() % (rad_bound + 1)), static_cast<I>(random() % den_bound) + 1};
        const I grid = static_cast<I>(random() % 2000001) - 1000000;
        // Include close radical/grid comparisons, as well as enormous squares.
        if (i % 3 == 0) { c.base = grid * c.denominator - static_cast<I>(random() % 10000000000001ULL) + 5000000000000LL; }
        if (c.base < -base_bound || c.base > base_bound) continue;
        const Wide delta = Wide{grid} * c.denominator - c.base;
        s::Order expected;
        if (!c.coefficient || !c.radicand) expected = delta > 0 ? s::Order::less : delta < 0 ? s::Order::greater : s::Order::equal;
        else if (c.coefficient > 0 && delta < 0) expected = s::Order::greater;
        else if (c.coefficient < 0 && delta > 0) expected = s::Order::less;
        else {
            const Wide root = Wide{c.coefficient} * c.coefficient * c.radicand, square = delta * delta;
            expected = root < square ? s::Order::less : root > square ? s::Order::greater : s::Order::equal;
            if (c.coefficient < 0) expected = expected == s::Order::less ? s::Order::greater : expected == s::Order::greater ? s::Order::less : expected;
        }
        require(std::get<s::Order>(n::compare_to_grid(c, grid)) == expected, "portable two-limb radical/grid product agrees with independent compiler-wide arithmetic"); ++comparisons;
    }
    for (const auto root : {I{0}, I{1}, I{7}, I{65537}, I{1} << 30}) for (const auto coefficient : {-32768, -1, 0, 1, 32768}) {
        const n::Coordinate c{123, coefficient, root * root, 2};
        const auto rational = std::get<std::optional<F>>(n::rational_view(c));
        require(rational && value(*rational) == (123 + static_cast<long double>(coefficient) * root) / 2, "perfect radicals have exact reduced rational views including coefficient and root extrema");
    }
    require(!std::get<std::optional<F>>(n::rational_view({0, 1, 2, 1})), "irrational coordinates have no fabricated rational view");
    require(std::get<std::optional<F>>(n::rational_view({3, 0, 2, 2})) == std::optional<F>{F{3, 2}}, "zero radical coefficient is rational even with nonsquare unused field");
    for (const auto c : {n::Coordinate{0, 0, -1, 1}, {0, 0, rad_bound + 1, 1}, {base_bound + 1, 0, 0, 1}, {0, coefficient_bound + 1, 0, 1}, {0, 0, 0, 0}, {0, 0, 0, den_bound + 1}})
        require(std::get<n::Error>(n::compare_to_grid(c, 0)) == n::Error::invalid_coordinate && std::get<n::Error>(n::rational_view(c)) == n::Error::invalid_coordinate, "all raw algebraic guards precede products");
    require(std::get<n::Error>(n::compare_to_grid({}, std::numeric_limits<I>::max())) == n::Error::invalid_grid, "raw grid extrema reject before multiplication");
    for (const auto sign : {-1, 1}) require(std::get<s::Order>(n::compare_to_grid({0, sign * 3, 4, 2}, sign * 3)) == s::Order::equal, "exact radical equality remains equality on both signs");
}

void consumers() {
    struct Case { std::vector<std::string_view> args; bool matched; int exit; const char* detail; };
    const std::array<Case, 23> cases{{
        {{{"standard", "positive", "slow", "full"}}, true, 0, "Both fixed work windows reached"},
        {{{"standard", "positive", "reverse", "full"}}, true, 0, "Both fixed work windows reached"},
        {{{"long-arm", "positive", "slow", "full"}}, true, 0, "Both fixed work windows reached"},
        {{{"long-arm", "positive", "reverse", "full"}}, true, 0, "Both fixed work windows reached"},
        {{{"short-arm", "positive", "slow", "full"}}, false, 0, "work windows missed"},
        {{{"standard", "negative", "slow", "full"}}, false, 0, "work windows missed"},
        {{{"long-arm", "negative", "slow", "full"}}, false, 0, "work windows missed"},
        {{{"shifted", "positive", "slow", "full"}}, false, 0, "work windows missed"},
        {{{"standard", "positive", "slow", "short"}}, false, 0, "unpowered 0/1"},
        {{{"long-arm", "positive", "slow", "short"}}, false, 0, "unpowered 0/1"},
        {{{"standard", "positive", "fast", "full"}}, false, 0, "rotating 5/2"},
        {{{"standard", "positive", "stalled", "full"}}, false, 0, "stalled 0/1"},
        {{{"standard", "positive", "off", "full"}}, false, 0, "unpowered 0/1"},
        {{{"locks-later", "positive", "slow", "full"}}, false, 0, "full closure no"},
        {{{"change-point", "positive", "slow", "full"}}, false, 0, "regular no"},
        {{{"coincident", "positive", "slow", "full"}}, false, 2, "underconstrained"},
        {{{"near-edge", "positive", "slow", "full"}}, false, 2, "representation_limit"},
        {{{"standard", "bogus", "slow", "full"}}, false, 2, "assembly branch"},
        {{{"unknown", "positive", "slow", "full"}}, false, 2, "Unknown"},
        {{{"standard", "positive", "unknown", "full"}}, false, 2, "Unknown"},
        {{{"standard", "positive", "slow", "extra"}}, false, 2, "input shaft"},
        {{{"standard"}}, false, 2, "Choose"},
        {{{"list"}}, false, 0, "geometric derivatives"}
    }};
    for (const auto& test : cases) {
        std::ostringstream out, errors;
        require(n::workbench(test.args, out, errors) == test.exit, "consumer returns expected success/refusal status");
        require((out.str().find("Goal matched:") != std::string::npos) == test.matched, "only distinct complete working kits match");
        require((out.str() + errors.str()).find(test.detail) != std::string::npos, "specific consumer discriminator is visible"); ++traces;
    }
}
int main() {
    branches_and_frames(); limits_and_discriminators(); raw_comparisons(); consumers();
    std::cout << checks << " four-bar assertions passed; profiles=" << profiles << " reachable=" << observations
        << " refused_geometry=" << unreachable << " independent_wide_comparisons=" << comparisons << " consumer_traces=" << traces << ".\n";
}
