#include "factory/slotted_bank.hpp"

#include <algorithm>
#include <numeric>
#include <utility>

namespace factory::slotted_bank {
namespace s = slotted_link;
namespace {
static_assert(mechanics::maximum_coordinate <= 1000000);
bool before(Fraction a, Fraction b) noexcept {
    // Native stroke denominators are <= 2e6, so products are <= 4e12.
    return a.numerator * b.denominator < b.numerator * a.denominator;
}
bool original_time(Fraction& value, Coordinate prefix, Coordinate total) noexcept {
    if (value.denominator < 1 || value.numerator < 0 || value.numerator > value.denominator || prefix % value.denominator != 0)
        return false;
    // A reduced grid-distance/prefix fraction has a denominator dividing the
    // integer prefix. Cancel before multiplication; distance stays <= 2e6.
    const auto distance = value.numerator * (prefix / value.denominator);
    const auto divisor = std::gcd(distance, total);
    value = {distance / divisor, total / divisor};
    return true;
}
}  // namespace
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_profile: return "invalid_profile";
        case Error::invalid_id: return "invalid_id";
        case Error::duplicate_id: return "duplicate_id";
        case Error::invalid_state: return "invalid_state";
        case Error::link_refused: return "link_refused";
        case Error::inconsistent_link: return "inconsistent_link";
    }
    return "unknown";
}
Plan prepare(std::span<const Link> links, const State& state, const s::Observation& observation) {
    if (links.empty() || links.size() > maximum_links) return Refusal{Error::invalid_profile, 0, {}};
    std::vector<Link> ordered(links.begin(), links.end());
    std::sort(ordered.begin(), ordered.end(), [](const auto& a, const auto& b) { return a.id < b.id; });
    for (std::size_t index = 0; index < ordered.size(); ++index) {
        if (ordered[index].id == 0) return Refusal{Error::invalid_id, 0, {}};
        if (index != 0 && ordered[index - 1].id == ordered[index].id) return Refusal{Error::duplicate_id, ordered[index].id, {}};
    }
    if (state.followers.size() != ordered.size()) return Refusal{Error::invalid_state, 0, {}};
    std::vector<s::Plan> plans;
    for (std::size_t index = 0; index < ordered.size(); ++index) {
        const auto& follower = state.followers[index];
        if (follower.id != ordered[index].id) return Refusal{Error::invalid_state, follower.id, {}};
        auto plan = s::prepare(ordered[index].slot, {state.pin, follower.position}, observation);
        if (const auto* error = std::get_if<s::Error>(&plan)) return Refusal{Error::link_refused, follower.id, *error};
        plans.push_back(std::move(plan));
    }
    if (!observation.powered) return Hold{state, Stop::unpowered, {}};
    if (observation.destination == state.pin) return Hold{state, Stop::rest, {}};
    std::optional<Limit> first;
    Coordinate pin = observation.destination;
    for (std::size_t index = 0; index < ordered.size(); ++index) {
        std::optional<s::Endstop> candidate;
        Coordinate at = state.pin;
        if (const auto* held = std::get_if<s::Hold>(&plans[index])) {
            if (held->reason != s::Stop::lower_end && held->reason != s::Stop::upper_end)
                return Refusal{Error::inconsistent_link, ordered[index].id, {}};
            candidate = s::Endstop{held->reason == s::Stop::upper_end ? s::Side::positive : s::Side::negative, {0, 1}};
        } else {
            const auto& advance = std::get<s::Advance>(plans[index]);
            candidate = advance.endstop;
            at = advance.next.pin;
        }
        if (candidate && (!first || before(candidate->at, first->stop.at))) {
            first = Limit{ordered[index].id, *candidate};
            pin = at;
        }
    }
    if (pin == state.pin) return Hold{state, Stop::limit, first};
    const auto total = observation.destination > state.pin ? observation.destination - state.pin : state.pin - observation.destination;
    const auto prefix = pin > state.pin ? pin - state.pin : state.pin - pin;
    Advance result{state, {}, first};
    result.next.pin = pin;
    for (std::size_t index = 0; index < ordered.size(); ++index) {
        const auto id = ordered[index].id;
        const auto proposal = s::prepare(ordered[index].slot, {state.pin, state.followers[index].position}, {pin});
        const auto* next = std::get_if<s::Advance>(&proposal);
        if (!next || next->next.pin != pin) return Refusal{Error::inconsistent_link, id, {}};
        Trace trace{id, next->contact, next->follower_motion, next->endstop};
        if ((trace.contact && !original_time(trace.contact->at, prefix, total)) ||
            (trace.follower_motion && (!original_time(trace.follower_motion->begin, prefix, total) ||
                                       !original_time(trace.follower_motion->end, prefix, total))) ||
            (trace.endstop && !original_time(trace.endstop->at, prefix, total)))
            return Refusal{Error::inconsistent_link, id, {}};
        result.next.followers[index].position = next->next.follower;
        result.traces.push_back(std::move(trace));
    }
    return result;
}
}  // namespace factory::slotted_bank
