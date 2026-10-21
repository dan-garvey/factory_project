#include "factory/slotted_shuttle.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>

namespace h = factory::slotted_shuttle;
namespace b = factory::slotted_bank;
namespace p = factory::slotted_pairs;
namespace s = factory::slotted_clearance;
namespace c = factory::clearance;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
std::size_t assertions{}, model_cases{}, frame_model_cases{};
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

void stationary_controls() {
    const h::Profile long_stroke{{5, 0}}, short_stroke{{4, 0}}, staged{{1, 4, 0}};
    const std::array<c::Obstacle, 1> near_frame{{{11, box(5, 0)}}}, far_frame{{{11, box(8, 0)}}};
    const auto omitted = h::inspect(long_stroke, links, initial, shapes(), pairs, 16);
    require(omitted.loop && omitted.loop->unmoved_followers.empty(), "empty stationary set admits the frame-free control");
    const auto observed = h::inspect(long_stroke, links, initial, shapes(), pairs, 16, true, near_frame);
    require(observed.outcome == h::Outcome::held && !observed.loop && observed.path == std::vector<h::State>{initial},
        "the actual frame observation prevents the otherwise reported recurrence");
    const auto& hold = *observed.hold;
    require(hold.state == initial && hold.reason == h::Stop::obstructed && hold.stationary_contact &&
        hold.stationary_contact->member == p::Member{7} && hold.stationary_contact->hit == c::Hit{11, {3, 5}, false} &&
        !hold.conflict && !hold.limit, "frame hold keeps the whole original bank and pending stop with an owned typed witness");
    const auto later = h::inspect(staged, links, initial, shapes(), pairs, 16, true, near_frame);
    const h::State first_stop{{1, {{3, 0}, {7, 0}}}, 1};
    require(later.outcome == h::Outcome::held && later.path == std::vector<h::State>{initial, first_stop} &&
        later.hold && later.hold->state == first_stop && later.hold->stationary_contact &&
        later.hold->stationary_contact->hit == c::Hit{11, {2, 3}, false} && !later.loop,
        "later blocked leg preserves its accepted prefix without consuming the blocked stop");
    const auto far = h::inspect(long_stroke, links, initial, shapes(), pairs, 16, true, far_frame);
    require(far.outcome == h::Outcome::recurrent && far.loop == omitted.loop && far.path == omitted.path,
        "farther frame restores the complete original trajectory and recurrence");
    auto raised = shapes(2);
    raised.followers[1].at_zero = box(2, 3);
    const auto high = h::inspect(long_stroke, links, initial, raised, pairs, 16, true, near_frame);
    require(high.loop && high.loop->pin_moves && high.loop->unmoved_followers.empty(),
        "raised guide clears the near frame and sustains both followers");

    const auto accepted = h::prepare(long_stroke, links, initial, shapes(), pairs, true, far_frame);
    const auto workcell = factory::slotted_workcell::prepare(links, initial.bank, shapes(), {{5, true}, far_frame}, pairs);
    const auto& step = std::get<h::Step>(accepted);
    const auto& bank_step = std::get<b::Advance>(workcell);
    require(step.next.bank == bank_step.next && step.traces == bank_step.traces && step.limit == bank_step.limit &&
        step.reached && step.next.cursor == 1, "clear observed frame preserves the exact parent effects and reached-stop phase");
    const auto moving = h::prepare(short_stroke, links, initial, shapes(2), pairs, true, near_frame);
    const auto& moving_hold = std::get<h::Hold>(moving);
    require(moving_hold.conflict && !moving_hold.stationary_contact && moving_hold.state == initial &&
        moving_hold.conflict->time == c::Fraction{1, 2}, "moving contact details remain intact with stationary observations present");

    const std::array<c::Obstacle, 1> penetration{{{11, box(4, 0)}}};
    for (const bool powered : {false, true}) {
        const auto resting = h::inspect(h::Profile{{0, 0}}, links, initial, shapes(), pairs, 16, powered, penetration);
        require(resting.outcome == h::Outcome::held && resting.path.size() == 1 && resting.hold &&
            resting.hold->state == initial && resting.hold->stationary_contact &&
            resting.hold->stationary_contact->hit == c::Hit{11, {0, 1}, true} && !resting.loop,
            "initial stationary penetration holds phase even paused or already at the stop");
    }
    const std::array<c::Obstacle, 2> invalid{{{11, box(5, 0)}, {99, {{0, 0, 0}, {0, 1, 1}}}}};
    for (const bool powered : {false, true}) {
        const auto candidate = h::prepare(short_stroke, links, initial, shapes(2), pairs, powered, invalid);
        const auto* refused = std::get_if<h::Refusal>(&candidate);
        require(refused && refused->reason == h::Error::parent_refused && !refused->parent_error &&
            refused->workcell_error && refused->workcell_error->stationary_error,
            "bad later obstacle refuses before an earlier pair hit or pause");
    }
    const auto refused_trace = h::inspect(staged, links, initial, shapes(), pairs, 16, true, invalid);
    require(refused_trace.outcome == h::Outcome::refused && refused_trace.path == std::vector<h::State>{initial} &&
        refused_trace.refusal && !refused_trace.hold && !refused_trace.loop, "invalid fixed observations grant no accepted prefix");
    const std::array<p::Pair, 2> bad_pairs{{{3, 7}, {3, 99}}};
    const auto both = h::prepare(short_stroke, links, initial, shapes(), bad_pairs, false, invalid);
    const auto& both_error = std::get<h::Refusal>(both);
    require(both_error.parent_error && both_error.workcell_error && both_error.workcell_error->stationary_error &&
        both_error.workcell_error->moving_error, "both parent refusal families remain inspectable");
    std::vector<c::Obstacle> excessive(g::maximum_parts + 1, near_frame[0]);
    require(std::holds_alternative<h::Refusal>(h::prepare(long_stroke, links, initial, shapes(), pairs, false, excessive)),
        "complete oversized stationary set refuses instead of truncating");

    auto invalid_rig = shapes();
    invalid_rig.followers[0].at_zero.maximum[0] = invalid_rig.followers[0].at_zero.minimum[0];
    const auto old_error = p::prepare(links, initial.bank, invalid_rig, {5, false}, pairs);
    const auto compatible = h::prepare(long_stroke, links, initial, invalid_rig, pairs, false);
    require(std::get<h::Refusal>(compatible) == h::Refusal{h::Error::parent_refused, std::get<p::Refusal>(old_error)},
        "empty-set source calls preserve original refusal values without new details");
    const h::Hold old_hold{initial, h::Stop::obstructed, h::Conflict{pairs[0], {1, 2}, false}, {}};
    require(std::get<h::Hold>(h::prepare(short_stroke, links, initial, shapes(2), pairs)) == old_hold,
        "empty-set source calls preserve original moving hold values");
    auto mutable_frames = near_frame;
    auto mutable_state = initial;
    const auto owned = h::inspect(long_stroke, links, mutable_state, shapes(), pairs, 16, true, mutable_frames);
    const auto owned_hold = *owned.hold;
    mutable_state.bank.followers.clear();
    mutable_frames[0].id = 99;
    require(*owned.hold == owned_hold, "retained stationary hold owns identities, original state and witness values");
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
    std::optional<factory::slotted_workcell::StationaryContact> stationary;
};
Expected model(const h::Profile& profile, I pin, std::size_t cursor, std::size_t bound, bool powered,
               std::optional<I> frame = {}) {
    Expected result;
    result.path.emplace_back(pin, cursor);
    for (std::size_t tick = 0; tick < bound; ++tick) {
        const I target = profile.stops[cursor];
        const I next = powered ? std::clamp(target, I{-2}, I{2}) : pin;
        // Independent unit-interval contact along the rigid guides. A's box
        // starts at pin; B's starts four units farther along. The pin occupies
        // a separate lane. Initial interior overlap is a hold even paused.
        if (frame) for (const auto& [identity, offset] : std::array<std::pair<b::Id, I>, 2>{{{3, 0}, {7, 4}}}) {
            const I start = pin + offset, finish = next + offset;
            std::optional<c::Fraction> hit;
            if (start == *frame) hit = c::Fraction{0, 1};
            else if ((finish > start && start < *frame && finish >= *frame) ||
                     (finish < start && start > *frame && finish <= *frame)) {
                const I numerator = finish > start ? *frame - 1 - start : start - *frame - 1;
                const I denominator = std::abs(target - pin);
                const auto divisor = std::gcd(numerator, denominator);
                hit = c::Fraction{numerator / divisor, denominator / divisor};
            }
            if (!hit) continue;
            const factory::slotted_workcell::StationaryContact contact{identity, {11, *hit, start == *frame}};
            if (!result.stationary || hit->numerator * result.stationary->hit.time.denominator <
                result.stationary->hit.time.numerator * hit->denominator) result.stationary = contact;
        }
        if (result.stationary) { result.outcome = h::Outcome::held; result.hold = h::Stop::obstructed; break; }
        if (!powered) { result.outcome = h::Outcome::held; result.hold = h::Stop::unpowered; break; }
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

void stationary_exhaustive() {
    const std::array<b::Link, 2> rigid{{{3, {-2, 2, 0, 0}}, {7, {-2, 2, 0, 0}}}};
    const std::array<I, 5> choices{{-3, -1, 0, 1, 3}};
    for (std::size_t count = 1, combinations = 5; count <= 2; ++count, combinations *= 5)
    for (std::size_t encoding = 0; encoding < combinations; ++encoding) {
        h::Profile profile;
        profile.stops.clear();
        auto code = encoding;
        for (std::size_t stop = 0; stop < count; ++stop) { profile.stops.push_back(choices[code % 5]); code /= 5; }
        for (I pin = -2; pin <= 2; ++pin) for (std::size_t cursor = 0; cursor < count; ++cursor)
        for (const auto bound : {std::size_t{1}, std::size_t{4}}) for (const bool powered : {false, true})
        for (const I frame : {-1, 1, 4, 6}) {
            const std::array<c::Obstacle, 1> obstacles{{{11, box(frame, 0)}}};
            const auto expected = model(profile, pin, cursor, bound, powered, frame);
            const auto actual = h::inspect(profile, rigid, rigid_state(pin, cursor), shapes(), pairs, bound, powered, obstacles);
            ++frame_model_cases;
            require(actual.outcome == expected.outcome && actual.path.size() == expected.path.size(),
                "frame observation and phase outcome agree with independent interval sequencer");
            for (std::size_t index = 0; index < actual.path.size(); ++index)
                require(actual.path[index] == rigid_state(expected.path[index].first, expected.path[index].second),
                    "each observed-frame accepted prefix retains the independent bank and cursor");
            require(actual.loop == expected.loop && !actual.refusal, "obstruction cannot become a recurrence or a spurious refusal");
            require(actual.hold.has_value() == expected.hold.has_value(), "observed-frame hold presence matches the independent model");
            if (actual.hold) require(actual.hold->reason == *expected.hold && actual.hold->state == actual.path.back() &&
                actual.hold->stationary_contact == expected.stationary && !actual.hold->conflict,
                "actual stationary witness and retained stop match independent interval contact");
        }
    }
}
}  // namespace
int main() {
    controls();
    stationary_controls();
    exhaustive();
    stationary_exhaustive();
    std::cout << assertions << " slotted-shuttle assertions passed, including " << model_cases
              << " independent bounded-sequencer cases and " << frame_model_cases << " independent stationary-frame cases.\n";
}
