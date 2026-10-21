#include "factory/fractional_slots.hpp"

#include <numeric>

namespace factory::fractional_slots {
namespace g = mechanics;
namespace b = slotted_bank;
namespace s = slotted_link;
namespace c = clearance;
namespace w = slotted_workcell;
using I = g::Integer;
namespace {
static_assert(maximum_scale > 0 && maximum_scale <= 1024 && g::maximum_coordinate <= 1000000);
bool valid(Coordinate value) noexcept {
    if (value.denominator < 1 || value.denominator > maximum_scale) return false;
    const I bound = g::maximum_coordinate * value.denominator;
    if (value.numerator < -bound || value.numerator > bound) return false;
    // Magnitudes are bounded before gcd, including for a malicious INT64_MIN.
    return std::gcd(value.numerator, value.denominator) == 1;
}
bool include(I& scale, Coordinate value) noexcept {
    const I factor = value.denominator / std::gcd(scale, value.denominator);
    if (factor > maximum_scale / scale) return false;
    scale *= factor;
    return true;
}
bool profile_valid(const s::Profile& slot) {
    return !std::holds_alternative<s::Error>(s::prepare(slot, {slot.lower, slot.lower}, {slot.lower, false}));
}
bool box_valid(const c::Box& box) noexcept { return c::sweep(box, {}, {}).error == c::Error::none; }
bool scale_box(c::Box& box, I scale) noexcept {
    for (std::size_t axis = 0; axis < 3; ++axis) {
        box.minimum[axis] *= scale;
        box.maximum[axis] *= scale;
    }
    return box_valid(box);
}
I integral(Coordinate value, I scale) noexcept { return value.numerator * (scale / value.denominator); }
Coordinate rational(I value, I scale) noexcept {
    const I divisor = std::gcd(value, scale);
    return {value / divisor, scale / divisor};
}
bool in_grid(I value) noexcept { return value >= -g::maximum_coordinate && value <= g::maximum_coordinate; }
}  // namespace

const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::invalid_input: return "invalid_input";
        case Error::invalid_fraction: return "invalid_fraction";
        case Error::scale_limit: return "scale_limit";
        case Error::representation_limit: return "representation_limit";
        case Error::parent_refused: return "parent_refused";
    }
    return "unknown";
}

Plan prepare(std::span<const b::Link> links, const State& state, const slotted_clearance::Rig& rig,
             const Observation& observation, std::span<const slotted_pairs::Pair> pairs) {
    if (links.empty() || links.size() > b::maximum_links || state.followers.size() != links.size() ||
        rig.followers.size() != links.size() || observation.obstacles.size() > g::maximum_parts ||
        pairs.size() > slotted_pairs::maximum_pairs) return Refusal{Error::invalid_input, {}};
    if (!valid(state.pin) || !valid(observation.destination)) return Refusal{Error::invalid_fraction, {}};
    for (const auto& follower : state.followers)
        if (!valid(follower.position)) return Refusal{Error::invalid_fraction, {}};
    for (const auto& link : links)
        if (!profile_valid(link.slot)) return Refusal{Error::invalid_input, {}};
    if (!box_valid(rig.pin_at_zero)) return Refusal{Error::invalid_input, {}};
    for (const auto& follower : rig.followers)
        if (!box_valid(follower.at_zero)) return Refusal{Error::invalid_input, {}};
    for (const auto& obstacle : observation.obstacles)
        if (!box_valid(obstacle.box)) return Refusal{Error::invalid_input, {}};

    I scale = 1;
    if (!include(scale, state.pin) || !include(scale, observation.destination)) return Refusal{Error::scale_limit, {}};
    for (const auto& follower : state.followers)
        if (!include(scale, follower.position)) return Refusal{Error::scale_limit, {}};

    // Every multiplication below is bounded by maximum_coordinate*maximum_scale
    // after raw validation. Existing adapters still enforce their smaller grid.
    std::vector<b::Link> scaled_links(links.begin(), links.end());
    for (auto& link : scaled_links) {
        link.slot.lower *= scale;
        link.slot.upper *= scale;
        link.slot.back *= scale;
        link.slot.front *= scale;
        if (!profile_valid(link.slot)) return Refusal{Error::representation_limit, {}};
    }
    b::State scaled_state{integral(state.pin, scale), {}};
    const I destination = integral(observation.destination, scale);
    if (!in_grid(scaled_state.pin) || !in_grid(destination)) return Refusal{Error::representation_limit, {}};
    for (const auto& follower : state.followers) {
        const I position = integral(follower.position, scale);
        if (!in_grid(position)) return Refusal{Error::representation_limit, {}};
        scaled_state.followers.push_back({follower.id, position});
    }
    auto scaled_rig = rig;
    if (!scale_box(scaled_rig.pin_at_zero, scale)) return Refusal{Error::representation_limit, {}};
    for (auto& follower : scaled_rig.followers)
        if (!scale_box(follower.at_zero, scale)) return Refusal{Error::representation_limit, {}};
    std::vector<c::Obstacle> obstacles(observation.obstacles.begin(), observation.obstacles.end());
    for (auto& obstacle : obstacles)
        if (!scale_box(obstacle.box, scale)) return Refusal{Error::representation_limit, {}};

    const auto plan = w::prepare(scaled_links, scaled_state, scaled_rig, {{destination, observation.powered}, obstacles}, pairs);
    if (const auto* refused = std::get_if<w::Refusal>(&plan)) return Refusal{Error::parent_refused, *refused};
    if (const auto* blocked = std::get_if<w::Blocked>(&plan)) return Blocked{state, blocked->contact};
    if (const auto* held = std::get_if<b::Hold>(&plan)) return Hold{state, held->reason, held->limit};
    const auto& advance = std::get<b::Advance>(plan);
    Advance result{{rational(advance.next.pin, scale), {}}, advance.traces, advance.limit};
    for (const auto& follower : advance.next.followers)
        result.next.followers.push_back({follower.id, rational(follower.position, scale)});
    return result;
}
}  // namespace factory::fractional_slots
