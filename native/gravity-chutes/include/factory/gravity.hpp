#pragma once

#include <cstddef>
#include <cstdint>
#include <span>

// Original construction geometry experiment. No item custody, transport ticks,
// physics bodies, actor reach or live World state is stored here.
namespace factory::gravity {
struct Point {
    std::int32_t x{}, y{}, z{};
    bool operator==(const Point&) const = default;
};

// Bounds are inclusive. Blocked points are unavailable construction anchors.
// The point budget is a fixture's kit limit, not a permanent game restriction.
struct Site {
    Point minimum, maximum;
    std::span<const Point> blocked;
    std::size_t max_points{64};
};

struct Route {
    std::span<const Point> points;
    Point inlet, outlet;
};

enum class Fault {
    none, invalid_site, no_routes, too_short, too_long, insufficient_elevation,
    wrong_inlet, wrong_outlet, outside_site, blocked_anchor, invalid_drop,
    invalid_horizontal_step, shared_anchor, crossing_segments,
};

struct Report {
    Fault fault{Fault::none};
    std::size_t route{}, point{}, other_route{}, other_point{};
    [[nodiscard]] bool solved() const noexcept { return fault == Fault::none; }
};

[[nodiscard]] const char* explanation(Fault) noexcept;

// A piece drops exactly one level and moves at most one cell along ONE horizontal
// axis. Routes cannot share anchors or cross between anchors. This tests exact
// centerline geometry, not thick-body native collision or material throughput.
// Report indices are zero-based; a segment uses its destination point's index.
[[nodiscard]] Report inspect(const Site&, std::span<const Route>) noexcept;
}  // namespace factory::gravity
