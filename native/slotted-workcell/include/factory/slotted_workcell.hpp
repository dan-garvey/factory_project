#pragma once

#include "factory/slotted_pairs.hpp"

namespace factory::slotted_workcell {
enum class Error { stationary_refused, moving_refused, inconsistent_proposal };
struct Refusal {
    Error reason;
    std::optional<slotted_clearance::Refusal> stationary_error;
    std::optional<slotted_pairs::Refusal> moving_error;
    bool operator==(const Refusal&) const = default;
};
struct StationaryContact {
    slotted_pairs::Member member;
    clearance::Hit hit;
    bool operator==(const StationaryContact&) const = default;
};
struct MovingContact {
    slotted_pairs::Pair pair;
    clearance::Fraction time;
    bool initially_overlapping{};
    bool operator==(const MovingContact&) const = default;
};
struct Blocked {
    slotted_bank::State state;  // Only the ORIGINAL whole bank, without proposed effects.
    std::variant<StationaryContact, MovingContact> contact;
    bool operator==(const Blocked&) const = default;
};
using Plan = std::variant<Refusal, Blocked, slotted_bank::Hold, slotted_bank::Advance>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure combined stationary-obstacle and moving-member admission for one bank.
// The caller supplies the COMPLETE relevant stationary set and forbidden-pair
// set. Both existing adapters validate before any obstruction is published,
// including during pause; an earlier hit never hides a bad later constraint.
// Select the earliest ORIGINAL commanded-stroke time. Exact family ties choose
// stationary contact; each adapter retains its existing canonical identity ties.
// Initial penetration, strict grazing and destination-only contact keep their
// existing policies. Every blocked result owns only the original entire bank.
//
// Clear adapters must agree on the full hold/advance, traces and stop cause;
// otherwise refuse rather than select conflicting proposals. The accepted bank
// proposal is unchanged. This adds no collision rule, force response, mating
// exemption, clock, World, material or persistence owner. The caller still
// admits all other constraints and atomically commits its one live bank.
[[nodiscard]] Plan prepare(std::span<const slotted_bank::Link>, const slotted_bank::State&,
                           const slotted_clearance::Rig&, const slotted_clearance::Observation&,
                           std::span<const slotted_pairs::Pair>);
}  // namespace factory::slotted_workcell
