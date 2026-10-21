#include "factory/slotted_cascade.hpp"

#include <algorithm>

namespace factory::slotted_cascade {
namespace b = slotted_bank;
namespace s = slotted_link;
namespace w = slotted_workcell;
namespace g = mechanics;
namespace {
const b::Follower& follower(const b::State& state, b::Id id) {
    return *std::lower_bound(state.followers.begin(), state.followers.end(), id,
        [](const auto& value, auto identity) { return value.id < identity; });
}
std::optional<Refusal> local(std::span<const b::Link> chain, const b::State& state) {
    auto pin = state.pin;
    for (const auto& stage : chain) {
        const auto position = follower(state, stage.id).position;
        const auto plan = s::prepare(stage.slot, {pin, position}, {pin, false});
        if (const auto* error = std::get_if<s::Error>(&plan))
            return Refusal{Error::link_refused, stage.id, *error, {}};
        pin = position;
    }
    return {};
}
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_chain: return "invalid_chain";
        case Error::invalid_state: return "invalid_state";
        case Error::link_refused: return "link_refused";
        case Error::representation_limit: return "representation_limit";
        case Error::workcell_refused: return "workcell_refused";
        case Error::inconsistent_proposal: return "inconsistent_proposal";
    }
    return "unknown";
}

Plan prepare(std::span<const b::Link> chain, const b::State& state, const slotted_clearance::Rig& rig,
             const slotted_clearance::Observation& observation, std::span<const slotted_pairs::Pair> pairs) {
    if (chain.empty() || chain.size() > b::maximum_links) return Refusal{Error::invalid_chain, {}, {}, {}};
    std::vector<b::Id> identities;
    for (const auto& stage : chain) identities.push_back(stage.id);
    std::sort(identities.begin(), identities.end());
    for (std::size_t index = 0; index < identities.size(); ++index)
        if (identities[index] == 0 || (index && identities[index] == identities[index - 1]))
            return Refusal{Error::invalid_chain, identities[index], {}, {}};
    if (state.followers.size() != identities.size() || state.pin < -g::maximum_coordinate || state.pin > g::maximum_coordinate)
        return Refusal{Error::invalid_state, {}, {}, {}};
    for (std::size_t index = 0; index < identities.size(); ++index)
        if (state.followers[index].id != identities[index] || state.followers[index].position < -g::maximum_coordinate ||
            state.followers[index].position > g::maximum_coordinate)
            return Refusal{Error::invalid_state, state.followers[index].id, {}, {}};
    if (const auto error = local(chain, state)) return *error;
    std::vector<b::Link> effective;
    g::Integer back = 0, front = 0;
    for (const auto& stage : chain) {
        // Every local profile was validated before arithmetic. Existing single
        // slot bounds also bound both sums here; no raw signed value is added.
        if (stage.slot.back > g::maximum_dimension - back || stage.slot.front > g::maximum_dimension - front)
            return Refusal{Error::representation_limit, stage.id, {}, {}};
        back += stage.slot.back;
        front += stage.slot.front;
        const s::Profile slot{stage.slot.lower, stage.slot.upper, back, front};
        const auto probe = s::prepare(slot, {slot.lower, slot.lower}, {slot.lower, false});
        if (std::holds_alternative<s::Error>(probe)) return Refusal{Error::representation_limit, stage.id, {}, {}};
        effective.push_back({stage.id, slot});
    }
    const auto plan = w::prepare(effective, state, rig, observation, pairs);
    if (const auto* error = std::get_if<w::Refusal>(&plan)) return Refusal{Error::workcell_refused, {}, {}, *error};
    if (const auto* blocked = std::get_if<w::Blocked>(&plan)) return *blocked;
    if (const auto* held = std::get_if<b::Hold>(&plan)) return *held;
    const auto& step = std::get<b::Advance>(plan);
    if (local(chain, step.next)) return Refusal{Error::inconsistent_proposal, {}, {}, {}};
    Advance result{step.next, {}, step.limit};
    for (const auto& trace : step.traces)
        result.traces.push_back({trace.id, trace.contact, trace.follower_motion, trace.endstop});
    return result;
}
}  // namespace factory::slotted_cascade
