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

enum class Error { none, invalid_box, invalid_motion, too_many_obstacles, invalid_id, duplicate_id };

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
}  // namespace factory::clearance
