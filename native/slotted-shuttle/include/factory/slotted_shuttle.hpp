#pragma once

#include "factory/slotted_workcell.hpp"

namespace factory::slotted_shuttle {
inline constexpr std::size_t maximum_stops = 16;
inline constexpr std::size_t maximum_steps = 256;
struct Profile {
    std::vector<slotted_bank::Coordinate> stops{4, 0};
};
struct State {
    slotted_bank::State bank;
    std::size_t cursor{};  // Index of the NEXT stop, never a mirrored pose.
    bool operator==(const State&) const = default;
};
enum class Error { invalid_profile, invalid_cursor, invalid_bound, parent_refused };
struct Refusal {
    Error reason;
    std::optional<slotted_pairs::Refusal> parent_error;
    std::optional<slotted_workcell::Refusal> workcell_error{};
    bool operator==(const Refusal&) const = default;
};
enum class Stop { unpowered, obstructed, endstop };
struct Conflict {
    slotted_pairs::Pair pair;
    clearance::Fraction time;
    bool initially_overlapping{};
    bool operator==(const Conflict&) const = default;
};
struct Hold {
    State state;
    Stop reason;
    std::optional<Conflict> conflict;
    std::optional<slotted_bank::Limit> limit;
    std::optional<slotted_workcell::StationaryContact> stationary_contact{};
    bool operator==(const Hold&) const = default;
};
struct Step {
    State next;
    std::vector<slotted_bank::Trace> traces;
    std::optional<slotted_bank::Limit> limit;
    bool reached{};  // False means an admitted clipped prefix; cursor stays put.
    bool operator==(const Step&) const = default;
};
using Plan = std::variant<Refusal, Hold, Step>;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* stop_name(Stop) noexcept;

// Pure alternating-stop proposal. Validate the entire bounded stop list and
// current cursor even while paused; existing work-cell admission validates the
// whole rig, stationary set and moving pairs. Consume a stop only after actual
// arrival, including powered rest there. A clipped moving prefix preserves the
// pending stop. Pause and collision
// retain the original ENTIRE bank/cursor and expose no proposed movement effects.
// The caller admits other constraints and commits this single state atomically.
// Supply the COMPLETE relevant stationary set. The default empty set grants no
// stationary protection; it preserves existing frame-free source calls. Holds
// retain owned stationary or moving contact details, never a proposed stop phase.
[[nodiscard]] Plan prepare(const Profile&, std::span<const slotted_bank::Link>, const State&,
                           const slotted_clearance::Rig&, std::span<const slotted_pairs::Pair>,
                           bool powered = true, std::span<const clearance::Obstacle> stationary = {});

struct Loop {
    std::size_t begin{}, period{};  // Indices in Report::path; final state repeats begin.
    bool pin_moves{};
    std::vector<slotted_bank::Id> unmoved_followers; // Canonical IDs, across THIS loop only.
    bool operator==(const Loop&) const = default;
};
enum class Outcome { recurrent, held, refused, bound };
struct Report {
    Outcome outcome{Outcome::bound};
    std::vector<State> path;  // Original plus accepted steps; never a held/refused candidate.
    std::optional<Loop> loop;
    std::optional<Hold> hold;
    std::optional<Refusal> refusal;
};

// Read-only bounded trajectory under FIXED profile, geometry, pairs, stationary
// obstacles and power. The same complete observation reaches EVERY path edge.
// Every path edge uses prepare(). Detect recurrence using the entire bank AND
// cursor; a pause or hard stop is a hold, not a closed motion cycle. Report each
// follower that remains parked in the actual repeated interval, excluding any
// startup movement. An idle stop sequence can recur without any moving member.
//
// This is conditional kinematic evidence, not actual clock admission, material
// work, future observations, World persistence or unattended production proof.
// It creates no live state owner, quantities or force/contact response rules.
[[nodiscard]] Report inspect(const Profile&, std::span<const slotted_bank::Link>, const State&,
                             const slotted_clearance::Rig&, std::span<const slotted_pairs::Pair>,
                             std::size_t steps, bool powered = true,
                             std::span<const clearance::Obstacle> stationary = {});
}  // namespace factory::slotted_shuttle
