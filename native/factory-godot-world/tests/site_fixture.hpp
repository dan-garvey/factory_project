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
// An explicit invented stream for Host consumers that place waterwheels.
inline values::Value::Object channel_site() {
    using V = values::Value;
    using I = V::Integer;
    V::Array heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    return {{"axis", V(V::Array{V(-128.0), V(-0.8), V(-0.725), V(128.0)})},
            {"heights", V(heights)}, {"obstacles", V(V::Array{})},
            {"water", V(V::Array{V(V::Array{V(I{-4}), V(I{0}), V(I{-20}), V(I{-400}), V(I{200}), V(I{-200})}),
                                 V(V::Array{V(I{-4}), V(I{4}), V(I{-20}), V(I{-400}), V(I{200}), V(I{-200})})})}};
}
}
