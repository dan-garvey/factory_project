#pragma once

#include "factory/mechanics.hpp"

#include <cstdint>
#include <optional>
#include <span>

namespace factory::clearance {
using Coordinate = mechanics::Integer;
using Point = mechanics::Point;

struct Box {
    Point minimum{}, maximum{};
    bool operator==(const Box&) const = default;
};

struct Obstacle {
    std::uint64_t id{};  // Positive, opaque caller-owned identity; never allocated here.
    Box box;
};

struct Fraction {
    Coordinate numerator{};
    Coordinate denominator{1};
    bool operator==(const Fraction&) const = default;
};

struct Hit {
    std::uint64_t obstacle{};
    Fraction time;  // First contact in [0,1), reduced with a positive denominator.
    bool initially_overlapping{};  // Refers to this selected obstacle.
    bool operator==(const Hit&) const = default;
};

enum class Error { none, invalid_box, invalid_motion, too_many_obstacles, invalid_id, duplicate_id, arithmetic_limit };

struct Result {
    Error error{Error::none};
    std::optional<Hit> hit{};
    [[nodiscard]] bool clear() const noexcept { return error == Error::none && !hit; }
    bool operator==(const Result&) const = default;
};

[[nodiscard]] const char* error_name(Error) noexcept;

// Exact translation-only query for positive-volume, axis-aligned boxes within
// the existing bounded integer grid. The chosen prototype policy blocks positive
// interior overlap: sliding/grazing or contact only at the destination is clear;
// contact at the start followed by penetration is blocked at time zero.
// Initial penetration is reported even when the proposed motion would escape.
//
// The caller supplies the COMPLETE relevant obstacle set (up to maximum_parts).
// Never truncate that set on refusal. All inputs are validated before publishing
// a hit, and equal contact times choose the lowest identity regardless of order.
// World owns shapes, admission, actual motion/contact policy and phase/state
// commits. This component stores no body, world, quantities, clock or response.
[[nodiscard]] Result sweep(const Box&, const Point& displacement,
                           std::span<const Obstacle>) noexcept;

struct Rotor {
    Box box;  // Initial world-space box on the same integer grid.
    Point pivot{};
    mechanics::Axis axis{mechanics::Axis::y};
    bool operator==(const Rotor&) const = default;
};

struct FullTurnHit {
    std::uint64_t obstacle{};
    // A nonempty open interval of squared radii occupied by both interiors.
    // This is an existence witness, not an angle, time or penetration depth.
    Coordinate radial_lower_squared{}, radial_upper_squared{};
    bool operator==(const FullTurnHit&) const = default;
};

struct FullTurnResult {
    Error error{Error::none};
    std::optional<FullTurnHit> hit{};
    [[nodiscard]] bool clear() const noexcept { return error == Error::none && !hit; }
    bool operator==(const FullTurnResult&) const = default;
};

// Exact existence query over a COMPLETE continuous turn about a fixed coordinate
// axis, against stationary positive-volume boxes. It does not infer clearance
// from index stops or sampled angles. Tangency is clear under the experimental
// strict-interior policy above. The complete swept box must fit the grid bounds;
// an invalid axis/pivot or an escaping turn returns invalid_motion.
//
// Every obstacle is validated before publishing the lowest obstructing identity,
// independent of input order. This does not choose the first impact or admit a
// partial-angle move. Dynamic bodies, mating exemptions, response and phase
// commits remain with the caller/authority; no body, clock or cargo is stored.
[[nodiscard]] FullTurnResult full_turn(const Rotor&, std::span<const Obstacle>) noexcept;

enum class TurnDirection { positive, negative };  // Right-hand rule about the positive axis.
struct QuarterTurnResult {
    Error error{Error::none};
    std::optional<std::uint64_t> obstacle{};
    [[nodiscard]] bool clear() const noexcept { return error == Error::none && !obstacle; }
    bool operator==(const QuarterTurnResult&) const = default;
};

// Continuous existence query over exactly the requested signed quarter-turn.
// Unlike full_turn(), an obstruction elsewhere on the circle does not block it.
// Bounds apply to this entire requested path, not an enclosing full circle.
// Exact separating-axis inequalities use bounded quadratic root isolation;
// arithmetic refusal returns no partial obstruction. Input validation, strict
// interior policy and lowest-identity selection match full_turn(). No impact
// angle, phase, response or body admission is published.
[[nodiscard]] QuarterTurnResult quarter_turn(const Rotor&, TurnDirection,
                                            std::span<const Obstacle>) noexcept;
}  // namespace factory::clearance
