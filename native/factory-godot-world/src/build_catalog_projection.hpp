#pragma once

#include "factory/world.hpp"

namespace factory::godot_world::build_catalog_projection {

// The part names are shared by the kit/catalog view and Host's existing
// machine records. No offered count or recipe is stored outside World.
[[nodiscard]] const char* kind(stationary::Role role);
[[nodiscard]] values::Value::Object fields(
    const world::Profile& profile, const world::Snapshot& snapshot);

}  // namespace factory::godot_world::build_catalog_projection
