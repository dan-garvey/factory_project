#include "factory/slotted_workcell.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>

namespace w = factory::slotted_workcell;
namespace s = factory::slotted_clearance;
namespace p = factory::slotted_pairs;
namespace b = factory::slotted_bank;
namespace c = factory::clearance;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
std::size_t assertions{}, oracle_cases{};
void require(bool condition, const char* message) {
    ++assertions;
    if (!condition) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
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
s::Rig rig(std::size_t axis, I spacing = 2, I lane = 0) {
    return {static_cast<g::Axis>(axis), box(axis, -2, -8), {{3, box(axis, 0)}, {7, box(axis, spacing, lane)}}};
}
const b::State initial{0, {{3, 0}, {7, 0}}};
const std::array<b::Link, 2> links{{{3, {0, 6, 2, 1}}, {7, {0, 6, 1, 3}}}};
const std::array<p::Pair, 1> pair_set{{{3, 7}}};
c::Fraction time(const w::Blocked& blocked) {
    if (const auto* fixed = std::get_if<w::StationaryContact>(&blocked.contact)) return fixed->hit.time;
    return std::get<w::MovingContact>(blocked.contact).time;
}
void controls() {
    const std::array<c::Obstacle, 1> near_frame{{{11, box(0, 5)}}};
    auto result = w::prepare(links, initial, rig(0), {{4, true}, near_frame}, pair_set);
    const auto* blocked = std::get_if<w::Blocked>(&result);
    require(blocked && blocked->state == initial && std::holds_alternative<w::MovingContact>(blocked->contact) &&
        time(*blocked) == c::Fraction{1, 2}, "close tools collide before reaching the frame");
    result = w::prepare(links, initial, rig(0, 4), {{4, true}, near_frame}, pair_set);
    blocked = std::get_if<w::Blocked>(&result);
    require(blocked && std::holds_alternative<w::StationaryContact>(blocked->contact) &&
        std::get<w::StationaryContact>(blocked->contact).member == p::Member{7} && time(*blocked) == c::Fraction{3, 4},
        "spreading tools clears the pair but exposes the delayed frame contact");
    const std::array<c::Obstacle, 1> early_frame{{{11, box(0, 1)}}};
    result = w::prepare(links, initial, rig(0), {{4, true}, early_frame}, pair_set);
    blocked = std::get_if<w::Blocked>(&result);
    require(blocked && std::holds_alternative<w::StationaryContact>(blocked->contact) && time(*blocked) == c::Fraction{1, 4},
        "earlier stationary contact beats a later moving-pair hit");

    auto tied_rig = rig(0);
    tied_rig.followers[0].at_zero.maximum[1] = 2;
    tied_rig.followers[1].at_zero.minimum[1] = 1;
    tied_rig.followers[1].at_zero.maximum[1] = 3;
    const std::array<c::Obstacle, 2> tied_obstacles{{{11, box(0, 2)}, {5, box(0, 2)}}};
    result = w::prepare(links, initial, tied_rig, {{4, true}, tied_obstacles}, pair_set);
    blocked = std::get_if<w::Blocked>(&result);
    require(blocked && time(*blocked) == c::Fraction{1, 2} && std::holds_alternative<w::StationaryContact>(blocked->contact) &&
        std::get<w::StationaryContact>(blocked->contact).hit.obstacle == 5,
        "equal global times choose stationary family and its canonical obstacle identity");
    auto reordered_rig = tied_rig;
    std::reverse(reordered_rig.followers.begin(), reordered_rig.followers.end());
    auto reordered_obstacles = tied_obstacles;
    std::reverse(reordered_obstacles.begin(), reordered_obstacles.end());
    const std::array<p::Pair, 1> reversed_pair{{{7, 3}}};
    require(w::prepare(links, initial, reordered_rig, {{4, true}, reordered_obstacles}, reversed_pair) == result,
        "shape, obstacle and pair order preserve the same combined witness");

    // A lower-ID tangent must not hide A's existing penetration during slack.
    // The pin/A pair also enters at global zero, so the corrected stationary
    // adapter must supply its original overlap for the declared family tie.
    auto overlapping = rig(0, 10, 5);
    overlapping.pin_at_zero = box(0, -1, 1);
    overlapping.pin_at_zero.maximum[1] = 3;
    overlapping.followers[0].at_zero.maximum[0] = 2;
    overlapping.followers[0].at_zero.maximum[1] = 2;
    const std::array<c::Obstacle, 2> shadow{{{1, box(0, 2)}, {9, box(0, 0)}}};
    const std::array<p::Pair, 1> pin_pair{{{{}, 3}}};
    result = w::prepare(links, initial, overlapping, {{4, true}, shadow}, pin_pair);
    blocked = std::get_if<w::Blocked>(&result);
    const auto* original = blocked ? std::get_if<w::StationaryContact>(&blocked->contact) : nullptr;
    require(original && original->member == p::Member{3} && original->hit.obstacle == 9 &&
        original->hit.initially_overlapping && original->hit.time == c::Fraction{0, 1},
        "delayed original penetration survives the local-zero ambiguity and family competition");

    const std::array<c::Obstacle, 1> initial_frame{{{11, box(0, 0)}}};
    const std::array<p::Pair, 2> unknown_pair{{{3, 7}, {3, 99}}};
    result = w::prepare(links, initial, rig(0), {{4, false}, initial_frame}, unknown_pair);
    const auto* refusal = std::get_if<w::Refusal>(&result);
    require(refusal && refusal->reason == w::Error::moving_refused && refusal->moving_error && !refusal->stationary_error,
        "earlier stationary penetration cannot hide an invalid later moving pair while paused");
    const std::array<c::Obstacle, 2> invalid_obstacles{{{11, box(0, 5)}, {99, {{0, 0, 0}, {0, 1, 1}}}}};
    result = w::prepare(links, initial, rig(0), {{4, true}, invalid_obstacles}, pair_set);
    refusal = std::get_if<w::Refusal>(&result);
    require(refusal && refusal->reason == w::Error::stationary_refused && refusal->stationary_error,
        "moving-pair hit cannot hide an invalid later stationary obstacle");
    result = w::prepare(links, initial, rig(0), {{4, false}, invalid_obstacles}, unknown_pair);
    refusal = std::get_if<w::Refusal>(&result);
    require(refusal && refusal->stationary_error && refusal->moving_error, "both refusal families survive without a proposed result");
    auto bad_state = initial;
    bad_state.pin = std::numeric_limits<I>::min();
    result = w::prepare(links, bad_state, rig(0), {{std::numeric_limits<I>::max(), false}, near_frame}, pair_set);
    refusal = std::get_if<w::Refusal>(&result);
    require(refusal && refusal->stationary_error && refusal->moving_error, "raw invalid coordinates refuse before time comparison");

    const auto raised = rig(0, 2, 3);
    result = w::prepare(links, initial, raised, {{4, false}, near_frame}, pair_set);
    const auto stopped = s::prepare(links, initial, raised, {{4, false}, near_frame});
    require(std::holds_alternative<b::Hold>(result) && std::get<b::Hold>(result) == std::get<b::Hold>(stopped),
        "clear unpowered hold is exactly the existing bank proposal");
    const std::array<c::Obstacle, 1> distant{{{11, box(0, 50)}}};
    result = w::prepare(links, initial, raised, {{32, true}, distant}, pair_set);
    const auto parent = s::prepare(links, initial, raised, {{32, true}, distant});
    require(std::holds_alternative<b::Advance>(result) && std::get<b::Advance>(result) == std::get<b::Advance>(parent) &&
        std::get<b::Advance>(result).limit, "clear clipped advance preserves every original trace and stop cause");
    const auto advanced = std::get<b::Advance>(result).next;
    require(w::prepare(links, advanced, raised, {{32, true}, distant}, pair_set) ==
        w::Plan{std::get<b::Hold>(s::prepare(links, advanced, raised, {{32, true}, distant}))}, "time-zero endstop hold remains unchanged");

    auto mutable_state = initial;
    auto mutable_rig = rig(0, 4);
    auto mutable_obstacles = near_frame;
    result = w::prepare(links, mutable_state, mutable_rig, {{4, true}, mutable_obstacles}, pair_set);
    const auto retained = std::get<w::Blocked>(result);
    mutable_state.followers.clear();
    mutable_rig.followers.clear();
    mutable_obstacles[0].id = 99;
    require(std::get<w::Blocked>(result) == retained, "combined blocked output owns the original state and typed witness");

    const auto large_id = std::numeric_limits<p::Id>::max();
    auto opaque_links = links;
    opaque_links[1].id = large_id;
    auto opaque_state = initial;
    opaque_state.followers[1].id = large_id;
    auto opaque_rig = rig(0, 4);
    opaque_rig.followers[1].id = large_id;
    auto opaque_obstacles = near_frame;
    opaque_obstacles[0].id = std::numeric_limits<std::uint64_t>::max();
    const std::array<p::Pair, 1> opaque_pair{{{large_id, 3}}};
    result = w::prepare(opaque_links, opaque_state, opaque_rig, {{4, true}, opaque_obstacles}, opaque_pair);
    blocked = std::get_if<w::Blocked>(&result);
    original = blocked ? std::get_if<w::StationaryContact>(&blocked->contact) : nullptr;
    require(original && original->member == p::Member{large_id} && original->hit.obstacle == opaque_obstacles[0].id,
        "maximum opaque identities survive without coordinate conversion");

    constexpr I bound = g::maximum_coordinate;
    const std::array<b::Link, 1> far_link{{{3, {-bound + 1, bound - 4, 0, 4}}}};
    const b::State far_state{-bound + 1, {{3, -bound + 1}}};
    const s::Rig far_rig{g::Axis::x, box(0, 0), {{3, box(0, 2)}}};
    const std::array<c::Obstacle, 1> far_obstacle{{{11, box(0, 0)}}};
    result = w::prepare(far_link, far_state, far_rig, {{bound - 1, true}, far_obstacle}, pin_pair);
    blocked = std::get_if<w::Blocked>(&result);
    require(blocked && std::holds_alternative<w::MovingContact>(blocked->contact) && time(*blocked) == fraction(1, 2 * bound - 2),
        "near-grid-bound parent times compare exactly without arithmetic expansion");
}

bool before(const w::Blocked& a, const w::Blocked& other) {
    const auto ta = time(a), tb = time(other);
    if (ta.numerator * tb.denominator != tb.numerator * ta.denominator)
        return ta.numerator * tb.denominator < tb.numerator * ta.denominator;
    if (a.contact.index() != other.contact.index()) return a.contact.index() < other.contact.index();
    if (const auto* fixed = std::get_if<w::StationaryContact>(&a.contact)) {
        const auto& other_fixed = std::get<w::StationaryContact>(other.contact);
        return fixed->member != other_fixed.member ? fixed->member < other_fixed.member : fixed->hit.obstacle < other_fixed.hit.obstacle;
    }
    const auto& pair = std::get<w::MovingContact>(a.contact).pair;
    const auto& other_pair = std::get<w::MovingContact>(other.contact).pair;
    return pair.first != other_pair.first ? pair.first < other_pair.first : pair.second < other_pair.second;
}
bool overlap(const c::Box& a, I offset_a, const c::Box& other, I offset_b, std::size_t axis) {
    for (std::size_t dimension = 0; dimension < 3; ++dimension) {
        const auto shift_a = dimension == axis ? offset_a : 0;
        const auto shift_b = dimension == axis ? offset_b : 0;
        if (2 * a.maximum[dimension] + shift_a <= 2 * other.minimum[dimension] + shift_b ||
            2 * a.minimum[dimension] + shift_a >= 2 * other.maximum[dimension] + shift_b) return false;
    }
    return true;
}
struct Oracle { b::State next; std::optional<w::Blocked> blocked; };
// Independent simultaneous half-grid pushes and strict box interiors. No bank,
// pair, clearance or combined API supplies a pose, contact or stop. First
// penetration occurs half a grid step after an integer contact plane. Track
// first contacts separately so later samples cannot relabel initial overlap.
Oracle simulate(const std::array<b::Link, 2>& profiles, const b::State& state, const s::Rig& shapes,
                const std::array<c::Obstacle, 2>& obstacles, std::span<const p::Pair> pairs, I destination, bool powered) {
    Oracle expected{state, {}};
    const auto axis = static_cast<std::size_t>(shapes.axis);
    const std::array<c::Box, 3> boxes{{shapes.pin_at_zero, shapes.followers[0].at_zero, shapes.followers[1].at_zero}};
    std::array<I, 3> positions{{2 * state.pin, 2 * state.followers[0].position, 2 * state.followers[1].position}};
    const I ticks = 2 * std::abs(destination - state.pin);
    const I direction = destination < state.pin ? -1 : 1;
    std::array<std::array<bool, 2>, 3> seen_fixed{};
    std::vector<bool> seen_pair(pairs.size(), false);
    const auto accept = [&](w::Blocked hit) {
        if (!expected.blocked || before(hit, *expected.blocked)) expected.blocked = std::move(hit);
    };
    const auto sample = [&](I tick) {
        for (std::size_t member = 0; member < boxes.size(); ++member)
        for (std::size_t obstacle = 0; obstacle < obstacles.size(); ++obstacle) {
            if (seen_fixed[member][obstacle] || !overlap(boxes[member], positions[member], obstacles[obstacle].box, 0, axis)) continue;
            seen_fixed[member][obstacle] = true;
            require(tick == 0 || tick % 2 == 1, "joint fixed contact follows an integer plane");
            const auto at = tick == 0 ? c::Fraction{0, 1} : fraction(tick - 1, ticks);
            const p::Member identity = member == 0 ? p::Member{} : p::Member{state.followers[member - 1].id};
            accept({state, w::StationaryContact{identity, {obstacles[obstacle].id, at, tick == 0}}});
        }
        const auto index = [](p::Member member) { return member ? (*member == 3 ? 1U : 2U) : 0U; };
        for (std::size_t pair = 0; pair < pairs.size(); ++pair) {
            const auto a = index(pairs[pair].first), other = index(pairs[pair].second);
            if (seen_pair[pair] || !overlap(boxes[a], positions[a], boxes[other], positions[other], axis)) continue;
            seen_pair[pair] = true;
            require(tick == 0 || tick % 2 == 1, "joint moving contact follows an integer plane");
            const auto at = tick == 0 ? c::Fraction{0, 1} : fraction(tick - 1, ticks);
            accept({state, w::MovingContact{pairs[pair], at, tick == 0}});
        }
    };
    sample(0);
    if (powered) for (I tick = 1; tick <= ticks; ++tick) {
        auto next = positions;
        next[0] += direction;
        bool stopped = false;
        for (std::size_t follower = 0; follower < profiles.size(); ++follower) {
            const auto& slot = profiles[follower].slot;
            next[follower + 1] = std::clamp(positions[follower + 1], next[0] - 2 * slot.front, next[0] + 2 * slot.back);
            if (next[follower + 1] < 2 * slot.lower || next[follower + 1] > 2 * slot.upper) stopped = true;
        }
        if (stopped) break;
        positions = next;
        sample(tick);
    }
    expected.next.pin = positions[0] / 2;
    for (std::size_t follower = 0; follower < state.followers.size(); ++follower)
        expected.next.followers[follower].position = positions[follower + 1] / 2;
    return expected;
}
void exhaustive() {
    const std::array<std::pair<I, I>, 3> clearances{{{0, 0}, {2, 1}, {1, 2}}};
    for (const auto& [back_a, front_a] : clearances) for (const auto& [back_b, front_b] : clearances)
    for (I a = -1; a <= 1; ++a) for (I other = -1; other <= 1; ++other) {
        if (0 < a - back_a || 0 > a + front_a || 0 < other - back_b || 0 > other + front_b) continue;
        const std::array<b::Link, 2> profiles{{{3, {-2, 2, back_a, front_a}}, {7, {-2, 2, back_b, front_b}}}};
        const b::State state{0, {{3, a}, {7, other}}};
        for (const I destination : {-3, 0, 3}) for (const I spacing : {0, 2}) for (const I frame : {2, 4})
        for (const I lane : {0, 1}) for (const bool include_pin : {false, true})
        for (std::size_t axis = 0; axis < 3; ++axis) for (const bool powered : {false, true}) {
            auto shapes = rig(axis, spacing, lane);
            if (include_pin) shapes.pin_at_zero = box(axis, -2);
            const std::array<c::Obstacle, 2> obstacles{{{11, box(axis, frame)}, {5, box(axis, frame + 1)}}};
            const std::vector<p::Pair> pairs = include_pin ? std::vector<p::Pair>{{{}, 3}, {3, 7}} : std::vector<p::Pair>{{3, 7}};
            const auto expected = simulate(profiles, state, shapes, obstacles, pairs, destination, powered);
            const auto actual = w::prepare(profiles, state, shapes, {{destination, powered}, obstacles}, pairs);
            ++oracle_cases;
            require(!std::holds_alternative<w::Refusal>(actual), "valid combined joint-path case must not refuse");
            const auto* blocked = std::get_if<w::Blocked>(&actual);
            require((blocked != nullptr) == expected.blocked.has_value(), "combined obstruction agrees with independent joint path");
            if (blocked) require(*blocked == *expected.blocked, "earliest global typed witness and original bank agree with joint path");
            else {
                const auto& next = std::holds_alternative<b::Advance>(actual) ? std::get<b::Advance>(actual).next : std::get<b::Hold>(actual).state;
                require(next == expected.next, "clear bank agrees with independent simultaneous pushes and guide stops");
            }
        }
    }
}
}  // namespace
int main() {
    controls();
    exhaustive();
    std::cout << assertions << " slotted-workcell assertions passed, including " << oracle_cases
              << " independent joint-obstacle half-grid cases.\n";
}
