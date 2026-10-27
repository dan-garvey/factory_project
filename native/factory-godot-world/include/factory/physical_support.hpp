#pragma once

#include "factory/world.hpp"

#include <cstddef>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace factory::godot_world::physical_support {

// Host confirms these physical seats against terrain and nearby objects.
// The readout consumes them but never chooses or stores a separate route.
struct TransmissionSupport {
    authority::Point foot, bearing;
    std::vector<std::pair<authority::Point, authority::Point>> boxes;
    std::size_t route{};
};

using Routes = std::map<std::string, std::size_t>;
using TerrainObstacles = std::vector<std::pair<authority::Point, authority::Point>>;
using TerrainRange = std::function<std::optional<std::pair<double, double>>(
    double x, double z, double half_x, double half_z)>;
using SiteBlocked = std::function<bool(const authority::Point& low, const authority::Point& high)>;
using ActorBlocked = std::function<bool(const authority::Point& center, const authority::Point& half)>;

// These callbacks read the Host's one confirmed terrain and obstacle view.
// The layout borrows World state and route identities; it owns no simulation.
struct Site {
    const world::Profile& profile;
    const TerrainObstacles& terrain_obstacles;
    TerrainRange terrain_range;
    SiteBlocked site_blocked;
};

[[nodiscard]] constexpr bool fixed_transmission(stationary::Role role) {
    return role == stationary::Role::shaft || role == stationary::Role::gear ||
           role == stationary::Role::gearbox || role == stationary::Role::vertical_gearbox ||
           role == stationary::Role::chain_drive;
}

[[nodiscard]] std::map<std::string, TransmissionSupport> layout(const Site& site,
    const world::State& state, const Routes* preferred_routes = nullptr);
[[nodiscard]] const char* change_refusal(const Site& site, const world::State& before,
    const world::State& after, const Routes& preferred_routes, const ActorBlocked& actor_blocked);

}  // namespace factory::godot_world::physical_support
