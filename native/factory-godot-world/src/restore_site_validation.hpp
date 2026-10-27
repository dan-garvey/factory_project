#pragma once

#include "factory/physical_site.hpp"

#include <cstddef>
#include <map>
#include <string>

namespace factory::godot_world::restore_site_validation {

// Validate physical geometry after World and historical-wire decoding. A null
// result accepts the site; otherwise the result is Host's existing refusal.
// The optional route map is present only for schema-4 checkpoints.
[[nodiscard]] const char* geometry(const world::Profile& profile,
    const terrain_surface::Surface& terrain, const world::State& state,
    const std::map<std::string, physical_support::TransmissionSupport>& supports,
    const std::map<std::string, std::size_t>* saved_routes);

}  // namespace factory::godot_world::restore_site_validation
