#include "factory/geneva_drive.hpp"
#include "factory/geneva_drive_workbench.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace n = factory::geneva_drive;
namespace s = factory::slider_crank;
namespace g = factory::mechanics;
namespace k = factory::geared_cycle;
using I = g::Integer;
using F = g::Rate;
namespace {
std::size_t assertions{}, profiles{}, observations{}, constrained{}, unconstrained{}, traces{}, chart_cases{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
F fraction(I numerator, I denominator = 1) {
    if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
    const auto divisor = std::gcd(numerator, denominator); return {numerator / divisor, denominator / divisor};
}
F add(F a, F b) { return fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator); }
F scale(F a, I multiplier) { return fraction(a.numerator * multiplier, a.denominator); }
F multiply(F a, F b) { return fraction(a.numerator * b.numerator, a.denominator * b.denominator); }
F divide(F a, F b) { require(b.numerator != 0, "independent angular constraint has a nonzero radial denominator"); return fraction(a.numerator * b.denominator, a.denominator * b.numerator); }
F dot(const n::Point& a, const n::Point& b) { F result{}; for (std::size_t i = 0; i < 3; ++i) result = add(result, multiply(a[i], b[i])); return result; }
n::Point cross(const n::Point& a, const n::Point& b) {
    n::Point result{}; for (std::size_t i = 0; i < 3; ++i) result[i] = add(multiply(a[(i + 1) % 3], b[(i + 2) % 3]), scale(multiply(a[(i + 2) % 3], b[(i + 1) % 3]), -1)); return result;
}
g::Motion moving(F rate = {1, 2}) { return {g::MotionState::rotating, rate}; }
template<class T> bool refused(const T& value, n::Error reason) { const auto* error = std::get_if<n::Refusal>(&value); return error && error->reason == reason; }
// Exact independent Q(sqrt(3)) arithmetic for entry/exit and seam continuity.
struct Q { F plain{}, root{}; bool operator==(const Q&) const = default; };
Q plus(Q a, Q b) { return {add(a.plain, b.plain), add(a.root, b.root)}; }
Q times(Q a, Q b) { return {add(multiply(a.plain, b.plain), scale(multiply(a.root, b.root), 3)), add(multiply(a.plain, b.root), multiply(a.root, b.plain))}; }
Q scaled(Q a, I value) { return {scale(a.plain, value), scale(a.root, value)}; }
Q decode(const s::Coordinate& coordinate, I radius) {
    Q result{fraction(coordinate.base, coordinate.denominator), {}};
    if (coordinate.radicand) {
        require(coordinate.radicand == 3 * radius * radius, "boundary root retains an exact sqrt(3) coefficient without an invented rational value");
        result.root = fraction((coordinate.branch == s::Branch::positive ? 1 : -1) * radius, coordinate.denominator);
    }
    return result;
}

void pin_slot_and_velocity() {
    const std::array<n::Direction, 20> directions{{{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}, {3, 4, 5}, {3, -4, 5}, {-3, 4, 5}, {-3, -4, 5},
        {4, 3, 5}, {4, -3, 5}, {5, 12, 13}, {12, 5, 13}, {8, 15, 17}, {15, -8, 17}, {33, 56, 65}, {33, -56, 65}, {95, 168, 193}, {95, -168, 193}, {209, 120, 241}, {-209, -120, 241}}};
    const std::array<g::Motion, 6> sources{{moving(), moving({-1, 2}), moving({-7, 11}), {}, {g::MotionState::stopped, {}}, {g::MotionState::stalled, {}}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        const auto v = 3 - a - u;
        const I handed = (a + 1) % 3 == u ? 1 : -1;
        for (const auto origin : {g::Point{0, 0, 8}, {-23, 17, 31}}) for (I radius : {2, 6, 10}) for (std::size_t variant = 0; variant < 4; ++variant) {
            n::Profile p; p.origin = origin; p.shaft = static_cast<g::Axis>(a); p.span = static_cast<g::Axis>(u); p.radius = radius; p.slot_inner = radius - 1; p.slot_outer = 2 * radius;
            if (variant == 1) p.slot_outer = 2 * radius - 1;
            if (variant == 2) p.slot_inner = radius + 1;
            if (variant == 3) p.dwell_lock = false;
            const auto cycle = std::get<n::Cycle>(n::inspect(p));
            require(cycle.profile == p && cycle.slot_covers == (p.slot_inner <= radius && p.slot_outer * p.slot_outer >= 3 * radius * radius) && cycle.complete() == (cycle.slot_covers && p.dwell_lock), "whole finite-slot coverage and declared lock remain separate from current engagement");
            require(cycle.index_fraction == F{1, 3} && cycle.dwell_fraction == F{2, 3} && cycle.step_per_positive_turn == F{-1, 6}, "six-slot inspection keeps nonuniform indexing and dwell fractions explicit");
            std::array<std::array<Q, 2>, 2> edges{};
            for (std::size_t edge = 0; edge < 2; ++edge) {
                edges[edge] = {decode(cycle.boundary_rays[edge][u], radius), scaled(decode(cycle.boundary_rays[edge][v], radius), handed)};
                const auto& ray = edges[edge]; const auto pin_u = plus(ray[0], Q{fraction(2 * radius), {}}), pin_v = ray[1];
                require(plus(times(pin_u, pin_u), times(pin_v, pin_v)) == Q{fraction(radius * radius), {}}, "irrational entry/exit lies exactly on the independent crank circle");
                require(plus(times(ray[0], ray[0]), times(ray[1], ray[1])) == Q{fraction(cycle.maximum_radius_squared), {}}, "exact boundary rays attain the full active radial maximum");
                require(plus(times(ray[0], pin_u), times(ray[1], pin_v)) == Q{}, "entry/exit pin radius is perpendicular to the slot, so actual pin velocity has zero angular output");
                require(!std::get<std::optional<F>>(s::rational_view(cycle.boundary_rays[edge][v])), "irrational boundary coordinates never receive a rounded rational phase");
            }
            const Q cosine{F{1, 2}, {}}, sine{{}, F{1, 2}};
            const auto rotated_u = plus(times(cosine, edges[1][0]), scaled(times(sine, edges[1][1]), -1));
            const auto rotated_v = plus(times(sine, edges[1][0]), times(cosine, edges[1][1]));
            require(rotated_u == edges[0][0] && rotated_v == edges[0][1], "outgoing ray rotated +60 degrees is the next incoming slot ray, preserving the same physical wheel at the caller-owned seam");
            auto turns = edges[0];
            for (std::size_t turn = 0; turn < 6; ++turn) turns = {plus(times(cosine, turns[0]), scaled(times(sine, turns[1]), -1)), plus(times(sine, turns[0]), times(cosine, turns[1]))};
            require(turns == edges[0], "six exact slot permutations close without a floating angle or hidden phase counter");
            for (const auto direction : directions) for (std::uint32_t slot = 0; slot < 6; ++slot) for (const auto input : sources) {
                const n::Frame frame{direction, slot}; const auto sample = std::get<n::Sample>(n::sample(p, frame, input));
                n::Point from_driver{}, from_wheel{}, normal{}; normal[a] = {1, 1};
                for (std::size_t i = 0; i < 3; ++i) { from_driver[i] = add(sample.pin[i], fraction(-p.origin[i])); from_wheel[i] = add(sample.pin[i], fraction(-sample.wheel[i])); }
                require(sample.profile == p && sample.frame == frame && sample.input == input, "owned observations preserve the one caller frame, supplied slot identity and distinct native source state");
                require(dot(from_driver, from_driver) == fraction(radius * radius) && from_driver[a] == F{}, "independent three-dimensional pin geometry retains crank length and shaft plane");
                const auto distance_squared = dot(from_wheel, from_wheel);
                require(distance_squared == sample.pin_distance_squared, "actual vector distance, not a copied phase formula, supplies the finite radial test");
                const bool active = 2 * from_driver[u].numerator > radius * from_driver[u].denominator;
                const bool fits = distance_squared.numerator >= p.slot_inner * p.slot_inner * distance_squared.denominator && distance_squared.numerator <= p.slot_outer * p.slot_outer * distance_squared.denominator;
                require(sample.radial_fits == fits && (sample.stage == n::Stage::indexing) == active, "physical pin projection and true radial distance independently determine engagement and fit");
                const bool constrained_now = active ? fits : p.dwell_lock;
                require(sample.constraint.has_value() == constrained_now, "a missed finite slot or absent dwell lock cannot manufacture an output constraint");
                if (!active) require(sample.stage == (handed * from_driver[v].numerator < 0 || (from_driver[v].numerator == 0 && from_driver[u].numerator < 0) ? n::Stage::incoming_dwell : n::Stage::outgoing_dwell), "the canonical negative-X seam and proper signed frame distinguish both dwells");
                if (sample.constraint) {
                    const auto& constraint = *sample.constraint; F ratio{};
                    if (active) {
                        const auto pin_velocity = cross(normal, from_driver), angular = cross(from_wheel, pin_velocity);
                        ratio = divide(angular[a], distance_squared);
                        require(ratio.numerator < 0 && -ratio.numerator <= ratio.denominator, "independent pin/slot velocity has opposite sense and finite magnitude at most one");
                        for (std::size_t i = 0; i < 3; ++i) require(std::get<std::optional<F>>(s::rational_view(constraint.slot_ray[i])) == std::optional<F>{from_wheel[i]}, "engaged ray is the actual wheel-relative pin direction");
                    } else require(constraint.slot_ray == cycle.boundary_rays[sample.stage == n::Stage::incoming_dwell ? 0 : 1], "locked dwell holds the exact endpoint direction instead of following the withdrawn pin");
                    require(constraint.per_input_radian == ratio, "actual 3D pin/slot velocity constraint independently derives the nonlinear angular ratio");
                    const auto rate = multiply(input.rate, ratio); auto state = input.state;
                    if (state == g::MotionState::rotating && rate.numerator == 0) state = g::MotionState::stopped;
                    require(constraint.output == g::Motion{state, rate}, "conditional output preserves unavailable/stopped/stalled source semantics and explicit zero locked dwell");
                    ++constrained;
                } else ++unconstrained;
                ++observations;
            }
            ++profiles;
        }
    }
}

void boundaries_raw_and_chart() {
    n::Profile p;
    const auto mid = std::get<n::Sample>(n::sample(p, {}, moving()));
    require(mid.constraint->output.rate == F{-1, 2} && mid.constraint->per_input_radian == F{-1, 1}, "the native mid-index output reverses input, without claiming constant output");
    p.slot_outer = 17;
    require(std::get<n::Sample>(n::sample(p, {}, moving())).radial_fits && !std::get<n::Cycle>(n::inspect(p)).slot_covers &&
        !std::get<n::Sample>(n::sample(p, {{33, 56, 65}, 0}, moving())).constraint, "a fitting midpoint cannot conceal the actual finite-slot miss near tangential entry");
    p = {}; p.dwell_lock = false;
    require(std::get<n::Sample>(n::sample(p, {}, moving())).constraint.has_value() && !std::get<n::Sample>(n::sample(p, {{0, 1, 1}, 0}, moving())).constraint && !std::get<n::Cycle>(n::inspect(p)).complete(), "engagement alone never proves a physically held dwell");
    p = {};
    const auto before = std::get<n::Sample>(n::sample(p, {{95, 168, 193}, 5}, moving()));
    const auto after = std::get<n::Sample>(n::sample(p, {{33, 56, 65}, 5}, moving()));
    require(before.stage == n::Stage::outgoing_dwell && before.constraint->output.state == g::MotionState::stopped && after.stage == n::Stage::indexing && after.constraint->output.state == g::MotionState::rotating,
        "real primitive directions on opposite sides of cos=1/2 discriminate locked dwell from active indexing");
    for (I q = 1; q <= factory::scotch_yoke::maximum_direction_scale; ++q) for (I x = -q; x <= q; ++x) for (I y = -q; y <= q; ++y) {
        if (x * x + y * y != q * q || std::gcd(std::gcd(x, y), q) != 1) continue;
        for (const auto source : {moving(), moving({-1, 2})}) {
            const auto pose = n::sample(p, {{x, y, q}, 0}, source);
            require(std::holds_alternative<n::Sample>(pose) && std::get<n::Sample>(pose).constraint.has_value(), "the working kit supports BOTH half-speed sources through the entire bounded physical-circle chart, without an intermediate native precision hole");
            ++chart_cases;
        }
    }
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    for (std::size_t field = 0; field < 3; ++field) for (I value : {low, high, I{-1}, I{0}, g::maximum_dimension + 1}) {
        p = {}; if (field == 0) p.radius = value; else if (field == 1) p.slot_inner = value; else p.slot_outer = value;
        require(refused(n::sample(p, {}, moving()), n::Error::invalid_profile) && refused(n::inspect(p), n::Error::invalid_profile), "raw radial extrema refuse before subtraction, products or bounds");
    }
    p = {}; p.radius = n::maximum_radius + 1; require(refused(n::inspect(p), n::Error::invalid_profile), "the explicit 2R native dimension bound remains enforced");
    for (std::size_t field = 0; field < 3; ++field) { p = {}; p.origin[field] = low; require(refused(n::inspect(p), n::Error::invalid_profile), "every raw origin validates before geometry"); }
    for (std::size_t field = 0; field < 3; ++field) { p = {}; if (field == 0) p.driver_id = 0; else if (field == 1) p.wheel_id = 0; else p.wheel_id = p.driver_id;
        require(refused(n::inspect(p), n::Error::invalid_profile), "opaque driver and wheel identities remain distinct and nonzero"); }
    for (auto axis : {static_cast<g::Axis>(-1), static_cast<g::Axis>(3), g::Axis::z}) { p = {}; p.span = axis; require(refused(n::sample(p, {}, moving()), n::Error::invalid_axes), "invalid or parallel axes refuse before indexing"); }
    p = {};
    for (const std::uint32_t slot : {6U, std::numeric_limits<std::uint32_t>::max()}) require(refused(n::sample(p, {{}, slot}, moving()), n::Error::invalid_frame), "out-of-domain slot identities are not wrapped into a fictitious winding");
    for (const n::Direction direction : {n::Direction{low, 0, 1}, {high, 0, 1}, {0, low, 1}, {0, high, 1}, {1, 0, low}, {1, 0, high}, {1, 0, 0}, {1, 0, -1}, {2, 0, 2}, {1, 1, 1}, {1, 1, 2}, {255, 32, 257}})
        require(refused(n::sample(p, {direction, 0}, moving()), n::Error::invalid_direction), "malformed and rounded irrational endpoint directions refuse before squares/gcd");
    for (const F rate : {F{1, 0}, {0, -1}, {low, 1}, {high, 1}, {1, k::maximum_denominator + 1}, {257, 1}}) require(refused(n::sample(p, {}, moving(rate)), n::Error::invalid_rate), "raw native rate limits remain active before constrained output");
    require(refused(n::sample(p, {}, {static_cast<g::MotionState>(-1), {}}), n::Error::invalid_motion) && refused(n::sample(p, {}, moving({})), n::Error::invalid_motion), "unknown states and rotating zero refuse");
    for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled}) {
        require(refused(n::sample(p, {}, {state, {1, 1}}), n::Error::invalid_motion), "unavailable native states cannot carry nonzero speed");
        require(std::get<n::Sample>(n::sample(p, {}, {state, {0, high}})).constraint->output == g::Motion{state, {}}, "reducible zero retains each distinct native state");
    }
    for (const F rate : {F{high, high}, {low, I{1} << 62}}) {
        const F expected = rate.numerator == low ? F{2, 1} : F{-1, 1};
        require(std::get<n::Sample>(n::sample(p, {}, moving(rate))).constraint->output.rate == expected, "raw signed extrema reduce before nonlinear sign multiplication");
    }
    require(refused(n::sample(p, {{33, 56, 65}, 0}, moving({1, 1000000})), n::Error::unsupported_result), "an unsupported inferred denominator returns no partial pin/constraint result");
    p.origin[0] = g::maximum_coordinate - 20;
    require(refused(n::sample(p, {}, moving()), n::Error::representation_limit) && refused(n::inspect(p), n::Error::representation_limit), "both APIs keep the full declared pin/slot envelope inside the native grid");
    require(refused(n::sample(p, {}, {g::MotionState::unpowered, {1, 0}}), n::Error::invalid_rate), "bad unavailable source representation cannot hide behind a geometric refusal");
    p = {}; p.radius = n::maximum_radius; p.slot_inner = 1; p.slot_outer = g::maximum_dimension;
    require(std::holds_alternative<n::Sample>(n::sample(p, {{209, 120, 241}, 5}, moving())) && std::get<n::Cycle>(n::inspect(p)).complete(), "maximum supported radius and slot retain exact coordinate/rate representation");
    auto owned = mid; owned.frame.slot = 5; owned.pin[0] = {99, 1};
    require(mid.frame.slot == 0 && mid.pin[0] != owned.pin[0] && std::get<n::Sample>(n::sample(n::Profile{}, {}, moving())).frame.slot == 0, "samples and future calls have no hidden mutable phase or wheel owner");
}

void consumers() {
    struct Case { std::string_view kit, source, shaft, finding; bool matched; int exit; };
    const std::array<Case, 24> cases{{
        {"standard", "slow", "full", "Goal matched:", true, 0}, {"standard", "reverse", "full", "Goal matched:", true, 0},
        {"compact", "slow", "full", "Goal matched:", true, 0}, {"compact", "reverse", "full", "Goal matched:", true, 0},
        {"short-slot", "slow", "full", "full active radial range", false, 0}, {"inner-miss", "slow", "full", "pin misses", false, 0},
        {"no-lock", "slow", "full", "inactive wheel free", false, 0}, {"shifted", "slow", "full", "readout unpowered", false, 0},
        {"short-input", "slow", "full", "source unpowered", false, 0}, {"standard", "slow", "short", "readout unpowered", false, 0},
        {"compact", "slow", "short", "readout unpowered", false, 0}, {"standard", "reverse", "short", "readout unpowered", false, 0},
        {"standard", "fast", "full", "speed magnitude 1/2", false, 0}, {"compact", "fast", "full", "speed magnitude 1/2", false, 0},
        {"standard", "off", "full", "source unpowered", false, 0}, {"standard", "stalled", "full", "source stalled", false, 0},
        {"compact", "off", "full", "source unpowered", false, 0}, {"compact", "stalled", "full", "source stalled", false, 0},
        {"no-lock", "off", "full", "inactive wheel free", false, 0}, {"short-slot", "off", "full", "full active radial range", false, 0},
        {"near-edge", "slow", "full", "representation_limit", false, 2}, {"near-edge", "off", "full", "representation_limit", false, 2},
        {"bad-slot", "slow", "full", "invalid_frame", false, 2}, {"bad-slot", "off", "full", "invalid_frame", false, 2},
    }};
    for (const auto& test : cases) {
        const std::array args{test.kit, test.source, test.shaft}; std::ostringstream out, errors;
        require(n::workbench(args, out, errors) == test.exit, "the actual native Geneva consumer returns the declared trace/refusal status");
        require((out.str() + errors.str()).find(test.finding) != std::string::npos && (out.str().find("Goal matched:") != std::string::npos) == test.matched, "complete slot/lock geometry and real source/readout connectivity decide the original indexing goal");
        require(test.exit == 2 ? !errors.str().empty() : errors.str().empty(), "valid unfinished assembly differs from native/frame refusal");
        if (test.matched) require(out.str().find("locked dwell output stopped") != std::string::npos && out.str().find("no constant output is claimed") != std::string::npos, "actual midpoint rate and separately declared dwell cannot masquerade as uniform transmission");
        if (test.kit == "short-slot") require(out.str().find("Mid-index radial slot fit yes") != std::string::npos, "the real caller exposes the misleading fitting midpoint and still rejects the cycle");
        ++traces;
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{}, {"list"}, {"--help"}}) {
        std::ostringstream out, errors; require(n::workbench(args, out, errors) == 0 && errors.str().empty() && out.str().find("Exact irrational boundary") != std::string::npos, "catalogue states the exact boundary chart and physical-adoption limits");
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{"bogus", "slow", "full"}, {"standard", "bogus", "full"}, {"standard", "slow", "bogus"}, {"standard"}, {"standard", "slow"}, {"standard", "slow", "full", "extra"}, {"list", "extra"}}) {
        std::ostringstream out, errors; require(n::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().find("Goal matched:") == std::string::npos, "malformed callers cannot publish an indexing setup match");
    }
    std::ostringstream out, errors; out.setstate(std::ios::badbit);
    const std::array<std::string_view, 3> args{"standard", "slow", "full"};
    require(n::workbench(args, out, errors) == 2, "an unwritable transcript is not a successful observation");
}
}  // namespace

int main() {
    pin_slot_and_velocity(); boundaries_raw_and_chart(); consumers();
    std::cout << "PASS " << assertions << " assertions; " << profiles << " geometry profiles; " << observations << " source/frame observations; " << constrained << " constrained; " << unconstrained
        << " unconstrained; " << chart_cases << " complete-chart half-speed cases; " << traces << " consumer traces.\n";
}
