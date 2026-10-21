#pragma once

#include "factory/clearance.hpp"
#include "factory/slotted_bank.hpp"

#include <optional>
#include <span>
#include <variant>
#include <vector>

namespace factory::slotted_clearance {
using Id = slotted_bank::Id;
struct FollowerBox { Id id{}; clearance::Box at_zero; };
struct Rig {
    mechanics::Axis axis{mechanics::Axis::x};
    clearance::Box pin_at_zero;
    std::vector<FollowerBox> followers;  // Exactly one declared box per bank follower.
};
enum class Error { bank_refused, invalid_rig, invalid_geometry, query_refused, inconsistent_motion };
struct Refusal {
    Error reason;
    std::optional<Id> follower;  // Empty identifies the common pin or whole-rig input.
    std::optional<slotted_bank::Refusal> bank_error;
    clearance::Error geometry_error{clearance::Error::none};
    bool operator==(const Refusal&) const = default;
};
struct Blocked {
    slotted_bank::State state;  // ONLY the original complete state; no proposed effects.
    std::optional<Id> follower;  // Empty is the pin; otherwise the opaque follower ID.
    clearance::Hit hit;  // Time is in the ORIGINAL commanded stroke, not local travel.
    bool operator==(const Blocked&) const = default;
};
struct Observation {
    slotted_link::Observation drive;
    std::span<const clearance::Obstacle> obstacles;
};
using Plan = std::variant<Refusal, Blocked, slotted_bank::Hold, slotted_bank::Advance>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure continuous stationary-obstacle admission for an existing slotted bank.
// Every declared box translates on the same axis, offset by the single pin or
// its original follower coordinate. Sweep the ENTIRE proposed prefix, including
// each follower's stationary slack interval. A blocked stroke retains the whole
// original state and emits no proposed movement, limit or contact effects.
//
// Map local sweep contact through the follower's delay into original stroke
// time. Initial penetration is time zero, even before delayed motion or while
// unpowered. Earliest time wins; ties choose pin, then lowest follower ID, then
// lowest obstacle ID. Validate the whole rig and complete relevant stationary
// obstacle set before publishing any blocked result, including paused strokes.
// Exact grazing and destination-only contact inherit the canonical sweep policy.
//
// The caller supplies the complete explicit box proxies. Mutual moving-body
// contact, physical slot solids, mating exemptions, forces, upstream stall
// response and actual World/body ownership are outside this adapter. It creates
// no parallel state, clock, material owner or authority. The sole bank proposal
// must be adopted atomically by the existing authority after all other checks.
[[nodiscard]] Plan prepare(std::span<const slotted_bank::Link>, const slotted_bank::State&,
                           const Rig&, const Observation&);
}  // namespace factory::slotted_clearance
