#include "factory/physical_support.hpp"
#include "component_geometry.hpp"
#include "physical_geometry.hpp"
#include "factory/site_geometry_contract.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <tuple>

namespace factory::godot_world::physical_support {
namespace {
using Bounds = physical_geometry::Bounds;
using Role = stationary::Role;
using component_geometry::component_bounds;
using physical_geometry::collector_external_bounds;
using physical_geometry::collector_intake_intersects;
using physical_geometry::foundation_bounds;
using physical_geometry::intersects_belt;
using physical_geometry::overlap;
using physical_geometry::wheel_support_bounds;
using site_geometry::height_denominator;
using site_geometry::height_step;
using site_geometry::anchor_height;
}  // namespace

std::map<std::string, TransmissionSupport> layout(
        const Site& site, const world::State& state, const Routes* preferred_routes) {
    std::vector<const stationary::PlacedPart*> parts;
    for (const auto& part : state.topology.parts) parts.push_back(&part);
    auto jobs = parts;
    std::erase_if(jobs, [](const auto* part) { return !fixed_transmission(part->role); });
    std::sort(jobs.begin(), jobs.end(), [preferred_routes](const auto* a, const auto* b) {
        // Existing hardware owns its route before a newly placed stand chooses
        // one. The placement order cannot silently displace a surviving post.
        const bool a_pinned = preferred_routes && preferred_routes->contains(a->geometry.id);
        const bool b_pinned = preferred_routes && preferred_routes->contains(b->geometry.id);
        if (a_pinned != b_pinned) return a_pinned;
        const auto& ac = a->geometry.center;
        const auto& bc = b->geometry.center;
        return std::tie(ac[1], ac[0], ac[2], a->geometry.axis, a->geometry.id) <
               std::tie(bc[1], bc[0], bc[2], b->geometry.axis, b->geometry.id);
    });
    std::map<std::string, TransmissionSupport> result;
    std::vector<Bounds> occupied;
    const auto beam = [](const authority::Point& a, const authority::Point& b) {
        Bounds bounds{};
        for (std::size_t dimension = 0; dimension < 3; ++dimension) {
            bounds.center[dimension] = (a[dimension] + b[dimension]) / 2;
            bounds.half[dimension] = std::abs(a[dimension] - b[dimension]) / 2 + 0.0475;
        }
        return bounds;
    };
    for (const auto* part : jobs) {
        const auto& center = part->geometry.center;
        const auto axis = part->geometry.axis;
        const authority::Point at{center[0] * height_step,
            anchor_height + center[1] * height_step, center[2] * height_step};
        // Fixed bearings stay coaxial. Move only the post, using a short arm
        // when another axle or a previously fitted stand occupies its column.
        // Try the other end of a horizontal axle if its first bearing face is
        // obstructed, for example by the collector's exterior lift.
        const std::size_t lateral = axis == mechanics::Axis::x ? 2 : 0;
        // Stacked cases need posts outside lower shells. A diagonal fallback
        // can stand beside the river shaft and ore outcrop while its complete
        // post and arm still pass the same terrain and occupancy checks.
        constexpr std::array offsets{0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.6, -1.6};
        constexpr std::array diagonals{
            std::array{-1.6, -1.6}, std::array{-1.6, 1.6},
            std::array{1.6, -1.6}, std::array{1.6, 1.6}};
        const auto routes = offsets.size() * (axis == mechanics::Axis::y ? 1 : 2) +
            (axis == mechanics::Axis::y ? diagonals.size() : 0);
        const auto pinned = preferred_routes ? preferred_routes->find(part->geometry.id) :
            std::map<std::string, std::size_t>::const_iterator{};
        const bool keep_route = preferred_routes && pinned != preferred_routes->end();
        for (std::size_t choice = 0; choice < (keep_route ? 1u : routes); ++choice) {
            // Leave the central ground-level column available for a later
            // coaxial machine beneath a raised axle.
            const bool raised = axis != mechanics::Axis::y && center[1] > height_denominator;
            const std::size_t route = keep_route ? pinned->second :
                raised && choice < 2 ? 1 - choice : choice;
            if (route >= routes) continue;
            const bool diagonal = axis == mechanics::Axis::y && route >= offsets.size();
            const double offset = diagonal ? diagonals[route - offsets.size()][0] : offsets[route % offsets.size()];
            const double axial = route < offsets.size() ? 0.55 : -0.55;
            auto bearing = at;
            if (axis == mechanics::Axis::x) bearing[0] += axial;
            else if (axis == mechanics::Axis::z) bearing[2] += axial;
            else bearing[1] -= 0.50;
            auto foot = bearing;
            if (axis == mechanics::Axis::y) foot[0] += 0.24;
            foot[lateral] += offset;
            if (diagonal) foot[2] += diagonals[route - offsets.size()][1];
            const auto ground = site.terrain_range(foot[0], foot[2], 0.17, 0.17);
            if (!ground) continue;
            double seat = ground->second;
            for (const auto& [id, foundation] : state.foundations) {
                (void)id;
                const auto bounds = foundation_bounds(foundation);
                if (std::abs(foot[0] - bounds.center[0]) + 0.17 <= bounds.half[0] &&
                    std::abs(foot[2] - bounds.center[2]) + 0.17 <= bounds.half[2])
                    seat = std::max(seat, bounds.center[1] + bounds.half[1]);
            }
            const double base_seat = seat;
            for (const auto& obstacle : site.terrain_obstacles) {
                if (obstacle.first[0] < foot[0] && obstacle.second[0] > foot[0] &&
                    obstacle.first[2] < foot[2] && obstacle.second[2] > foot[2] &&
                    obstacle.first[1] <= base_seat + 0.12)
                    seat = std::max(seat, obstacle.second[1]);
            }
            if (seat > at[1] - 0.02) continue;
            foot[1] = seat;
            const auto fitted_bearing = bearing;
            if (bearing[1] - seat > 9.0) continue;
            const double post_top = bearing[1] - 0.24;
            if (post_top <= seat) continue;
            const double column_top = std::max(post_top, seat + 0.14);
            std::vector<Bounds> boxes{{{foot[0], (seat + column_top) / 2, foot[2]},
                                      {0.17, (column_top - seat) / 2, 0.17}}};
            authority::Point half{0.185, 0.185, 0.185};
            half[static_cast<std::size_t>(axis)] = 0.1525;
            boxes.push_back({fitted_bearing, half});
            boxes.push_back({{bearing[0], bearing[1] - 0.20, bearing[2]}, {0.155, 0.04, 0.155}});
            if (foot[0] != fitted_bearing[0] || foot[2] != fitted_bearing[2]) {
                auto post_arm = foot;
                auto bearing_arm = fitted_bearing;
                post_arm[1] = bearing_arm[1] -= 0.24;
                boxes.push_back(beam(post_arm, bearing_arm));
            } else boxes.push_back({{bearing[0], post_top, bearing[2]}, {0.155, 0.0475, 0.155}});
            bool clear = true;
            for (const auto& box : boxes) {
                const auto terrain = site.terrain_range(box.center[0], box.center[2], box.half[0], box.half[2]);
                const authority::Point low{box.center[0] - box.half[0], box.center[1] - box.half[1], box.center[2] - box.half[2]};
                const authority::Point high{box.center[0] + box.half[0], box.center[1] + box.half[1], box.center[2] + box.half[2]};
                if (!terrain || terrain->second > low[1] + 1e-9 || site.site_blocked(low, high) ||
                    intersects_belt(state, box, &part->geometry.id)) clear = false;
                for (const auto& [id, foundation] : state.foundations) {
                    (void)id;
                    if (overlap(box, foundation_bounds(foundation))) clear = false;
                }
                for (const auto& [id, component] : state.placed_components) {
                    (void)id;
                    if (overlap(box, component_bounds(site.profile, component.kind, component.center))) clear = false;
                }
                for (const auto* other : parts) {
                    if (other == part) continue;
                    if (collector_intake_intersects(box, site.profile, *other)) clear = false;
                    if (other->role == Role::waterwheel) {
                        const auto wheel_feet = wheel_support_bounds(other->geometry.center, other->geometry.axis,
                            site.terrain_range);
                        if (!wheel_feet) clear = false;
                        else for (const auto& wheel_foot : *wheel_feet)
                            if (overlap(box, wheel_foot)) clear = false;
                    }
                    if (other->role == Role::collector)
                        for (const auto& external : collector_external_bounds(other->geometry.center))
                            if (overlap(box, external)) clear = false;
                }
                for (const auto& prior : occupied) if (overlap(box, prior)) clear = false;
                if (!clear) break;
            }
            if (!clear) continue;
            TransmissionSupport fitted{foot, fitted_bearing, {}, route};
            for (const auto& box : boxes) fitted.boxes.emplace_back(box.center, box.half);
            result.emplace(part->geometry.id, std::move(fitted));
            occupied.insert(occupied.end(), boxes.begin(), boxes.end());
            break;
        }
    }
    return result;
}

const char* change_refusal(const Site& site, const world::State& before,
        const world::State& after, const Routes& preferred_routes,
        const ActorBlocked& actor_blocked) {
    const auto previous = layout(site, before, &preferred_routes);
    const auto next = layout(site, after, &preferred_routes);
    std::optional<std::map<std::string, TransmissionSupport>> free_layout;
    for (const auto& part : after.topology.parts) {
        if (!fixed_transmission(part.role) || next.contains(part.geometry.id)) continue;
        // A route exists, but using it would relocate an already built stand.
        // Keep the neighboring machine buildable after its owner is reclaimed.
        if (preferred_routes.contains(part.geometry.id)) {
            if (!free_layout) free_layout = layout(site, after);
            if (free_layout->contains(part.geometry.id)) return "stand_in_use";
        }
        return "support_required";
    }
    for (const auto& [id, support] : next) {
        const auto old = previous.find(id);
        if (old != previous.end() && old->second.foot == support.foot &&
            old->second.bearing == support.bearing && old->second.boxes == support.boxes) continue;
        for (const auto& [center, half] : support.boxes)
            if (actor_blocked(center, half)) return "actor_occupied";
    }
    return nullptr;
}

}  // namespace factory::godot_world::physical_support
