#pragma once

#include "factory/world.hpp"

#include <map>
#include <string>

namespace factory::godot_world::arrival_geometry {

struct Bounds {
    authority::Point center, half;
};

struct Solid {
    std::string entity;
    authority::Integer generation;
    Bounds bounds;
};

// These coarse occupied boxes follow the supplied, deployed meshes. Their
// anchors use the same quarter-pitch floor coordinates as ordinary foundations;
// the spindle offset must not be applied to floor-authored pod or bench parts.
// Geometry is derived from World, never saved or independently mutable.
inline std::map<std::string, Solid> supplied(const world::State& state, double height_step) {
    std::map<std::string, Solid> result;
    const auto append = [&](const std::string& entity, authority::Integer generation,
            const mechanics::Point& grid, const char* name,
            authority::Point offset, authority::Point half) {
        for (std::size_t axis = 0; axis < 3; ++axis) offset[axis] += grid[axis] * height_step;
        result.emplace(entity + '/' + name, Solid{entity, generation, {offset, half}});
    };
    if (state.landing_pod) {
        const auto& pod = *state.landing_pod;
        const auto add = [&](const char* name, authority::Point at, authority::Point half) {
            append(pod.id, pod.generation, pod.center, name, at, half);
        };
        add("lower-hull", {0, 0.275, 0.02}, {0.74, 0.155, 0.88});
        add("rear-bulkhead", {0, 0.66, 0.79}, {0.56, 0.29, 0.06});
        add("folded-cover-floor", {0, 0.09, 1.65}, {0.62, 0.07, 0.85});
        add("folded-cover-west", {-0.615, 0.69, 1.65}, {0.065, 0.37, 0.85});
        add("folded-cover-east", {0.615, 0.69, 1.65}, {0.065, 0.37, 0.85});
        add("folded-hatch", {0, 0.61, 2.52}, {0.56, 0.45, 0.04});
        add("foot-west-front", {-0.65, 0.07, -0.72}, {0.14, 0.07, 0.145});
        add("foot-west-rear", {-0.65, 0.07, 0.72}, {0.14, 0.07, 0.145});
        add("foot-east-front", {0.65, 0.07, -0.72}, {0.14, 0.07, 0.145});
        add("foot-east-rear", {0.65, 0.07, 0.72}, {0.14, 0.07, 0.145});
    }
    if (state.fabrication_hub && !state.fabrication_hub->holder) {
        const auto& hub = *state.fabrication_hub;
        const auto add = [&](const char* name, authority::Point at, authority::Point half) {
            append(hub.id, hub.generation, hub.center, name, at, half);
        };
        add("leg-west-front", {-0.40, 0.34, -0.27}, {0.0425, 0.34, 0.0425});
        add("leg-west-rear", {-0.40, 0.34, 0.27}, {0.0425, 0.34, 0.0425});
        add("leg-east-front", {0.40, 0.34, -0.27}, {0.0425, 0.34, 0.0425});
        add("leg-east-rear", {0.40, 0.34, 0.27}, {0.0425, 0.34, 0.0425});
        add("worktop", {0, 0.74, 0}, {0.58, 0.0575, 0.35});
        add("steel-insert", {-0.16, 0.805, -0.06}, {0.26, 0.01, 0.19});
        add("tool-post", {0.35, 1.01, -0.19}, {0.07, 0.22, 0.07});
        add("tool-rail", {0.20, 1.23, -0.19}, {0.15, 0.0325, 0.0325});
        add("clamp-west", {-0.35, 0.88, -0.06}, {0.0375, 0.065, 0.135});
        add("clamp-east", {0.03, 0.88, -0.06}, {0.0375, 0.065, 0.135});
    }
    return result;
}

}  // namespace factory::godot_world::arrival_geometry
