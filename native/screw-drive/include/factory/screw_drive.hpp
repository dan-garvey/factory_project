#pragma once

#include "factory/geared_cycle.hpp"

#include <optional>
#include <span>

namespace factory::screw_drive {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Turns = geared_cycle::Phase;
using Id = std::uint32_t;
inline constexpr Integer maximum_turns = 4096;
inline constexpr std::size_t maximum_nuts = 16;

struct Nut {
    Id id{};
    mechanics::Point origin{};
    mechanics::Axis axis{mechanics::Axis::x};
    Integer lead{1};  // Signed coordinate units per spindle revolution.
};
struct Profile {
    Integer limit_turns{4};
    std::vector<Nut> nuts{{1, {}, mechanics::Axis::x, 1}};
};
struct NutPose {
    Id id{};
    std::array<Fraction, 3> position;
    bool operator==(const NutPose&) const = default;
};
enum class End { lower, upper };
struct Endstop {
    End end;
    Fraction at;  // First arrival in the original admitted tick, in (0,1].
    bool operator==(const Endstop&) const = default;
};
struct Crossing {
    Integer turn{};
    int direction{};
    Fraction at;
    bool operator==(const Crossing&) const = default;
};
enum class Stop { unpowered, stopped, lower_end, upper_end };
struct Hold {
    Turns turns;
    std::vector<NutPose> poses;
    Stop reason;
};
struct Advance {
    Turns next;
    std::vector<NutPose> poses;
    std::vector<Crossing> crossings;
    std::optional<Endstop> endstop;
};
enum class Error { invalid_profile, invalid_nut, duplicate_nut, invalid_turns, clock_refused, inconsistent_clock };
struct Refusal {
    Error reason;
    std::optional<geared_cycle::Error> clock_error;
    Id subject{};
    bool operator==(const Refusal&) const = default;
};
struct Observation { Fraction rate{1, 1}; bool powered{true}; };
using Sample = std::variant<Refusal, std::vector<NutPose>>;
using Plan = std::variant<Refusal, Hold, Advance>;
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] const char* stop_name(Stop) noexcept;
[[nodiscard]] Sample sample(const Profile&, Turns);

// Pure non-cyclic actuator with one caller-owned unwrapped spindle phase.
// Every nut derives from that same phase. This fixture interprets native rate 1
// as one spindle revolution per admitted tick; thread lead sets translation.
// Reach the declared end stop exactly, retain only the reached turn crossings
// with their ORIGINAL tick times, then hold for the remainder. Exact endpoint
// arrivals also report a stop. An outward attempt already at a stop is a Hold
// at time zero. Validate the whole assembly and rate even while unpowered.
//
// The existing clock supplies supported interior phases and crossing plans;
// clipping before an end stop avoids rejecting an unrepresentable overshoot.
// No cyclic wrap, fresh nut, reset or rounded position is substituted. The
// authority owns atomic effects, actual stall propagation, force/contact,
// geometry, reach, World/material/Store and persistence. Declared travel limits
// are not detected body collisions. No live clock or mutable assembly is stored.
[[nodiscard]] Plan prepare(const Profile&, Turns, const Observation&);
}  // namespace factory::screw_drive
