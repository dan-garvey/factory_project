#include "factory/slotted_rocker.hpp"
#include "factory/slotted_rocker_workbench.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace n = factory::slotted_rocker;
namespace g = factory::mechanics;
namespace s = factory::slider_crank;
using I = n::Integer;
using F = n::Fraction;
std::size_t checks{}, profiles{}, observations{}, chart_cases{}, traces{};
void require(bool p, const char* message) { ++checks; if (!p) { std::cerr << "FAIL " << message << '\n'; std::exit(1); } }
F fraction(I a, I b = 1) { const auto d = std::gcd(a, b); return {a / d, b / d}; }
F add(F a, F b) { const auto d = std::gcd(a.denominator, b.denominator); return fraction(a.numerator * (b.denominator / d) + b.numerator * (a.denominator / d), a.denominator * (b.denominator / d)); }
F neg(F a) { return {-a.numerator, a.denominator}; }
F times(F a, F b) { const auto c = std::gcd(a.numerator, b.denominator), d = std::gcd(b.numerator, a.denominator); return fraction((a.numerator / c) * (b.numerator / d), (a.denominator / d) * (b.denominator / c)); }
F divide(F a, F b) { return b.numerator < 0 ? times(neg(a), {b.denominator, -b.numerator}) : times(a, {b.denominator, b.numerator}); }
F dot(const n::Point& a, const n::Point& b) { F r{}; for (std::size_t i = 0; i < 3; ++i) r = add(r, times(a[i], b[i])); return r; }
n::Point cross(const n::Point& a, const n::Point& b) { n::Point r{}; for (std::size_t i = 0; i < 3; ++i) r[i] = add(times(a[(i + 1) % 3], b[(i + 2) % 3]), neg(times(a[(i + 2) % 3], b[(i + 1) % 3]))); return r; }
g::Motion moving(F f = {1, 2}) { return {g::MotionState::rotating, f}; }
bool refused(const n::Reading& r, n::Error e) { const auto* p = std::get_if<n::Refusal>(&r); return p && p->reason == e; }
struct Q { F rational{}, root{}; bool operator==(const Q&) const = default; };  // Q(sqrt(3)).
Q plus(Q a, Q b) { return {add(a.rational, b.rational), add(a.root, b.root)}; }
Q multiply(Q a, Q b) { return {add(times(a.rational, b.rational), times({3, 1}, times(a.root, b.root))), add(times(a.rational, b.root), times(a.root, b.rational))}; }
Q scaled(Q q, I x) { return {times(q.rational, {x, 1}), times(q.root, {x, 1})}; }
Q decode(const s::Coordinate& c, I radius) {
    require(!c.radicand || c.radicand == 3 * radius * radius, "reversal retains an exact sqrt(3) field");
    return {fraction(c.base, c.denominator), c.radicand ? fraction((c.branch == s::Branch::positive ? 1 : -1) * radius, c.denominator) : F{}};
}

void actual_geometry(const n::Sample& r) {
    const auto& p = r.profile; const auto a = static_cast<std::size_t>(p.shaft);
    n::Point pin{}, ray{}, normal{}; normal[a] = {1, 1};
    for (std::size_t i = 0; i < 3; ++i) {
        pin[i] = add(r.pin[i], {-p.origin[i], 1}); ray[i] = add(r.pin[i], {-r.pivot[i], 1});
        require(ray[i] == r.lever_ray[i], "actual pin and fixed pivot independently recover the complete lever ray");
    }
    require(dot(pin, pin) == F{p.radius * p.radius, 1} && pin[a] == F{}, "actual world pin retains crank length and shaft plane");
    const auto radial = dot(ray, ray);
    require(radial == r.distance_squared, "independent 3D vector length determines radial slot contact");
    const bool fits = radial.numerator >= p.slot_inner * p.slot_inner * radial.denominator && radial.numerator <= p.slot_outer * p.slot_outer * radial.denominator;
    require(r.slot_fits == fits && r.constraint.has_value() == fits, "missing finite radial contact supplies no output constraint on either stroke");
    if (!fits) return;
    const auto pin_velocity = cross(normal, pin), angular = cross(ray, pin_velocity);
    const auto ratio = divide(angular[a], radial);
    require(ratio == r.constraint->per_input_radian, "actual Cartesian dot/cross velocity gives the independent nonlinear angular ratio");
    require((ratio.numerator < 0) == (r.stroke == n::Stroke::short_arc) && ratio.numerator != 0, "all rational physical chart poses distinguish the two rocking senses; exact irrational reversals are separate");
    const auto rate = times(r.input.rate, ratio); auto state = r.input.state;
    if (state == g::MotionState::rotating && rate.numerator == 0) state = g::MotionState::stopped;
    require(r.constraint->output == g::Motion{state, rate}, "conditional angular observation preserves distinct native source states");
}

void all_frames_and_sources() {
    const std::array<n::Direction, 18> directions{{{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}, {3, 4, 5}, {-3, 4, 5}, {3, -4, 5}, {-4, -3, 5},
        {5, 12, 13}, {12, -5, 13}, {8, 15, 17}, {15, -8, 17}, {33, 56, 65}, {33, -56, 65}, {95, 168, 193}, {95, -168, 193}, {-209, 120, 241}, {209, -120, 241}}};
    const std::array<g::Motion, 6> sources{{moving(), moving({-1, 2}), moving({7, 11}), {}, {g::MotionState::stopped, {}}, {g::MotionState::stalled, {}}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        const auto v = 3 - a - u; const I handed = (a + 1) % 3 == u ? 1 : -1;
        for (const auto origin : {g::Point{0, 0, 8}, {-23, 17, 31}}) for (I radius : {2, 6, 10, 1365}) for (int variant = 0; variant < 3; ++variant) {
            n::Profile p; p.origin = origin; p.shaft = static_cast<g::Axis>(a); p.span = static_cast<g::Axis>(u); p.radius = radius;
            p.slot_inner = radius - 1; p.slot_outer = 3 * radius + 1;
            if (variant == 1) p.slot_outer = 3 * radius - 1;
            if (variant == 2) p.slot_inner = radius + 1;
            const auto cycle = std::get<n::Cycle>(n::inspect(p));
            require(cycle.profile == p && cycle.minimum_distance == radius && cycle.maximum_distance == 3 * radius && cycle.slot_covers == (variant == 0), "whole finite slot uses the complete R..3R range, distinct from an intermittent Geneva engagement");
            require(cycle.short_input_fraction == F{1, 3} && cycle.long_input_fraction == F{2, 3}, "constant physical input divides the strokes into unequal turn fractions");
            std::array<std::array<Q, 2>, 2> pins{};
            for (std::size_t edge = 0; edge < 2; ++edge) {
                const auto& end = cycle.reversals[edge];
                const std::array<Q, 2> pin{decode(end.pin_from_crank[u], radius), scaled(decode(end.pin_from_crank[v], radius), handed)};
                const std::array<Q, 2> ray{decode(end.lever_from_pivot[u], radius), scaled(decode(end.lever_from_pivot[v], radius), handed)};
                require(plus(multiply(pin[0], pin[0]), multiply(pin[1], pin[1])) == Q{F{radius * radius, 1}, {}}, "exact reversal crank pin lies on its finite circle");
                require(plus(multiply(ray[0], ray[0]), multiply(ray[1], ray[1])) == Q{F{3 * radius * radius, 1}, {}}, "actual tangent ray length squared is 3R squared");
                require(plus(multiply(pin[0], ray[0]), multiply(pin[1], ray[1])) == Q{}, "actual reversal crank radius is normal to the lever ray, so angular output is exactly zero");
                require(plus(ray[0], Q{F{2 * radius, 1}, {}}) == pin[0] && ray[1] == pin[1], "both irrational vectors meet the same real pin");
                require(!std::get<std::optional<F>>(s::rational_view(end.pin_from_crank[v])), "irrational endpoint does not become a fabricated rational circle Direction");
                pins[edge] = pin;
            }
            const Q cosine{F{-1, 2}, {}}, sine{{}, F{1, 2}};
            const auto rotated_x = plus(multiply(cosine, pins[0][0]), scaled(multiply(sine, pins[0][1]), -1));
            const auto rotated_y = plus(multiply(sine, pins[0][0]), multiply(cosine, pins[0][1]));
            require(rotated_x == pins[1][0] && rotated_y == pins[1][1], "exact 120-degree carrier rotation connects both tangent endpoints, leaving a 240-degree complementary stroke");
            for (const auto direction : directions) for (const auto input : sources) {
                const auto result = std::get<n::Sample>(n::sample(p, direction, input));
                require(result.profile == p && result.direction == direction && result.input == input, "owned observations retain caller phase, finite assembly and native input");
                actual_geometry(result); ++observations;
            }
            ++profiles;
        }
    }
}

void admission_and_discriminators() {
    n::Profile p; p.slot_outer = 18;
    const auto front = std::get<n::Sample>(n::sample(p, {}, moving())), back = std::get<n::Sample>(n::sample(p, {-1, 0, 1}, moving()));
    require(front.constraint && !back.constraint && !std::get<n::Cycle>(n::inspect(p)).slot_covers, "a slot covering the complete Geneva active range still misses this continuously engaged return");
    p = {}; const auto near = std::get<n::Sample>(n::sample(p, {}, moving())), far = std::get<n::Sample>(n::sample(p, {-1, 0, 1}, moving()));
    require(near.constraint->output.rate == F{-1, 2} && far.constraint->output.rate == F{1, 6} && far.constraint->output.state == g::MotionState::rotating, "return really reverses at nonzero one-third output ratio instead of a held dwell");
    require(refused(n::sample(p, {5, 12, 13}, moving({1, 999983})), n::Error::unsupported_result), "unsupported inferred native rate refuses without a partial output");
    for (const auto rate : {F{std::numeric_limits<I>::max(), std::numeric_limits<I>::max()}, {-4, 8}}) {
        const auto result = std::get<n::Sample>(n::sample(p, {}, moving(rate)));
        require(result.input.rate == (rate.numerator > 0 ? F{1, 1} : F{-1, 2}), "raw native rates normalize before inference");
    }
    for (const auto direction : {n::Direction{0, 0, 1}, {2, 0, 2}, {1, 1, 1}, {1, 0, 0}, {1, 0, 257}, {std::numeric_limits<I>::min(), 0, 1}})
        require(refused(n::sample({}, direction, {}), n::Error::invalid_direction), "physical direction raw bounds precede products even unpowered");
    for (const auto rate : {F{1, 0}, {1, -1}, {std::numeric_limits<I>::min(), 1}, {1, 1000001}, {std::numeric_limits<I>::max(), 1}}) {
        p = {}; p.slot_outer = 9;
        require(refused(n::sample(p, {}, moving(rate)), n::Error::invalid_rate), "missing current slot contact cannot hide malformed native rates");
    }
    for (const auto input : {g::Motion{g::MotionState::rotating, {}}, {g::MotionState::stopped, {1, 2}}, {g::MotionState::stalled, {-1, 2}}, {static_cast<g::MotionState>(99), {}}})
        require(refused(n::sample({}, {}, input), n::Error::invalid_motion), "source state/rate inconsistencies reject");
    for (int variant = 0; variant < 8; ++variant) {
        p = {};
        if (variant == 0) p.radius = 0;
        if (variant == 1) p.radius = 1366;
        if (variant == 2) p.radius = std::numeric_limits<I>::min();
        if (variant == 3) p.slot_inner = 0;
        if (variant == 4) p.slot_outer = 4097;
        if (variant == 5) p.slot_inner = p.slot_outer;
        if (variant == 6) p.crank_id = p.lever_id;
        if (variant == 7) p.origin[0] = std::numeric_limits<I>::max();
        require(refused(n::sample(p, {}, {}), n::Error::invalid_profile) && std::get<n::Refusal>(n::inspect(p)).reason == n::Error::invalid_profile, "raw profile extrema precede useful sample or full-turn result");
    }
    p = {}; p.span = p.shaft; require(refused(n::sample(p, {}, {}), n::Error::invalid_axes), "equal axes reject");
    p.span = static_cast<g::Axis>(99); require(refused(n::sample(p, {}, {}), n::Error::invalid_axes), "invalid axis enum rejects");
    p = {}; p.origin[0] = g::maximum_coordinate - 20;
    require(refused(n::sample(p, {}, {}), n::Error::representation_limit), "declared whole slot envelope validates before an unpowered result");
    for (I q = 1; q <= 256; ++q) for (I x = -q; x <= q; ++x) for (I y = -q; y <= q; ++y) {
        if (x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1) continue;
        for (const auto input : {moving(), moving({-1, 2})}) { const auto current = std::get<n::Sample>(n::sample({}, {x, y, q}, input)); actual_geometry(current); ++chart_cases; }
    }
    auto changed = near; changed.profile.radius = 1; changed.lever_ray[0] = {999, 1};
    require(std::get<n::Sample>(n::sample({}, {}, moving())).lever_ray == near.lever_ray && changed.lever_ray != near.lever_ray, "no live or shared mutable phase/sample state exists");
}

void consumers() {
    struct Case { std::vector<std::string_view> args; int exit; bool won; const char* text; };
    const std::array<Case, 22> cases{{
        {{{"standard", "slow", "full"}}, 0, true, "Far readout rotating 1/6"},
        {{{"standard", "reverse", "full"}}, 0, true, "Near readout rotating 1/2"},
        {{{"compact", "slow", "full"}}, 0, true, "Goal matched:"},
        {{{"compact", "reverse", "full"}}, 0, true, "Far readout rotating -1/6"},
        {{{"short-slot", "slow", "full"}}, 0, false, "fitting near pose"},
        {{{"inner-miss", "slow", "full"}}, 0, false, "current pin misses"},
        {{{"shifted", "slow", "full"}}, 0, false, "readout unpowered"},
        {{{"short-input", "slow", "full"}}, 0, false, "source unpowered"},
        {{{"standard", "slow", "short"}}, 0, false, "readout unpowered"},
        {{{"compact", "slow", "short"}}, 0, false, "readout unpowered"},
        {{{"standard", "fast", "full"}}, 0, false, "speed magnitude 1/2"},
        {{{"standard", "stalled", "full"}}, 0, false, "source stalled"},
        {{{"standard", "off", "full"}}, 0, false, "source unpowered"},
        {{{"compact", "off", "full"}}, 0, false, "source unpowered"},
        {{{"near-edge", "slow", "full"}}, 2, false, "representation_limit"},
        {{{"near-edge", "off", "full"}}, 2, false, "representation_limit"},
        {{{"bogus", "slow", "full"}}, 2, false, "Unknown"},
        {{{"standard", "bogus", "full"}}, 2, false, "Unknown"},
        {{{"standard", "slow", "bogus"}}, 2, false, "Choose"},
        {{{"standard"}}, 2, false, "Choose"},
        {{{"list"}}, 0, false, "without a held dwell"},
        {std::vector<std::string_view>{}, 0, false, "Usage:"}
    }};
    for (const auto& c : cases) {
        std::ostringstream out, error;
        require(n::workbench(c.args, out, error) == c.exit, "consumer exit status is explicit");
        require((out.str().find("Goal matched:") != std::string::npos) == c.won, "only complete powered near/far shaft solutions win");
        require((out.str() + error.str()).find(c.text) != std::string::npos, "specific source/geometry discriminator remains visible"); ++traces;
    }
}
int main() {
    all_frames_and_sources(); admission_and_discriminators(); consumers();
    std::cout << checks << " slotted-rocker assertions passed; profiles=" << profiles << " observations=" << observations
        << " bounded_circle_chart=" << chart_cases << " consumer_traces=" << traces << ".\n";
}
