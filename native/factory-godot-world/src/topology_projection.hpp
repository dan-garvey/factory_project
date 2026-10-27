#pragma once

#include "factory/arrival_geometry.hpp"
#include "factory/physical_support.hpp"

#include <array>
#include <map>
#include <string>

namespace factory::godot_world::topology_projection {

using WheelSupports = std::map<std::string, std::array<arrival_geometry::Bounds, 2>>;

struct Fields {
    values::Value::Object entities;
    values::Value::Object transmission_parts;
    values::Value::Object foundations;
};

// Formats one World state and the physical supports already confirmed by Host.
// No entity, support route or foundation has a second owner here.
[[nodiscard]] Fields fields(const world::State& state,
    const std::map<std::string, physical_support::TransmissionSupport>& supports,
    const WheelSupports& wheel_supports);

}  // namespace factory::godot_world::topology_projection
