#pragma once

#include "factory/terrain_surface.hpp"

#include <map>
#include <optional>
#include <string>

namespace factory::godot_world::complete_projection {

// A temporary read of Host's actor samples, not a second owner of actor state.
struct ActorObservation {
    authority::Point position{};
    authority::Integer epoch{};
    bool ready{};
};
using Actors = std::map<std::string, ActorObservation>;

[[nodiscard]] values::Value::Object harvest_clearances(const world::Profile& profile,
    const terrain_surface::Surface& terrain, const world::State& state,
    const authority::Point& actor, bool ready);

// Compose one complete Godot view from the same World snapshot and physical
// observations. The caller retains World, actor and support-route ownership.
[[nodiscard]] std::optional<values::Value> build(const world::Profile& profile,
    const world::Snapshot& snapshot, const terrain_surface::Surface& terrain,
    const std::map<std::string, std::size_t>& support_routes, const Actors& actors);

}  // namespace factory::godot_world::complete_projection
