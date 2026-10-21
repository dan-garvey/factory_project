#pragma once

#include "factory/clearance.hpp"
#include "factory/geared_cycle.hpp"

#include <array>
#include <optional>
#include <span>
#include <variant>

namespace factory::scotch_yoke {
using Integer = mechanics::Integer;
using Fraction = mechanics::Rate;
using Point = std::array<Fraction, 3>;
inline constexpr Integer maximum_direction_scale = 256;
struct Direction {
    Integer cosine{1}, sine{}, scale{1};  // Primitive signed unit circle, x²+y²=q².
    bool operator==(const Direction&) const = default;
};
struct Profile {
    std::uint32_t crank_id{7}, yoke_id{11};
    mechanics::Point origin{0, 0, 8};
    mechanics::Axis shaft{mechanics::Axis::z}, travel{mechanics::Axis::x};
    Integer radius{6}, pin_radius{1};
    Integer slot_half_width{1}, slot_half_length{7}, wall{1}, half_thickness{1};
    bool operator==(const Profile&) const = default;
};
struct Sample {
    Profile profile;
    Direction direction;
    mechanics::Motion crank;
    Point pin, yoke, yoke_per_radian;
};
struct Turn {
    Profile profile;
    std::array<bool, 2> slot_fits;  // Width, complete-turn length, including pin radius.
    clearance::Rotor pin_proxy;
    clearance::FullTurnResult pin_clearance;
    std::array<clearance::Box, 4> wall_start;  // Left, right, bottom, top at -radius.
    mechanics::Point wall_traverse{};
    std::array<clearance::Result, 4> walls;
    [[nodiscard]] bool admitted() const noexcept {
        if (!slot_fits[0] || !slot_fits[1] || !pin_clearance.clear()) return false;
        for (const auto& result : walls) if (!result.clear()) return false;
        return true;
    }
};
enum class Error { invalid_profile, invalid_axes, invalid_direction, invalid_motion, invalid_rate,
                   outside_slot_width, outside_slot_length, representation_limit, query_refused };
struct Refusal {
    Error reason;
    std::optional<geared_cycle::Error> rate_error{};
    std::optional<clearance::Error> geometry_error{};
};
using Reading = std::variant<Refusal, Sample>;
using TurnPlan = std::variant<Refusal, Turn>;
[[nodiscard]] const char* error_name(Error) noexcept;

// Pure ideal Scotch-yoke observation from ONE caller-owned circle direction.
// The native positive shaft/travel axes define a proper right-handed plane.
// The circular pin's travel coordinate fixes the yoke centre; its other plane
// coordinate slides inside the slot. Raw validation and finite pin fit apply
// even while unpowered. Opposite directions and native zero-speed states stay
// distinct. The geometric derivative is per RADIAN, never a native displacement
// per tick or an implicit conversion of the supplied crank rate's units.
[[nodiscard]] Reading sample(const Profile&, Direction, mechanics::Motion);

// Pure COMPLETE-turn setup proposal, not a tick/prefix or adopted body movement.
// Four separate walls preserve the OPEN slot. Cosine translation covers every
// scalar displacement in [-R,R], so each wall's canonical straight sweep gives
// exact stationary-overlap existence over the cycle. Its Hit::time is only that
// artificial traversal parameter, NOT actual crank time or impact phase.
// The circular pin uses a conservative rotating-box envelope. Whole obstacle
// sets and grid bounds must validate before any blocked/admitted result escapes.
// Crank arm, guides/collars, load, physical force/contact, graph, phase/clock,
// World and persistence remain with the authority; neither API owns live state.
[[nodiscard]] TurnPlan prepare_turn(const Profile&, std::span<const clearance::Obstacle>);
}  // namespace factory::scotch_yoke
