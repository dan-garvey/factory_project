#pragma once

#include "factory/ore_columns.hpp"
#include "factory/terrain_surface.hpp"

namespace factory::godot_world::arrival_excavation {
// Bind finite opening ore to the trusted emitted natural terrain once, before
// the World starts. Construction and presentation cannot refill this seed.
[[nodiscard]] std::optional<world::ore_columns::Seed> seed(
    const terrain_surface::Surface&, materials::Quantity total);
}
