#include "factory/oldham_pair.hpp"
#include "factory/oldham_pair_workbench.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace o = factory::oldham_pair;
namespace g = factory::mechanics;
namespace c = factory::clearance;
namespace k = factory::geared_cycle;
using I = g::Integer;
using F = g::Rate;
namespace {
std::size_t assertions{}, profiles{}, intersections{}, caller_traces{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
F fraction(I n, I d = 1) {
    require(d != 0, "independent rational oracle has a nonzero denominator");
    if (d < 0) { n = -n; d = -d; }
    const auto divisor = std::gcd(n, d);
    return {n / divisor, d / divisor};
}
F add(F a, F b) { return fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator); }
F scale(F a, I b) { return fraction(a.numerator * b, a.denominator); }
F square(F a) { return fraction(a.numerator * a.numerator, a.denominator * a.denominator); }
g::Motion moving(F rate = {1, 2}) { return {g::MotionState::rotating, rate}; }
bool refused(const o::Reading& value, o::Error reason) {
    const auto* error = std::get_if<o::Refusal>(&value);
    return error && error->reason == reason;
}
bool turn_refused(const o::TurnPlan& value, o::Error reason, std::optional<c::Error> geometry = {}) {
    const auto* error = std::get_if<o::Refusal>(&value);
    return error && error->reason == reason && error->geometry_error == geometry;
}
const std::array<c::Obstacle, 1> post{{{99, {{2, -8, 1}, {6, -6, 3}}}}};

void line_intersections() {
    const std::array<g::Point, 3> origins{{{0, 0, 0}, {-42, 17, -20}, {73, -52, 91}}};
    const std::array<std::array<I, 2>, 7> offsets{{{0, 0}, {8, 0}, {-8, 0}, {0, -6}, {3, 4}, {-5, 7}, {11, -9}}};
    const std::array<g::Motion, 5> motions{{moving(), moving({-7, 11}), {g::MotionState::unpowered, {}}, {g::MotionState::stopped, {}}, {g::MotionState::stalled, {}}}};
    for (std::size_t axis = 0; axis < 3; ++axis) for (const auto origin : origins)
    for (const auto d : offsets) for (I gap : {-6, -3, 2, 8}) {
        o::Profile p;
        p.input = {4001, origin, static_cast<g::Axis>(axis)};
        p.output = {97, origin, p.input.axis};
        const auto u = (axis + 1) % 3, v = (axis + 2) % 3;
        p.output.center[axis] += gap; p.output.center[u] += d[0]; p.output.center[v] += d[1];
        p.input_travel = p.output_travel = 32;
        ++profiles;
        for (I x = -6; x <= 6; ++x) for (I y = -6; y <= 6; ++y) if (std::gcd(x, y) == 1) {
            // Solve the two lines by Cramer's rule, not by the production
            // projection formula. input + t*(x,y) = output + s*(-y,x).
            const I vx = -y, vy = x, determinant = x * vy - y * vx;
            const F t = fraction(d[0] * vy - d[1] * vx, determinant);
            const F s = fraction(d[0] * y - d[1] * x, determinant);
            const F cu = add(fraction(origin[u]), scale(t, x));
            const F cv = add(fraction(origin[v]), scale(t, y));
            require(cu == add(fraction(p.output.center[u]), scale(s, vx)) && cv == add(fraction(p.output.center[v]), scale(s, vy)),
                "independent line intersection lies on both perpendicular slots");
            const F midu = fraction(origin[u] + p.output.center[u], 2), midv = fraction(origin[v] + p.output.center[v], 2);
            const F ru = add(cu, scale(midu, -1)), rv = add(cv, scale(midv, -1));
            require(add(square(ru), square(rv)) == fraction(d[0] * d[0] + d[1] * d[1], 4),
                "intersection centre lies on the midpoint circle with half the shaft offset as radius");
            for (const auto input : motions) {
                const auto reading = o::sample(p, {x, y}, input);
                require(std::holds_alternative<o::Sample>(reading), "bounded independent line intersection is representable");
                const auto& sample = std::get<o::Sample>(reading);
                require(sample.profile == p && sample.dial == o::Dial{x, y}, "owned descriptors and signed caller dial survive unchanged");
                require(sample.centre[u] == cu && sample.centre[v] == cv && sample.centre[axis] == fraction(origin[axis] + p.output.center[axis], 2),
                    "all three native axes and translated signed offsets match the independent line solve");
                require(sample.travel_squared == std::array<F, 2>{scale(square(t), determinant), scale(square(s), determinant)} &&
                    add(sample.travel_squared[0], sample.travel_squared[1]) == fraction(d[0] * d[0] + d[1] * d[1]),
                    "the two physical slide distances partition the complete squared offset");
                require(sample.centre_per_radian[u] == scale(rv, -2) && sample.centre_per_radian[v] == scale(ru, 2) && sample.centre_per_radian[axis] == F{},
                    "geometric derivative is twice the angular cross product about the midpoint, independent of source rate units");
                require(sample.rotation == std::array<g::Motion, 3>{input, input, input},
                    "disc and output spin stay 1:1 without confusing the centre's twice-frequency orbit");
            }
            ++intersections;
        }
    }
}

void complete_turns() {
    o::Profile p;
    const auto whole = std::get<o::Turn>(o::prepare_turn(p, post));
    require(!whole.admitted() && whole.travel_fits == std::array<bool, 2>{true, true} && whole.clearance.hit && whole.clearance.hit->obstacle == 99,
        "the wide disc is continuously obstructed although both full-turn slot limits fit exactly");
    for (const o::Dial dial : {o::Dial{1, 0}, {0, 1}, {-1, 0}, {0, -1}}) {
        const auto s = std::get<o::Sample>(o::sample(p, dial, moving()));
        c::Box box;
        for (std::size_t a = 0; a < 3; ++a) {
            require(s.centre[a].denominator == 1, "quarter-stop fixture centres are exact integers");
            const I extent = a == 2 ? p.half_thickness : p.disc_radius;
            box.minimum[a] = s.centre[a].numerator - extent;
            box.maximum[a] = s.centre[a].numerator + extent;
        }
        require(c::sweep(box, {}, post).clear(), "all four sampled quarter-turn stops miss the post");
    }
    const auto between = std::get<o::Sample>(o::sample(p, {-1, 1}, moving()));
    require(between.centre == o::Point{F{4, 1}, F{-4, 1}, F{2, 1}}, "a missed 135-degree input pose places the actual circular body beside the post");
    const I nearest_x = std::clamp<I>(4, post[0].box.minimum[0], post[0].box.maximum[0]);
    const I nearest_y = std::clamp<I>(-4, post[0].box.minimum[1], post[0].box.maximum[1]);
    require((4 - nearest_x) * (4 - nearest_x) + (-4 - nearest_y) * (-4 - nearest_y) < p.disc_radius * p.disc_radius &&
        2 - p.half_thickness < post[0].box.maximum[2] && 2 + p.half_thickness > post[0].box.minimum[2],
        "a strict circle/rectangle and axial overlap proves a real disc hit, beyond the conservative box proxy");
    p.disc_radius = 1;
    require(std::get<o::Turn>(o::prepare_turn(p, post)).admitted(), "the compact disc clears continuously");
    p.disc_radius = 3; p.input.center[0] = 16;
    require(std::get<o::Turn>(o::prepare_turn(p, post)).admitted(), "routing the larger disc on the other side is a distinct complete-turn solution");
    for (std::size_t a = 0; a < 3; ++a) for (I dx : {-8, 0, 6}) for (I dy : {-6, 0, 8}) {
        p = {};
        p.input.axis = p.output.axis = static_cast<g::Axis>(a);
        p.input.center = {-30, 44, -16}; p.output.center = p.input.center;
        p.output.center[a] += 4; p.output.center[(a + 1) % 3] += dx; p.output.center[(a + 2) % 3] += dy;
        for (I limit : {1, 7, 8, 10}) {
            p.input_travel = limit; p.output_travel = 10;
            const auto turn = std::get<o::Turn>(o::prepare_turn(p, {}));
            require(turn.travel_fits[0] == (dx * dx + dy * dy <= limit * limit) && turn.travel_fits[1] == (dx * dx + dy * dy <= 100),
                "continuous slot admission matches the analytic maximum in each translated native axis");
            require(turn.clearance.clear() && turn.admitted() == (dx * dx + dy * dy <= limit * limit && dx * dx + dy * dy <= 100),
                "slot refusal does not masquerade as a geometry-query error or an adopted partial turn");
        }
    }
    for (bool input_slot : {false, true}) {
        p = {}; p.disc_radius = 1;
        (input_slot ? p.input_travel : p.output_travel) = 7;
        require(std::holds_alternative<o::Sample>(o::sample(p, {1, 1}, moving())), "a travel-seven slot fits the initial diagonal pose");
        const auto turn = std::get<o::Turn>(o::prepare_turn(p, post));
        require(!turn.admitted() && !turn.travel_fits[input_slot ? 0 : 1] && turn.clearance.clear(),
            "the same finite slot cannot complete the turn despite a clear compact body");
        const auto boundary = o::sample(p, input_slot ? o::Dial{1, 0} : o::Dial{0, 1}, moving());
        require(refused(boundary, input_slot ? o::Error::outside_input_slot : o::Error::outside_output_slot), "a later pose witnesses the full-turn slot failure");
    }
    p = {};
    std::vector<c::Obstacle> obstacles{post[0], {13, post[0].box}};
    const auto selected = std::get<o::Turn>(o::prepare_turn(p, obstacles));
    std::reverse(obstacles.begin(), obstacles.end());
    require(selected.clearance == std::get<o::Turn>(o::prepare_turn(p, obstacles)).clearance && selected.clearance.hit->obstacle == 13,
        "opaque obstruction identity is deterministic and never called the earliest impact");
    p.input_travel = 1;
    obstacles.push_back({0, post[0].box});
    require(turn_refused(o::prepare_turn(p, obstacles), o::Error::query_refused, c::Error::invalid_id), "a known slot/body failure cannot hide a malformed last obstacle");
    obstacles.back().id = 13;
    require(turn_refused(o::prepare_turn(p, obstacles), o::Error::query_refused, c::Error::duplicate_id), "duplicate final obstacle identities refuse the entire proposal");
    obstacles.back().id = 777; obstacles.back().box.minimum[0] = obstacles.back().box.maximum[0];
    require(turn_refused(o::prepare_turn(p, obstacles), o::Error::query_refused, c::Error::invalid_box), "invalid final obstacle boxes refuse without a partial hit");
    obstacles.assign(g::maximum_parts + 1, post[0]);
    require(turn_refused(o::prepare_turn(p, obstacles), o::Error::query_refused, c::Error::too_many_obstacles), "oversized obstacle input is never truncated");
}

void raw_and_owned() {
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    const g::Motion powered = moving();
    for (auto bad : {low, high, -g::maximum_coordinate - 1, g::maximum_coordinate + 1}) for (std::size_t axis = 0; axis < 3; ++axis) {
        o::Profile p; p.output.center[axis] = bad;
        require(refused(o::sample(p, {1, 1}, powered), o::Error::invalid_port) && turn_refused(o::prepare_turn(p, {}), o::Error::invalid_port),
            "raw coordinate extrema refuse before any subtraction or multiplication");
    }
    for (auto bad : {low, high, I{0}, I{-1}, g::maximum_dimension + 1}) for (unsigned field = 0; field < 4; ++field) {
        o::Profile p;
        *std::array<I*, 4>{&p.input_travel, &p.output_travel, &p.disc_radius, &p.half_thickness}[field] = bad;
        require(refused(o::sample(p, {1, 1}, powered), o::Error::invalid_profile) && turn_refused(o::prepare_turn(p, {}), o::Error::invalid_profile),
            "every raw dimension is checked before bounded geometry");
    }
    for (auto which : {0, 1}) {
        o::Profile p; auto& port = which ? p.output : p.input; port.id = 0;
        require(refused(o::sample(p, {1, 1}, powered), o::Error::invalid_port), "both caller identities must be positive");
        port.id = 543; port.axis = static_cast<g::Axis>(-1);
        require(turn_refused(o::prepare_turn(p, {}), o::Error::invalid_port), "invalid signed axis values refuse");
    }
    o::Profile p; p.output.id = p.input.id;
    require(refused(o::sample(p, {1, 1}, powered), o::Error::duplicate_id), "duplicate opaque ports do not create a self link");
    p = {}; p.output.axis = g::Axis::x;
    require(refused(o::sample(p, {1, 1}, powered), o::Error::not_parallel), "perpendicular shafts cannot silently become an Oldham pair");
    for (I gap : {-1, 0, 1}) { p = {}; p.output.center[2] = gap;
        require(turn_refused(o::prepare_turn(p, {}), o::Error::axial_gap), "axial space must fit the declared disc thickness"); }
    p = {};
    for (const o::Dial dial : {o::Dial{0, 0}, {2, 2}, {65, 1}, {1, -65}, {low, 1}, {1, high}})
        require(refused(o::sample(p, dial, powered), o::Error::invalid_dial), "primitive signed raw dials are bounded before gcd and products");
    for (const F rate : {F{1, 0}, {0, -1}, {low, 1}, {high, 1}, {1, k::maximum_denominator + 1}, {257, 1}})
        require(refused(o::sample(p, {1, 1}, moving(rate)), o::Error::invalid_rate), "unsupported native rates refuse without rounding");
    require(refused(o::sample(p, {1, 1}, {g::MotionState::unpowered, {1, 0}}), o::Error::invalid_rate), "bad rates are validated even while unpowered");
    require(refused(o::sample(p, {1, 1}, {static_cast<g::MotionState>(-1), {}}), o::Error::invalid_motion), "unknown motion state refuses");
    for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled}) {
        require(refused(o::sample(p, {1, 1}, {state, {1, 1}}), o::Error::invalid_motion), "nonrotating native states cannot carry nonzero prescribed speed");
        const auto s = std::get<o::Sample>(o::sample(p, {-1, -1}, {state, {0, high}}));
        require(s.rotation[2] == g::Motion{state, {}}, "zero is normalized while preserving each native nonrotating state");
    }
    require(refused(o::sample(p, {1, 1}, moving({0, 1})), o::Error::invalid_motion), "rotating zero is not an invented fourth zero-speed state");
    for (const auto raw : {F{high, high}, F{low, I{1} << 62}, F{256, 1}, F{-256, 1}, F{1, k::maximum_denominator}}) {
        const auto s = std::get<o::Sample>(o::sample(p, {63, 64}, moving(raw)));
        const auto normal = raw.numerator == low ? F{-2, 1} : fraction(raw.numerator, raw.denominator);
        require(s.rotation[0] == moving(normal) && s.rotation[2] == moving(normal), "reducible raw extrema normalize before native bounds and remain 1:1");
    }
    p.output.center[2] = 5;
    require(std::get<o::Sample>(o::sample(p, {1, 1}, powered)).centre[2] == F{5, 2} && turn_refused(o::prepare_turn(p, {}), o::Error::representation_limit),
        "a rational current centre is supported while an unrepresentable integer-grid full-turn proxy refuses rather than rounds");
    p = {}; p.output.center[0] = 9; p.input_travel = p.output_travel = 10;
    require(std::holds_alternative<o::Sample>(o::sample(p, {1, 1}, powered)) && turn_refused(o::prepare_turn(p, {}), o::Error::representation_limit),
        "fractional transverse midpoint is a proxy limit rather than a false clearance claim");
    p = {}; p.input.center[0] = g::maximum_coordinate - 8; p.output.center[0] = g::maximum_coordinate;
    require(turn_refused(o::prepare_turn(p, {}), o::Error::representation_limit, c::Error::invalid_box), "initial proxy outside the finite grid refuses");
    p = {}; p.input.center[0] = g::maximum_coordinate - 9; p.output.center[0] = g::maximum_coordinate - 1; p.disc_radius = 1;
    require(turn_refused(o::prepare_turn(p, {}), o::Error::representation_limit, c::Error::invalid_motion), "a valid initial box cannot hide a full-turn orbit escaping the grid");
    p = {}; p.input.center[0] = p.output.center[0] = g::maximum_coordinate; p.output.center[1] = 8;
    require(refused(o::sample(p, {1, 1}, powered), o::Error::representation_limit), "even a derived rational centre must stay inside bounded coordinates");
    p = {};
    const auto saved = std::get<o::Sample>(o::sample(p, {3, -5}, powered));
    std::vector<c::Obstacle> observations(post.begin(), post.end());
    const auto turn = std::get<o::Turn>(o::prepare_turn(p, observations));
    p.output.center = {}; observations[0].id = 1; observations.clear();
    require(saved.profile == o::Profile{} && saved.dial == o::Dial{3, -5} && turn.profile == o::Profile{} && turn.clearance.hit->obstacle == 99,
        "samples and proposals own their observations after caller inputs mutate or disappear");
    const std::vector<g::Part> ordinary{{"a", g::Kind::hub, {0, 0, 0}, g::Axis::z}, {"as", g::Kind::shaft, {0, 0, 2}, g::Axis::z, 0, 8},
        {"b", g::Kind::hub, {8, 0, 4}, g::Axis::z}, {"bs", g::Kind::shaft, {8, 0, 2}, g::Axis::z, 0, 8}};
    const auto native = g::evaluate(ordinary, {{"a", {1, 2}}});
    require(native.accepted() && native.motion.at("a") == powered && native.motion.at("b").state == g::MotionState::unpowered,
        "ordinary offset native shafts remain disconnected without explicit proposed coupling adoption");
}

void consumers() {
    struct Case { std::string_view kit, source, shaft, finding; bool matched; int exit; };
    const std::array<Case, 20> cases{{
        {"compact", "slow", "full", "Goal matched.", true, 0}, {"other-side", "slow", "full", "Goal matched.", true, 0},
        {"wide", "slow", "full", "overlaps post 99", false, 0}, {"short-input", "slow", "full", "input slot fits this pose", false, 0},
        {"short-output", "slow", "full", "output slot fits this pose", false, 0}, {"compact", "slow", "short", "readout unpowered", false, 0},
        {"shifted", "slow", "full", "readout unpowered", false, 0}, {"parallel-miss", "slow", "full", "not_parallel", false, 0},
        {"gap", "slow", "full", "axial_gap", false, 0}, {"compact", "reverse", "full", "readout rotating -1/2", false, 0},
        {"compact", "fast", "full", "readout rotating 5/2", false, 0}, {"compact", "stalled", "full", "source stalled", false, 0},
        {"compact", "off", "full", "source unpowered", false, 0}, {"other-side", "reverse", "full", "readout rotating -1/2", false, 0},
        {"other-side", "fast", "full", "readout rotating 5/2", false, 0}, {"other-side", "stalled", "full", "source stalled", false, 0},
        {"other-side", "off", "full", "source unpowered", false, 0}, {"other-side", "slow", "short", "readout unpowered", false, 0},
        {"half-grid", "slow", "full", "representation_limit", false, 2}, {"half-grid", "off", "full", "representation_limit", false, 2},
    }};
    for (const auto& test : cases) {
        const std::array args{test.kit, test.source, test.shaft};
        std::ostringstream out, errors;
        require(o::workbench(args, out, errors) == test.exit, "original fixture returns its declared observation/refusal status");
        const auto transcript = out.str() + errors.str();
        require(transcript.find(test.finding) != std::string::npos && (out.str().find("Goal matched.") != std::string::npos) == test.matched,
            "actual source geometry, complete slots/body and readout shaft decide the puzzle");
        require(test.exit == 2 ? !errors.str().empty() : errors.str().empty(), "caller refusal and valid unfinished traces use separate error channels");
        ++caller_traces;
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{}, {"list"}, {"--help"}}) {
        std::ostringstream out, errors;
        require(o::workbench(args, out, errors) == 0 && errors.str().empty() && out.str().find("twice per input") != std::string::npos,
            "catalogue explains centre orbit and complete-turn admission without a live phase claim");
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{"bogus", "slow", "full"}, {"compact", "bogus", "full"},
        {"compact", "slow", "bogus"}, {"compact"}, {"compact", "slow"}, {"compact", "slow", "full", "extra"}, {"list", "extra"}}) {
        std::ostringstream out, errors;
        require(o::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().find("Goal matched.") == std::string::npos,
            "malformed argv refuses before any victory result");
    }
    std::ostringstream failed, errors; failed.setstate(std::ios::badbit);
    const std::array<std::string_view, 3> args{"compact", "slow", "full"};
    require(o::workbench(args, failed, errors) == 2, "an unwritable observation stream is not a successful trace");
}
}  // namespace

int main() {
    line_intersections(); complete_turns(); raw_and_owned(); consumers();
    std::cout << "PASS " << assertions << " assertions; " << profiles << " profiles; " << intersections << " independent line intersections; "
        << caller_traces << " consumer traces.\n";
}
