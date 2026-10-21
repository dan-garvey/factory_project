#include "factory/crank_clamp.hpp"
#include "factory/crank_clamp_workbench.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace c = factory::crank_clamp;
namespace s = factory::slider_crank;
namespace g = factory::mechanics;
namespace k = factory::geared_cycle;
using I = g::Integer;
using F = g::Rate;
namespace {
std::size_t assertions{}, profiles{}, poses{}, unreachable{}, traces{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
F fraction(I n, I d = 1) { const auto divisor = std::gcd(n, d); return {n / divisor, d / divisor}; }
F add(F a, F b) { return fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator); }
F scale(F a, I n) { return fraction(a.numerator * n, a.denominator); }
F multiply(F a, F b) { return fraction(a.numerator * b.numerator, a.denominator * b.denominator); }
g::Motion moving(F rate = {1, 2}) { return {g::MotionState::rotating, rate}; }
const std::array<g::Motion, 2> powered{moving(), moving({-1, 2})};
template<class T> bool refused(const T& value, c::Error reason) {
    const auto* refusal = std::get_if<c::Refusal>(&value);
    return refusal && refusal->reason == reason;
}
long double numeric(const s::Coordinate& value) {
    return (value.base + (value.branch == s::Branch::positive ? 1 : -1) * std::sqrt(static_cast<long double>(value.radicand))) / value.denominator;
}

void two_rods_and_whole_cycle() {
    const std::array<c::Direction, 20> directions{{{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1},
        {3, 4, 5}, {-3, 4, 5}, {3, -4, 5}, {-3, -4, 5}, {4, 3, 5}, {-4, 3, 5}, {4, -3, 5}, {-4, -3, 5},
        {5, 12, 13}, {-5, 12, 13}, {5, -12, 13}, {-5, -12, 13}, {8, 15, 17}, {-8, -15, 17}, {20, -21, 29}, {209, 120, 241}}};
    const std::array<std::array<g::Motion, 2>, 6> sources{{powered, {moving({-7, 11}), moving({7, 11})},
        {g::Motion{}, g::Motion{}}, {g::Motion{g::MotionState::stalled, {}}, g::Motion{g::MotionState::stalled, {}}},
        {g::Motion{g::MotionState::stopped, {}}, g::Motion{g::MotionState::stopped, {}}}, {moving(), g::Motion{}}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        for (const auto origin : {g::Point{0, 0, 8}, {-42, 17, 36}}) for (I spacing : {9, 20})
        for (I radius : {1, 3, 5}) for (I length : {1, 2, 3, 5, 8}) for (auto clock : {c::Clocking::opposed, c::Clocking::same_reference}) {
            c::Profile p; p.origin = origin; p.shaft = static_cast<g::Axis>(a); p.travel = static_cast<g::Axis>(u);
            p.spacing = spacing; p.radius = radius; p.rod_length = length; p.clocking = clock;
            const auto cycle = std::get<c::Cycle>(c::inspect(p));
            const auto quarter = c::sample(p, {0, 1, 1}, powered);
            require(cycle.closed() == std::holds_alternative<c::Sample>(quarter), "a perpendicular rod observation independently witnesses whole-turn reach");
            require(cycle.gap_extrema.has_value() == cycle.closed(), "impossible cycles cannot invent gap bounds");
            require(cycle.centre.fixed() == (clock == c::Clocking::opposed), "only the opposed clocking has a whole-cycle fixed centre");
            for (std::size_t i = 0; i < 3; ++i) require(cycle.centre.reference[i] == (i == u ? fraction(2 * origin[i] + spacing, 2) : fraction(origin[i])), "odd pivot spacing retains an exact half-unit reference centre in every proper frame");
            if (cycle.closed()) {
                require(cycle.regular() == std::get<c::Sample>(quarter).jaws[0].per_radian.has_value(), "a regular cycle is distinct from a singular projection");
                const auto at_zero = std::get<c::Sample>(c::sample(p, {}, powered));
                const auto at_far = std::get<c::Sample>(c::sample(p, {-1, 0, 1}, powered));
                const auto& low = (*cycle.gap_extrema)[0];
                const auto& high = (*cycle.gap_extrema)[1];
                require(std::get<std::optional<F>>(s::rational_view(low)) == std::get<std::optional<F>>(s::rational_view(at_zero.gap)), "the minimum gap is attained by the independently solved collinear rods");
                if (clock == c::Clocking::opposed) require(std::get<std::optional<F>>(s::rational_view(high)) == std::get<std::optional<F>>(s::rational_view(at_far.gap)), "the opposed maximum gap is attained at the other collinear pose");
                else require(high == std::get<c::Sample>(quarter).gap, "the wrong-clock maximum retains the exact perpendicular nonsquare rod projection");
            }
            for (const auto d : directions) for (const auto& motions : sources) {
                const auto reading = c::sample(p, d, motions);
                if (std::holds_alternative<c::Refusal>(reading)) {
                    const auto failure = std::get<c::Refusal>(reading);
                    require(failure.reason == c::Error::parent_refused && failure.parent_error == s::Error::unreachable,
                        "only genuinely unreachable rod geometry refuses a bounded valid pose");
                    ++unreachable; continue;
                }
                const auto& pose = std::get<c::Sample>(reading);
                require(pose.profile == p && pose.direction == d, "the owned observation preserves caller setup and direction");
                require(pose.powered == (motions[0].state == g::MotionState::rotating && motions[1].state == g::MotionState::rotating), "an absent second crank never borrows remote power");
                for (std::size_t side = 0; side < 2; ++side) {
                    const auto& jaw = pose.jaws[side];
                    require(jaw.profile.crank_id == p.ids[2 * side] && jaw.profile.slider_id == p.ids[2 * side + 1] && jaw.crank == motions[side], "both opaque identities and distinct native source states reach their own parent observations");
                    require(jaw.slider.branch == (side ? s::Branch::negative : s::Branch::positive) && jaw.guide_fits, "explicit opposing branches stay inside the complete native guide");
                    F crank_square{}, rod_square = fraction(jaw.slider.radicand, jaw.slider.denominator * jaw.slider.denominator);
                    for (std::size_t i = 0; i < 3; ++i) {
                        const auto from_pivot = add(jaw.pin[i], fraction(-jaw.profile.origin[i]));
                        crank_square = add(crank_square, multiply(from_pivot, from_pivot));
                        if (i == u) require(add(fraction(jaw.slider.base, jaw.slider.denominator), scale(jaw.pin[i], -1)) == F{}, "longitudinal rod difference has only the exact root term");
                        else { const auto transverse = add(fraction(jaw.guide_anchor[i]), scale(jaw.pin[i], -1)); rod_square = add(rod_square, multiply(transverse, transverse)); }
                    }
                    require(crank_square == fraction(radius * radius) && rod_square == fraction(length * length), "independent three-dimensional pin and rod distances preserve both physical lengths exactly");
                    require(jaw.pin[a] == fraction(origin[a]), "pins retain the declared shaft plane without a mirrored fourth coordinate");
                }
                const auto& left = pose.jaws[0]; const auto& right = pose.jaws[1];
                require(left.slider.radicand == right.slider.radicand, "matched rods share their exact root magnitude");
                const auto left_base = fraction(left.slider.base, left.slider.denominator), right_base = fraction(right.slider.base, right.slider.denominator);
                const auto average = add(left_base, right_base);
                require(pose.centre[u] == fraction(average.numerator, 2 * average.denominator), "opposite root branches cancel in the exact average of the two independently solved working planes");
                for (std::size_t i = 0; i < 3; ++i) if (i != u) require(pose.centre[i] == fraction(origin[i]), "fixed guide coordinates survive the assembly composition");
                require(fraction(pose.gap.base, pose.gap.denominator) == add(right_base, scale(left_base, -1)) && pose.gap.radicand == 4 * left.slider.radicand && pose.gap.branch == s::Branch::negative,
                    "gap subtraction composes the two exact working planes without rounding or an independent root solver");
                const auto expected_centre = add(cycle.centre.reference[u], fraction(cycle.centre.cosine_coefficient * d.cosine, d.scale));
                require(pose.centre[u] == expected_centre, "every observed centre agrees with the whole-cycle coefficient, including wrong clocking");
                require(left.per_radian.has_value() == right.per_radian.has_value(), "both matched rods retain the same singular projection status");
                if (left.per_radian) {
                    require(left.per_radian->inverse_root == right.per_radian->inverse_root && left.per_radian->radicand == right.per_radian->radicand, "the root derivative cancels under the actual opposite-clock chain rule");
                    const auto difference = add(left.per_radian->direct, scale(right.per_radian->direct, -1));
                    require(difference == (clock == c::Clocking::opposed ? F{} : fraction(-2 * radius * d.sine, d.scale)), "parent local derivatives retain their own crank-angle units");
                }
                if (cycle.closed()) {
                    // Supplemental floating containment only; exact distances,
                    // centre cancellation and attained endpoint witnesses above
                    // establish the result without adopting a rounded coordinate.
                    const auto gap = numeric(pose.gap);
                    require(gap >= numeric((*cycle.gap_extrema)[0]) - 1e-11L && gap <= numeric((*cycle.gap_extrema)[1]) + 1e-11L, "bounded sampled gaps stay inside the exact whole-cycle endpoints");
                }
                ++poses;
            }
            ++profiles;
        }
    }
}

void discriminators_and_raw() {
    c::Profile p;
    const auto fixed = std::get<c::Cycle>(c::inspect(p));
    require(std::get<std::optional<F>>(s::rational_view((*fixed.gap_extrema)[0])) == std::optional<F>{{4, 1}} && std::get<std::optional<F>>(s::rational_view((*fixed.gap_extrema)[1])) == std::optional<F>{{16, 1}}, "the original working kit closes at four and opens to sixteen");
    p.clocking = c::Clocking::same_reference;
    require(std::get<c::Sample>(c::sample(p, {0, 1, 1}, powered)).centre[0] == F{10, 1} && !std::get<c::Cycle>(c::inspect(p)).centre.fixed(), "a centred quarter-turn snapshot cannot masquerade as a fixed work centre");
    require(std::get<c::Sample>(c::sample(p, {}, powered)).centre[0] == F{13, 1}, "another actual pose exposes the wrong reference mounting");
    p = {}; p.spacing = 1;
    require(std::get<s::Order>(s::compare_to_grid(std::get<c::Sample>(c::sample(p, {}, powered)).gap, 0)) == s::Order::less, "negative gap diagnoses reversed jaw order without inventing collision response");
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    for (std::size_t field = 0; field < 3; ++field) for (I value : {low, high, I{0}, I{-1}, g::maximum_dimension + 1}) {
        p = {}; if (field == 0) p.spacing = value; else if (field == 1) p.radius = value; else p.rod_length = value;
        require(refused(c::sample(p, {}, powered), c::Error::invalid_profile) && refused(c::inspect(p), c::Error::invalid_profile), "raw dimensions refuse before products, reflections or parent arithmetic");
    }
    for (std::size_t field = 1; field < 3; ++field) { p = {}; (field == 1 ? p.radius : p.rod_length) = c::maximum_arm + 1;
        require(refused(c::inspect(p), c::Error::invalid_profile), "the explicit radical adapter bound is enforced"); }
    for (std::size_t i = 0; i < 4; ++i) { p = {}; p.ids[i] = 0; require(refused(c::inspect(p), c::Error::invalid_profile), "every jaw/crank identity must be nonzero");
        for (std::size_t j = i + 1; j < 4; ++j) { p = {}; p.ids[j] = p.ids[i]; require(refused(c::sample(p, {}, powered), c::Error::invalid_profile), "cross-side duplicate identities cannot alias observations"); } }
    for (std::size_t i = 0; i < 3; ++i) for (I value : {low, high, -g::maximum_coordinate - 1, g::maximum_coordinate + 1}) { p = {}; p.origin[i] = value;
        require(refused(c::inspect(p), c::Error::invalid_profile), "raw origin extremes refuse before adding pivot spacing"); }
    p = {}; p.clocking = static_cast<c::Clocking>(-1); require(refused(c::inspect(p), c::Error::invalid_profile), "unknown mounting enums cannot silently select a branch");
    for (auto axis : {static_cast<g::Axis>(-1), static_cast<g::Axis>(3), g::Axis::z}) { p = {}; p.travel = axis;
        require(refused(c::sample(p, {}, powered), c::Error::invalid_axes), "invalid or parallel frame axes refuse before indexing"); }
    p = {}; p.shaft = static_cast<g::Axis>(3); require(refused(c::inspect(p), c::Error::invalid_axes), "invalid shaft enums refuse before indexing");
    p = {};
    for (const c::Direction d : {c::Direction{low, 0, 1}, {high, 0, 1}, {0, low, 1}, {0, high, 1}, {1, 0, low}, {1, 0, high}, {1, 0, 0}, {1, 0, -1}, {2, 0, 2}, {1, 1, 1}, {255, 32, 257}})
        require(refused(c::sample(p, d, powered), c::Error::invalid_direction), "raw physical directions refuse before unsafe negation, squares or gcd");
    for (std::size_t side = 0; side < 2; ++side) {
        p = {}; p.rod_length = 1; // The first rod is unreachable at the test direction.
        for (const F rate : {F{1, 0}, {0, -1}, {low, 1}, {high, 1}, {1, k::maximum_denominator + 1}, {257, 1}}) {
            auto inputs = powered; inputs[side] = moving(rate);
            const auto reading = c::sample(p, {0, 1, 1}, inputs);
            require(refused(reading, c::Error::invalid_rate) && std::get<c::Refusal>(reading).subject == p.ids[2 * side], "both native rates validate before an unreachable parent can conceal the second malformed source");
        }
        for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled, static_cast<g::MotionState>(-1)}) {
            auto inputs = powered; inputs[side] = {state, {1, 1}};
            require(refused(c::sample(p, {0, 1, 1}, inputs), c::Error::invalid_motion), "every unavailable or unknown state still rejects a contradictory nonzero rate before reach refusal");
        }
        auto inputs = powered; inputs[side] = moving({});
        require(refused(c::sample(p, {0, 1, 1}, inputs), c::Error::invalid_motion), "rotating zero does not become fabricated power");
        p = {};
        for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled}) {
            inputs = powered; inputs[side] = {state, {0, high}};
            const auto pose = std::get<c::Sample>(c::sample(p, {}, inputs));
            require(!pose.powered && pose.jaws[side].crank == g::Motion{state, {}}, "reducible zero preserves distinct native unpowered/stopped/stalled states");
        }
    }
    p = {};
    for (const auto inputs : {std::array{moving(), moving()}, std::array{moving(), moving({-1, 1})}})
        require(refused(c::sample(p, {}, inputs), c::Error::drive_mismatch), "same-sense or unequal opposite crank speeds cannot claim the declared mounting");
    const auto reduced = std::get<c::Sample>(c::sample(p, {}, {moving({high, high}), moving({-high, high})}));
    require(reduced.jaws[0].crank.rate == F{1, 1} && reduced.jaws[1].crank.rate == F{-1, 1}, "both raw rate extrema normalize before opposite-rate comparison");
    const auto minimum = std::get<c::Sample>(c::sample(p, {}, {moving({low, I{1} << 62}), moving({2, 1})}));
    require(minimum.jaws[0].crank.rate == F{-2, 1}, "minimum signed native rate reduces without unsafe signed absolute value");
    p.radius = c::maximum_arm; p.rod_length = c::maximum_arm; p.spacing = g::maximum_dimension;
    require(std::holds_alternative<c::Sample>(c::sample(p, {209, 120, 241}, powered)) && std::holds_alternative<c::Cycle>(c::inspect(p)), "largest supported radical products retain exact representation");
    p = {}; p.origin[0] = g::maximum_coordinate;
    require(refused(c::sample(p, {}, powered), c::Error::representation_limit) && refused(c::inspect(p), c::Error::representation_limit), "the derived right pivot cannot escape the native grid");
    p.origin[0] -= p.spacing;
    const auto boundary = c::inspect(p);
    require(refused(boundary, c::Error::parent_refused) && std::get<c::Refusal>(boundary).parent_error == s::Error::representation_limit && std::get<c::Refusal>(boundary).subject == p.ids[2], "a valid current pose cannot conceal a right crank leaving the grid later in its cycle");
}

void consumers() {
    struct Case { std::string_view kit, source, finding; bool matched; int exit; };
    const std::array<Case, 25> cases{{
        {"standard", "slow", "Goal matched.", true, 0}, {"standard", "reverse", "Goal matched.", true, 0},
        {"wide", "slow", "Goal matched.", true, 0}, {"wide", "reverse", "Goal matched.", true, 0},
        {"compact", "slow", "loading aperture is smaller", false, 0}, {"wrong-clock", "slow", "centre moves despite", false, 0},
        {"tight", "slow", "closed jaws miss", false, 0}, {"loose", "slow", "closed jaws miss", false, 0},
        {"singular", "slow", "zero rod projection", false, 0}, {"short-rod", "slow", "rods cannot close", false, 0},
        {"shifted", "slow", "fixed work centre", false, 0}, {"wrong-travel", "slow", "fixed work centre", false, 0},
        {"short-source", "slow", "left unpowered 0/1; right unpowered 0/1", false, 0},
        {"short-right", "slow", "left rotating 1/2; right unpowered 0/1", false, 0},
        {"wrong-gear", "slow", "left rotating 1/2; right unpowered 0/1", false, 0},
        {"standard", "fast", "speed magnitude must be 1/2", false, 0}, {"wide", "fast", "speed magnitude must be 1/2", false, 0},
        {"standard", "stalled", "left stalled 0/1; right stalled 0/1", false, 0}, {"standard", "off", "left unpowered 0/1; right unpowered 0/1", false, 0},
        {"wide", "stalled", "both crank hubs need", false, 0}, {"wide", "off", "both crank hubs need", false, 0},
        {"short-right", "reverse", "left rotating -1/2; right unpowered 0/1", false, 0}, {"wrong-gear", "reverse", "left rotating -1/2; right unpowered 0/1", false, 0},
        {"near-edge", "slow", "representation_limit", false, 2}, {"near-edge", "off", "representation_limit", false, 2},
    }};
    for (const auto& test : cases) {
        const std::array args{test.kit, test.source}; std::ostringstream out, errors;
        require(c::workbench(args, out, errors) == test.exit, "the actual native clamp caller returns the declared valid/refused status");
        require((out.str() + errors.str()).find(test.finding) != std::string::npos && (out.str().find("Goal matched.") != std::string::npos) == test.matched, "real gears, shafts, centre clocking and complete aperture decide the original puzzle");
        require(test.exit == 2 ? !errors.str().empty() : errors.str().empty(), "valid unfinished mechanisms remain separate from representation refusal");
        if (test.matched) require(out.str().find("sqrt(") != std::string::npos, "working kits expose an actual exact nonsquare gap");
        if (test.kit == "wrong-clock") require(out.str().find("Current centre: 10/1 0/1 8/1") != std::string::npos, "the misleading centred snapshot reaches the real caller and still cannot win");
        ++traces;
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{}, {"list"}, {"--help"}}) {
        std::ostringstream out, errors; require(c::workbench(args, out, errors) == 0 && errors.str().empty() && out.str().find("One centred snapshot") != std::string::npos, "the catalogue states the phase and physical-adoption limits");
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{"bogus", "slow"}, {"standard", "bogus"}, {"standard"}, {"standard", "slow", "extra"}, {"list", "extra"}}) {
        std::ostringstream out, errors; require(c::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().find("Goal matched.") == std::string::npos, "malformed callers cannot publish a successful clamp observation");
    }
    std::ostringstream out, errors; out.setstate(std::ios::badbit);
    const std::array<std::string_view, 2> args{"standard", "slow"};
    require(c::workbench(args, out, errors) == 2, "an unwritable transcript is not a successful observation");
}
}  // namespace

int main() {
    two_rods_and_whole_cycle(); discriminators_and_raw(); consumers();
    std::cout << "PASS " << assertions << " assertions; " << profiles << " cycle profiles; " << poses << " reachable source-state observations; "
        << unreachable << " unreachable observations; " << traces << " consumer traces.\n";
}
