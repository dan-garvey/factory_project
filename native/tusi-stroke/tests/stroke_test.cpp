#include "factory/tusi_stroke.hpp"
#include "factory/tusi_stroke_workbench.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace n = factory::tusi_stroke;
namespace g = factory::mechanics;
namespace s = factory::slider_crank;
using I = n::Integer;
using F = n::Fraction;
std::size_t checks{}, profiles{}, observations{}, chart_cases{}, traces{};
void require(bool pass, const char* message) { ++checks; if (!pass) { std::cerr << "FAIL " << message << '\n'; std::exit(1); } }
F fraction(I numerator, I denominator = 1) {
    const auto divisor = std::gcd(numerator, denominator); return {numerator / divisor, denominator / divisor};
}
F add(F a, F b) {
    const auto common = std::gcd(a.denominator, b.denominator);
    return fraction(a.numerator * (b.denominator / common) + b.numerator * (a.denominator / common), a.denominator * (b.denominator / common));
}
F neg(F f) { return {-f.numerator, f.denominator}; }
F sub(F a, F b) { return add(a, neg(b)); }
F times(F a, F b) {
    const auto one = std::gcd(a.numerator, b.denominator), two = std::gcd(b.numerator, a.denominator);
    return fraction((a.numerator / one) * (b.numerator / two), (a.denominator / two) * (b.denominator / one));
}
F dot(const n::Point& a, const n::Point& b) { F result{}; for (std::size_t i = 0; i < 3; ++i) result = add(result, times(a[i], b[i])); return result; }
n::Point cross(const n::Point& a, const n::Point& b) {
    n::Point result{}; for (std::size_t i = 0; i < 3; ++i) result[i] = sub(times(a[(i + 1) % 3], b[(i + 2) % 3]), times(a[(i + 2) % 3], b[(i + 1) % 3])); return result;
}
n::Point difference(const n::Point& a, const n::Point& b) { n::Point r{}; for (std::size_t i = 0; i < 3; ++i) r[i] = sub(a[i], b[i]); return r; }
g::Motion moving(F rate = {1, 2}) { return {g::MotionState::rotating, rate}; }
bool refused(const n::Reading& r, n::Error e) { const auto* v = std::get_if<n::Refusal>(&r); return v && v->reason == e; }

void actual_vectors(const n::Sample& r) {
    const auto& p = r.profile; const auto a = static_cast<std::size_t>(p.shaft), u = static_cast<std::size_t>(p.span), v = 3 - a - u;
    const I handed = (a + 1) % 3 == u ? 1 : -1;
    n::Point origin{}, normal{}; normal[a] = {1, 1}; for (std::size_t i = 0; i < 3; ++i) origin[i] = {p.origin[i], 1};
    const auto center = difference(r.center, origin), contact = difference(r.contact, origin), pin_arm = difference(r.pin, r.center), contact_arm = difference(r.contact, r.center);
    require(dot(center, center) == F{p.radius * p.radius, 1} && dot(contact, contact) == F{4 * p.radius * p.radius, 1}, "actual centre and contact have the independent 1:2 pitch radii");
    require(dot(contact_arm, contact_arm) == F{p.radius * p.radius, 1} && dot(pin_arm, pin_arm) == F{p.radius * p.radius, 1}, "both contact and pin lie on the moving circle");
    const auto center_velocity = cross(normal, center), contact_spin = cross(normal, contact_arm), pin_spin = cross(normal, pin_arm);
    require(center_velocity == contact_spin, "opposite unit absolute spin exactly cancels carrier translation at the material pitch contact");
    require(r.planet.state == r.carrier.state && r.planet.rate == neg(r.carrier.rate), "conditional absolute spin reverses the source without manufacturing power or a brake");
    for (std::size_t i = 0; i < 3; ++i) require(r.pin_per_input_radian[i] == sub(center_velocity[i], pin_spin[i]), "independent vector velocity derives the pin derivative without differentiating the production formula");
    const F cosine{r.direction.cosine, r.direction.scale}, sine{r.direction.sine, r.direction.scale};
    const auto local_y = times(pin_arm[v], {handed, 1});
    const auto rotated_x = sub(times(pin_arm[u], cosine), times(local_y, sine));
    const auto rotated_y = add(times(pin_arm[u], sine), times(local_y, cosine));
    require(rotated_x == fraction(p.radius * p.clocking.cosine, p.clocking.scale) && rotated_y == fraction(p.radius * p.clocking.sine, p.clocking.scale), "rotating the real pin arm back by the carrier angle recovers the one initial clocking");
    const auto tip = difference(r.pin, origin); I nx = -p.clocking.sine, ny = p.clocking.scale + p.clocking.cosine;
    if (!nx && !ny) { nx = p.clocking.scale - p.clocking.cosine; ny = -p.clocking.sine; }
    require(add(times(tip[u], {nx, 1}), times(tip[v], {handed * ny, 1})) == F{}, "all real pin positions lie on the clocking-dependent diameter, including the vertical degeneracy");
    require(add(times(r.pin_per_input_radian[u], {nx, 1}), times(r.pin_per_input_radian[v], {handed * ny, 1})) == F{}, "pin velocity stays on that same line");
    require(r.pin[a] == F{p.origin[a], 1} && r.center[a] == r.pin[a] && r.contact[a] == r.pin[a] && r.pin_per_input_radian[a] == F{}, "proper 3D mounting retains the shaft plane");
    bool guide = true; for (std::size_t i = 0; i < 3; ++i) guide = guide && r.pin[i].numerator >= p.lower[i] * r.pin[i].denominator && r.pin[i].numerator <= p.upper[i] * r.pin[i].denominator;
    require(guide == r.guide_fits, "finite guide acceptance follows actual rational pin position");
}

void frames_and_clockings() {
    const std::array<n::Direction, 16> rays{{{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}, {3, 4, 5}, {3, -4, 5}, {-3, 4, 5}, {-4, -3, 5},
        {5, 12, 13}, {12, -5, 13}, {8, 15, 17}, {33, 56, 65}, {95, 168, 193}, {95, -168, 193}, {-209, 120, 241}, {209, -120, 241}}};
    const std::array<g::Motion, 6> sources{{moving(), moving({-1, 2}), moving({7, 11}), {}, {g::MotionState::stopped, {}}, {g::MotionState::stalled, {}}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        for (const auto origin : {g::Point{0, 0, 8}, {-23, 17, 31}}) for (I radius : std::array<I, 4>{1, 4, 17, n::maximum_radius}) for (const auto clock : rays) {
            n::Profile p; p.origin = origin; p.shaft = static_cast<g::Axis>(a); p.span = static_cast<g::Axis>(u); p.radius = radius; p.clocking = clock;
            p.lower = {-9000, -9000, -9000}; p.upper = {9000, 9000, 9000};
            const auto cycle = std::get<n::Cycle>(n::inspect(p)); require(cycle.profile == p && cycle.guide_fits, "whole cycle retains profile and full generous guide");
            for (std::size_t i = 0; i < 3; ++i) {
                const auto& low = cycle.bounds[i][0]; const auto& high = cycle.bounds[i][1];
                require(low.branch == s::Branch::negative && high.branch == s::Branch::positive && low.base == high.base && low.radicand == high.radicand && low.denominator == high.denominator, "whole-axis extrema preserve both exact radical signs");
                if (i == a) { require(std::get<std::optional<F>>(s::rational_view(low)) == std::optional<F>{F{p.origin[i], 1}}, "shaft coordinate has zero stroke"); continue; }
                const I first = i == u ? clock.scale + clock.cosine : clock.sine;
                const I second = i == u ? clock.sine : clock.scale - clock.cosine;
                require(low.radicand == radius * radius * (first * first + second * second) && low.denominator == clock.scale && low.base == origin[i] * clock.scale, "independent row-vector norm supplies whole-axis stroke amplitude");
            }
            for (const auto ray : rays) for (const auto input : sources) {
                const auto current = std::get<n::Sample>(n::sample(p, ray, input));
                require(current.profile == p && current.direction == ray && current.carrier == input, "one caller phase and native source state remain exact and owned");
                actual_vectors(current); ++observations;
            }
            ++profiles;
        }
    }
}

void whole_stroke_and_admission() {
    n::Profile p; p.clocking = {0, 1, 1}; p.lower = {-5, -5, 8}; p.upper = {5, 5, 8};
    for (const auto ray : {n::Direction{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}}) require(std::get<n::Sample>(n::sample(p, ray, moving())).guide_fits, "four quarter poses all fit the diagonal fixture");
    require(!std::get<n::Cycle>(n::inspect(p)).guide_fits && !std::get<n::Sample>(n::sample(p, {3, 4, 5}, moving())).guide_fits, "four fitting snapshots miss the exact irrational full-stroke overtravel");
    const auto oblique = std::get<n::Cycle>(n::inspect(p)); require(!std::get<std::optional<F>>(s::rational_view(oblique.bounds[0][1])), "oblique full-stroke extrema retain an irrational coordinate");
    p = {}; p.radius = 5; require(std::get<n::Cycle>(n::inspect(p)).guide_fits, "inclusive guide endpoints admit exact whole-stroke contact");
    p.upper[0] = 9; require(!std::get<n::Cycle>(n::inspect(p)).guide_fits, "one grid unit of finite overtravel cannot pass");
    p = {}; p.ring_locked = false;
    require(refused(n::sample(p, {}, {}), n::Error::unconstrained_ring) && std::get<n::Refusal>(n::inspect(p)).reason == n::Error::unconstrained_ring, "a free ring supplies neither a pin phase nor a complete stroke");
    require(refused(n::sample(p, {}, moving({1, 0})), n::Error::invalid_rate), "a free ring cannot hide malformed source rates");
    require(refused(n::sample(p, {1, 1, 1}, {}), n::Error::invalid_direction), "free or unpowered inputs still validate their caller direction");
    for (const auto rate : {F{std::numeric_limits<I>::max(), std::numeric_limits<I>::max()}, {-4, 8}}) {
        const auto sample = std::get<n::Sample>(n::sample({}, {}, moving(rate)));
        require(sample.carrier.rate == (rate.numerator > 0 ? F{1, 1} : F{-1, 2}) && sample.planet.rate == neg(sample.carrier.rate), "normalize rates before reversing absolute planet spin");
    }
    for (const auto d : {n::Direction{0, 0, 1}, {2, 0, 2}, {1, 1, 1}, {1, 0, 0}, {1, 0, 257}, {std::numeric_limits<I>::min(), 0, 1}}) {
        require(refused(n::sample({}, d, {}), n::Error::invalid_direction), "raw input directions reject before products");
        p = {}; p.clocking = d; require(refused(n::sample(p, {}, {}), n::Error::invalid_clocking), "raw initial clockings validate independently");
    }
    for (const auto rate : {F{1, 0}, {1, -1}, {std::numeric_limits<I>::min(), 1}, {1, 1000001}, {std::numeric_limits<I>::max(), 1}})
        require(refused(n::sample({}, {}, moving(rate)), n::Error::invalid_rate), "raw native rate extrema reject before arithmetic");
    for (const auto state : {g::Motion{g::MotionState::rotating, {}}, {g::MotionState::stopped, {1, 2}}, {g::MotionState::stalled, {1, 2}}, {static_cast<g::MotionState>(99), {}}})
        require(refused(n::sample({}, {}, state), n::Error::invalid_motion), "native state/rate inconsistencies never become motion");
    for (int variant = 0; variant < 7; ++variant) {
        p = {};
        if (variant == 0) p.radius = 0;
        if (variant == 1) p.radius = 2049;
        if (variant == 2) p.radius = std::numeric_limits<I>::min();
        if (variant == 3) p.pin_id = p.ring_id;
        if (variant == 4) p.planet_id = 0;
        if (variant == 5) p.origin[0] = std::numeric_limits<I>::max();
        if (variant == 6) p.lower[1] = p.upper[1] + 1;
        require(refused(n::sample(p, {}, {}), n::Error::invalid_profile) && std::get<n::Refusal>(n::inspect(p)).reason == n::Error::invalid_profile, "complete raw assembly and guide guards precede products");
    }
    p = {}; p.shaft = p.span; require(refused(n::sample(p, {}, {}), n::Error::invalid_axes), "nonproper plane rejects");
    p.span = static_cast<g::Axis>(99); require(refused(n::sample(p, {}, {}), n::Error::invalid_axes), "raw invalid axis rejects");
    p = {}; p.origin[0] = g::maximum_coordinate - 1; require(refused(n::sample(p, {-1, 0, 1}, {}), n::Error::representation_limit), "entire pitch-circle grid bounds validate even when a current inward pose would fit");
    p.origin = {g::maximum_coordinate - 4096, 0, 8}; p.radius = 2048; p.clocking = {-209, 120, 241}; p.lower = {-1000000, -1000000, -1000000}; p.upper = {1000000, 1000000, 1000000};
    require(std::get<n::Cycle>(n::inspect(p)).guide_fits, "extreme whole pitch-circle fits exactly against the native grid boundary");
    for (I q = 1; q <= 256; ++q) for (I x = -q; x <= q; ++x) for (I y = -q; y <= q; ++y) {
        if (x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1) continue;
        actual_vectors(std::get<n::Sample>(n::sample(p, {x, y, q}, moving()))); ++chart_cases;
    }
    const auto original = std::get<n::Sample>(n::sample({}, {}, moving())); auto changed = original; changed.pin[0] = {999, 1}; changed.profile.radius = 1;
    require(std::get<n::Sample>(n::sample({}, {}, moving())).pin == original.pin && changed.pin != original.pin, "no shared mutable sample or phase state exists");
}

void consumers() {
    struct Case { std::vector<std::string_view> args; int exit; bool won; const char* needle; };
    const std::array<Case, 21> cases{{
        {{{"standard", "slow", "full"}}, 0, true, "Absolute planet rotating -1/2"},
        {{{"standard", "reverse", "full"}}, 0, true, "Absolute planet rotating 1/2"},
        {{{"long-stroke", "slow", "full"}}, 0, true, "Goal matched:"},
        {{{"long-stroke", "reverse", "full"}}, 0, true, "Goal matched:"},
        {{{"short-stroke", "slow", "full"}}, 0, false, "Goal unfinished:"},
        {{{"tilted", "slow", "full"}}, 0, false, "complete stroke exceeds"},
        {{{"vertical", "slow", "full"}}, 0, false, "complete stroke exceeds"},
        {{{"shifted", "slow", "full"}}, 0, false, "Goal unfinished:"},
        {{{"standard", "slow", "short"}}, 0, false, "Carrier unpowered"},
        {{{"long-stroke", "slow", "short"}}, 0, false, "Carrier unpowered"},
        {{{"standard", "fast", "full"}}, 0, false, "Carrier rotating 5/2"},
        {{{"standard", "stalled", "full"}}, 0, false, "Absolute planet stalled"},
        {{{"standard", "off", "full"}}, 0, false, "Carrier unpowered"},
        {{{"free-ring", "slow", "full"}}, 2, false, "unconstrained_ring"},
        {{{"near-edge", "slow", "full"}}, 2, false, "representation_limit"},
        {{{"bad-clocking", "slow", "full"}}, 2, false, "invalid_clocking"},
        {{{"bogus", "slow", "full"}}, 2, false, "Unknown"},
        {{{"standard", "bogus", "full"}}, 2, false, "Unknown"},
        {{{"standard", "slow", "bogus"}}, 2, false, "Choose"},
        {{{"standard"}}, 2, false, "Choose"},
        {{{"list"}}, 0, false, "Every pin clocking produces a line"}
    }};
    for (const auto& c : cases) {
        std::ostringstream out, error;
        require(n::workbench(c.args, out, error) == c.exit, "consumer exit status is explicit");
        require((out.str().find("Goal matched:") != std::string::npos) == c.won, "only complete powered fixed-ring solutions win");
        require((out.str() + error.str()).find(c.needle) != std::string::npos, "specific geometry or source failure remains visible"); ++traces;
    }
}
int main() {
    frames_and_clockings(); whole_stroke_and_admission(); consumers();
    std::cout << checks << " Tusi assertions passed; profiles=" << profiles << " observations=" << observations
        << " bounded_circle_chart=" << chart_cases << " consumer_traces=" << traces << ".\n";
}
