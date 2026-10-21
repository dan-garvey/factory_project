#include "factory/slotted_clearance.hpp"

#include <algorithm>
#include <numeric>

namespace factory::slotted_clearance {
namespace b = slotted_bank;
namespace c = clearance;
namespace g = mechanics;
namespace {
using I = g::Integer;
static_assert(g::maximum_coordinate > 0 && g::maximum_coordinate <= 1000000);
I magnitude(I value) noexcept { return value < 0 ? -value : value; }  // Validated grid differences only.
std::optional<I> distance(b::Fraction at, I total) noexcept {
    if (total <= 0 || at.denominator < 1 || at.numerator < 0 || at.numerator > at.denominator || total % at.denominator != 0)
        return {};
    return at.numerator * (total / at.denominator);
}
struct Witness { std::optional<Id> follower; c::Hit hit; };
bool before(const Witness& a, const Witness& other) noexcept {
    const auto left = a.hit.time.numerator * other.hit.time.denominator;
    const auto right = other.hit.time.numerator * a.hit.time.denominator;
    if (left != right) return left < right;
    if (a.follower != other.follower) return a.follower < other.follower;
    return a.hit.obstacle < other.hit.obstacle;
}
struct Body {
    std::optional<Id> follower;
    c::Box zero;
    I start{}, finish{}, delay{};
};
}  // namespace
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::bank_refused: return "bank_refused";
        case Error::invalid_rig: return "invalid_rig";
        case Error::invalid_geometry: return "invalid_geometry";
        case Error::query_refused: return "query_refused";
        case Error::inconsistent_motion: return "inconsistent_motion";
    }
    return "unknown";
}
Plan prepare(std::span<const b::Link> links, const b::State& state, const Rig& rig, const Observation& observation) {
    const auto candidate = b::prepare(links, state, observation.drive);
    if (const auto* error = std::get_if<b::Refusal>(&candidate)) return Refusal{Error::bank_refused, {}, *error};
    if (static_cast<std::size_t>(rig.axis) >= 3 || rig.followers.size() != state.followers.size())
        return Refusal{Error::invalid_rig, {}, {}};
    auto shapes = rig.followers;
    std::sort(shapes.begin(), shapes.end(), [](const auto& a, const auto& other) { return a.id < other.id; });
    const auto* advancing = std::get_if<b::Advance>(&candidate);
    if (advancing && (advancing->traces.size() != state.followers.size() || advancing->next.followers.size() != state.followers.size()))
        return Refusal{Error::inconsistent_motion, {}, {}};
    const auto& next = advancing ? advancing->next : state;
    // The bank validated every raw position/destination before subtraction.
    const I total = magnitude(observation.drive.destination - state.pin);
    const I prefix = magnitude(next.pin - state.pin);
    std::vector<Body> bodies{{{}, rig.pin_at_zero, state.pin, next.pin, 0}};
    for (std::size_t index = 0; index < shapes.size(); ++index) {
        const auto id = state.followers[index].id;
        if (shapes[index].id != id) return Refusal{Error::invalid_rig, shapes[index].id, {}};
        if (next.followers[index].id != id || (advancing && advancing->traces[index].id != id))
            return Refusal{Error::inconsistent_motion, id, {}};
        const I travel = magnitude(next.followers[index].position - state.followers[index].position);
        I delay{};
        if (travel != 0) {
            if (!advancing || !advancing->traces[index].follower_motion || !advancing->traces[index].contact)
                return Refusal{Error::inconsistent_motion, id, {}};
            if ((next.followers[index].position > state.followers[index].position) != (next.pin > state.pin))
                return Refusal{Error::inconsistent_motion, id, {}};
            const auto& trace = advancing->traces[index];
            const auto begin = distance(trace.follower_motion->begin, total), end = distance(trace.follower_motion->end, total);
            if (!begin || !end || *end != prefix || *begin + travel != prefix || trace.contact->at != trace.follower_motion->begin)
                return Refusal{Error::inconsistent_motion, id, {}};
            delay = *begin;
        }
        bodies.push_back({id, shapes[index].at_zero, state.followers[index].position, next.followers[index].position, delay});
    }
    // Validate all unshifted proxies before arithmetic or any contact result.
    for (const auto& body : bodies) {
        const auto check = c::sweep(body.zero, {}, {});
        if (check.error != c::Error::none) return Refusal{Error::invalid_geometry, body.follower, {}, check.error};
    }
    std::optional<Witness> first;
    const auto axis = static_cast<std::size_t>(rig.axis);
    for (const auto& body : bodies) {
        auto box = body.zero;
        box.minimum[axis] += body.start;
        box.maximum[axis] += body.start;
        g::Point move{};
        move[axis] = body.finish - body.start;
        const auto query = c::sweep(box, move, observation.obstacles);
        if (query.error != c::Error::none) return Refusal{Error::query_refused, body.follower, {}, query.error};
        if (!query.hit) continue;
        auto hit = *query.hit;
        if (hit.initially_overlapping) hit.time = {0, 1};
        else {
            const I travel = magnitude(move[axis]);
            if (travel == 0 || hit.time.denominator < 1 || hit.time.numerator < 0 || hit.time.numerator >= hit.time.denominator ||
                travel % hit.time.denominator != 0 || total <= 0)
                return Refusal{Error::inconsistent_motion, body.follower, {}};
            const I numerator = body.delay + hit.time.numerator * (travel / hit.time.denominator);
            const auto divisor = std::gcd(numerator, total);
            hit.time = {numerator / divisor, total / divisor};
        }
        const Witness witness{body.follower, hit};
        if (!first || before(witness, *first)) first = witness;
    }
    // Earlier hits never bypass validation of a later body or obstacle query.
    if (first) return Blocked{state, first->follower, first->hit};
    if (advancing) return *advancing;
    return std::get<b::Hold>(candidate);
}
}  // namespace factory::slotted_clearance
