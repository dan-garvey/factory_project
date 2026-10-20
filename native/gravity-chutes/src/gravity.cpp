#include "factory/gravity.hpp"

#include <algorithm>
#include <array>

namespace factory::gravity {
namespace {
bool inside(Point p, const Site& site) noexcept {
    return p.x >= site.minimum.x && p.x <= site.maximum.x &&
           p.y >= site.minimum.y && p.y <= site.maximum.y &&
           p.z >= site.minimum.z && p.z <= site.maximum.z;
}

std::int64_t distance(std::int32_t a, std::int32_t b) noexcept {
    const auto delta = static_cast<std::int64_t>(a) - b;
    return delta < 0 ? -delta : delta;
}

std::array<std::int64_t, 3> twice_midpoint(Point a, Point b) noexcept {
    return {static_cast<std::int64_t>(a.x) + b.x,
            static_cast<std::int64_t>(a.y) + b.y,
            static_cast<std::int64_t>(a.z) + b.z};
}
}  // namespace

const char* explanation(Fault fault) noexcept {
    switch (fault) {
        case Fault::none: return "Every route reaches its outlet with legal descending pieces and clear crossings.";
        case Fault::invalid_site: return "The site bounds, blocked anchors or point budget are invalid.";
        case Fault::no_routes: return "Supply at least one route.";
        case Fault::too_short: return "A route needs at least an inlet and an outlet.";
        case Fault::too_long: return "The route exceeds its construction point budget.";
        case Fault::insufficient_elevation: return "The fixed inlet has insufficient elevation to reach its outlet by gravity.";
        case Fault::wrong_inlet: return "The route must start at its fixed inlet.";
        case Fault::wrong_outlet: return "The route must end at its fixed outlet.";
        case Fault::outside_site: return "This construction anchor lies outside the site.";
        case Fault::blocked_anchor: return "This construction anchor is occupied by the site obstruction.";
        case Fault::invalid_drop: return "Every chute piece must descend exactly one level. Flat, rising and skipped levels need another mechanism.";
        case Fault::invalid_horizontal_step: return "A chute piece can move one cell along one horizontal axis, or drop vertically.";
        case Fault::shared_anchor: return "Two routes use the same construction anchor. Separate their height or footprint.";
        case Fault::crossing_segments: return "Two chute pieces cross between anchors. Use another elevation or a side clearance.";
    }
    return "Unknown route fault.";
}

Report inspect(const Site& site, std::span<const Route> routes) noexcept {
    if (site.minimum.x > site.maximum.x || site.minimum.y > site.maximum.y ||
        site.minimum.z > site.maximum.z || site.max_points < 2) return {Fault::invalid_site};
    for (const auto blocked : site.blocked) if (!inside(blocked, site)) return {Fault::invalid_site};
    if (routes.empty()) return {Fault::no_routes};
    for (std::size_t r = 0; r < routes.size(); ++r) {
        const auto& route = routes[r];
        if (route.points.size() < 2) return {Fault::too_short, r};
        if (route.points.size() > site.max_points) return {Fault::too_long, r, site.max_points};
        const auto drop = static_cast<std::int64_t>(route.inlet.y) - route.outlet.y;
        if (drop <= 0 || distance(route.inlet.x, route.outlet.x) +
                         distance(route.inlet.z, route.outlet.z) > drop) {
            return {Fault::insufficient_elevation, r};
        }
        if (route.points.front() != route.inlet) return {Fault::wrong_inlet, r};
        if (route.points.back() != route.outlet) return {Fault::wrong_outlet, r, route.points.size() - 1};
        for (std::size_t i = 0; i < route.points.size(); ++i) {
            const auto p = route.points[i];
            if (!inside(p, site)) return {Fault::outside_site, r, i};
            if (std::find(site.blocked.begin(), site.blocked.end(), p) != site.blocked.end()) {
                return {Fault::blocked_anchor, r, i};
            }
            if (i == 0) continue;
            const auto previous = route.points[i - 1];
            if (static_cast<std::int64_t>(previous.y) - p.y != 1) return {Fault::invalid_drop, r, i};
            if (distance(previous.x, p.x) + distance(previous.z, p.z) > 1) {
                return {Fault::invalid_horizontal_step, r, i};
            }
        }
    }
    // With one-cell, axis-aligned horizontal motion and exactly one level of
    // descent, interior intersections can only occur at a common midpoint.
    // Equal endpoints are checked separately; no float tolerance is involved.
    for (std::size_t r = 1; r < routes.size(); ++r) {
        for (std::size_t other = 0; other < r; ++other) {
            const auto points = routes[r].points;
            const auto earlier = routes[other].points;
            for (std::size_t i = 0; i < points.size(); ++i) {
                for (std::size_t j = 0; j < earlier.size(); ++j) {
                    if (points[i] == earlier[j]) return {Fault::shared_anchor, r, i, other, j};
                }
            }
            for (std::size_t i = 1; i < points.size(); ++i) {
                for (std::size_t j = 1; j < earlier.size(); ++j) {
                    if (twice_midpoint(points[i - 1], points[i]) == twice_midpoint(earlier[j - 1], earlier[j])) {
                        return {Fault::crossing_segments, r, i, other, j};
                    }
                }
            }
        }
    }
    return {};
}
}  // namespace factory::gravity
