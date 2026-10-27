#pragma once

#include "factory/world.hpp"

#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace factory::godot_world {

// Authored starting content for one native World. Host owns the resulting World
// and physical actors; this builder has no live state or engine dependency.
struct ArrivalConfiguration {
    world::Profile profile;
    world::State seed;
    std::vector<std::pair<std::string, authority::Point>> actor_starts;
};

[[nodiscard]] std::optional<ArrivalConfiguration> make_arrival_configuration(
    bool arrival, bool advanced_fixture, const std::vector<std::string>& actors);

}  // namespace factory::godot_world
