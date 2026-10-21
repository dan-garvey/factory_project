#pragma once

#include "factory/slotted_workcell.hpp"

namespace factory::fractional_slots {
using Coordinate = mechanics::Rate;
using Id = slotted_bank::Id;
inline constexpr mechanics::Integer maximum_scale = 1024;
struct Follower {
    Id id{};
    Coordinate position;
    bool operator==(const Follower&) const = default;
};
struct State {
    Coordinate pin;
    std::vector<Follower> followers;  // Exactly one per link; strictly ascending IDs.
    bool operator==(const State&) const = default;
};
struct Observation {
    Coordinate destination;
    bool powered{true};
    std::span<const clearance::Obstacle> obstacles;
};
enum class Error { invalid_input, invalid_fraction, scale_limit, representation_limit, parent_refused };
struct Refusal {
    Error reason;
    std::optional<slotted_workcell::Refusal> parent_error;
    bool operator==(const Refusal&) const = default;
};
using Contact = std::variant<slotted_workcell::StationaryContact, slotted_workcell::MovingContact>;
struct Blocked {
    State state;  // Only the ORIGINAL rational bank, without proposed effects.
    Contact contact;
    bool operator==(const Blocked&) const = default;
};
struct Hold {
    State state;
    slotted_bank::Stop reason;
    std::optional<slotted_bank::Limit> limit;
    bool operator==(const Hold&) const = default;
};
struct Advance {
    State next;
    std::vector<slotted_bank::Trace> traces;
    std::optional<slotted_bank::Limit> limit;
    bool operator==(const Advance&) const = default;
};
using Plan = std::variant<Refusal, Blocked, Hold, Advance>;
[[nodiscard]] const char* error_name(Error) noexcept;

// One caller-owned bank of exact, reduced rational positions. Profiles and box
// proxies retain their existing integer physical units. Validate raw inputs,
// then uniformly scale ALL positions, profiles, bodies and stationary obstacles
// to a temporary exact integer query of the existing combined work cell. Its
// stationary and moving witnesses, original-stroke times, traces, stop causes,
// complete-set validation and strict-interior policy remain unchanged.
//
// Position denominators AND their common least multiple must fit maximum_scale.
// The scaled query must also fit existing native grid/dimension bounds. Refuse
// inputs that exceed those experimental representation limits; never round,
// truncate obstacle/pair sets, widen a native bound or store a mirrored bank.
// Event-time denominators are not position denominators and are not so capped.
// A blocked proposal owns only the original rational state. Clear endpoints
// reduce back to canonical coordinates; temporary scaling adds no live phase.
//
// The authority still owns atomic adoption, the complete relevant constraints,
// power, force response, body/World ownership, material and persistence. This
// selects neither permanent game units nor a general rational physics engine.
[[nodiscard]] Plan prepare(std::span<const slotted_bank::Link>, const State&,
                           const slotted_clearance::Rig&, const Observation&,
                           std::span<const slotted_pairs::Pair>);
}  // namespace factory::fractional_slots
