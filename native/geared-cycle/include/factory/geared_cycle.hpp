#pragma once

#include "factory/mechanics.hpp"

#include <variant>

namespace factory::geared_cycle {
using Integer = mechanics::Integer;
inline constexpr Integer maximum_teeth = 65536;
inline constexpr Integer maximum_denominator = 1000000;
inline constexpr Integer maximum_intervals = 256;

// One canonical phase in [0, cycle teeth). Numerator/denominator must already
// be reduced; zero is 0/1. The caller owns this one phase, including its fraction.
struct Phase {
    Integer numerator{};
    Integer denominator{1};
    bool operator==(const Phase&) const = default;
};

struct Crossing {
    Integer tooth{};  // Reached boundary modulo the cycle, never a starting stop.
    int direction{};
    mechanics::Rate at;  // Exact fraction in (0,1] of this admitted tick.
    bool operator==(const Crossing&) const = default;
};

struct Prepared {
    Phase next;
    std::vector<Crossing> crossings;  // Chronological, including complete wraps.
};
enum class Error { invalid_profile, invalid_phase, invalid_rate, rate_limit, phase_limit };
using Plan = std::variant<Error, Prepared>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure ideal phase proposal. The fixture interprets native angular rate 1 as
// one tooth interval per admitted tick; this conversion is not a production rule.
// Reverse rates retain their sign. Never round a fraction or alias a complete
// revolution to a no-op. Refuse unsupported denominators/speeds without partial
// events. Validate inputs even when power is off; a paused tick accrues no debt.
//
// The authority supplies actual rate/power and must atomically admit the phase
// and every effect after checking the entire proposed interval. Crossings alone
// are not continuous collision or tool-contact evidence. No live clock, World,
// material, tick source, requests or persistence is stored here.
[[nodiscard]] Plan prepare(Integer teeth, Phase, mechanics::Rate, bool powered = true);
}  // namespace factory::geared_cycle
