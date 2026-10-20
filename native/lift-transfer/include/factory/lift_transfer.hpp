#pragma once

#include "factory/clearance.hpp"
#include "factory/cycle.hpp"

#include <iosfwd>
#include <optional>
#include <span>
#include <variant>

namespace factory::lift {
struct Profile {
    mechanisms::Slide timing{2, 4, 2};
    clearance::Box lower_box{{1, 1, -1}, {3, 2, 1}};
    clearance::Coordinate rise{4};
    bool operator==(const Profile&) const = default;
};
struct Pose {
    mechanisms::Pose cycle;
    clearance::Box platform;
    bool operator==(const Pose&) const = default;
};
struct Observation {
    bool powered{true};
    bool loaded{};
    bool source_available{};
    bool receiver_accepts{true};  // Admission/space/gate observations, not a reservation.
    std::span<const clearance::Obstacle> obstacles;
};
enum class Error { none, invalid_profile, invalid_phase, invalid_obstacles };
enum class Stop { unpowered, empty_source, receiver_closed, missing_load, load_on_return, obstructed };
enum class Direction { load, unload };
struct Hold {
    Stop reason;
    mechanisms::Phase phase;
    Pose pose;
    std::optional<clearance::Hit> hit;
    bool operator==(const Hold&) const = default;
};
struct Handoff {
    Direction direction;
    mechanisms::Phase phase;
    Pose pose;
    bool operator==(const Handoff&) const = default;
};
struct Step {
    mechanisms::Phase next;
    Pose pose;
    bool operator==(const Step&) const = default;
};
using Plan = std::variant<Error, Hold, Handoff, Step>;

[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* stop_name(Stop) noexcept;

// Experimental integer-grid adapter: a positive rise must be divisible by the
// travel interval count. Both endpoint boxes must fit the accepted bounded grid.
// No permanent game unit, collision response or physical support policy is set.
// Every refusal preserves the supplied output.
[[nodiscard]] Error sample(const Profile&, mechanisms::Phase, Pose&) noexcept;

// Pure proposal. The caller owns the sole phase, cargo, ports and complete
// obstacle observations. Validate every obstacle even while unpowered or waiting.
// Loading/unloading holds phase; the caller must revalidate and atomically commit
// actual custody. A repeated proposal does not consume a load or admit a replay.
// Empty-source and blocked-receiver holds preserve phase indefinitely. Only a
// Step proposes a phase change. Travel uses the accepted continuous box sweep.
// The supplied box must enclose the platform AND any supported load throughout
// this translation; the library does not create bodies or infer cargo geometry.
// No World, material counts, clock, request cache, persistence or fallback exists.
[[nodiscard]] Plan prepare(const Profile&, mechanisms::Phase, const Observation&) noexcept;

// Original finite metadata-tag fixture, not World goods or native body evidence.
[[nodiscard]] int play(std::istream&, std::ostream&, std::ostream&);
[[nodiscard]] int compare(std::ostream&);
}  // namespace factory::lift
