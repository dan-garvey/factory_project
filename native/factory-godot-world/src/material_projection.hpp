#pragma once

#include "factory/world.hpp"

namespace factory::godot_world::material_projection {

// These fields are derived from a trusted native snapshot. They hold no
// material, clock, request or actor state of their own.
[[nodiscard]] values::Value point_value(const authority::Point& point);
[[nodiscard]] values::Value cargo_value(const materials::Cargo& cargo, bool resources, bool copper);
[[nodiscard]] bool copper_forms(const materials::Config& config);
[[nodiscard]] values::Value::Object slide_phase_projection(const world::State& state);
[[nodiscard]] values::Value::Object tick_fields(
    const world::Profile& profile, const world::Snapshot& snapshot);

}  // namespace factory::godot_world::material_projection
