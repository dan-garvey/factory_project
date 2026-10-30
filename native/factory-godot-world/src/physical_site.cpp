#include "factory/physical_site.hpp"

#include "component_geometry.hpp"
#include "physical_geometry.hpp"
#include "factory/arrival_geometry.hpp"
#include "factory/mineral_site.hpp"
#include "factory/site_geometry_contract.hpp"
#include "factory/waterwheel.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

namespace factory::godot_world::physical_site {
namespace {
using Bounds = arrival_geometry::Bounds;
using Integer = mechanics::Integer;
using Role = stationary::Role;
using component_geometry::component_bounds;
using physical_geometry::wheel_support_bounds;
using physical_geometry::collector_external_bounds;
using physical_geometry::foundation_bounds;
using physical_geometry::part_bounds;
using physical_geometry::slide_head_fitting;
using physical_geometry::guide_ram_fitting;
using physical_geometry::frame_anvil_fitting;
using physical_geometry::workbed_tray_fitting;
using physical_geometry::frame_ram_fitting;
using physical_geometry::overlap;
using physical_geometry::overlaps_supports;
using physical_geometry::gear_half_extents;
using physical_geometry::gear_axle_half_extents;
using physical_geometry::transmission_intersects;
using physical_geometry::shaft_meets_component_cog;
using physical_geometry::shaft_meets_slide_input;
using physical_geometry::intersects_belt;
using site_geometry::height_denominator;
using site_geometry::height_step;
using site_geometry::anchor_height;
using site_geometry::machine_width;
using site_geometry::machine_height;
}  // namespace

physical_support::Site support_site(const Site& site) {
    const auto* terrain = &site.terrain;
    return {site.profile, terrain->obstacles,
        [terrain](double x, double z, double half_x, double half_z) {
            return terrain->range(x, z, half_x, half_z);
        },
        [terrain](const authority::Point& low, const authority::Point& high) {
            return terrain->blocked(low, high);
        }};
}

const char* wheel_refusal(const Site& site, const mechanics::Point& center, mechanics::Axis axis, Integer tiles) {
    const auto sample = site.profile.water.find({center[0], center[2]});
    if (sample == site.profile.water.end()) return "not_at_stream";
    const auto contact = waterwheel::immersed(center[1] * 100 + site.profile.wheel_axle_offset,
                                              site.profile.wheel_radius * tiles, axis, sample->second);
    if (!contact || !*contact) return "not_at_stream";
    const double x = center[0] * height_step, y = center[1] * height_step + anchor_height;
    const double z = center[2] * height_step;
    const double radius = site.profile.wheel_radius * tiles * height_step / 100.0;
    const double half_x = axis == mechanics::Axis::x ? 0.3 : radius;
    const double half_z = axis == mechanics::Axis::z ? 0.3 : radius;
    if (site.terrain.blocked({x - half_x, y - radius, z - half_z}, {x + half_x, y + radius, z + half_z}))
        return "site_occupied";
    // Bound the entire rotating rim against the same emitted terrain triangles.
    // Each strip uses its highest ground and the lowest point of the arc in
    // that strip, so an unchecked peak cannot pass between point samples.
    const auto strips = static_cast<Integer>(std::ceil(2 * radius / height_step));
    for (Integer index = 0; index < strips; ++index) {
        const double a = -radius + 2 * radius * index / strips;
        const double b = -radius + 2 * radius * (index + 1) / strips;
        const double middle = (a + b) / 2, span = (b - a) / 2;
        const auto terrain = axis == mechanics::Axis::x ? site.terrain.range(x, z + middle, 0.3, span) :
                                                        site.terrain.range(x + middle, z, span, 0.3);
        if (!terrain) return "terrain_unavailable";
        const double nearest = a > 0 ? a : b < 0 ? -b : 0;
        const double low_arc = y - std::sqrt(std::max(0.0, radius * radius - nearest * nearest));
        if (terrain->second > low_arc) return "site_occupied";
    }
    const auto supports = wheel_support_bounds(center, axis,
        [&site](double sx, double sz, double hx, double hz) { return site.terrain.range(sx, sz, hx, hz); });
    if (!supports) return "support_required";
    for (const auto& support : *supports) {
        const authority::Point low{support.center[0] - support.half[0],
            support.center[1] - support.half[1], support.center[2] - support.half[2]};
        const authority::Point high{support.center[0] + support.half[0],
            support.center[1] + support.half[1], support.center[2] + support.half[2]};
        if (site.terrain.blocked(low, high)) return "site_occupied";
    }
    return nullptr;
}

const char* machine_refusal(const Site& site, const world::State& state, const mechanics::Point& center,
        bool collector) {
    const auto x = center[0] * height_step;
    const auto floor = center[1] * height_step;
    const auto z = center[2] * height_step;
    const bool supported = std::any_of(state.foundations.begin(), state.foundations.end(),
        [&](const auto& entry) { return entry.second.center == center; });
    const auto terrain = site.terrain.range(x, z);
    // A foundation supplies support, not clearance through the real ground.
    // Foundation blocks themselves may be buried; ordinary machines may not.
    if (terrain && terrain->second > floor) return "foundation_required";
    if (!supported) {
        if (!terrain) return "terrain_unavailable";
        // This is the existing seating fit, not additional character reach.
        if (terrain->first < floor - 0.04) return "foundation_required";
    }
    if (site.terrain.blocked({x - machine_width / 2, floor, z - machine_width / 2},
                     {x + machine_width / 2, floor + machine_height, z + machine_width / 2}))
        return "site_occupied";
    const auto external = collector ? collector_external_bounds(center) : std::vector<Bounds>{};
    for (std::size_t index = 0; index < external.size(); ++index) {
        const auto& at = external[index].center;
        const auto& half = external[index].half;
        const authority::Point low{at[0] - half[0], at[1] - half[1], at[2] - half[2]};
        const authority::Point high{at[0] + half[0], at[1] + half[1], at[2] + half[2]};
        const auto ground = site.terrain.range(at[0], at[2], half[0], half[2]);
        if (!ground) return "terrain_unavailable";
        if (ground->second > low[1] ||
            site.terrain.blocked(low, high, index == 0 ? site.terrain.source_obstacle : std::nullopt))
            return "site_occupied";
    }
    return nullptr;
}

const char* transmission_refusal(const Site& site, const world::State& state, const mechanics::Point& center,
        mechanics::Axis axis, bool gear) {
    const authority::Point at{center[0] * height_step, anchor_height + center[1] * height_step, center[2] * height_step};
    const auto axle = gear_axle_half_extents(axis);
    const auto check = [&](const authority::Point& half) -> const char* {
        const auto ground = site.terrain.range(at[0], at[2], half[0], half[2]);
        if (!ground) return "terrain_unavailable";
        if (ground->second > at[1] - half[1] + 1e-9) return "site_occupied";
        if (site.terrain.blocked({at[0] - half[0], at[1] - half[1], at[2] - half[2]},
                         {at[0] + half[0], at[1] + half[1], at[2] + half[2]})) return "site_occupied";
        return nullptr;
    };
    if (const auto* refusal = check(axle)) return refusal;
    if (gear) if (const auto* refusal = check(gear_half_extents(axis, 0))) return refusal;
    for (const auto& part : state.topology.parts) if (part.role == Role::waterwheel) {
        const auto supports = wheel_support_bounds(part.geometry.center, part.geometry.axis,
            [&site](double sx, double sz, double hx, double hz) {
                return site.terrain.range(sx, sz, hx, hz);
            });
        if (!supports) return "support_required";
        for (const auto& support : *supports)
            if (transmission_intersects(support, center, axis, gear)) return "site_occupied";
    }
    return nullptr;
}

const char* collector_refusal(const Site& site, const mechanics::Point& center) {
    const mineral_site::Cell cell{center[0] / height_denominator, center[2] / height_denominator};
    if (site.profile.ore_field ? !mineral_site::field_contains(cell) :
            !mineral_site::contains(cell)) return "not_at_seam";
    const auto surface = site.terrain.range(center[0] * height_step, center[2] * height_step);
    if (!surface) return "terrain_unavailable";
    const auto measured = mineral_site::Surface{surface->first, surface->second};
    const auto allowed = site.profile.ore_field ?
        mineral_site::admit_field(cell, center[1] * height_step, measured,
            mineral_site::extraction_depth_steps * height_step) :
        mineral_site::admit(cell, center[1] * height_step, measured,
            mineral_site::extraction_depth_steps * height_step);
    return allowed == mineral_site::Error::none ? nullptr : mineral_site::error_name(allowed);
}

const char* component_refusal(const Site& site, const world::State& state,
        std::optional<materials::Component> kind, const mechanics::Point& center) {
    const auto volume = component_bounds(site.profile, kind, center);
    const auto& at = volume.center;
    const auto ground = site.terrain.range(at[0], at[2], volume.half[0], volume.half[2]);
    if (!ground) return "terrain_unavailable";
    if (ground->second > at[1] - volume.half[1]) return "site_occupied";
    if (kind && materials::channel_spec(*kind) && center[1] == 0 &&
        ground->first < at[1] - volume.half[1] - 0.04)
        return "support_required";
    if (kind == materials::Component::broad_anvil &&
        ground->first < at[1] - volume.half[1] - 0.04) {
        const auto cells = materials::component_workcells(*kind, center);
        if (!cells || std::any_of(cells->begin(), cells->end(), [&](const auto& cell) {
                return std::none_of(state.foundations.begin(), state.foundations.end(),
                    [&](const auto& entry) { return entry.second.center == cell; });
            })) return "support_required";
    }
    if (kind == materials::Component::anvil &&
        ground->first < at[1] - volume.half[1] - 0.04) {
        const bool foundation = std::any_of(state.foundations.begin(), state.foundations.end(),
            [&](const auto& entry) { return entry.second.center == center; });
        const bool frame = std::any_of(state.placed_components.begin(),
            state.placed_components.end(), [&](const auto& entry) {
                return entry.second.kind == materials::Component::wooden_frame &&
                    entry.second.center == mechanics::Point{center[0], center[1] - 1, center[2]};
            });
        if (!foundation && !frame) return "support_required";
    }
    if (kind == materials::Component::wooden_workbench) {
        const bool supported = std::any_of(state.foundations.begin(), state.foundations.end(),
            [&](const auto& entry) { return entry.second.center == center; });
        if (!supported && ground->first < at[1] - volume.half[1] - 0.04)
            return "support_required";
    }
    // Only the named cutting edge at one of the two trusted ore faces may
    // enter the source hull. The source obstacle is separately identified and
    // validated when terrain binds; every other obstacle still blocks it.
    bool source_contact = false;
    if (kind == materials::Component::cutting_edge)
        for (const auto& face : site.profile.collector_faces)
            for (Integer height : {Integer{0}, Integer{1}})
                if (center == mechanics::Point{
                    face.machine_center[0] + 2 * face.toward_ore[0],
                    face.machine_center[1] + height,
                    face.machine_center[2] + 2 * face.toward_ore[2]}) source_contact = true;
    const auto ignored = source_contact ? site.terrain.source_obstacle : std::nullopt;
    if (site.terrain.blocked({at[0] - volume.half[0], at[1] - volume.half[1], at[2] - volume.half[2]},
                     {at[0] + volume.half[0], at[1] + volume.half[1], at[2] + volume.half[2]}, ignored))
        return "site_occupied";
    return nullptr;
}

const char* component_space_refusal(const Site& site, const world::State& state,
        std::optional<materials::Component> kind, const mechanics::Point& center,
        const std::string* current_id) {
    const auto volume = component_bounds(site.profile, kind, center);
    for (const auto& [id, foundation] : state.foundations) {
        (void)id;
        if (overlap(volume, foundation_bounds(foundation))) return "occupied";
    }
    for (const auto& [id, other] : state.placed_components)
        if ((!current_id || id != *current_id) &&
            !slide_head_fitting(kind, center, other.kind, other.center) &&
            !guide_ram_fitting(kind, center, other.kind, other.center) &&
            !frame_anvil_fitting(kind, center, other.kind, other.center) &&
            !workbed_tray_fitting(kind, center, other.kind, other.center) &&
            !frame_ram_fitting(kind, center, other.kind, other.center) &&
            overlap(volume, component_bounds(site.profile, other.kind, other.center))) return "occupied";
    if (intersects_belt(state, volume)) return "occupied";
    for (const auto& part : state.topology.parts) {
        if (part.role == Role::gear || part.role == Role::shaft) {
            if (transmission_intersects(volume, part.geometry.center, part.geometry.axis,
                                        part.role == Role::gear) &&
                !(part.role == Role::shaft && shaft_meets_component_cog(
                    kind, center, part.geometry.center, part.geometry.axis)) &&
                !(part.role == Role::shaft && shaft_meets_slide_input(
                    kind, center, part.geometry.center, part.geometry.axis))) return "occupied";
        } else if (overlap(volume, part_bounds(site.profile, part))) return "occupied";
        if (part.role == Role::collector)
            for (const auto& external : collector_external_bounds(part.geometry.center))
                if (overlap(volume, external)) return "occupied";
        if (part.role == Role::waterwheel) {
            const auto supports = wheel_support_bounds(part.geometry.center, part.geometry.axis,
                [&site](double x, double z, double hx, double hz) {
                    return site.terrain.range(x, z, hx, hz);
                });
            if (!supports) return "support_required";
            if (overlaps_supports(*supports, volume)) return "occupied";
        }
    }
    return nullptr;
}

const char* supplied_space_refusal(const Site& site, const world::State& state) {
    const auto solids = arrival_geometry::supplied(state, height_step);
    if (solids.empty()) return nullptr;
    const auto supports = physical_support::layout(support_site(site), state);
    for (const auto& [id, solid] : solids) {
        const auto& box = solid.bounds;
        for (const auto& [other_id, other] : solids)
            if (id < other_id && solid.entity != other.entity && overlap(box, other.bounds))
                return "occupied";
        for (const auto& [unused, floor] : state.foundations) {
            (void)unused;
            if (overlap(box, foundation_bounds(floor))) return "occupied";
        }
        for (const auto& [unused, component] : state.placed_components) {
            (void)unused;
            if (overlap(box, component_bounds(site.profile, component.kind, component.center))) return "occupied";
        }
        if (intersects_belt(state, box)) return "occupied";
        for (const auto& part : state.topology.parts) {
            if (part.role == Role::shaft || part.role == Role::gear) {
                if (transmission_intersects(box, part.geometry.center, part.geometry.axis,
                        part.role == Role::gear)) return "occupied";
            } else if (overlap(box, part_bounds(site.profile, part))) return "occupied";
            if (part.role == Role::collector)
                for (const auto& external : collector_external_bounds(part.geometry.center))
                    if (overlap(box, external)) return "occupied";
            if (part.role == Role::waterwheel) {
                const auto feet = wheel_support_bounds(part.geometry.center, part.geometry.axis,
                    [&site](double x, double z, double hx, double hz) { return site.terrain.range(x, z, hx, hz); });
                if (!feet) return "support_required";
                if (overlaps_supports(*feet, box)) return "occupied";
            }
        }
        for (const auto& [unused, support] : supports) {
            (void)unused;
            for (const auto& [center, half] : support.boxes)
                if (overlap(box, {center, half})) return "occupied";
        }
    }
    return nullptr;
}

namespace {

std::vector<std::pair<authority::Point, authority::Point>> build_solid_boxes(
        const Site& site, const world::State& state) {
    std::vector<std::pair<authority::Point, authority::Point>> boxes;
    boxes.reserve(state.placed_components.size() + state.topology.parts.size());
    const auto append_bounds = [&](const Bounds& bounds) {
        authority::Point low{}, high{};
        for (std::size_t axis = 0; axis < 3; ++axis) {
            low[axis] = bounds.center[axis] - bounds.half[axis];
            high[axis] = bounds.center[axis] + bounds.half[axis];
        }
        boxes.emplace_back(low, high);
    };
    for (const auto& [id, part] : state.placed_components) {
        (void)id;
        append_bounds(component_bounds(site.profile, part.kind, part.center));
    }
    for (const auto& part : state.topology.parts)
        append_bounds(part_bounds(site.profile, part));
    return boxes;
}

bool harvest_path_clear_boxes(const Site& site, const world::State& state,
        const std::vector<std::pair<authority::Point, authority::Point>>& solid_boxes,
        const std::string& source, const authority::Point& actor,
        const authority::Point& contact) {
    // The held tool just above the actor center is the origin; the selected source's own obstacle
    // is the destination, not a wall between the two. Other trusted solids
    // and the emitted ground can still stop a cut despite valid radial reach.
    auto start = actor;
    start[1] += 0.20;
    const authority::Point delta{contact[0] - start[0], contact[1] - start[1], contact[2] - start[2]};
    const auto intersects = [&](const authority::Point& low, const authority::Point& high) {
        double entry = 0.0, exit = 1.0;
        for (std::size_t axis = 0; axis < 3; ++axis) {
            if (std::abs(delta[axis]) < 1e-9) {
                if (start[axis] < low[axis] || start[axis] > high[axis]) return false;
                continue;
            }
            const double a = (low[axis] - start[axis]) / delta[axis];
            const double b = (high[axis] - start[axis]) / delta[axis];
            entry = std::max(entry, std::min(a, b));
            exit = std::min(exit, std::max(a, b));
        }
        return entry <= exit && entry < 1.0 - 1e-6 && exit > 1e-6;
    };
    for (std::size_t index = 0; index < site.terrain.obstacles.size(); ++index) {
        if (site.terrain.source_obstacle == index && site.profile.material.manual_ore &&
            (site.profile.material.manual_ore->id == source ||
                world::ore_region_index(site.profile, source) ==
                    mineral_site::field_region({0, 0}))) continue;
        if (const auto tree = site.terrain.tree_obstacles.find(index);
            tree != site.terrain.tree_obstacles.end() &&
            (tree->second == source || state.material.timber_remaining.at(tree->second) == 0)) continue;
        const auto& [low, high] = site.terrain.obstacles[index];
        if (intersects(low, high)) return false;
    }
    for (const auto& [low, high] : solid_boxes)
        if (intersects(low, high)) return false;
    const double span = std::hypot(delta[0], delta[2]);
    const int steps = std::max(1, static_cast<int>(std::ceil(span / 0.15)));
    for (int step = 1; step < steps; ++step) {
        const double t = static_cast<double>(step) / steps;
        const auto ground = site.terrain.range(start[0] + delta[0] * t,
            start[2] + delta[2] * t, 0, 0);
        if (!ground || ground->second > start[1] + delta[1] * t - 0.02) return false;
    }
    return true;
}

}  // namespace

bool harvest_path_clear(const Site& site, const world::State& state,
        const std::string& source, const authority::Point& actor,
        const authority::Point& contact) {
    return harvest_path_clear_boxes(site, state, build_solid_boxes(site, state), source, actor, contact);
}

std::map<std::string, bool> harvest_clearances(const Site& site,
        const world::State& state, const authority::Point& actor) {
    const auto solid_boxes = build_solid_boxes(site, state);
    std::map<std::string, bool> clear;
    const auto examine = [&](const std::string& id, const materials::DropPoint& center, bool ore) {
        const auto contact = world::manual_cut_target(site.profile, center, actor, ore);
        clear.emplace(id, harvest_path_clear_boxes(site, state, solid_boxes, id, actor, contact));
    };
    if (site.profile.material.manual_ore)
        examine(site.profile.material.manual_ore->id, site.profile.material.manual_ore->center, true);
    if (site.profile.ore_field && site.profile.material.manual_ore)
        for (mineral_site::Integer region = 0;
                region < mineral_site::field_region_count; ++region) {
            const auto id = world::ore_region_id(site.profile, region);
            const auto contact = world::ore_region_cut_target(site.profile, region, actor);
            clear.emplace(id, harvest_path_clear_boxes(site, state, solid_boxes, id, actor, contact));
        }
    for (const auto& [id, timber] : site.profile.material.timber_sites)
        examine(id, timber.center, false);
    return clear;
}

}  // namespace factory::godot_world::physical_site
