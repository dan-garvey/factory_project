#pragma once

#include "factory/physical_support.hpp"
#include "factory/terrain_surface.hpp"

#include <map>
#include <optional>
#include <string>

namespace factory::godot_world::physical_site {

// Every physical admission reads the same confirmed World profile and emitted
// terrain surface. It never owns parts, material, actor positions or history.
struct Site {
    const world::Profile& profile;
    const terrain_surface::Surface& terrain;
};

[[nodiscard]] physical_support::Site support_site(const Site& site);
[[nodiscard]] const char* wheel_refusal(const Site& site, const mechanics::Point& center,
    mechanics::Axis axis, mechanics::Integer tiles);
[[nodiscard]] const char* machine_refusal(const Site& site, const world::State& state,
    const mechanics::Point& center, bool collector);
[[nodiscard]] const char* transmission_refusal(const Site& site, const world::State& state,
    const mechanics::Point& center, mechanics::Axis axis, bool gear);
[[nodiscard]] const char* collector_refusal(const Site& site, const mechanics::Point& center);
[[nodiscard]] const char* component_refusal(const Site& site, const world::State& state,
    std::optional<materials::Component> kind, const mechanics::Point& center);
[[nodiscard]] const char* component_space_refusal(const Site& site, const world::State& state,
    std::optional<materials::Component> kind, const mechanics::Point& center,
    const std::string* current_id = nullptr);
[[nodiscard]] const char* supplied_space_refusal(const Site& site, const world::State& state);

}  // namespace factory::godot_world::physical_site
