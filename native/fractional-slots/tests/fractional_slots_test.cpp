#include "factory/fractional_slots.hpp"
#include "factory/fractional_slots_workbench.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace f = factory::fractional_slots;
namespace b = factory::slotted_bank;
namespace s = factory::slotted_link;
namespace w = factory::slotted_workcell;
namespace c = factory::clearance;
namespace p = factory::slotted_pairs;
namespace g = factory::mechanics;
namespace r = factory::slotted_clearance;
using I = g::Integer;
namespace {
std::size_t assertions{}, model_cases{}, moving_cases{};
void require(bool condition, const char* message) {
    ++assertions;
    if (!condition) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
g::Rate fraction(I n, I d = 1) {
    const auto divisor = std::gcd(n, d);
    return {n / divisor, d / divisor};
}
c::Fraction time(I n, I d) { const auto value = fraction(n, d); return {value.numerator, value.denominator}; }
c::Box box(I x, I y) { return {{x, y, 0}, {x + 1, y + 1, 1}}; }
const std::array<b::Link, 1> links{{{7, {-2, 4, 2, 1}}}};
const r::Rig rig{g::Axis::x, box(0, -3), {{7, box(0, 0)}}};
const std::array<c::Obstacle, 1> frame{{{11, box(2, 0)}}};
const f::State initial{{0, 1}, {{7, {0, 1}}}};
f::State adopted(const f::Plan& plan) { return std::get<f::Advance>(plan).next; }
bool refused(const f::Plan& plan, f::Error reason) {
    const auto* value = std::get_if<f::Refusal>(&plan);
    return value && value->reason == reason;
}

void controls() {
    const auto half = std::get<f::Advance>(f::prepare(links, initial, rig, {{3, 2}, true, frame}, {}));
    const f::State goal{{3, 2}, {{7, {1, 2}}}};
    require(half.next == goal && half.traces.size() == 1 && half.traces[0].contact == s::Contact{s::Side::positive, {2, 3}} &&
        half.traces[0].follower_motion == s::Span{{2, 3}, {1, 1}}, "fractional wall contact retains original-command time");
    for (I denominator : {2, 4}) {
        auto state = initial;
        for (I step = 1; step <= 3 * denominator / 2; ++step)
            state = adopted(f::prepare(links, state, rig, {fraction(step, denominator), true, frame}, {}));
        require(state == goal, "half and quarter strokes reach the same exact original bank");
    }
    auto thirds = initial;
    for (I step = 1; step <= 4; ++step)
        thirds = adopted(f::prepare(links, thirds, rig, {fraction(step, 3), true, {}}, {}));
    require(thirds == f::State{{4, 3}, {{7, {1, 3}}}}, "nonbinary thirds accumulate without rounded or mirrored state");
    const auto mixed = adopted(f::prepare(links, {{1, 3}, {{7, {1, 4}}}}, rig, {{5, 3}, true, {}}, {}));
    require(mixed == f::State{{5, 3}, {{7, {2, 3}}}}, "mixed position denominators share one exact common query");

    const f::State coarse{{2, 1}, {{7, {1, 1}}}};
    const auto collision = std::get<f::Blocked>(f::prepare(links, coarse, rig, {{3, 1}, true, frame}, {}));
    const auto fixed = std::get<w::StationaryContact>(collision.contact);
    require(collision.state == coarse && fixed.member == 7 && fixed.hit == c::Hit{11, {0, 1}, false},
        "tangent coarse stroke blocks at zero and owns only the original bank");
    const auto reversed = std::get<f::Advance>(f::prepare(links, coarse, rig, {{-3, 2}, true, frame}, {}));
    require(reversed.next == f::State{{-3, 2}, {{7, {1, 2}}}} &&
        reversed.traces[0].contact == s::Contact{s::Side::negative, {6, 7}}, "reversal retains original backlash before moving the tool");
    const auto recovered = std::get<f::Advance>(f::prepare(links, reversed.next, rig, {{3, 2}, true, frame}, {}));
    require(recovered.next == goal && recovered.traces[0].contact == s::Contact{s::Side::positive, {1, 1}} &&
        !recovered.traces[0].follower_motion, "corrective forward stroke touches the opposite wall only at its destination");
    const auto paused = std::get<f::Hold>(f::prepare(links, goal, rig, {{-3, 2}, false, frame}, {}));
    require(paused == f::Hold{goal, b::Stop::unpowered, {}}, "pause owns original fractions without a pending command");
    const auto clipped = std::get<f::Advance>(f::prepare(links, {{19, 4}, {{7, {15, 4}}}}, rig, {{27, 4}, true, {}}, {}));
    require(clipped.next == f::State{{5, 1}, {{7, {4, 1}}}} &&
        clipped.limit == b::Limit{7, {s::Side::positive, {1, 8}}} &&
        clipped.traces[0].follower_motion == s::Span{{0, 1}, {1, 8}}, "fractional hard stop clips the complete original stroke");
    const auto held = std::get<f::Hold>(f::prepare(links, clipped.next, rig, {{27, 4}, true, {}}, {}));
    require(held.reason == b::Stop::limit && held.limit == b::Limit{7, {s::Side::positive, {0, 1}}},
        "existing hard-stop hold does not invent a new arrival event");
    for (bool power : {false, true}) {
        const f::State buried{{5, 2}, {{7, {3, 2}}}};
        const auto blocked = std::get<f::Blocked>(f::prepare(links, buried, rig, {{5, 2}, power, frame}, {}));
        require(blocked.state == buried && std::get<w::StationaryContact>(blocked.contact).hit == c::Hit{11, {0, 1}, true},
            "initial fractional penetration is checked before pause or rest");
    }

    const std::array<b::Link, 2> bank{{{3, {0, 6, 2, 1}}, {7, {0, 6, 1, 3}}}};
    const f::State shared{{1, 2}, {{3, {0, 1}}, {7, {0, 1}}}};
    const r::Rig crossed{g::Axis::x, box(0, -3), {{3, box(0, 0)}, {7, box(2, 0)}}};
    const std::array<p::Pair, 1> pairs{{{3, 7}}};
    const auto moving = std::get<f::Blocked>(f::prepare(bank, shared, crossed, {{9, 2}, true, {}}, pairs));
    require(moving.state == shared && std::get<w::MovingContact>(moving.contact) == w::MovingContact{{3, 7}, {3, 8}, false},
        "fractional relative sweep retains opaque members and original contact time");
    const std::array<c::Obstacle, 1> pin_frame{{{99, box(3, -3)}}};
    const auto tied = std::get<f::Blocked>(f::prepare(bank, shared, crossed, {{9, 2}, true, pin_frame}, pairs));
    require(std::get<w::StationaryContact>(tied.contact) == w::StationaryContact{{}, {99, {3, 8}, false}},
        "uniform scaling preserves the parent's exact static-before-moving tie");
    auto mutable_state = shared;
    auto mutable_frame = pin_frame;
    auto owned = f::prepare(bank, mutable_state, crossed, {{9, 2}, true, mutable_frame}, pairs);
    mutable_state.followers.clear();
    mutable_frame[0].id = 1;
    require(std::get<f::Blocked>(owned) == tied, "blocked state and contact are independent owned values");
}

void validation() {
    const auto minimum = std::numeric_limits<I>::min(), maximum = std::numeric_limits<I>::max();
    const std::array<g::Rate, 9> malformed{{{1, 0}, {1, -1}, {2, 2}, {0, 2}, {minimum, 1}, {maximum, 1024},
        {1, 1025}, {1, minimum}, {1, maximum}}};
    for (const auto invalid : malformed) {
        auto state = initial;
        state.pin = invalid;
        require(refused(f::prepare(links, state, rig, {{1, 2}, false, frame}, {}), f::Error::invalid_fraction), "reject raw invalid pin safely");
        state = initial;
        state.followers[0].position = invalid;
        require(refused(f::prepare(links, state, rig, {{1, 2}, false, frame}, {}), f::Error::invalid_fraction), "reject raw invalid follower safely");
        require(refused(f::prepare(links, initial, rig, {invalid, false, frame}, {}), f::Error::invalid_fraction), "reject raw invalid destination even paused");
    }
    require(refused(f::prepare(links, {{0, 1}, {{7, {1, 31}}}}, rig, {{1, 37}, false, {}}, {}), f::Error::scale_limit),
        "individually valid denominators cannot exceed the common-scale cap");
    require(std::holds_alternative<f::Advance>(f::prepare(links, initial, rig, {{1, 1024}, true, {}}, {})),
        "maximum admitted denominator remains exact");
    auto wide = links;
    wide[0].slot.front = 4095;
    wide[0].slot.back = 1;
    require(refused(f::prepare(wide, initial, rig, {{1, 2}, true, {}}, {}), f::Error::representation_limit),
        "valid physical slot cannot silently widen scaled native dimension bounds");
    auto far = rig;
    far.pin_at_zero = box(999999, -3);
    require(refused(f::prepare(links, initial, far, {{1, 2}, true, {}}, {}), f::Error::representation_limit),
        "valid physical box beyond scaled grid refuses without rounding");
    require(refused(f::prepare(links, {{1, 2}, {{7, {0, 1}}}}, rig, {{1000000, 1}, true, {}}, {}), f::Error::representation_limit),
        "destination representation is checked before the child query");
    for (I invalid : {minimum, maximum}) {
        auto bad = links;
        bad[0].slot.lower = invalid;
        require(refused(f::prepare(bad, initial, rig, {{1, 2}, false, frame}, {}), f::Error::invalid_input), "profile validated before scaling");
        auto bad_box = rig;
        bad_box.followers[0].at_zero.minimum[0] = invalid;
        require(refused(f::prepare(links, initial, bad_box, {{1, 2}, false, frame}, {}), f::Error::invalid_input), "box validated before multiplication");
    }
    auto bad = frame;
    bad[0].id = 0;
    const std::array<p::Pair, 1> unknown{{{7, 99}}};
    const auto errors = std::get<f::Refusal>(f::prepare(links, initial, rig, {{9, 2}, false, bad}, unknown));
    require(errors.reason == f::Error::parent_refused && errors.parent_error && errors.parent_error->stationary_error &&
        errors.parent_error->moving_error, "invalid stationary and moving constraints are both retained before pause");
    bad[0].box.maximum[0] = bad[0].box.minimum[0];
    require(refused(f::prepare(links, initial, rig, {{9, 2}, true, bad}, {}), f::Error::invalid_input), "malformed geometry cannot become an obstruction");
    require(refused(f::prepare({}, initial, rig, {{1, 2}, true, frame}, {}), f::Error::invalid_input), "empty bank refuses");
    auto missing = initial;
    missing.followers.clear();
    require(refused(f::prepare(links, missing, rig, {{1, 2}, true, frame}, {}), f::Error::invalid_input), "missing state cannot be manufactured");
    auto wrong = rig;
    wrong.followers[0].id = 99;
    require(refused(f::prepare(links, initial, wrong, {{1, 2}, true, frame}, {}), f::Error::parent_refused), "opaque rig identity remains a parent constraint");
    wrong = rig;
    wrong.axis = static_cast<g::Axis>(99);
    require(refused(f::prepare(links, initial, wrong, {{1, 2}, true, frame}, {}), f::Error::parent_refused), "invalid axis refuses even when otherwise clear");
    std::vector<c::Obstacle> many;
    for (std::size_t index = 0; index < g::maximum_parts; ++index) many.push_back({index + 1, box(100, 0)});
    many.back().box = box(2, 0);
    const auto last = std::get<f::Blocked>(f::prepare(links, {{1, 2}, {{7, {0, 1}}}}, rig, {{9, 2}, true, many}, {}));
    require(std::get<w::StationaryContact>(last.contact).hit == c::Hit{g::maximum_parts, {3, 8}, false},
        "last permitted obstacle participates in contact");
    many.push_back({999, box(0, 0)});
    require(refused(f::prepare(links, initial, rig, {{9, 2}, true, many}, {}), f::Error::invalid_input), "oversized obstacle set never truncates");
    std::vector<p::Pair> too_many(p::maximum_pairs + 1, {{}, 7});
    require(refused(f::prepare(links, initial, rig, {{1, 2}, true, {}}, too_many), f::Error::invalid_input), "oversized pair set never truncates");

    std::vector<b::Link> full;
    f::State state{{0, 1}, {}};
    auto shapes = rig;
    shapes.followers.clear();
    std::vector<p::Member> members{{}};
    for (std::size_t index = 0; index < b::maximum_links; ++index) {
        const auto id = std::numeric_limits<b::Id>::max() - static_cast<b::Id>(b::maximum_links - 1 - index);
        full.push_back({id, {-1, 2, 0, 0}});
        state.followers.push_back({id, {0, 1}});
        shapes.followers.push_back({id, box(0, static_cast<I>(index) * 3)});
        members.push_back(id);
    }
    std::vector<p::Pair> all_pairs;
    for (std::size_t a = 0; a < members.size(); ++a)
        for (std::size_t other = a + 1; other < members.size(); ++other) all_pairs.push_back({members[a], members[other]});
    require(all_pairs.size() == p::maximum_pairs, "test declares the complete maximum pair set");
    std::reverse(full.begin(), full.end());
    std::reverse(shapes.followers.begin(), shapes.followers.end());
    const auto complete = std::get<f::Advance>(f::prepare(full, state, shapes, {{1, 2}, true, {}}, all_pairs));
    require(complete.next.followers.size() == b::maximum_links && complete.next.followers.back().position == g::Rate{1, 2},
        "all maximum-count opaque followers and pairs survive canonical derivation");
    all_pairs.back().second = 1;
    require(refused(f::prepare(full, state, shapes, {{1, 2}, true, {}}, all_pairs), f::Error::parent_refused), "invalid last full-set pair cannot hide behind clear earlier pairs");
    full.push_back(full.back());
    require(refused(f::prepare(full, state, shapes, {{1, 2}, true, {}}, {}), f::Error::invalid_input), "oversized bank refuses before copy");
}

void integer_equivalence() {
    const std::array<b::Link, 2> bank{{{3, {0, 4, 2, 1}}, {7, {0, 4, 1, 3}}}};
    const b::State state{0, {{3, 0}, {7, 0}}};
    const f::State rational{{0, 1}, {{3, {0, 1}}, {7, {0, 1}}}};
    const std::array<p::Pair, 1> pairs{{{3, 7}}};
    for (int axis = 0; axis < 3; ++axis) for (I destination : {-5, 0, 2, 4, 9}) for (bool power : {false, true}) {
        r::Rig shapes{static_cast<g::Axis>(axis), box(0, -3), {{3, box(0, 0)}, {7, box(2, 0)}}};
        const auto parent = w::prepare(bank, state, shapes, {{destination, power}, frame}, pairs);
        const auto plan = f::prepare(bank, rational, shapes, {{destination, 1}, power, frame}, pairs);
        if (const auto* error = std::get_if<w::Refusal>(&parent)) {
            require(std::get<f::Refusal>(plan) == f::Refusal{f::Error::parent_refused, *error}, "unit scale preserves exact parent error");
        } else if (const auto* blocked = std::get_if<w::Blocked>(&parent)) {
            require(std::get<f::Blocked>(plan) == f::Blocked{rational, blocked->contact}, "unit scale preserves exact parent witness");
        } else if (const auto* hold = std::get_if<b::Hold>(&parent)) {
            require(std::get<f::Hold>(plan) == f::Hold{rational, hold->reason, hold->limit}, "unit scale preserves exact parent hold");
        } else {
            const auto& step = std::get<b::Advance>(parent);
            const auto& actual = std::get<f::Advance>(plan);
            f::State expected{{step.next.pin, 1}, {}};
            for (const auto& follower : step.next.followers) expected.followers.push_back({follower.id, {follower.position, 1}});
            require(actual == f::Advance{expected, step.traces, step.limit}, "unit scale preserves full parent advance and times");
        }
    }
}

// Independent model: inputs lie on a quarter-unit lattice; walk the pin in
// eighth-unit increments, push each wall directly and stop the WHOLE bank before
// a follower would escape. Integer boxes have exact quarter-lattice contact
// boundaries, so the first strict interior sample follows its boundary by one
// eighth, including delayed moving-pair contact. No production sweep, link,
// scaling or proposal helper participates in this oracle.
struct Model {
    std::vector<I> coordinates;  // Eighth units: pin, then follower(s).
    bool blocked{}, initial{}, limit{};
    I entry{}, total{}, prefix{};
};
Model walk(std::vector<I> coordinates, const std::vector<s::Profile>& slots, I destination, bool powered,
           I frame_x, bool moving_pair) {
    for (auto& value : coordinates) value *= 2;  // Quarter inputs -> eighths.
    destination *= 2;
    Model result{coordinates, false, false, false, 0, std::abs(destination - coordinates[0]), 0};
    const auto intersects = [&](const std::vector<I>& at) {
        if (moving_pair) return at[1] + 8 > at[2] + 16 && at[1] < at[2] + 24;
        return at[1] + 8 > frame_x * 8 && at[1] < frame_x * 8 + 8;
    };
    if (intersects(coordinates)) { result.blocked = result.initial = true; return result; }
    if (!powered || result.total == 0) return result;
    const I direction = destination > coordinates[0] ? 1 : -1;
    for (I distance = 1; distance <= result.total; ++distance) {
        auto next = coordinates;
        next[0] += direction;
        bool outside = false;
        for (std::size_t index = 0; index < slots.size(); ++index) {
            const auto& slot = slots[index];
            const auto follower = index + 1;
            if (next[0] > next[follower] + slot.front * 8) next[follower] = next[0] - slot.front * 8;
            if (next[0] < next[follower] - slot.back * 8) next[follower] = next[0] + slot.back * 8;
            if (next[follower] < slot.lower * 8 || next[follower] > slot.upper * 8) outside = true;
        }
        if (outside) { result.limit = true; break; }
        if (intersects(next)) { result.blocked = true; result.entry = distance - 1; return result; }
        coordinates = std::move(next);
        result.prefix = distance;
    }
    result.coordinates = coordinates;
    // Reaching a stop at the commanded endpoint is also an arrival event.
    for (std::size_t index = 0; index < slots.size(); ++index)
        if (coordinates[0] == (direction > 0 ? slots[index].upper + slots[index].front : slots[index].lower - slots[index].back) * 8)
            result.limit = true;
    return result;
}

void independent_stationary() {
    const auto shapes = rig;
    for (I back = 0; back <= 2; ++back) for (I front = 0; front <= 2; ++front) {
        const s::Profile profile{-1, 2, back, front};
        const std::array<b::Link, 1> bank{{{7, profile}}};
        for (I follower = -4; follower <= 8; follower += 2)
        for (I pin = follower - 4 * back; pin <= follower + 4 * front; ++pin)
        for (I destination = -12; destination <= 16; destination += 3)
        for (I barrier : {-2, 0, 2, 4}) for (bool power : {false, true}) {
            ++model_cases;
            const f::State state{fraction(pin, 4), {{7, fraction(follower, 4)}}};
            const std::array<c::Obstacle, 1> obstacle{{{23, box(barrier, 0)}}};
            const auto expected = walk({pin, follower}, {profile}, destination, power, barrier, false);
            const auto plan = f::prepare(bank, state, shapes, {fraction(destination, 4), power, obstacle}, {});
            if (expected.blocked) {
                const auto* value = std::get_if<f::Blocked>(&plan);
                require(value && value->state == state, "independent quarter-grid static block keeps original state");
                const auto witness = std::get<w::StationaryContact>(value->contact);
                const auto at = expected.initial ? c::Fraction{0, 1} : time(expected.entry, expected.total);
                require(witness == w::StationaryContact{7, {23, at, expected.initial}}, "independent static entry time and initial penetration");
            } else if (expected.prefix == 0) {
                const auto* value = std::get_if<f::Hold>(&plan);
                const auto reason = !power ? b::Stop::unpowered : pin == destination ? b::Stop::rest : b::Stop::limit;
                require(value && value->state == state && value->reason == reason, "independent paused/rest/zero-prefix hold");
                require(value->limit.has_value() == (reason == b::Stop::limit), "independent zero-time stop cause");
            } else {
                const auto* value = std::get_if<f::Advance>(&plan);
                const f::State next{fraction(expected.coordinates[0], 8), {{7, fraction(expected.coordinates[1], 8)}}};
                require(value && value->next == next && value->limit.has_value() == expected.limit, "independent exact fractional endpoint and endstop");
                const I direction = destination > pin ? 1 : -1;
                const I face = follower + (direction > 0 ? front : -back) * 4;
                const I distance = direction * (face - pin) * 2;
                const auto& trace = value->traces[0];
                require(trace.contact.has_value() == (distance <= expected.prefix), "independent reached wall contact existence");
                if (trace.contact) require(trace.contact->at == fraction(distance, expected.total), "independent wall contact remains in original stroke time");
                require(trace.follower_motion.has_value() == (expected.coordinates[1] != follower * 2), "independent positive-duration follower trace");
                if (trace.follower_motion) require(*trace.follower_motion == s::Span{fraction(distance, expected.total), fraction(expected.prefix, expected.total)},
                    "independent fractional moving interval");
                if (value->limit) require(value->limit->id == 7 && value->limit->stop.at == fraction(expected.prefix, expected.total), "independent endstop original-command fraction");
            }
        }
    }
}

void independent_moving() {
    const std::array<b::Link, 2> bank{{{3, {0, 4, 2, 1}}, {7, {0, 4, 1, 3}}}};
    const r::Rig shapes{g::Axis::x, box(0, -3), {{3, box(0, 0)}, {7, box(2, 0)}}};
    const std::array<p::Pair, 1> pairs{{{7, 3}}};
    for (I pin = 0; pin <= 12; ++pin) for (I first = 0; first <= 16; first += 2) for (I second = 0; second <= 16; second += 2) {
        if (pin < first - 8 || pin > first + 4 || pin < second - 4 || pin > second + 12) continue;
        for (I destination = -4; destination <= 24; destination += 3) for (bool power : {false, true}) {
            ++moving_cases;
            const f::State state{fraction(pin, 4), {{3, fraction(first, 4)}, {7, fraction(second, 4)}}};
            const auto expected = walk({pin, first, second}, {bank[0].slot, bank[1].slot}, destination, power, 0, true);
            const auto plan = f::prepare(bank, state, shapes, {fraction(destination, 4), power, {}}, pairs);
            if (expected.blocked) {
                const auto* value = std::get_if<f::Blocked>(&plan);
                require(value && value->state == state, "independent fractional moving block retains the entire bank");
                const auto at = expected.initial ? c::Fraction{0, 1} : time(expected.entry, expected.total);
                require(std::get<w::MovingContact>(value->contact) == w::MovingContact{{3, 7}, at, expected.initial}, "independent moving-pair entry and canonical identity");
            } else if (expected.prefix == 0) {
                const auto* value = std::get_if<f::Hold>(&plan);
                require(value && value->state == state, "independent fractional moving bank hold");
            } else {
                const auto* value = std::get_if<f::Advance>(&plan);
                const f::State next{fraction(expected.coordinates[0], 8), {{3, fraction(expected.coordinates[1], 8)}, {7, fraction(expected.coordinates[2], 8)}}};
                require(value && value->next == next && value->limit.has_value() == expected.limit, "independent moving bank exact endpoints and prefix");
            }
        }
    }
}

void terminal() {
    struct Case { const char* input; int code; const char* evidence; };
    const std::array<Case, 8> cases{{
        {"power off\ngear half\npower on\nstep 3\nquit\n", 0, "Native output 1/2."},
        {"power off\ngear quarter\npower on\nstep 6\nquit\n", 0, "Native output 1/4."},
        {"step 3\nquit\n", 1, "Frame 11 blocks tool 7 at 0/1; all original positions retained."},
        {"step 3\npower off\ngear half\ndirection reverse\npower on\nstep 7\npower off\ndirection forward\npower on\nstep 6\nquit\n", 0, "Matched: original pin 3/2 and tool 1/2"},
        {"step 3\npower off\ngear quarter\ndirection reverse\npower on\nstep 14\npower off\ndirection forward\npower on\nstep 12\nquit\n", 0, "Matched: original pin 3/2 and tool 1/2"},
        {"gear half\nstep 1\nquit\n", 1, "Refused: stop power before changing the drive."},
        {"power off\nstep 32\nquit\n", 1, "Hold unpowered; all original positions retained."},
        {"step 0\nstep 33\nstep 1tail\nstep 1 extra\nquit tail\nstatus\nquit\n", 1, "Pin 0/1; tool 0/1; gear direct"},
    }};
    for (const auto& value : cases) {
        std::istringstream input(value.input);
        std::ostringstream output, errors;
        const auto code = f::play(input, output, errors);
        require(code == value.code && errors.str().empty() && output.str().find(value.evidence) != std::string::npos,
            "actual gear-driven terminal consumer preserves outcome and witness");
    }
    std::istringstream oversized(std::string(513, 'x') + "\nstatus\nquit\n");
    std::ostringstream output, errors;
    require(f::play(oversized, output, errors) == 1 && output.str().find("command exceeds 512 bytes") != std::string::npos &&
        output.str().find("Pin 0/1; tool 0/1") != std::string::npos, "oversized command drains without changing original state");
    std::istringstream failed;
    failed.setstate(std::ios::badbit);
    require(f::play(failed, output, errors) == 2, "failed input returns an operational error");
}
}  // namespace

int main() {
    controls();
    validation();
    integer_equivalence();
    independent_stationary();
    independent_moving();
    terminal();
    std::cout << "Passed " << assertions << " assertions; " << model_cases << " independent fractional static cases and "
              << moving_cases << " independent fractional moving cases.\n";
}
