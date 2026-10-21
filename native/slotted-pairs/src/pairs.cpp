#include "factory/slotted_pairs.hpp"

#include <algorithm>
#include <numeric>

namespace factory::slotted_pairs {
namespace b = slotted_bank;
namespace c = clearance;
namespace s = slotted_clearance;
namespace {
using I = mechanics::Integer;
static_assert(mechanics::maximum_coordinate > 0 && mechanics::maximum_coordinate <= 1000000);
I magnitude(I value) noexcept { return value < 0 ? -value : value; } // Validated differences only.
bool before(const Pair& a, const Pair& other) noexcept {
    return a.first != other.first ? a.first < other.first : a.second < other.second;
}
struct Body {
    Member member;
    c::Box start;
    I travel{}, delay{};
};
bool before(const Blocked& a, const Blocked& other) noexcept {
    const auto left = a.time.numerator * other.time.denominator;
    const auto right = other.time.numerator * a.time.denominator;
    return left != right ? left < right : before(a.pair, other.pair);
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::parent_refused: return "parent_refused";
        case Error::invalid_pair_set: return "invalid_pair_set";
        case Error::query_refused: return "query_refused";
        case Error::inconsistent_motion: return "inconsistent_motion";
    }
    return "unknown";
}

Plan prepare(std::span<const b::Link> links, const b::State& state, const s::Rig& rig,
             const slotted_link::Observation& drive, std::span<const Pair> pairs) {
    const auto parent = s::prepare(links, state, rig, {drive, {}});
    if (const auto* error = std::get_if<s::Refusal>(&parent))
        return Refusal{Error::parent_refused, {}, *error};
    const auto* advancing = std::get_if<b::Advance>(&parent);
    if (!advancing && !std::holds_alternative<b::Hold>(parent))
        return Refusal{Error::inconsistent_motion, {}, {}};
    const auto& next = advancing ? advancing->next : state;
    const I total = magnitude(drive.destination - state.pin);
    const I prefix = magnitude(next.pin - state.pin);
    const I direction = next.pin < state.pin ? -1 : 1;
    const auto axis = static_cast<std::size_t>(rig.axis);
    if (prefix > total) return Refusal{Error::inconsistent_motion, {}, {}};

    auto pin_box = rig.pin_at_zero;
    pin_box.minimum[axis] += state.pin;
    pin_box.maximum[axis] += state.pin;
    std::vector<Body> bodies{{{}, pin_box, prefix, 0}};
    for (std::size_t index = 0; index < state.followers.size(); ++index) {
        const auto& original = state.followers[index];
        const auto shape = std::find_if(rig.followers.begin(), rig.followers.end(),
            [&](const auto& entry) { return entry.id == original.id; });
        const I change = next.followers[index].position - original.position;
        const I travel = magnitude(change);
        if (shape == rig.followers.end() || travel > prefix || (change != 0 && change * direction < 0))
            return Refusal{Error::inconsistent_motion, {}, {}};
        auto box = shape->at_zero;
        box.minimum[axis] += original.position;
        box.maximum[axis] += original.position;
        bodies.push_back({original.id, box, travel, prefix - travel});
    }
    if (pairs.size() > maximum_pairs) return Refusal{Error::invalid_pair_set, {}, {}};
    const auto lookup = [&](Member member) {
        return std::find_if(bodies.begin(), bodies.end(), [&](const auto& body) { return body.member == member; });
    };
    std::vector<Pair> canonical(pairs.begin(), pairs.end());
    for (auto& pair : canonical) {
        if (pair.second < pair.first) std::swap(pair.first, pair.second);
        if (pair.first == pair.second || lookup(pair.first) == bodies.end() || lookup(pair.second) == bodies.end())
            return Refusal{Error::invalid_pair_set, pair, {}};
    }
    std::sort(canonical.begin(), canonical.end(), [](const Pair& a, const Pair& other) { return before(a, other); });
    for (std::size_t index = 1; index < canonical.size(); ++index)
        if (canonical[index] == canonical[index - 1])
            return Refusal{Error::invalid_pair_set, canonical[index], {}};

    std::optional<Blocked> first;
    for (const auto& pair : canonical) {
        const auto a = lookup(pair.first), other = lookup(pair.second);
        const auto& early = a->travel >= other->travel ? *a : *other;
        const auto& late = a->travel >= other->travel ? *other : *a;
        const I relative = early.travel - late.travel;
        mechanics::Point move{};
        move[axis] = direction * relative;
        const c::Obstacle obstacle{1, late.start};
        const auto query = c::sweep(early.start, move, std::span{&obstacle, 1});
        if (query.error != c::Error::none)
            return Refusal{Error::query_refused, pair, {}, query.error};
        if (!query.hit) continue;
        auto time = query.hit->time;
        if (query.hit->initially_overlapping) time = {0, 1};
        else {
            if (relative == 0 || total == 0 || time.denominator < 1 || time.numerator < 0 ||
                time.numerator >= time.denominator || relative % time.denominator != 0)
                return Refusal{Error::inconsistent_motion, pair, {}};
            const I at = early.delay + time.numerator * (relative / time.denominator);
            if (at >= prefix) return Refusal{Error::inconsistent_motion, pair, {}};
            const auto divisor = std::gcd(at, total);
            time = {at / divisor, total / divisor};
        }
        Blocked witness{state, pair, time, query.hit->initially_overlapping};
        if (!first || before(witness, *first)) first = std::move(witness);
    }
    if (first) return *first;
    if (advancing) return *advancing;
    return std::get<b::Hold>(parent);
}
}  // namespace factory::slotted_pairs
