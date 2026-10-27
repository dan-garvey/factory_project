#pragma once

#include "factory/world.hpp"

namespace factory::godot_world::drive_projection {

// Readouts for the Godot adapter, derived from one trusted World snapshot and
// its mechanical result. No request, actor, or simulation state is retained.
struct Fields {
    values::Value::Array links;
    values::Value::Array drive_links;
    values::Value::Array engagements;
    values::Value::Object motion;
};

[[nodiscard]] Fields fields(const world::State& state, const world::DrivePower& power);

}  // namespace factory::godot_world::drive_projection
