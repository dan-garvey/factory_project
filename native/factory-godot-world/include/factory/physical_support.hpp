#pragma once

#include "factory/world.hpp"

#include <cstddef>
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

[[nodiscard]] constexpr bool fixed_transmission(stationary::Role role) {
    return role == stationary::Role::shaft || role == stationary::Role::gear ||
           role == stationary::Role::gearbox || role == stationary::Role::vertical_gearbox ||
           role == stationary::Role::chain_drive;
}

}  // namespace factory::godot_world::physical_support
