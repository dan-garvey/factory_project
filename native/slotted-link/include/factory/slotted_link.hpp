#pragma once

#include "factory/mechanics.hpp"

#include <optional>
#include <variant>

namespace factory::slotted_link {
using Coordinate = mechanics::Integer;
using Fraction = mechanics::Rate;
struct Profile {
    Coordinate lower{}, upper{4};  // Follower travel limits on one native grid axis.
    Coordinate back{2}, front{1};  // Slot walls at follower-back and follower+front.
};
struct State {
    Coordinate pin{}, follower{};
    bool operator==(const State&) const = default;
};
enum class Side { negative, positive };
struct Contact {
    Side side;
    Fraction at;  // First touch in [0,1], in the original requested stroke.
    bool operator==(const Contact&) const = default;
};
struct Span {
    Fraction begin, end;  // Positive-duration follower motion, not just a touch.
    bool operator==(const Span&) const = default;
};
struct Endstop {
    Side side;
    Fraction at;  // Exact first arrival in (0,1], including an endpoint arrival.
    bool operator==(const Endstop&) const = default;
};
enum class Stop { unpowered, rest, lower_end, upper_end };
struct Hold { State state; Stop reason; };
struct Advance {
    State next;
    std::optional<Contact> contact;
    std::optional<Span> follower_motion;
    std::optional<Endstop> endstop;
};
enum class Error { invalid_profile, invalid_state, invalid_destination };
struct Observation { Coordinate destination{}; bool powered{true}; };
using Plan = std::variant<Error, Hold, Advance>;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* stop_name(Stop) noexcept;

// Pure ideal point-pin and guided-slot proposal in one dimension. The commanded
// pin path is linear over one admitted stroke. It moves freely inside the slot,
// then pushes the contacted wall. Reversal takes up the opposite clearance;
// the caller's ONE pin/follower state pair retains that history. A zero-clearance
// profile is a rigid limiting case. No rounded or mirrored follower is stored.
//
// At a declared follower travel limit, clip the complete pin/follower prefix and
// hold for the remainder. Contact and motion fractions refer to the ORIGINAL
// command, not a rescaled clipped stroke. Touch at the endpoint is no positive
// follower motion; an outward attempt already at a stop is a Hold without events.
// Validate everything even while unpowered; pause stores no pending command.
//
// This is a one-dimensional kinematic candidate, not body-volume collision,
// force, slot deformation or a freely coasting body's dynamics. The authority
// supplies the constraints, resolves upstream drive stalls/obstruction, and owns
// atomic adoption, 3D embedding, power, World, material, clocks and persistence.
[[nodiscard]] Plan prepare(const Profile&, const State&, const Observation&);
}  // namespace factory::slotted_link
