#pragma once

#include "factory/arrival_geometry.hpp"
#include "factory/world.hpp"

#include <optional>

namespace factory::godot_world::component_geometry {

// One occupied volume serves physical admission and the player-facing part
// readout. It is derived from the native kind and site, never saved separately.
[[nodiscard]] arrival_geometry::Bounds component_bounds(const world::Profile& profile,
    std::optional<materials::Component> kind, const mechanics::Point& center);

}  // namespace factory::godot_world::component_geometry
