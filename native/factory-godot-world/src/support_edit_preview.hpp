#pragma once

#include "factory/world.hpp"

#include <string_view>
#include <variant>

namespace factory::godot_world::support_edit_preview {

// These normalized World actions may alter the seats of existing native
// transmission parts. Host alone decides whether to admit and commit them.
[[nodiscard]] bool applies(std::string_view action);

// Make a temporary geometry-only state for the established physical support
// policy. The input is an already validated native intent, not a player wire.
// No inventory, history, material or World owner is copied or mutated.
using Result = std::variant<world::State, const char*>;
[[nodiscard]] Result build(const world::State& before, const values::Value::Object& normalized);

}  // namespace factory::godot_world::support_edit_preview
