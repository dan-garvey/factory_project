#pragma once
#include "factory/godot_world.hpp"

#include <stdexcept>
#include <string>

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
    return {{"axis", V(V::Array{V(-128.0), V(-1.1), V(-1.0), V(128.0)})},
            {"heights", V(heights)}, {"obstacles", V(V::Array{})},
            {"water", V(V::Array{V(V::Array{V(I{-12}), V(I{0}), V(I{-20}), V(I{-400}), V(I{200}), V(I{-200})}),
                                 V(V::Array{V(I{-12}), V(I{4}), V(I{-20}), V(I{-400}), V(I{200}), V(I{-200})}),
                                 V(V::Array{V(I{-8}), V(I{0}), V(I{-20}), V(I{-400}), V(I{200}), V(I{-200})}),
                                 V(V::Array{V(I{-8}), V(I{4}), V(I{-20}), V(I{-400}), V(I{200}), V(I{-200})}),
                                 V(V::Array{V(I{-4}), V(I{0}), V(I{-20}), V(I{-400}), V(I{200}), V(I{-200})}),
                                 V(V::Array{V(I{-4}), V(I{4}), V(I{-20}), V(I{-400}), V(I{200}), V(I{-200})})})}};
}

// Setup consumers complete real native time before spending harvested stock.
// Timing and interruption assertions live in harvest_host_test.cpp.
inline values::Value complete_manual_cut(Host& host, const std::string& actor,
        const values::Value::Object& wire) {
    using V = values::Value;
    const auto reply = host.command(actor, wire);
    const auto* fields = std::get_if<V::Object>(&reply.storage());
    if (!fields || !std::get<bool>(fields->at("accepted").storage())) return reply;
    for (values::Value::Integer tick = 0; tick < world::manual_cut_ticks; ++tick) {
        const auto advanced = host.advance();
        const auto* view = std::get_if<V::Object>(&advanced.storage());
        if (!view || !view->contains("revision"))
            throw std::runtime_error("Trusted Host cut could not advance.");
    }
    const auto view = host.projection();
    const auto& cuts = std::get<V::Object>(std::get<V::Object>(view.storage()).at("manual_cuts").storage());
    if (cuts.contains(actor)) throw std::runtime_error("Trusted Host cut did not settle.");
    return reply;
}
}
