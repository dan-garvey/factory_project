#pragma once

#include "factory/world.hpp"

namespace factory::godot_world::arrival_site_projection {

// Read the issued pod, movable workshop, cranks and placed buildables from one
// native state. A generic site has none of these optional arrival fields.
[[nodiscard]] values::Value::Object fields(const world::Profile& profile,
    const world::State& state, const world::DrivePower& power);

}  // namespace factory::godot_world::arrival_site_projection
