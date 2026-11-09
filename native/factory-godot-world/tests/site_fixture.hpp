#pragma once
#include "factory/godot_world.hpp"
#include "factory/site_geometry_contract.hpp"

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
    constexpr I grid_scale = static_cast<I>(1.65 / site_geometry::pitch);
    static_assert(grid_scale * site_geometry::pitch == 1.65);
    V::Array heights;
    for (int row = 0; row < 4; ++row) {
        heights.emplace_back(-1.65); heights.emplace_back(-1.65);
        heights.emplace_back(-0.02); heights.emplace_back(-0.02);
    }
    const auto water = [grid_scale](I x, I z) {
        return V(V::Array{V(x * grid_scale), V(z * grid_scale),
            V(I{-20} * grid_scale), V(I{-400} * grid_scale),
            V(I{200} * grid_scale), V(I{-200} * grid_scale)});
    };
    return {{"axis", V(V::Array{V(-128.0), V(-1.1), V(-1.0), V(128.0)})},
            {"heights", V(heights)}, {"obstacles", V(V::Array{})},
            {"water", V(V::Array{water(-12, 0), water(-12, 4),
                water(-8, 0), water(-8, 4), water(-4, 0), water(-4, 4)})}};
}

// Setup acquires an actual reachable column each time; no legacy source alias
// enters the wire and no actor position or native stock is fabricated.
inline std::string reachable_ore(Host& host, const std::string& actor, const std::string& operation = {}) {
    using V = values::Value;
    const auto view = std::get<V::Object>(host.projection().storage());
    const auto& sources = std::get<V::Object>(view.at("hand_sources").storage());
    const auto observation = std::get<V::Object>(host.actor_projection(actor).storage());
    const auto& clear = std::get<V::Object>(observation.at("harvest_clear").storage());
    std::string selected;
    V::Integer highest = -1;
    for (const auto& [id, source] : sources) {
        if (!id.starts_with("ore-column:") || !clear.contains(id) ||
                !std::get<bool>(clear.at(id).storage())) continue;
        const auto& fields = std::get<V::Object>(source.storage());
        const auto remaining = std::get<V::Integer>(fields.at("remaining").storage());
        if (remaining > highest) { selected = id; highest = remaining; }
    }
    if (selected.empty()) throw std::runtime_error(operation + ": no actual ore column is reachable for fixture setup.");
    return selected;
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
