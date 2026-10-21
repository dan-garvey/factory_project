#include "factory/slotted_shuttle.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>

namespace h = factory::slotted_shuttle;
namespace b = factory::slotted_bank;
namespace p = factory::slotted_pairs;
namespace s = factory::slotted_clearance;
namespace c = factory::clearance;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
std::size_t assertions{}, model_cases{};
void require(bool condition, const char* message) {
    ++assertions;
    if (!condition) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
c::Box box(I x, I lane) { return {{x, lane, 0}, {x + 1, lane + 1, 1}}; }
s::Rig shapes(I spacing = 4) { return {g::Axis::x, box(0, -8), {{3, box(0, 0)}, {7, box(spacing, 0)}}}; }
const std::array<b::Link, 2> links{{{3, {0, 6, 2, 1}}, {7, {0, 6, 1, 3}}}};
const std::array<p::Pair, 1> pairs{{{3, 7}}};
const h::State initial{{0, {{3, 0}, {7, 0}}}, 0};

void controls() {
    const h::Profile short_stroke{{4, 0}}, long_stroke{{5, 0}};
    const auto short_report = h::inspect(short_stroke, links, initial, shapes(), pairs, 16);
    const std::vector<h::State> short_path{
        initial, {{4, {{3, 3}, {7, 1}}}, 1}, {{0, {{3, 2}, {7, 1}}}, 0}, {{4, {{3, 3}, {7, 1}}}, 1}};
    require(short_report.path == short_path, "short stroke retains actual transient and steady bank states");
    require(short_report.outcome == h::Outcome::recurrent && short_report.loop == h::Loop{1, 2, true, {7}},
        "startup movement cannot hide a follower parked in the repeated interval");
    require(short_report.path[0].bank.pin == short_report.path[2].bank.pin && short_report.path[0] != short_report.path[2],
        "pin-only return aliases a different retained bank and is not recurrence");
    const auto long_report = h::inspect(long_stroke, links, initial, shapes(), pairs, 16);
    require(long_report.loop == h::Loop{1, 2, true, {}}, "long stroke moves both followers in the repeated interval");
    auto matched_links = links;
    matched_links[1].slot.front = 1;
    const auto compact = h::inspect(short_stroke, matched_links, initial, shapes(2), pairs, 16);
    require(compact.loop == h::Loop{1, 2, true, {}}, "matched clearances sustain compact short motion");
    require(compact.path[2].bank == b::State{0, {{3, 2}, {7, 1}}}, "same original retained members reach the common home state");

    const auto parent = p::prepare(links, initial.bank, shapes(), {5, true}, pairs);
    auto proposal = h::prepare(long_stroke, links, initial, shapes(), pairs);
    const auto& step = std::get<h::Step>(proposal);
    const auto& parent_step = std::get<b::Advance>(parent);
    require(step.next.bank == parent_step.next && step.traces == parent_step.traces && step.limit == parent_step.limit &&
        step.reached && step.next.cursor == 1, "one reached stop preserves the exact parent state, traces and limit");
    const h::Profile overtravel{{10, 0}};
    proposal = h::prepare(overtravel, links, initial, shapes(), pairs);
    const auto clipped = std::get<h::Step>(proposal);
    require(clipped.next == h::State{{7, {{3, 6}, {7, 4}}}, 0} && !clipped.reached && clipped.limit && clipped.limit->id == 3,
        "clipped prefix retains its unreached stop and actual bank endpoint");
    proposal = h::prepare(overtravel, links, clipped.next, shapes(), pairs);
    const auto& limit = std::get<h::Hold>(proposal);
    require(limit.reason == h::Stop::endstop && limit.state == clipped.next && limit.limit && !limit.conflict,
        "hard-stop hold cannot consume a target it has not reached");
    const auto limited = h::inspect(overtravel, links, initial, shapes(), pairs, 16);
    require(limited.outcome == h::Outcome::held && limited.path == std::vector<h::State>{initial, clipped.next} &&
        limited.hold && limited.hold->state == clipped.next && !limited.loop, "report retains accepted prefix before the later hold");
    const auto recovered = h::inspect(long_stroke, links, clipped.next, shapes(), pairs, 16);
    require(recovered.loop && recovered.loop->pin_moves && recovered.loop->unmoved_followers.empty() &&
        recovered.path.front() == clipped.next, "corrected future stops recover without resetting any retained member");

    const auto blocked = h::inspect(short_stroke, links, initial, shapes(2), pairs, 16);
    require(blocked.outcome == h::Outcome::held && blocked.path == std::vector<h::State>{initial} &&
        blocked.hold && blocked.hold->state == initial && blocked.hold->reason == h::Stop::obstructed &&
        blocked.hold->conflict && blocked.hold->conflict->time == c::Fraction{1, 2} && !blocked.loop,
        "blocked first stroke exposes only the original bank/cursor and conflict");
    const h::Profile idle{{0, 0}};
    const auto paused = h::inspect(idle, links, initial, shapes(), pairs, 16, false);
    require(paused.outcome == h::Outcome::held && paused.path.size() == 1 && paused.hold &&
        paused.hold->reason == h::Stop::unpowered && paused.hold->state == initial && !paused.loop,
        "pause does not consume an already reached stop or become an idle cycle");
    const auto resting = h::inspect(idle, links, initial, shapes(), pairs, 16);
    require(resting.loop == h::Loop{0, 2, false, {3, 7}}, "powered rest consumes stops but remains a motionless recurrence");

    for (const auto count : {std::size_t{0}, h::maximum_steps + 1}) {
        const auto report = h::inspect(short_stroke, links, initial, shapes(), pairs, count);
        require(report.outcome == h::Outcome::refused && report.refusal && report.refusal->reason == h::Error::invalid_bound &&
            report.path == std::vector<h::State>{initial}, "invalid bound produces no simulated prefix");
    }
    h::Profile long_idle;
    long_idle.stops.assign(h::maximum_stops, 0);
    const auto short_bound = h::inspect(long_idle, links, initial, shapes(), pairs, h::maximum_stops - 1);
    require(short_bound.outcome == h::Outcome::bound && !short_bound.loop && short_bound.path.size() == h::maximum_stops,
        "equal poses with different pending stops do not close the full state");
    const auto full_bound = h::inspect(long_idle, links, initial, shapes(), pairs, h::maximum_steps);
    require(full_bound.loop == h::Loop{0, h::maximum_stops, false, {3, 7}}, "maximum stop and step bounds retain the full cursor cycle");
    const std::array<h::Profile, 4> invalid_profiles{{{{}}, {{4, std::numeric_limits<I>::max()}},
        {{4, std::numeric_limits<I>::min()}}, {std::vector<I>(h::maximum_stops + 1, 0)}}};
    for (const auto& profile : invalid_profiles) {
        const auto candidate = h::prepare(profile, links, initial, shapes(), pairs, false);
        const auto* refused = std::get_if<h::Refusal>(&candidate);
        require(refused && refused->reason == h::Error::invalid_profile, "entire stop list validates before pause or an earlier valid stop");
    }
    auto bad_cursor = initial;
    bad_cursor.cursor = std::numeric_limits<std::size_t>::max();
    proposal = h::prepare(short_stroke, links, bad_cursor, shapes(), pairs, false);
    require(std::get<h::Refusal>(proposal).reason == h::Error::invalid_cursor, "cursor validates before indexing a stop");
    auto bad_rig = shapes();
    bad_rig.followers[1].at_zero.maximum[0] = bad_rig.followers[1].at_zero.minimum[0];
    proposal = h::prepare(short_stroke, links, initial, bad_rig, pairs, false);
    require(std::get<h::Refusal>(proposal).reason == h::Error::parent_refused && std::get<h::Refusal>(proposal).parent_error,
        "paused sequencer preserves complete parent validation");

    auto mutable_profile = long_stroke;
    auto mutable_state = initial;
    auto mutable_rig = shapes();
    auto owned = h::inspect(mutable_profile, links, mutable_state, mutable_rig, pairs, 16);
    const auto original_path = owned.path;
    const auto original_loop = owned.loop;
    mutable_profile.stops.clear();
    mutable_state.bank.followers.clear();
    mutable_rig.followers.clear();
    require(owned.path == original_path && owned.loop == original_loop, "report owns its path and recurrence rather than input views");
}

h::State rigid_state(I pin, std::size_t cursor) { return {{pin, {{3, pin}, {7, pin}}}, cursor}; }
// Independent finite sequencer model for rigid slots: all positions equal the
// pin, and guide bounds are [-2,2]. There is no slot, pair or shuttle API call.
// Its state is just (position, pending stop); a target outside the guides clips
// once, then waits. Compare both the entire accepted path and loop diagnostics.
struct Expected {
    h::Outcome outcome{h::Outcome::bound};
    std::vector<std::pair<I, std::size_t>> path;
    std::optional<h::Loop> loop;
    std::optional<h::Stop> hold;
};
Expected model(const h::Profile& profile, I pin, std::size_t cursor, std::size_t bound, bool powered) {
    Expected result;
    result.path.emplace_back(pin, cursor);
    for (std::size_t tick = 0; tick < bound; ++tick) {
        if (!powered) { result.outcome = h::Outcome::held; result.hold = h::Stop::unpowered; break; }
        const I target = profile.stops[cursor];
        const I next = std::clamp(target, I{-2}, I{2});
        if (next == pin && target != pin) { result.outcome = h::Outcome::held; result.hold = h::Stop::endstop; break; }
        pin = next;
        if (pin == target) cursor = cursor + 1 == profile.stops.size() ? 0 : cursor + 1;
        const std::pair<I, std::size_t> state{pin, cursor};
        std::size_t previous = result.path.size();
        for (std::size_t index = 0; index < result.path.size(); ++index)
            if (result.path[index] == state) { previous = index; break; }
        result.path.push_back(state);
        if (previous == result.path.size() - 1) continue;
        bool moving = false;
        for (std::size_t index = previous + 1; index < result.path.size(); ++index)
            if (result.path[index].first != result.path[previous].first) moving = true;
        result.outcome = h::Outcome::recurrent;
        result.loop = h::Loop{previous, result.path.size() - 1 - previous, moving, moving ? std::vector<b::Id>{} : std::vector<b::Id>{3, 7}};
        break;
    }
    return result;
}
void exhaustive() {
    const std::array<b::Link, 2> rigid{{{3, {-2, 2, 0, 0}}, {7, {-2, 2, 0, 0}}}};
    const auto rig = shapes();
    const std::array<I, 5> choices{{-3, -1, 0, 1, 3}};
    for (std::size_t count = 1, combinations = 5; count <= 3; ++count, combinations *= 5)
    for (std::size_t encoding = 0; encoding < combinations; ++encoding) {
        h::Profile profile;
        profile.stops.clear();
        auto code = encoding;
        for (std::size_t stop = 0; stop < count; ++stop) { profile.stops.push_back(choices[code % 5]); code /= 5; }
        for (I pin = -2; pin <= 2; ++pin)
        for (std::size_t cursor = 0; cursor < count; ++cursor)
        for (const auto bound : {std::size_t{1}, std::size_t{2}, std::size_t{4}, std::size_t{16}})
        for (const bool powered : {false, true}) {
            const auto expected = model(profile, pin, cursor, bound, powered);
            const auto actual = h::inspect(profile, rigid, rigid_state(pin, cursor), rig, pairs, bound, powered);
            ++model_cases;
            require(actual.outcome == expected.outcome && actual.path.size() == expected.path.size(),
                "bounded outcome and accepted path length agree with independent sequencer");
            for (std::size_t index = 0; index < actual.path.size(); ++index)
                require(actual.path[index] == rigid_state(expected.path[index].first, expected.path[index].second),
                    "each accepted full bank and pending stop agree with independent model");
            require(actual.loop == expected.loop, "first recurrence and in-loop motion agree with independent model");
            require(actual.hold.has_value() == expected.hold.has_value() && !actual.refusal, "hold and refusal stay distinct from recurrence");
            if (actual.hold) require(actual.hold->reason == *expected.hold && actual.hold->state == actual.path.back(),
                "hold preserves the exact last accepted bank and cursor");
        }
    }
}
}  // namespace
int main() {
    controls();
    exhaustive();
    std::cout << assertions << " slotted-shuttle assertions passed, including " << model_cases
              << " independent bounded-sequencer cases.\n";
}
