#pragma once

#include "factory/world.hpp"

#include <optional>
#include <span>
#include <string_view>

namespace factory::repair_scenarios {
struct Definition {
    std::string_view id, title, objective, hint;
};

struct Scenario {
    const Definition* definition{};  // Immutable catalogue storage.
    world::Profile profile;
    world::State seed;
};

[[nodiscard]] std::span<const Definition> catalogue() noexcept;

// Trusted NEW-world content only. The caller supplies context and creates one
// World using this data. Never call this to recover an invalid import or reset
// an existing world. There is no mutable simulation or command path here.
// Three declared non-consuming water fixtures power independent small branches.
// All materials and construction parts are finite original startup stock.
[[nodiscard]] std::optional<Scenario> make(std::string_view id);
}  // namespace factory::repair_scenarios
