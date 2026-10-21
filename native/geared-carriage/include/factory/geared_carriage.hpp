#pragma once

#include "factory/clearance.hpp"
#include "factory/cycle.hpp"
#include "factory/geared_cycle.hpp"

#include <optional>
#include <span>
#include <variant>

namespace factory::geared_carriage {
struct Profile {
    mechanisms::Slide timing{2, 3, 2};
    clearance::Box dock{{0, 0, 0}, {1, 1, 1}};
    mechanics::Axis axis{mechanics::Axis::x};
    mechanics::Integer stroke{6};
};

// Exact interpolation between the existing integer-tooth carriage samples.
// The enclosing box must cover the complete carriage AND supported load.
struct Pose {
    clearance::Box from, to;
    clearance::Fraction fraction;
    bool operator==(const Pose&) const = default;
};

enum class Error { invalid_profile, invalid_clock, invalid_obstacles, query_failure, inconsistent_query };
struct Refusal {
    Error reason;
    std::optional<geared_cycle::Error> clock_error;
    clearance::Error geometry_error{clearance::Error::none};
    bool operator==(const Refusal&) const = default;
};

struct Contact {
    std::uint64_t obstacle{};
    std::size_t segment{};  // Chronological piece, including dwells, of this tick.
    mechanics::Integer tooth{};  // Left stop of the positive phase interval.
    clearance::Fraction fraction;  // Position in that interval, NOT tick time.
    bool initially_overlapping{};  // At the start of this selected piece.
    bool operator==(const Contact&) const = default;
};
enum class Stop { unpowered, stopped, obstructed };
struct Hold {
    geared_cycle::Phase phase;
    Stop reason;
    std::optional<Contact> contact;
    bool operator==(const Hold&) const = default;
};
struct Step {
    geared_cycle::Prepared proposed;
};
struct Observation {
    mechanics::Rate rate{1, 1};
    bool powered{true};
    std::span<const clearance::Obstacle> obstacles;
};
using Sample = std::variant<Refusal, Pose>;
using Plan = std::variant<Refusal, Hold, Step>;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* stop_name(Stop) noexcept;
[[nodiscard]] Sample sample(const Profile&, geared_cycle::Phase);

// Experimental integer-step envelope: positive stroke is divisible by travel
// teeth, while phase and native gear rate may be fractional or reversed. Use the
// existing clock to enumerate the WHOLE interval, including complete wraps. Two
// canonical sweeps bound each obstacle's interior-occupancy interval; clip those
// witnesses to the actual fractional piece. Never round a position or use only
// endpoints. Exact grazing/destination contact retains the clearance policy.
// Validate the entire obstacle set even while paused. Current penetration holds.
//
// A blocked tick returns ONLY the original phase and a contact: no proposed
// crossings or prefix effects escape. The authority must admit/commit all effects
// atomically and propagate obstruction to the actual drivetrain. This is a pure
// kinematic proposal, not body/contact response, mating exemptions, a live clock,
// player admission, material custody, World, persistence or a fallback authority.
[[nodiscard]] Plan prepare(const Profile&, geared_cycle::Phase, const Observation&);
}  // namespace factory::geared_carriage
