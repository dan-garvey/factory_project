#pragma once

#include "factory/world.hpp"

namespace factory::godot_world::assembly_projection {

// Collector and press inspections for the arrival view. This reads one trusted
// native state and its derived power without storing assembly or material state.
[[nodiscard]] values::Value::Object fields(const world::Profile& profile,
    const world::State& state, const world::DrivePower& power);

}  // namespace factory::godot_world::assembly_projection
