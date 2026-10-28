#pragma once

#include "factory/arrival_geometry.hpp"
#include "factory/world.hpp"

#include <array>
#include <functional>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace factory::godot_world::physical_geometry {

using Bounds = arrival_geometry::Bounds;
using TerrainRange = std::function<std::optional<std::pair<double, double>>(
    double x, double z, double half_x, double half_z)>;

[[nodiscard]] bool capsule_intersects(const authority::Point& actor, const Bounds& box,
    double tolerance = 0);
[[nodiscard]] std::optional<std::array<Bounds, 2>> wheel_support_bounds(
    const mechanics::Point& center, mechanics::Axis axis, const TerrainRange& terrain_range);
[[nodiscard]] Bounds part_bounds(const world::Profile& profile, const stationary::PlacedPart& part);
[[nodiscard]] std::optional<Bounds> collector_intake_bounds(const mechanics::Point& center);
[[nodiscard]] std::vector<Bounds> collector_external_bounds(const mechanics::Point& center);
[[nodiscard]] Bounds foundation_bounds(const world::Foundation& foundation);

[[nodiscard]] bool slide_head_fitting(std::optional<materials::Component> first,
    const mechanics::Point& first_center, materials::Component second,
    const mechanics::Point& second_center);
[[nodiscard]] bool guide_ram_fitting(std::optional<materials::Component> first,
    const mechanics::Point& first_center, materials::Component second,
    const mechanics::Point& second_center);
[[nodiscard]] bool frame_anvil_fitting(std::optional<materials::Component> first,
    const mechanics::Point& first_center, materials::Component second,
    const mechanics::Point& second_center);
[[nodiscard]] bool workbed_tray_fitting(std::optional<materials::Component> first,
    const mechanics::Point& first_center, materials::Component second,
    const mechanics::Point& second_center);
[[nodiscard]] bool frame_ram_fitting(std::optional<materials::Component> first,
    const mechanics::Point& first_center, materials::Component second,
    const mechanics::Point& second_center);

[[nodiscard]] bool overlap(const Bounds& a, const Bounds& b);
[[nodiscard]] bool overlaps_supports(const std::array<Bounds, 2>& supports, const Bounds& other);
[[nodiscard]] authority::Point gear_half_extents(mechanics::Axis axis, mechanics::Integer teeth);
[[nodiscard]] authority::Point gear_axle_half_extents(mechanics::Axis axis);
[[nodiscard]] bool transmission_intersects(const Bounds& other, const mechanics::Point& center,
    mechanics::Axis axis, bool gear);
[[nodiscard]] bool shaft_meets_component_cog(std::optional<materials::Component> kind,
    const mechanics::Point& component, const mechanics::Point& shaft, mechanics::Axis axis);
[[nodiscard]] bool shaft_meets_slide_input(std::optional<materials::Component> kind,
    const mechanics::Point& component, const mechanics::Point& shaft, mechanics::Axis axis);
[[nodiscard]] bool collector_intake_intersects(const Bounds& intake, const world::Profile& profile,
    const stationary::PlacedPart& other);
[[nodiscard]] bool transmission_intersects_foundations(const world::State& state,
    const mechanics::Point& center, mechanics::Axis axis, bool gear);
[[nodiscard]] const stationary::PlacedPart* find_part(const world::State& state,
    const std::string& id);

[[nodiscard]] std::vector<Bounds> belt_bounds(const mechanics::Part& first, const mechanics::Part& last);
[[nodiscard]] bool belt_intersects(const mechanics::Part& first, const mechanics::Part& last,
    const Bounds& bounds);
[[nodiscard]] bool intersects_belt(const world::State& state, const Bounds& bounds,
    const std::string* fitted_shaft = nullptr);

}  // namespace factory::godot_world::physical_geometry
