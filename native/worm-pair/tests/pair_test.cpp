#include "factory/worm_pair.hpp"
#include "factory/worm_pair_workbench.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace w = factory::worm_pair;
namespace g = factory::mechanics;
namespace c = factory::clearance;
namespace k = factory::geared_cycle;
using I = g::Integer;
namespace {
std::size_t assertions{}, witnesses{}, arrangements{}, caller_traces{};
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
bool refused(const w::Result& result, w::Error error) {
    const auto* value = std::get_if<w::Refusal>(&result);
    return value && value->reason == error;
}
g::Point tangent(const w::Wheel& wheel, const g::Point& contact) {
    g::Point unit{}, radius{};
    unit[static_cast<std::size_t>(wheel.axis)] = 1;
    for (std::size_t axis = 0; axis < 3; ++axis) radius[axis] = contact[axis] - wheel.center[axis];
    return {unit[1] * radius[2] - unit[2] * radius[1], unit[2] * radius[0] - unit[0] * radius[2], unit[0] * radius[1] - unit[1] * radius[0]};
}
c::Box cylinder_extrema(const g::Point& center, std::size_t axis, I radius, I half_span) {
    c::Box result{center, center};
    for (I face : {-1, 1}) for (std::size_t radial = 0; radial < 3; ++radial) if (radial != axis) for (I side : {-1, 1}) {
        auto point = center;
        point[axis] += face * half_span;
        point[radial] += side * radius;
        for (std::size_t coordinate = 0; coordinate < 3; ++coordinate) {
            result.minimum[coordinate] = std::min(result.minimum[coordinate], point[coordinate]);
            result.maximum[coordinate] = std::max(result.maximum[coordinate], point[coordinate]);
        }
    }
    return result;
}

void thread_travel_witnesses() {
    const std::array<g::Point, 2> origins{{{}, {-71, 53, -29}}};
    const std::array<g::Rate, 4> rates{{{0, 1}, {1, 1}, {-1, 1}, {2, 3}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t b = 0; b < 3; ++b) if (a != b)
    for (I side : {-1, 1}) for (I pattern : {-1, 1}) for (I starts : {1, 2, 3, 5}) for (I teeth : {7, 12, 24, 47})
    for (I radius : {1, 4, 11}) for (auto origin : origins) for (I offset : {-1, 0, 1}) {
        const auto normal = 3 - a - b;
        w::Worm worm{7, origin, static_cast<g::Axis>(a), radius, 7, starts, static_cast<w::Pattern>(pattern)};
        w::Wheel wheel{std::numeric_limits<w::Id>::max(), origin, static_cast<g::Axis>(b), teeth, 3};
        wheel.center[a] += offset * 3;
        wheel.center[b] += offset;
        wheel.center[normal] += side * (radius + teeth);
        auto contact = origin;
        contact[a] += offset * 3;
        contact[normal] += side * radius;
        const auto idle = std::get<w::Evaluation>(w::evaluate(worm, wheel, {}));
        require(idle.motion[0].state == g::MotionState::unpowered && idle.motion[1].state == g::MotionState::unpowered && !idle.prescribed[0] && !idle.prescribed[1],
            "missing source is free/unpowered rather than an inferred worm brake");
        require(idle.geometry.worm == worm && idle.geometry.wheel == wheel && idle.geometry.contact == contact,
            "all axis orders, mounting sides and finite-face offsets own the actual pitch contact");
        require(idle.geometry.pitch_bounds == std::array<c::Box, 2>{cylinder_extrema(worm.center, a, radius, 7), cylinder_extrema(wheel.center, b, teeth, 3)},
            "pitch-cylinder boxes agree with independently enumerated end-circle extrema");
        const auto velocity = tangent(wheel, contact);
        require(velocity[a] != 0, "wheel tangent lies along the finite worm axis");
        // At a fixed angular contact coordinate, the declared thread pattern
        // travels pattern*starts per input radian. Equate that axial travel to
        // the actual world wheel tangent, without a mesh-ratio or spur oracle.
        require(idle.geometry.wheel_from_worm == fraction(pattern * starts, velocity[a]), "signed ratio agrees with independent axial thread-travel constraint");
        for (auto rate : rates) {
            const auto other = fraction(pattern * starts * rate.numerator, velocity[a] * rate.denominator);
            for (std::size_t coordinate = 0; coordinate < 3; ++coordinate) {
                const I thread = coordinate == a ? pattern * starts : 0;
                require(thread * rate.numerator * other.denominator == velocity[coordinate] * other.numerator * rate.denominator,
                    "thread axial travel and all three wheel tangential components agree exactly");
            }
            const std::array<w::Drive, 1> from_worm{{{worm.id, rate}}}, from_wheel{{{wheel.id, other}}};
            const auto driven = std::get<w::Evaluation>(w::evaluate(worm, wheel, from_worm));
            require(driven.motion == std::array<g::Motion, 2>{motion(rate), motion(other)}, "native source solver respects global signs and exact start-count reduction");
            require(std::get<w::Evaluation>(w::evaluate(worm, wheel, from_wheel)).motion == driven.motion,
                "supplied ideal wheel drive is a reversible constraint rather than automatic self-locking");
            const std::array<w::Drive, 2> both{{{wheel.id, {2 * other.numerator, 2 * other.denominator}}, {worm.id, {2 * rate.numerator, 2 * rate.denominator}}}};
            const auto observed = std::get<w::Evaluation>(w::evaluate(worm, wheel, both));
            require(observed.motion == driven.motion && observed.prescribed[0] == rate && observed.prescribed[1] == other,
                "compatible observations normalize independently of source and ID order");
            auto conflicting = both;
            conflicting[0].rate = fraction(other.numerator + other.denominator, other.denominator);
            const auto stalled = std::get<w::Evaluation>(w::evaluate(worm, wheel, conflicting));
            require(stalled.motion == std::array<g::Motion, 2>{{{g::MotionState::stalled, {}}, {g::MotionState::stalled, {}}}} && stalled.prescribed[1] == conflicting[0].rate,
                "contradictory native observations retain owned prescriptions and stall both parts");
            ++witnesses;
            arrangements += 4;
        }
    }
}

void raw_validation() {
    const w::Worm worm{7, {0, 32, 0}};
    const w::Wheel wheel{11, {0, 32, 28}};
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    const std::array<w::Drive, 1> drive{{{7, {1, 1}}}};
    for (I value : {low, I{-1}, I{0}, I{4097}, high}) {
        for (int field = 0; field < 3; ++field) {
            auto bad = worm;
            if (field == 0) bad.radius = value;
            else if (field == 1) bad.half_span = value;
            else bad.starts = value;
            require(refused(w::evaluate(bad, wheel, drive), w::Error::invalid_worm), "raw worm dimensions are checked before arithmetic");
        }
        for (int field = 0; field < 2; ++field) {
            auto bad = wheel;
            if (field == 0) bad.teeth = value; else bad.half_width = value;
            require(refused(w::evaluate(worm, bad, drive), w::Error::invalid_wheel), "raw wheel dimensions are checked before arithmetic");
        }
    }
    for (std::size_t axis = 0; axis < 3; ++axis) for (I value : {low, I{-1000001}, I{1000001}, high}) {
        auto bad_worm = worm; bad_worm.center[axis] = value;
        auto bad_wheel = wheel; bad_wheel.center[axis] = value;
        require(refused(w::evaluate(bad_worm, wheel, drive), w::Error::invalid_worm), "raw worm coordinate refuses before subtraction");
        require(refused(w::evaluate(worm, bad_wheel, drive), w::Error::invalid_wheel), "raw wheel coordinate refuses before subtraction");
    }
    for (int value : {-1, 3, 99}) {
        auto bad_worm = worm; bad_worm.axis = static_cast<g::Axis>(value);
        auto bad_wheel = wheel; bad_wheel.axis = static_cast<g::Axis>(value);
        require(refused(w::evaluate(bad_worm, wheel, drive), w::Error::invalid_worm), "worm axis validates before indexing");
        require(refused(w::evaluate(worm, bad_wheel, drive), w::Error::invalid_wheel), "wheel axis validates before indexing");
    }
    for (int value : {-2, 0, 2, 99}) {
        auto bad = worm; bad.pattern = static_cast<w::Pattern>(value);
        require(refused(w::evaluate(bad, wheel, drive), w::Error::invalid_worm), "unknown axial-pattern enum is rejected");
    }
    auto bad_worm = worm; bad_worm.id = 0;
    auto bad_wheel = wheel; bad_wheel.id = 0;
    require(refused(w::evaluate(bad_worm, wheel, drive), w::Error::invalid_worm), "zero worm identity refuses");
    require(refused(w::evaluate(worm, bad_wheel, drive), w::Error::invalid_wheel), "zero wheel identity refuses");
    bad_wheel.id = worm.id;
    require(refused(w::evaluate(worm, bad_wheel, drive), w::Error::duplicate_id), "descriptor identities are distinct");
    bad_wheel = wheel; bad_wheel.axis = worm.axis;
    require(refused(w::evaluate(worm, bad_wheel, drive), w::Error::not_perpendicular), "same-axis worm/wheel is outside this explicit mesh contract");
    for (I offset : {-1, 1}) {
        bad_wheel = wheel; bad_wheel.center[2] += offset;
        require(refused(w::evaluate(worm, bad_wheel, drive), w::Error::pitch_gap), "one-unit pitch gap error cannot produce a transmission");
    }
    for (I side : {-1, 1}) {
        bad_wheel = wheel; bad_wheel.center[0] = side * worm.half_span;
        require(refused(w::evaluate(worm, bad_wheel, drive), w::Error::outside_worm_face), "contact at a finite worm cap has no admitted axial face interior");
        bad_wheel.center[0] -= side;
        require(std::holds_alternative<w::Evaluation>(w::evaluate(worm, bad_wheel, drive)), "contact one unit inside either worm end is supported");
        bad_worm = worm; bad_worm.center[1] += side * wheel.half_width;
        require(refused(w::evaluate(bad_worm, wheel, drive), w::Error::outside_wheel_face), "contact on either wheel face cap is refused");
        bad_worm.center[1] -= side;
        require(std::holds_alternative<w::Evaluation>(w::evaluate(bad_worm, wheel, drive)), "one unit inside either wheel face is supported");
    }
    const std::array<w::Drive, 3> excessive{{drive[0], {11, {-1, 24}}, drive[0]}};
    require(refused(w::evaluate(worm, wheel, excessive), w::Error::too_many_drives), "complete excessive drive set is never truncated");
    for (w::Id id : {w::Id{0}, w::Id{9}, std::numeric_limits<w::Id>::max()}) {
        const std::array<w::Drive, 2> values{{drive[0], {id, {1, 1}}}};
        require(refused(w::evaluate(worm, wheel, values), w::Error::unknown_part), "last unknown prescribed part refuses all output");
    }
    const std::array<w::Drive, 2> repeated{{drive[0], drive[0]}};
    require(refused(w::evaluate(worm, wheel, repeated), w::Error::duplicate_drive), "duplicate observations cannot silently replace an earlier source");
    for (g::Rate rate : {g::Rate{0, 0}, {1, -1}, {0, low}, {low, 1}, {high, 1}, {1, 1000001}, {257, 1}}) {
        const std::array<w::Drive, 2> values{{drive[0], {11, rate}}};
        require(refused(w::evaluate(worm, wheel, values), w::Error::invalid_rate), "invalid final rate cannot be hidden by power/conflict handling");
    }
}

void representation_and_ownership() {
    w::Worm worm{7, {0, 32, 0}, g::Axis::x, 4, 16, 1, w::Pattern::negative};
    w::Wheel wheel{11, {0, 32, 28}};
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    std::array<w::Drive, 1> drive{{{11, {low, I{1} << 62}}}};
    const auto owned = std::get<w::Evaluation>(w::evaluate(worm, wheel, drive));
    worm.center = {}; wheel.teeth = 1; drive[0].rate = {};
    require(owned.prescribed[1] == g::Rate{-2, 1} && owned.motion[0] == motion({-48, 1}) && owned.geometry.wheel.teeth == 24 && owned.geometry.worm.center == g::Point{0, 32, 0},
        "INT64_MIN reduces before sign mapping and results own caller descriptors/rates");
    worm = {7, {0, 32, 0}}; wheel = {11, {0, 32, 28}};
    const std::array<w::Drive, 1> huge_reducible{{{7, {high, high}}}};
    const auto normal = std::get<w::Evaluation>(w::evaluate(worm, wheel, huge_reducible));
    require(normal.motion[1] == motion({-1, 24}) && normal.geometry.wheel_from_worm == g::Rate{-1, 24} && normal.motion[1].rate != g::Rate{-1, 6},
        "one start on a four-unit-radius worm reduces by starts/teeth rather than cylinder radius/teeth");
    auto renamed_worm = worm; auto renamed_wheel = wheel;
    renamed_worm.id = 11; renamed_wheel.id = 7;
    const std::array<w::Drive, 1> renamed_drive{{{11, {1, 1}}}};
    require(std::get<w::Evaluation>(w::evaluate(renamed_worm, renamed_wheel, renamed_drive)).motion == normal.motion, "opaque identity ordering cannot reverse the mesh direction");
    for (std::size_t axis : {0U, 1U}) for (I side : {-1, 1}) {
        auto edge_worm = worm; auto edge_wheel = wheel;
        edge_worm.center[axis] = edge_wheel.center[axis] = side * (g::maximum_coordinate - (axis == 0 ? 24 : 4));
        require(std::holds_alternative<w::Evaluation>(w::evaluate(edge_worm, edge_wheel, huge_reducible)), "complete pitch cylinder may exactly touch either grid boundary");
        edge_worm.center[axis] += side; edge_wheel.center[axis] += side;
        const auto refusal = std::get<w::Refusal>(w::evaluate(edge_worm, edge_wheel, huge_reducible));
        require(refusal.reason == w::Error::representation_limit && refusal.subject == (axis == 0 ? 11U : 7U) && refusal.envelope_error == c::Error::invalid_box,
            "raw valid centers do not widen the finite envelope grid bound");
    }
    wheel.teeth = 256; wheel.center[2] = 260;
    const std::array<w::Drive, 1> wheel_source{{{11, {1, 1}}}};
    require(std::get<w::Evaluation>(w::evaluate(worm, wheel, wheel_source)).motion[0] == motion({-256, 1}), "ideal reverse-drive inferred speed exactly at native cap is admitted");
    wheel.teeth = 257; wheel.center[2] = 261;
    const auto fast_worm = std::get<w::Refusal>(w::evaluate(worm, wheel, wheel_source));
    require(fast_worm.reason == w::Error::unsupported_result && fast_worm.subject == 7 && fast_worm.rate_error == k::Error::rate_limit,
        "unsupported ideal reverse-drive speed refuses the whole result");
    wheel.teeth = 1; wheel.center[2] = 5; worm.starts = 256;
    const std::array<w::Drive, 1> worm_source{{{7, {1, 1}}}};
    require(std::get<w::Evaluation>(w::evaluate(worm, wheel, worm_source)).motion[1] == motion({-256, 1}), "forward inferred wheel rate exactly at cap is admitted");
    worm.starts = 257;
    require(std::get<w::Refusal>(w::evaluate(worm, wheel, worm_source)).subject == 11, "unsupported inferred wheel rate identifies its actual part");
    worm.starts = 1; wheel.teeth = 4096; wheel.center[2] = 4100;
    const std::array<w::Drive, 1> fine{{{7, {1, 999983}}}};
    require(refused(w::evaluate(worm, wheel, fine), w::Error::unsupported_result), "unsupported inferred denominator is never rounded");
    const std::array<w::Drive, 2> contradictory{{{7, {256, 1}}, {11, {256, 1}}}};
    require(std::get<w::Evaluation>(w::evaluate(worm, wheel, contradictory)).motion[0].state == g::MotionState::stalled,
        "native contradictory-source stall survives even when isolated reverse-drive inference would exceed representation");
}

void caller() {
    struct Case { std::array<std::string_view, 4> args; std::string_view witness; bool matched{}; };
    const std::array<Case, 21> cases{{
        {{{"standard", "axial+", "reverse", "full"}}, "readout rotating 1/48", true},
        {{{"standard", "axial-", "slow", "full"}}, "Wheel/worm 1/24", true},
        {{{"flipped", "axial+", "slow", "full"}}, "Contact (0,32,52)", true},
        {{{"multi", "axial+", "reverse", "full"}}, "starts 2; radius 4", true},
        {{{"long-body", "axial+", "reverse", "full"}}, "worm half-span 32", true},
        {{{"standard", "axial+", "slow", "full"}}, "readout rotating -1/48"},
        {{{"flipped", "axial+", "reverse", "full"}}, "readout rotating -1/48"},
        {{{"standard", "axial-", "reverse", "full"}}, "readout rotating -1/48"},
        {{{"standard", "axial+", "fast", "full"}}, "readout rotating -5/48"},
        {{{"multi", "axial-", "fast", "full"}}, "readout rotating 5/48"},
        {{{"short-body", "axial+", "reverse", "full"}}, "outside_worm_face"},
        {{{"edge-body", "axial+", "reverse", "full"}}, "outside_worm_face"},
        {{{"outside-face", "axial+", "reverse", "full"}}, "outside_wheel_face"},
        {{{"pitch-miss", "axial+", "reverse", "full"}}, "pitch_gap"},
        {{{"parallel", "axial+", "reverse", "full"}}, "not_perpendicular"},
        {{{"standard", "axial+", "reverse", "short"}}, "half-span 1; readout unpowered 0/1"},
        {{{"shifted", "axial+", "reverse", "full"}}, "half-span 16; readout unpowered 0/1"},
        {{{"low", "axial+", "reverse", "full"}}, "worm pitch envelope overlaps floor 99"},
        {{{"standard", "axial+", "off", "full"}}, "source unpowered; no wheel drive is admitted"},
        {{{"standard", "axial+", "stalled", "full"}}, "source stalled; no wheel drive is admitted"},
        {{{"long-body", "axial+", "reverse", "short"}}, "half-span 1; readout unpowered 0/1"},
    }};
    for (const auto& example : cases) {
        std::ostringstream out, errors;
        require(w::workbench(example.args, out, errors) == 0 && errors.str().empty(), "valid original layout produces an actual consumer trace");
        require(out.str().find(example.witness) != std::string::npos && (out.str().find("Goal matched.") != std::string::npos) == example.matched,
            "actual finite engagement, pattern, source, floor and output shaft determine the goal");
        ++caller_traces;
    }
    const std::array<std::vector<std::string_view>, 7> invalid{{{"standard"}, {"standard", "axial+", "slow"}, {"standard", "axial+", "slow", "full", "extra"},
        {"missing", "axial+", "slow", "full"}, {"standard", "missing", "slow", "full"}, {"standard", "axial+", "missing", "full"}, {"standard", "axial+", "slow", "missing"}}};
    for (const auto& args : invalid) {
        std::ostringstream out, errors;
        require(w::workbench(args, out, errors) == 2 && out.str().empty() && !errors.str().empty(), "invalid argv refuses before mechanical observations");
    }
    std::ostringstream out, errors;
    const std::array<std::string_view, 1> args{"list"};
    require(w::workbench(args, out, errors) == 0 && out.str().find("No automatic self-locking") != std::string::npos, "catalogue states the ideal backdrive and authority boundary");
    out.setstate(std::ios::badbit);
    require(w::workbench(args, out, errors) == 2, "failed output cannot claim a successful trace");
}
}  // namespace

int main() {
    thread_travel_witnesses();
    raw_validation();
    representation_and_ownership();
    caller();
    std::cout << assertions << " assertions; " << witnesses << " independent axial-thread/wheel-tangent witnesses; "
        << arrangements << " source arrangements; " << caller_traces << " original native caller traces passed.\n";
}
