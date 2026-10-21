#pragma once

#include "factory/geared_cycle.hpp"

#include <array>
#include <optional>
#include <variant>

namespace factory::cardan_pair {
using Integer = mechanics::Integer;
inline constexpr Integer maximum_dial_component = 64;
inline constexpr Integer maximum_bend_component = 32;

// Primitive signed direction, preserving all four quadrants. This is one
// caller-owned input pose, not an accumulated angle, winding count or clock.
struct Dial {
    Integer x{1}, y{};
    bool operator==(const Dial&) const = default;
};
struct Bend {
    Integer cosine{3}, sine{4}, scale{5};
    bool operator==(const Bend&) const = default;
};
enum class Mount { forward, compensating };
struct Joint {
    Bend bend;
    Mount mount{Mount::forward};
    bool operator==(const Joint&) const = default;
};
struct Profile {
    std::array<Joint, 2> joints{{{{3, 4, 5}, Mount::forward}, {{3, -4, 5}, Mount::compensating}}};
    bool operator==(const Profile&) const = default;
};
struct AxisDirection {
    Integer y{}, z{1}, scale{1};  // Unit vector (0,y/scale,z/scale).
    bool operator==(const AxisDirection&) const = default;
};
struct Diagonal {
    Integer x{1}, y{1};  // Positive, jointly reduced composite pose coefficients.
    [[nodiscard]] bool constant_rate() const noexcept { return x == y; }
    bool operator==(const Diagonal&) const = default;
};
struct Evaluation {
    Profile profile;
    std::array<Dial, 3> dial;  // Input, derived middle and derived output.
    std::array<mechanics::Motion, 3> motion;
    std::array<mechanics::Rate, 2> factors;  // Exact instantaneous derivatives.
    AxisDirection middle_axis, output_axis;
    Diagonal composite;
};
enum class Error { invalid_profile, invalid_mount, invalid_dial, invalid_motion, invalid_rate, unsupported_result };
struct Refusal {
    Error reason;
    std::size_t stage{};  // Profile 0/1; motion input 0, middle 1, output 2.
    std::optional<geared_cycle::Error> rate_error{};
};
using Result = std::variant<Refusal, Evaluation>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure fixed-bend ideal readings. A forward joint maps (x,y) to (q*x,p*y),
// where p/q is its positive cosine; compensating mounting exchanges p and q.
// For compensating mounting both fork references are clocked one quarter turn
// in their respective shaft frames. Angular drive direction is preserved.
// Its local yoke coordinates are explicit, not arbitrary native Part axes.
// Signed Pythagorean bends compose in one plane from an initial +Z shaft.
//
// Validate the COMPLETE profile, primitive input dial and truthful native motion
// even without power. Preserve unpowered/stopped/stalled distinctions. Both
// instantaneous derived rates must fit the existing native clock representation;
// a constant final mapping cannot hide an unsupported intermediate reading.
// Positive equal composite coefficients prove constant 1:1 motion at EVERY
// nonzero dial; one instantaneous or average reading does not prove that.
//
// These are owned pose/velocity observations, not a tick integrator, dynamics,
// contact/force admission, an angled shaft Part, live phase, graph or World.
[[nodiscard]] Result evaluate(const Profile&, Dial, mechanics::Motion);
}  // namespace factory::cardan_pair
