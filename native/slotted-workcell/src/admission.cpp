#include "factory/slotted_workcell.hpp"

namespace factory::slotted_workcell {
namespace s = slotted_clearance;
namespace p = slotted_pairs;
namespace b = slotted_bank;

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::stationary_refused: return "stationary_refused";
        case Error::moving_refused: return "moving_refused";
        case Error::inconsistent_proposal: return "inconsistent_proposal";
    }
    return "unknown";
}

Plan prepare(std::span<const b::Link> links, const b::State& state, const s::Rig& rig,
             const s::Observation& observation, std::span<const p::Pair> pairs) {
    const auto stationary = s::prepare(links, state, rig, observation);
    const auto moving = p::prepare(links, state, rig, observation.drive, pairs);
    const auto* stationary_error = std::get_if<s::Refusal>(&stationary);
    const auto* moving_error = std::get_if<p::Refusal>(&moving);
    if (stationary_error || moving_error) {
        Refusal refusal{stationary_error ? Error::stationary_refused : Error::moving_refused, {}, {}};
        if (stationary_error) refusal.stationary_error = *stationary_error;
        if (moving_error) refusal.moving_error = *moving_error;
        return refusal;
    }
    const auto* fixed = std::get_if<s::Blocked>(&stationary);
    const auto* mutual = std::get_if<p::Blocked>(&moving);
    // Parent times have positive denominators and native grid-bounded terms.
    // Products are at most (2*maximum_coordinate)^2 under this proof bound.
    static_assert(mechanics::maximum_coordinate > 0 && mechanics::maximum_coordinate <= 1000000);
    if (fixed && (!mutual || fixed->hit.time.numerator * mutual->time.denominator <=
                            mutual->time.numerator * fixed->hit.time.denominator))
        return Blocked{state, StationaryContact{fixed->follower, fixed->hit}};
    if (mutual) return Blocked{state, MovingContact{mutual->pair, mutual->time, mutual->initially_overlapping}};
    if (const auto* advance = std::get_if<b::Advance>(&stationary)) {
        const auto* other = std::get_if<b::Advance>(&moving);
        if (other && *advance == *other) return *advance;
    } else if (const auto* hold = std::get_if<b::Hold>(&stationary)) {
        const auto* other = std::get_if<b::Hold>(&moving);
        if (other && *hold == *other) return *hold;
    }
    return Refusal{Error::inconsistent_proposal, {}, {}};
}
}  // namespace factory::slotted_workcell
