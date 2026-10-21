#include "factory/slotted_pairs.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>

namespace p = factory::slotted_pairs;
namespace b = factory::slotted_bank;
namespace s = factory::slotted_clearance;
namespace c = factory::clearance;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
std::size_t assertions{}, oracle_cases{};
void require(bool condition, const char* message) {
    ++assertions;
    if (!condition) {
        std::cerr << "Assertion " << assertions << " failed: " << message << '\n';
        std::exit(1);
    }
}
c::Fraction fraction(I numerator, I denominator) {
    const auto divisor = std::gcd(numerator, denominator);
    return {numerator / divisor, denominator / divisor};
}
c::Box box(std::size_t axis, I along, I lane = 0) {
    c::Box result{{0, 0, 0}, {1, 1, 1}};
    result.minimum[axis] = along;
    result.maximum[axis] = along + 1;
    result.minimum[(axis + 1) % 3] = lane;
    result.maximum[(axis + 1) % 3] = lane + 1;
    return result;
}
s::Rig rig(std::size_t axis, I a = 0, I other = 2, I lane = 0) {
    return {static_cast<g::Axis>(axis), box(axis, 0, -8), {{3, box(axis, a)}, {7, box(axis, other, lane)}}};
}
const std::array<p::Pair, 1> followers{{{3, 7}}};
const b::State initial{0, {{3, 0}, {7, 0}}};
const std::array<b::Link, 2> delayed{{{3, {0, 6, 2, 1}}, {7, {0, 6, 1, 3}}}};

void controls() {
    auto shapes = rig(0);
    auto result = p::prepare(delayed, initial, shapes, {4, true}, followers);
    const auto* blocked = std::get_if<p::Blocked>(&result);
    require(blocked && blocked->state == initial && blocked->pair == followers[0] &&
        blocked->time == c::Fraction{1, 2} && !blocked->initially_overlapping, "delayed pair holds whole original bank at global half stroke");

    auto matched = delayed;
    matched[1].slot.front = 1;
    result = p::prepare(matched, initial, shapes, {4, true}, followers);
    require(std::holds_alternative<b::Advance>(result), "co-moving followers preserve their gap");
    const c::Obstacle naive_obstacle{1, shapes.followers[1].at_zero};
    require(c::sweep(shapes.followers[0].at_zero, {3, 0, 0}, std::span{&naive_obstacle, 1}).hit.has_value(),
        "treating the other moving follower as static would falsely obstruct");
    const auto parent = s::prepare(matched, initial, shapes, {{4, true}, {}});
    require(std::get<b::Advance>(result) == std::get<b::Advance>(parent), "clear result preserves every parent trace and limit");
    const auto outward = std::get<b::Advance>(result).next;
    result = p::prepare(matched, outward, shapes, {0, true}, followers);
    require(std::holds_alternative<b::Advance>(result) &&
        std::get<b::Advance>(result).next == b::State{0, {{3, 2}, {7, 1}}}, "reverse finishes matched kit with tangent relative endpoint");

    shapes = rig(0, 0, 1);
    result = p::prepare(delayed, initial, shapes, {4, true}, followers);
    blocked = std::get_if<p::Blocked>(&result);
    require(blocked && blocked->time == c::Fraction{1, 4} && !blocked->initially_overlapping,
        "touch followed by delayed penetration is at delay, not local zero");
    shapes = rig(0, 0, 0);
    for (const auto drive : {factory::slotted_link::Observation{4, false}, {0, true}, {4, true}}) {
        result = p::prepare(delayed, initial, shapes, drive, followers);
        blocked = std::get_if<p::Blocked>(&result);
        require(blocked && blocked->initially_overlapping && blocked->time == c::Fraction{0, 1} && blocked->state == initial,
            "existing penetration remains global time zero even paused");
    }

    const std::array<b::Link, 3> three{{{1, {0, 6, 1, 3}}, {3, {0, 6, 2, 2}}, {7, {0, 6, 0, 0}}}};
    const b::State three_state{0, {{1, 0}, {3, 0}, {7, 0}}};
    const s::Rig three_rig{g::Axis::x, box(0, 0, -8), {{1, box(0, 1)}, {3, box(0, 0)}, {7, box(0, -2)}}};
    const std::array<p::Pair, 2> two_pairs{{{1, 3}, {3, 7}}};
    result = p::prepare(three, three_state, three_rig, {4, true}, two_pairs);
    blocked = std::get_if<p::Blocked>(&result);
    require(blocked && blocked->pair == two_pairs[1] && blocked->time == c::Fraction{1, 4},
        "later canonical pair with nonzero local contact beats local-zero contact after longer delay");

    shapes = rig(0, 0, 0);
    shapes.pin_at_zero = box(0, 0);
    const std::array<p::Pair, 2> tied{{{7, 3}, {3, {}}}};
    result = p::prepare(delayed, initial, shapes, {4, false}, tied);
    blocked = std::get_if<p::Blocked>(&result);
    require(blocked && blocked->pair == p::Pair{{}, 3} && blocked->time == c::Fraction{0, 1}, "time ties select canonical pin pair");
    auto shuffled = shapes;
    std::reverse(shuffled.followers.begin(), shuffled.followers.end());
    const std::array<p::Pair, 2> reordered{{{{}, 3}, {3, 7}}};
    require(p::prepare(delayed, initial, shuffled, {4, false}, reordered) == result,
        "shape, pair and member order cannot change a witness");

    const std::array<p::Pair, 2> duplicate{{{3, 7}, {7, 3}}};
    const std::array<p::Pair, 2> unknown{{{3, 7}, {3, 9}}};
    const std::array<p::Pair, 1> self{{{3, 3}}}, zero{{{0, 3}}};
    for (const auto pairs : {std::span<const p::Pair>{duplicate}, std::span<const p::Pair>{unknown},
                             std::span<const p::Pair>{self}, std::span<const p::Pair>{zero}}) {
        result = p::prepare(delayed, initial, shapes, {4, false}, pairs);
        const auto* refusal = std::get_if<p::Refusal>(&result);
        require(refusal && refusal->reason == p::Error::invalid_pair_set, "invalid pair refuses despite an earlier overlap or pause");
    }
    std::vector<p::Pair> excessive(p::maximum_pairs + 1, followers[0]);
    require(std::holds_alternative<p::Refusal>(p::prepare(delayed, initial, shapes, {4, true}, excessive)), "overfull pair set refuses");
    result = p::prepare(delayed, initial, shapes, {4, false}, {});
    require(std::holds_alternative<b::Hold>(result), "empty pair set grants no implicit mating classification");

    auto invalid = shapes;
    invalid.followers[1].at_zero.maximum[1] = invalid.followers[1].at_zero.minimum[1];
    result = p::prepare(delayed, initial, invalid, {4, true}, tied);
    const auto* refusal = std::get_if<p::Refusal>(&result);
    require(refusal && refusal->reason == p::Error::parent_refused && refusal->parent_error,
        "late invalid proxy refuses before any earlier contact result");
    invalid = shapes;
    invalid.axis = static_cast<g::Axis>(99);
    require(std::holds_alternative<p::Refusal>(p::prepare(delayed, initial, invalid, {4, false}, followers)), "invalid axis is never indexed");
    auto raw_state = initial;
    raw_state.pin = std::numeric_limits<I>::min();
    require(std::holds_alternative<p::Refusal>(p::prepare(delayed, raw_state, shapes, {4, false}, followers)), "raw coordinate refusal precedes subtraction");
    require(std::holds_alternative<p::Refusal>(p::prepare(delayed, initial, shapes,
        {std::numeric_limits<I>::max(), false}, followers)), "raw destination refuses even paused");

    const auto largest = std::numeric_limits<p::Id>::max();
    auto opaque_links = delayed;
    opaque_links[1].id = largest;
    auto opaque_state = initial;
    opaque_state.followers[1].id = largest;
    auto opaque_rig = rig(0);
    opaque_rig.followers[1].id = largest;
    const std::array<p::Pair, 1> opaque_pair{{{largest, 3}}};
    result = p::prepare(opaque_links, opaque_state, opaque_rig, {4, true}, opaque_pair);
    blocked = std::get_if<p::Blocked>(&result);
    require(blocked && blocked->pair == p::Pair{3, largest}, "maximum opaque identity is not a coordinate or array index");

    constexpr I bound = g::maximum_coordinate;
    const std::array<b::Link, 1> far_link{{{3, {-bound + 1, bound - 4, 0, 4}}}};
    const b::State far_state{-bound + 1, {{3, -bound + 1}}};
    const s::Rig far_rig{g::Axis::x, box(0, 0), {{3, box(0, 2)}}};
    const std::array<p::Pair, 1> pin_pair{{{{}, 3}}};
    result = p::prepare(far_link, far_state, far_rig, {bound - 1, true}, pin_pair);
    blocked = std::get_if<p::Blocked>(&result);
    require(blocked && blocked->time == fraction(1, 2 * bound - 2), "near-bound relative path remains exact and in the canonical grid");

    std::vector<b::Link> full_links;
    b::State full_state;
    s::Rig full_rig{g::Axis::x, box(0, 0), {}};
    std::vector<p::Pair> all_pairs;
    for (p::Id id = 1; id <= b::maximum_links; ++id) {
        full_links.push_back({id, {-2, 2, 0, 0}});
        full_state.followers.push_back({id, 0});
        full_rig.followers.push_back({id, box(0, 0)});
        all_pairs.push_back({{}, id});
        for (p::Id other = 1; other < id; ++other) all_pairs.push_back({id, other});
    }
    require(all_pairs.size() == p::maximum_pairs, "full bounded rig admits all unordered pairs");
    result = p::prepare(full_links, full_state, full_rig, {1, true}, all_pairs);
    blocked = std::get_if<p::Blocked>(&result);
    require(blocked && blocked->pair == p::Pair{{}, 1}, "full bank selects first canonical pair without truncation");
    const auto retained = *blocked;
    full_state.followers[0].position = 1;
    full_rig.followers.clear();
    all_pairs.clear();
    require(std::get<p::Blocked>(result) == retained, "blocked result owns original state and witness");
}

// Independent half-grid model: increment the shared pin by half a unit, push
// each original follower only when its slot wall is crossed, and stop ALL
// members before any follower would exceed its guide. It never asks the bank,
// admission adapter or sweep for a pose or contact.
struct Oracle { b::State next; std::optional<c::Fraction> time; bool initial{}; };
bool overlap(const s::Rig& shapes, const std::array<I, 2>& positions) {
    const auto axis = static_cast<std::size_t>(shapes.axis);
    for (std::size_t dimension = 0; dimension < 3; ++dimension) {
        const auto& a = shapes.followers[0].at_zero;
        const auto& other = shapes.followers[1].at_zero;
        const I offset_a = dimension == axis ? positions[0] : 0;
        const I offset_b = dimension == axis ? positions[1] : 0;
        if (2 * a.maximum[dimension] + offset_a <= 2 * other.minimum[dimension] + offset_b ||
            2 * a.minimum[dimension] + offset_a >= 2 * other.maximum[dimension] + offset_b) return false;
    }
    return true;
}
Oracle simulate(const std::array<b::Link, 2>& links, const b::State& state, const s::Rig& shapes,
                I destination, bool powered) {
    Oracle expected{state, {}, false};
    std::array<I, 2> positions{{2 * state.followers[0].position, 2 * state.followers[1].position}};
    I pin = 2 * state.pin;
    const I ticks = 2 * std::abs(destination - state.pin);
    const I direction = destination < state.pin ? -1 : 1;
    if (overlap(shapes, positions)) { expected.time = c::Fraction{0, 1}; expected.initial = true; }
    if (powered) {
        for (I tick = 1; tick <= ticks; ++tick) {
            const I next_pin = pin + direction;
            auto proposed = positions;
            bool stop = false;
            for (std::size_t index = 0; index < links.size(); ++index) {
                const auto& slot = links[index].slot;
                proposed[index] = std::clamp(positions[index], next_pin - 2 * slot.front, next_pin + 2 * slot.back);
                if (proposed[index] < 2 * slot.lower || proposed[index] > 2 * slot.upper) stop = true;
            }
            if (stop) break;
            pin = next_pin;
            positions = proposed;
            if (!expected.time && overlap(shapes, positions)) {
                require(tick % 2 == 1, "integer geometry first penetrates a half-step after contact");
                expected.time = fraction(tick - 1, ticks);
            }
        }
    }
    expected.next.pin = pin / 2;
    for (std::size_t index = 0; index < positions.size(); ++index)
        expected.next.followers[index].position = positions[index] / 2;
    return expected;
}
void exhaustive() {
    const std::array<std::pair<I, I>, 4> clearances{{{0, 0}, {2, 1}, {1, 2}, {2, 2}}};
    for (const auto& [back_a, front_a] : clearances) for (const auto& [back_b, front_b] : clearances)
    for (I a = -1; a <= 1; ++a) for (I other = -1; other <= 1; ++other) {
        if (0 < a - back_a || 0 > a + front_a || 0 < other - back_b || 0 > other + front_b) continue;
        const std::array<b::Link, 2> links{{{3, {-2, 2, back_a, front_a}}, {7, {-2, 2, back_b, front_b}}}};
        const b::State state{0, {{3, a}, {7, other}}};
        for (I destination = -3; destination <= 3; ++destination)
        for (I offset_a = -1; offset_a <= 1; ++offset_a)
        for (I offset_b = 1; offset_b <= 3; ++offset_b)
        for (I lane = 0; lane <= 1; ++lane)
        for (std::size_t axis = 0; axis < 3; ++axis)
        for (const bool powered : {false, true}) {
            const auto shapes = rig(axis, offset_a, offset_b, lane);
            const auto expected = simulate(links, state, shapes, destination, powered);
            const auto actual = p::prepare(links, state, shapes, {destination, powered}, followers);
            ++oracle_cases;
            require(!std::holds_alternative<p::Refusal>(actual), "valid independent case must not refuse");
            const auto* blocked = std::get_if<p::Blocked>(&actual);
            require((blocked != nullptr) == expected.time.has_value(), "continuous pair overlap agrees with joint half-grid path");
            if (blocked) {
                require(blocked->state == state && blocked->pair == followers[0] &&
                    blocked->time == *expected.time && blocked->initially_overlapping == expected.initial,
                    "blocked result retains original state and exact original-stroke witness");
            } else {
                const auto& next = std::holds_alternative<b::Advance>(actual) ? std::get<b::Advance>(actual).next : std::get<b::Hold>(actual).state;
                require(next == expected.next, "clear whole-bank endpoint agrees with independent pushes and shared stop");
            }
        }
    }
}
}  // namespace
int main() {
    controls();
    exhaustive();
    std::cout << assertions << " slotted-pair assertions passed, including " << oracle_cases
              << " independent half-grid relative-path cases.\n";
}
