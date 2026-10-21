#pragma once

#include "factory/slotted_link.hpp"

#include <cstdint>
#include <optional>
#include <span>
#include <variant>
#include <vector>

namespace factory::slotted_bank {
using Id = std::uint32_t;
using Coordinate = slotted_link::Coordinate;
using Fraction = slotted_link::Fraction;
inline constexpr std::size_t maximum_links = 16;
struct Link { Id id{}; slotted_link::Profile slot; };
struct Follower {
    Id id{};
    Coordinate position{};
    bool operator==(const Follower&) const = default;
};
struct State {
    Coordinate pin{};
    std::vector<Follower> followers;  // Exactly one per link, strictly ascending IDs.
    bool operator==(const State&) const = default;
};
struct Trace {
    Id id{};
    std::optional<slotted_link::Contact> contact;
    std::optional<slotted_link::Span> follower_motion;
    std::optional<slotted_link::Endstop> endstop;
    bool operator==(const Trace&) const = default;
};
struct Limit {
    Id id{};
    slotted_link::Endstop stop;
    bool operator==(const Limit&) const = default;
};
enum class Stop { unpowered, rest, limit };
struct Hold {
    State state;
    Stop reason;
    std::optional<Limit> limit;  // At time zero, this is a constraint, not an arrival event.
    bool operator==(const Hold&) const = default;
};
struct Advance {
    State next;
    std::vector<Trace> traces;  // Canonical IDs, reached events in ORIGINAL stroke time.
    std::optional<Limit> limit;  // First stop cause; ties choose the lowest identity.
    bool operator==(const Advance&) const = default;
};
enum class Error { invalid_profile, invalid_id, duplicate_id, invalid_state, link_refused, inconsistent_link };
struct Refusal {
    Error reason;
    Id subject{};
    std::optional<slotted_link::Error> link_error;
    bool operator==(const Refusal&) const = default;
};
using Plan = std::variant<Refusal, Hold, Advance>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure composition of guided slots sharing ONE physical drive pin. The entire
// bounded bank and its canonical state are validated before any hold or motion.
// The first declared follower stop clips the common pin and ALL followers to
// the same prefix. Recompute each link at that prefix, preserving its exact
// original-command times; never keep an unreached full-branch contact or pose.
// A time-zero stop holds the original state and emits no per-link motion trace.
// Power pause retains neither a pending destination nor partial branch work.
//
// This delegates local slot geometry to slotted_link. It creates no second pin,
// follower owner, clock, World, force or material state. The authority owns 3D
// embedding, actual obstruction/stall response and atomic adoption of the entire
// proposal. These are ideal point-pin constraints, not body-volume collision or
// torque dynamics. Profile order is arbitrary; live follower IDs are canonical.
[[nodiscard]] Plan prepare(std::span<const Link>, const State&, const slotted_link::Observation&);
}  // namespace factory::slotted_bank
