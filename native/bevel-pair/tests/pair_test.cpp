#include "factory/bevel_pair.hpp"
#include "factory/bevel_pair_workbench.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace b = factory::bevel_pair;
namespace g = factory::mechanics;
namespace c = factory::clearance;
namespace k = factory::geared_cycle;
using I = g::Integer;
namespace {
std::size_t assertions{}, witnesses{}, source_arrangements{}, caller_traces{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
g::Rate fraction(I n, I d = 1) {
    if (d < 0) { n = -n; d = -d; }
    const auto divisor = std::gcd(n, d);
    return {n / divisor, d / divisor};
}
g::Motion motion(g::Rate rate) { return {rate.numerator ? g::MotionState::rotating : g::MotionState::stopped, rate}; }
bool refused(const b::Result& result, b::Error error) {
    const auto* value = std::get_if<b::Refusal>(&result);
    return value && value->reason == error;
}
g::Point tangent(const b::Gear& gear, const g::Point& contact) {
    g::Point unit{}, radius{};
    unit[static_cast<std::size_t>(gear.axis)] = 1;
    for (std::size_t axis = 0; axis < 3; ++axis) radius[axis] = contact[axis] - gear.center[axis];
    return {unit[1] * radius[2] - unit[2] * radius[1], unit[2] * radius[0] - unit[0] * radius[2], unit[0] * radius[1] - unit[1] * radius[0]};
}
// Independent world-space rolling-contact witness: (omega_a e_a) x r_a
// equals (omega_b e_b) x r_b. No production mounting sign or spur solver.
g::Rate velocity_oracle(const b::Gear& a, const b::Gear& d, const g::Point& contact, g::Rate input) {
    const auto va = tangent(a, contact), vb = tangent(d, contact);
    for (std::size_t axis = 0; axis < 3; ++axis) if (vb[axis]) return fraction(input.numerator * va[axis], input.denominator * vb[axis]);
    require(false, "test contact has a nonzero tangential direction");
    return {};
}
c::Box circle_apex_bounds(const b::Gear& gear, const g::Point& apex) {
    c::Box result{apex, apex};
    // Enumerate cardinal extrema of the outer pitch circle and the common
    // apex. Their convex hull is the ideal cone, so these bound its full turn.
    for (std::size_t axis = 0; axis < 3; ++axis) if (axis != static_cast<std::size_t>(gear.axis)) for (I sign : {-1, 1}) {
        auto rim = gear.center;
        rim[axis] += sign * gear.teeth;
        for (std::size_t coordinate = 0; coordinate < 3; ++coordinate) {
            result.minimum[coordinate] = std::min(result.minimum[coordinate], rim[coordinate]);
            result.maximum[coordinate] = std::max(result.maximum[coordinate], rim[coordinate]);
        }
    }
    return result;
}

void world_velocity_witnesses() {
    const std::array<I, 6> teeth{1, 2, 3, 5, 8, 13};
    const std::array<g::Point, 3> origins{{{}, {71, -53, 29}, {-82, 64, -37}}};
    const std::array<g::Rate, 5> rates{{{0, 1}, {1, 1}, {-1, 1}, {3, 5}, {-2, 3}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t d = 0; d < 3; ++d) if (a != d)
    for (I sa : {-1, 1}) for (I sd : {-1, 1}) for (auto za : teeth) for (auto zd : teeth) for (auto origin : origins) {
        b::Gear first{7, origin, static_cast<g::Axis>(a), za}, second{std::numeric_limits<b::Id>::max(), origin, static_cast<g::Axis>(d), zd};
        first.center[a] += sa * zd;
        second.center[d] += sd * za;
        auto contact = origin;
        contact[a] += sa * zd;
        contact[d] += sd * za;
        const auto no_power = std::get<b::Evaluation>(b::evaluate(first, second, {}));
        require(no_power.motion[0].state == g::MotionState::unpowered && no_power.motion[1].state == g::MotionState::unpowered &&
            !no_power.prescribed[0] && !no_power.prescribed[1], "missing power is not a stopped/locked bevel pair");
        require(no_power.geometry.apex == origin && no_power.geometry.contact == contact && no_power.geometry.gears == std::array<b::Gear, 2>{first, second},
            "all axis orders and mounting sides return owned descriptors, common apex and actual contact");
        require(no_power.geometry.pitch_bounds == std::array<c::Box, 2>{circle_apex_bounds(first, origin), circle_apex_bounds(second, origin)},
            "ideal cone boxes agree with independent apex and outer-rim extrema");
        require(no_power.geometry.second_from_first == velocity_oracle(first, second, contact, {1, 1}), "global signed ratio agrees with cross-product velocities");
        for (auto rate : rates) {
            const auto other = velocity_oracle(first, second, contact, rate);
            const auto va = tangent(first, contact), vb = tangent(second, contact);
            for (std::size_t coordinate = 0; coordinate < 3; ++coordinate)
                require(rate.numerator * va[coordinate] * other.denominator == other.numerator * vb[coordinate] * rate.denominator,
                    "all three tangential velocity components agree exactly");
            const std::array<b::Drive, 1> drive_first{{{first.id, rate}}}, drive_second{{{second.id, other}}};
            const auto powered_a = std::get<b::Evaluation>(b::evaluate(first, second, drive_first));
            const auto powered_d = std::get<b::Evaluation>(b::evaluate(first, second, drive_second));
            require(powered_a.motion == std::array<g::Motion, 2>{motion(rate), motion(other)} && powered_d.motion == powered_a.motion,
                "either real gear can be the prescribed source without changing global motion");
            const auto swapped = std::get<b::Evaluation>(b::evaluate(second, first, drive_first));
            require(swapped.motion[0] == powered_a.motion[1] && swapped.motion[1] == powered_a.motion[0] && swapped.geometry.contact == contact && swapped.geometry.apex == origin,
                "argument order and opaque ID sorting cannot choose direction or topology");
            const std::array<b::Drive, 2> consistent{{{second.id, {2 * other.numerator, 2 * other.denominator}}, {first.id, {2 * rate.numerator, 2 * rate.denominator}}}};
            const auto observed = std::get<b::Evaluation>(b::evaluate(first, second, consistent));
            require(observed.motion == powered_a.motion && observed.prescribed[0] == rate && observed.prescribed[1] == other,
                "compatible observations normalize independently of input order");
            auto conflict = consistent;
            conflict[0].rate = fraction(other.numerator + other.denominator, other.denominator);
            const auto blocked = std::get<b::Evaluation>(b::evaluate(first, second, conflict));
            require(blocked.motion == std::array<g::Motion, 2>{{{g::MotionState::stalled, {}}, {g::MotionState::stalled, {}}}} && blocked.prescribed[1] == conflict[0].rate,
                "incompatible observations retain their prescription and stall the entire native pair");
            ++witnesses;
            source_arrangements += 5;
        }
    }
}

void validation_and_limits() {
    const b::Gear first{7, {24, 32, 0}, g::Axis::x, 24}, second{11, {0, 56, 0}, g::Axis::y, 24};
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    const std::array<b::Drive, 1> drive{{{7, {1, 1}}}};
    for (std::size_t member = 0; member < 2; ++member) {
        const auto invalid = [&](b::Gear bad) { return member ? b::evaluate(first, bad, drive) : b::evaluate(bad, second, drive); };
        auto bad = member ? second : first;
        bad.id = 0;
        require(refused(invalid(bad), b::Error::invalid_gear), "zero gear ID is rejected before topology");
        for (auto axis : {-1, 3, 99}) {
            bad = member ? second : first;
            bad.axis = static_cast<g::Axis>(axis);
            require(refused(invalid(bad), b::Error::invalid_gear), "axis enum is checked before coordinate indexing");
        }
        for (I teeth : {low, I{-1}, I{0}, I{4097}, high}) {
            bad = member ? second : first;
            bad.teeth = teeth;
            require(refused(invalid(bad), b::Error::invalid_gear), "raw dimension extrema refuse before arithmetic");
        }
        for (std::size_t axis = 0; axis < 3; ++axis) for (I coordinate : {low, I{-1000001}, I{1000001}, high}) {
            bad = member ? second : first;
            bad.center[axis] = coordinate;
            require(refused(invalid(bad), b::Error::invalid_gear), "raw coordinate extrema refuse before subtracting centers");
        }
    }
    auto bad = second;
    bad.id = first.id;
    require(refused(b::evaluate(first, bad, drive), b::Error::duplicate_id), "duplicate descriptor IDs are never merged");
    bad = second; bad.axis = g::Axis::x;
    require(refused(b::evaluate(first, bad, drive), b::Error::not_right_angle), "ordinary parallel spur geometry is outside the explicit bevel contract");
    for (I offset : {-1, 1}) {
        bad = second; bad.center[2] += offset;
        require(refused(b::evaluate(first, bad, drive), b::Error::skew_axes), "perpendicular directions alone do not establish intersecting axes");
        for (std::size_t axis : {0U, 1U}) {
            bad = second; bad.center[axis] += offset;
            require(refused(b::evaluate(first, bad, drive), b::Error::pitch_mismatch), "outer pitch circles must share the same cone generator");
        }
    }
    const std::array<b::Drive, 3> excessive{{drive[0], {11, {-1, 1}}, {7, {1, 1}}}};
    require(refused(b::evaluate(first, second, excessive), b::Error::too_many_drives), "excessive complete drive input cannot be truncated");
    for (b::Id unknown : {b::Id{0}, b::Id{9}, std::numeric_limits<b::Id>::max()}) {
        const std::array<b::Drive, 2> values{{drive[0], {unknown, {1, 1}}}};
        require(refused(b::evaluate(first, second, values), b::Error::unknown_gear), "last unknown observation refuses all results");
    }
    const std::array<b::Drive, 2> duplicate{{drive[0], drive[0]}};
    require(refused(b::evaluate(first, second, duplicate), b::Error::duplicate_drive), "repeated observations do not silently replace one another");
    for (g::Rate rate : {g::Rate{0, 0}, {1, -1}, {0, low}, {low, 1}, {high, 1}, {1, 1000001}, {257, 1}}) {
        const std::array<b::Drive, 2> values{{drive[0], {11, rate}}};
        require(refused(b::evaluate(first, second, values), b::Error::invalid_rate), "every raw rate is admitted even after a valid source");
    }
    auto negative_mount = first; negative_mount.center[0] = -24;
    std::array<b::Drive, 1> extreme{{{7, {low, I{1} << 62}}}};
    const auto owned = std::get<b::Evaluation>(b::evaluate(negative_mount, second, extreme));
    negative_mount.center = {}; extreme[0].rate = {0, 1};
    require(owned.geometry.gears[0].center == g::Point{-24, 32, 0} && owned.prescribed[0] == g::Rate{-2, 1} && owned.motion[1] == motion({-2, 1}),
        "INT64_MIN is reduced before outward-axis negation, and every returned value is owned");
    const std::array<b::Drive, 2> huge_reducible{{{7, {high, high}}, {11, {-1, 1}}}};
    require(std::get<b::Evaluation>(b::evaluate(first, second, huge_reducible)).motion[0] == motion({1, 1}), "large raw reducible rates retain native admission");
    auto near_bound_a = first, near_bound_d = second;
    for (I side : {-1, 1}) {
        near_bound_a.center[2] = near_bound_d.center[2] = side * (g::maximum_coordinate - 24);
        require(std::holds_alternative<b::Evaluation>(b::evaluate(near_bound_a, near_bound_d, drive)), "full cone exactly touching the grid boundary fits");
        near_bound_a.center[2] += side; near_bound_d.center[2] += side;
        const auto refusal = std::get<b::Refusal>(b::evaluate(near_bound_a, near_bound_d, drive));
        require(refusal.reason == b::Error::representation_limit && refusal.envelope_error == c::Error::invalid_box,
            "valid raw centers cannot admit an expanded cone outside the existing grid");
    }
    const b::Gear large_a{7, {1, 0, 0}, g::Axis::x, 256}, small_d{11, {0, 256, 0}, g::Axis::y, 1};
    require(std::get<b::Evaluation>(b::evaluate(large_a, small_d, drive)).motion[1] == motion({-256, 1}), "exact inferred native speed limit is preserved");
    auto faster_a = large_a, faster_d = small_d;
    faster_a.teeth = 257; faster_d.center[1] = 257;
    const auto speed = std::get<b::Refusal>(b::evaluate(faster_a, faster_d, drive));
    require(speed.reason == b::Error::unsupported_result && speed.subject == 11 && speed.rate_error == k::Error::rate_limit,
        "one unsupported inferred speed refuses the whole bevel result");
    const b::Gear tiny_a{7, {4096, 0, 0}, g::Axis::x, 1}, huge_d{11, {0, 1, 0}, g::Axis::y, 4096};
    const std::array<b::Drive, 1> precise{{{7, {1, 999983}}}};
    require(refused(b::evaluate(tiny_a, huge_d, precise), b::Error::unsupported_result), "inferred denominator cannot be silently rounded below the clock cap");
    const std::array<b::Drive, 2> contradictory{{{7, {256, 1}}, {11, {256, 1}}}};
    require(std::get<b::Evaluation>(b::evaluate(faster_a, faster_d, contradictory)).motion[0].state == g::MotionState::stalled,
        "native contradictory-source stall remains a stall even when one isolated inference would be unsupported");

    // Boundary of reuse: the native spur API still rejects perpendicular mesh
    // by leaving separate components, rather than borrowing this new adapter.
    const std::vector<g::Part> ordinary{
        {"a", g::Kind::hub, first.center, first.axis}, {"sa", g::Kind::shaft, first.center, first.axis, 0, 1}, {"ga", g::Kind::gear, first.center, first.axis, first.teeth},
        {"d", g::Kind::hub, second.center, second.axis}, {"sd", g::Kind::shaft, second.center, second.axis, 0, 1}, {"gd", g::Kind::gear, second.center, second.axis, second.teeth},
    };
    const auto spur = g::evaluate(ordinary, {{"a", {1, 1}}});
    require(spur.accepted() && spur.motion.at("d").state == g::MotionState::unpowered &&
        std::none_of(spur.engagements.begin(), spur.engagements.end(), [](const auto& edge) { return edge.kind == g::EngagementKind::external_mesh; }),
        "existing perpendicular ordinary spur descriptors never gain an implicit bevel edge");
}

void caller() {
    struct Case { std::array<std::string_view, 3> args; std::string_view witness; bool matched{}; };
    const std::array<Case, 18> cases{{
        {{{"upper", "reverse", "full"}}, "half-span 4; readout rotating 1/2", true},
        {{{"lower", "slow", "full"}}, "half-span 28; readout rotating 1/2", true},
        {{{"reduction", "fast", "full"}}, "second/first 1/5", true},
        {{{"upper", "slow", "full"}}, "readout rotating -1/2"},
        {{{"lower", "reverse", "full"}}, "readout rotating -1/2"},
        {{{"upper", "fast", "full"}}, "readout rotating -5/2"},
        {{{"reduction", "slow", "full"}}, "readout rotating 1/10"},
        {{{"low", "reverse", "full"}}, "gear 7 pitch envelope overlaps floor 99"},
        {{{"low", "slow", "short"}}, "gear 7 pitch envelope overlaps floor 99"},
        {{{"upper", "reverse", "short"}}, "half-span 1; readout unpowered 0/1"},
        {{{"lower", "slow", "short"}}, "half-span 1; readout unpowered 0/1"},
        {{{"reduction", "fast", "short"}}, "half-span 1; readout unpowered 0/1"},
        {{{"upper", "off", "full"}}, "source unpowered; no output drive is admitted"},
        {{{"lower", "stalled", "full"}}, "source stalled; no output drive is admitted"},
        {{{"skew", "slow", "full"}}, "skew_axes"},
        {{{"pitch-miss", "slow", "full"}}, "pitch_mismatch"},
        {{{"parallel", "reverse", "full"}}, "not_right_angle"},
        {{{"lower", "fast", "full"}}, "readout rotating 5/2"},
    }};
    for (const auto& example : cases) {
        std::ostringstream out, errors;
        require(b::workbench(example.args, out, errors) == 0 && errors.str().empty(), "valid original puzzle recipe produces an actual consumer trace");
        require(out.str().find(example.witness) != std::string::npos && (out.str().find("Goal matched.") != std::string::npos) == example.matched,
            "source orientation, floor, signed ratio and actual shaft connectivity determine the goal");
        if (example.witness.find("floor") != std::string_view::npos || example.args[1] == "off" || example.args[1] == "stalled")
            require(out.str().find("Bevel output:") == std::string::npos, "unadmitted or unavailable source power never publishes an output drive");
        ++caller_traces;
    }
    const std::array<std::vector<std::string_view>, 6> invalid{{{"upper"}, {"upper", "slow"}, {"upper", "slow", "full", "extra"},
        {"missing", "slow", "full"}, {"upper", "missing", "full"}, {"upper", "slow", "missing"}}};
    for (const auto& args : invalid) {
        std::ostringstream out, errors;
        require(b::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().empty(), "invalid argv refuses before any mechanical proposal");
    }
    std::ostringstream list, errors;
    const std::array<std::string_view, 1> args{"list"};
    require(b::workbench(args, list, errors) == 0 && list.str().find("pitch envelopes") != std::string::npos, "catalogue states the ideal geometry boundary");
    list.setstate(std::ios::badbit);
    require(b::workbench(args, list, errors) == 2, "broken output stream cannot be a successful trace");
}
}  // namespace

int main() {
    world_velocity_witnesses();
    validation_and_limits();
    caller();
    std::cout << assertions << " assertions; " << witnesses << " independent world tangential-velocity witnesses; "
        << source_arrangements << " source arrangements; " << caller_traces << " original native caller traces passed.\n";
}
