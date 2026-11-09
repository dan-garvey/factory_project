#pragma once

#include "factory/arrival_geometry.hpp"
#include "factory/world.hpp"

#include <optional>
#include <vector>

namespace factory::godot_world::component_geometry {

// One occupied volume serves physical admission and the player-facing part
// readout. It is derived from the native kind and site, never saved separately.
[[nodiscard]] arrival_geometry::Bounds component_bounds(const world::Profile& profile,
    std::optional<materials::Component> kind, const mechanics::Point& center);

// Reservations govern construction; open structures collide only at their
// actual legs and crown. These same solids are projected for scene collision.
[[nodiscard]] std::vector<arrival_geometry::Bounds> component_solids(const world::Profile&,
    materials::Component, const mechanics::Point&);

}  // namespace factory::godot_world::component_geometry
