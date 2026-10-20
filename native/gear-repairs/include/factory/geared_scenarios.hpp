#pragma once

#include "factory/repair_scenarios.hpp"

namespace factory::geared_scenarios {
[[nodiscard]] std::span<const repair_scenarios::Definition> catalogue() noexcept;

// Trusted new-world content using the existing Scenario schema and World. All
// material and parts are original finite startup stock. These fixtures connect
// geometric gear construction to the existing rotating-power material gate;
// signed rate does not change recipe yield or timing in that fixed profile.
// No mutable simulation, replacement authority or import/reset path is added.
[[nodiscard]] std::optional<repair_scenarios::Scenario> make(std::string_view id);
}  // namespace factory::geared_scenarios
