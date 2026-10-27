#include "restore_site_validation.hpp"

#include "physical_geometry.hpp"
#include "factory/site_geometry_contract.hpp"

#include <algorithm>
#include <optional>
#include <vector>

namespace factory::godot_world::restore_site_validation {
namespace {
using Role = stationary::Role;
using Bounds = arrival_geometry::Bounds;
using physical_geometry::belt_bounds;
using physical_geometry::belt_intersects;
using physical_geometry::collector_external_bounds;
using physical_geometry::collector_intake_bounds;
using physical_geometry::collector_intake_intersects;
using physical_geometry::find_part;
using physical_geometry::foundation_bounds;
using physical_geometry::gear_axle_half_extents;
using physical_geometry::gear_half_extents;
using physical_geometry::intersects_belt;
using physical_geometry::overlap;
using physical_geometry::overlaps_supports;
using physical_geometry::part_bounds;
using physical_geometry::transmission_intersects;
using physical_geometry::transmission_intersects_foundations;
using physical_geometry::wheel_support_bounds;
using site_geometry::anchor_height;
using site_geometry::height_step;
using site_geometry::pitch;
}  // namespace

const char* geometry(const world::Profile& profile, const terrain_surface::Surface& terrain,
        const world::State& state,
        const std::map<std::string, physical_support::TransmissionSupport>& supports,
        const std::map<std::string, std::size_t>* saved_routes) {
    const physical_site::Site site{profile, terrain};
    for (const auto& part : state.topology.parts) {
        const auto& center = part.geometry.center;
        const bool relay = part.role == Role::gearbox || part.role == Role::vertical_gearbox ||
                           part.role == Role::chain_drive;
        if (std::any_of(center.begin(), center.end(), [](auto value) {
            return value < -mechanics::maximum_coordinate || value > mechanics::maximum_coordinate;
        })) return "incompatible_geometry";
        if (part.role == Role::shaft) {
            if (part.geometry.half_span != 2) return "incompatible_geometry";
        } else if (part.role == Role::gear) {
            if (part.geometry.teeth != 2 && part.geometry.teeth != 4) return "incompatible_geometry";
        } else if (part.role == Role::belt || center[0] % 4 != 0 || center[2] % 4 != 0)
            return "incompatible_geometry";
        if (relay && (center[1] % 4 != 0 ||
            (part.role == Role::gearbox && part.geometry.axis != mechanics::Axis::y) ||
            (part.role == Role::vertical_gearbox && part.geometry.axis == mechanics::Axis::y)))
            return "incompatible_geometry";
        if (part.role == Role::collector)
            if (const auto* refusal = physical_site::collector_refusal(site, center)) return refusal;
        for (const auto& external : part.role == Role::collector ?
                collector_external_bounds(center) : std::vector<Bounds>{}) {
            if (intersects_belt(state, external)) return "occupied";
            for (const auto& [id, foundation] : state.foundations) {
                (void)id;
                if (overlap(external, foundation_bounds(foundation))) return "occupied";
            }
            for (const auto& other : state.topology.parts)
                if (other.geometry.id != part.geometry.id &&
                    collector_intake_intersects(external, profile, other)) return "occupied";
        }
        if (part.role == Role::waterwheel) {
            if (const auto* refusal = physical_site::wheel_refusal(
                    site, center, part.geometry.axis, part.wheel_tiles)) return refusal;
            const auto wheel_supports = wheel_support_bounds(center, part.geometry.axis,
                [&terrain](double sx, double sz, double hx, double hz) {
                    return terrain.range(sx, sz, hx, hz);
                });
            if (!wheel_supports) return "support_required";
            for (const auto& [id, foundation] : state.foundations) {
                (void)id;
                if (overlap(part_bounds(profile, part), foundation_bounds(foundation)) ||
                    overlaps_supports(*wheel_supports, foundation_bounds(foundation))) return "occupied";
            }
            for (const auto& other : state.topology.parts) {
                if (other.geometry.id == part.geometry.id) continue;
                if (other.role == Role::gear || other.role == Role::shaft) {
                    for (const auto& support : *wheel_supports)
                        if (transmission_intersects(support, other.geometry.center, other.geometry.axis,
                                                    other.role == Role::gear)) return "occupied";
                } else if (overlap(part_bounds(profile, part), part_bounds(profile, other)) ||
                           overlaps_supports(*wheel_supports, part_bounds(profile, other))) return "occupied";
            }
        } else if (part.role != Role::shaft && part.role != Role::gear && !relay)
            if (const auto* refusal = physical_site::machine_refusal(
                    site, state, center, part.role == Role::collector)) return refusal;
        if (part.role == Role::shaft || part.role == Role::gear || relay) {
            if (transmission_intersects_foundations(state, center, part.geometry.axis,
                    part.role == Role::gear)) return "occupied";
            if (const auto* refusal = physical_site::transmission_refusal(
                    site, state, center, part.geometry.axis, part.role == Role::gear)) return refusal;
            if (!supports.contains(part.geometry.id)) return "support_required";
            if (relay) {
                const authority::Point at{center[0] * height_step,
                    anchor_height + center[1] * height_step, center[2] * height_step};
                const authority::Point half{pitch / 2, pitch / 2, pitch / 2};
                const Bounds shell{at, half};
                const auto shell_terrain = terrain.range(at[0], at[2], half[0], half[2]);
                if (!shell_terrain) return "terrain_unavailable";
                if (shell_terrain->second > at[1] - half[1] + 1e-9) return "site_occupied";
                if (terrain.blocked({at[0] - half[0], at[1] - half[1], at[2] - half[2]},
                                    {at[0] + half[0], at[1] + half[1], at[2] + half[2]}))
                    return "site_occupied";
                for (const auto& [id, foundation] : state.foundations) {
                    (void)id;
                    if (overlap(shell, foundation_bounds(foundation))) return "occupied";
                }
                for (const auto& other : state.topology.parts) {
                    if (other.geometry.id == part.geometry.id) continue;
                    if (other.geometry.center == center) return "occupied";
                    if (other.role != Role::shaft && other.role != Role::gear &&
                        other.role != Role::gearbox && other.role != Role::vertical_gearbox &&
                        other.role != Role::chain_drive && overlap(shell, part_bounds(profile, other)))
                        return "occupied";
                    if (other.role == Role::collector)
                        if (const auto intake = collector_intake_bounds(other.geometry.center))
                            if (overlap(shell, *intake)) return "occupied";
                }
                if (intersects_belt(state, shell)) return "occupied";
            }
        }
    }
    if (!state.topology.material_links.empty()) return "incompatible_geometry";
    for (const auto& span : state.topology.belt_spans) {
        const auto* first = find_part(state, span.geometry.first_shaft);
        const auto* last = find_part(state, span.geometry.last_shaft);
        const auto path = first && last ? mechanics::belt_path(first->geometry, last->geometry) : std::nullopt;
        if (!path) return "invalid_belt_geometry";
    }
    for (const auto& span : state.topology.belt_spans) {
        const auto* first = find_part(state, span.geometry.first_shaft);
        const auto* last = find_part(state, span.geometry.last_shaft);
        if (!first || !last) return "invalid_belt_geometry";
        for (const auto& [id, foundation] : state.foundations) {
            (void)id;
            if (belt_intersects(first->geometry, last->geometry, foundation_bounds(foundation))) return "occupied";
        }
        for (const auto& placed : state.topology.parts) {
            if (placed.role == Role::shaft) continue;
            const auto& point = placed.geometry.center;
            const Bounds bounds = placed.role == Role::gear ? Bounds{
                {point[0] * height_step, anchor_height + point[1] * height_step, point[2] * height_step},
                gear_half_extents(placed.geometry.axis, placed.geometry.teeth)} : part_bounds(profile, placed);
            if (belt_intersects(first->geometry, last->geometry, bounds)) return "occupied";
            if (placed.role == Role::gear && belt_intersects(first->geometry, last->geometry,
                {bounds.center, gear_axle_half_extents(placed.geometry.axis)})) return "occupied";
            if (placed.role == Role::waterwheel) {
                const auto wheel_supports = wheel_support_bounds(placed.geometry.center,
                    placed.geometry.axis, [&terrain](double sx, double sz, double hx, double hz) {
                        return terrain.range(sx, sz, hx, hz);
                    });
                if (!wheel_supports) return "support_required";
                for (const auto& support : *wheel_supports)
                    if (belt_intersects(first->geometry, last->geometry, support)) return "occupied";
            }
        }
        for (const auto& belt : belt_bounds(first->geometry, last->geometry)) {
            const auto& at = belt.center;
            const auto& half = belt.half;
            if (terrain.blocked({at[0] - half[0], at[1] - half[1], at[2] - half[2]},
                                {at[0] + half[0], at[1] + half[1], at[2] + half[2]}))
                return "site_occupied";
            const auto ground = terrain.range(at[0], at[2], half[0], half[2]);
            if (!ground) return "terrain_unavailable";
            if (ground->second > at[1] - half[1]) return "site_occupied";
        }
    }
    if (saved_routes) {
        if (supports.size() != saved_routes->size()) return "invalid_support_route";
        for (const auto& [id, route] : *saved_routes) {
            const auto found = supports.find(id);
            if (found == supports.end() || found->second.route != route)
                return "invalid_support_route";
        }
    }
    return nullptr;
}

}  // namespace factory::godot_world::restore_site_validation
