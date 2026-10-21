#pragma once
#include "factory/godot_world.hpp"

namespace factory::godot_world::tests {
// Explicit synthetic terrain, not a native physics or human-play observation.
inline values::Value::Object flat_site() {
    using V = values::Value;
    return {{"axis", V(V::Array{V(-128.0), V(128.0)})},
        {"heights", V(V::Array{V(-0.02), V(-0.02), V(-0.02), V(-0.02)})},
        {"obstacles", V(V::Array{})}};
}
}
