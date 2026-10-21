#pragma once

#include "factory/slotted_clearance.hpp"

namespace factory::slotted_pairs {
using Id = slotted_bank::Id;
using Member = std::optional<Id>;  // Empty is the common pin; otherwise a follower ID.
inline constexpr std::size_t maximum_pairs =
    (slotted_bank::maximum_links + 1) * slotted_bank::maximum_links / 2;

struct Pair {
    Member first, second;
    bool operator==(const Pair&) const = default;
};
enum class Error { parent_refused, invalid_pair_set, query_refused, inconsistent_motion };
struct Refusal {
    Error reason;
    std::optional<Pair> pair;
    std::optional<slotted_clearance::Refusal> parent_error;
    clearance::Error query_error{clearance::Error::none};
    bool operator==(const Refusal&) const = default;
};
struct Blocked {
    slotted_bank::State state;  // Only the ORIGINAL entire bank; no proposed effects.
    Pair pair;                // Canonical order: pin, then ascending follower ID.
    clearance::Fraction time; // Time in the ORIGINAL commanded stroke.
    bool initially_overlapping{};
    bool operator==(const Blocked&) const = default;
};
using Plan = std::variant<Refusal, Blocked, slotted_bank::Hold, slotted_bank::Advance>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure continuous contact admission for declared members of one slotted rig.
// The caller supplies the COMPLETE relevant forbidden-contact pair set. Pairs
// are unordered; duplicates, self-pairs and unknown members refuse, even paused.
// No automatic mating exemptions or slot-housing geometry are invented here.
// An empty pair set grants no mutual-contact protection.
//
// Reuse slotted_clearance with no stationary obstacles for full bank/rig
// validation. Different slack delays give exactly one relative-motion interval.
// Sweep the earlier mover through the difference of the travels against the
// other's original box, then restore the earlier delay in original stroke time.
// This relative segment stays inside the earlier mover's validated world path.
// Initial penetration is time zero, even paused. Exact grazing and contact only
// at the end of relative motion are clear. Select earliest time, then canonical
// pair; any obstruction retains ALL original positions and no movement effects.
//
// The authority still admits stationary obstacles and other constraints, owns
// upstream stalls, and commits its one bank atomically. This stores no second
// state, clock, World, material or persistence. It models neither forces nor
// general dynamic-body response, independent pushing or physical mating.
[[nodiscard]] Plan prepare(std::span<const slotted_bank::Link>, const slotted_bank::State&,
                           const slotted_clearance::Rig&, const slotted_link::Observation&,
                           std::span<const Pair>);
}  // namespace factory::slotted_pairs
