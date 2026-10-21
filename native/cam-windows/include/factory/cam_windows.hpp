#pragma once

#include "factory/cycle.hpp"
#include "factory/geared_cycle.hpp"

#include <optional>
#include <span>

namespace factory::cam_windows {
inline constexpr std::size_t maximum_cams = 16;
using Id = std::uint32_t;
using Fraction = mechanics::Rate;

struct Cam {
    Id id{};
    mechanisms::Cam lobe;
};
struct Span {
    Fraction begin, end;  // Open-time interval in this admitted tick, 0 <= t <= 1.
    bool operator==(const Span&) const = default;
};
struct Window {
    Id id{};
    bool at_start{}, at_end{};  // Exact geometric state at the two instants.
    std::vector<Span> active;   // Ordered, positive-duration, coalesced intervals.
    Fraction coverage{};       // Fraction of the tick, not processing work.
    bool operator==(const Window&) const = default;
};
struct Overlap {
    Id first{}, second{};
    std::vector<Span> active;
    Fraction coverage{};
    bool operator==(const Overlap&) const = default;
};
struct Prepared {
    geared_cycle::Prepared motion;
    bool shaft_advances{};  // Includes complete revolutions with equal endpoints.
    std::vector<Window> windows;  // Canonical ascending ID order.
    std::vector<Overlap> overlaps;  // Only positive-duration pairs, in ID order.
};
enum class Error { invalid_profile, too_many_cams, invalid_id, duplicate_id, invalid_cam, clock_refused, arithmetic_limit };
struct Refusal {
    Error reason;
    std::optional<geared_cycle::Error> clock_error;
    Id subject{};
    bool operator==(const Refusal&) const = default;
};
using Plan = std::variant<Refusal, Prepared>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure geometric follower schedule on one ideal phase shaft. Existing cam and
// clock components own lobe membership and every signed boundary crossing.
// Endpoints are reported separately: an isolated on-state instant contributes
// no interval or duration. In reverse, an immediate edge after t=0 may differ
// from at_start. A stopped-open cam remains open even without shaft power.
//
// Coverage and overlap DO NOT grant work, choose an overload/activation policy,
// move material or settle tool contact. The authority supplies actual rate/power,
// resolves obstruction, and atomically admits its sole phase and all effects.
// This stores no clock owner, World, quantity, request or persistence. Validate
// the whole bounded bank before publishing any schedule, including while paused.
[[nodiscard]] Plan prepare(const mechanisms::Slide&, geared_cycle::Phase,
                           mechanics::Rate, bool powered, std::span<const Cam>);
}  // namespace factory::cam_windows
