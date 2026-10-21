#pragma once

#include "factory/slotted_workcell.hpp"

namespace factory::slotted_cascade {
enum class Error { invalid_chain, invalid_state, link_refused, representation_limit, workcell_refused, inconsistent_proposal };
struct Refusal {
    Error reason;
    std::optional<slotted_bank::Id> stage;
    std::optional<slotted_link::Error> link_error;
    std::optional<slotted_workcell::Refusal> workcell_error;
    bool operator==(const Refusal&) const = default;
};
struct Trace {
    slotted_bank::Id id{};
    // When the complete drive-to-stage push path takes up in ORIGINAL stroke
    // time. This is NOT that stage's local first wall-touch time.
    std::optional<slotted_link::Contact> drive_engagement;
    std::optional<slotted_link::Span> motion;
    // When this guide becomes a binding drive constraint, including a tool
    // already resting at its travel bound with upstream slack still available.
    std::optional<slotted_link::Endstop> binding_stop;
    bool operator==(const Trace&) const = default;
};
struct Advance {
    slotted_bank::State next;
    std::vector<Trace> traces;  // Canonical identities, not chain order.
    std::optional<slotted_bank::Limit> limit;
    bool operator==(const Advance&) const = default;
};
using Plan = std::variant<Refusal, slotted_workcell::Blocked, slotted_bank::Hold, Advance>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Ordered SERIES of guided ideal slots. The first stage's pin is state.pin;
// every later pin is the preceding original follower, with no second live copy.
// The chain order is explicit and IDs opaque. State stays the one existing bank
// with exactly those followers sorted by identity. Profiles/boxes remain in
// world units on the same translation axis; lateral connectors and slot solids
// require their own caller-supplied geometry and are not invented here.
//
// Validate every LOCAL retained relation before deriving effective front/back
// clearances. For a monotone stroke the gaps telescope: a stage moves only after
// every preceding push wall is reached. Cumulative clearances therefore reuse
// the existing bank's globally clipped prefix and complete static/moving query.
// Cumulative representation must fit the unchanged native profile bounds.
// No rounding, bound increase, partial obstacle set or partial adoption occurs.
// Blocked output owns only the ORIGINAL bank and the existing typed witness.
//
// Drive engagement is cumulative take-up, not a local contact event. Original
// command times and first binding stop retain their existing units/tie rules.
// The caller owns atomic adoption, complete relevant proxies/pairs, upstream
// stalls, force/body/World rules, power, material, clocks and persistence.
[[nodiscard]] Plan prepare(std::span<const slotted_bank::Link> chain, const slotted_bank::State&,
                           const slotted_clearance::Rig&, const slotted_clearance::Observation&,
                           std::span<const slotted_pairs::Pair>);
}  // namespace factory::slotted_cascade
