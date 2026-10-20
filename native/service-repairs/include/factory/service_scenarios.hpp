#pragma once

#include "factory/repair_scenarios.hpp"

namespace factory::service_scenarios {
struct Goal {
    std::string_view original;
    stationary::Role role;
    std::span<const mechanics::Point> sites;
};

[[nodiscard]] std::span<const repair_scenarios::Definition> catalogue() noexcept;
[[nodiscard]] const Goal* goal(std::string_view id) noexcept;
[[nodiscard]] std::optional<repair_scenarios::Scenario> make(std::string_view id);

// Trusted optional NEW-world fixture goals, not command inputs or a progression
// authority. Derive relocation from a validated current World, without a second
// mutable completion flag. The sole World retains quantities, work, identities,
// admission, refunds and request history. Four carried products are also needed
// by the caller. These one-time service experiments do not impose recurring
// maintenance, permanent building sites, native body or file-persistence rules.
[[nodiscard]] bool relocated(const Goal&, const world::State&) noexcept;
[[nodiscard]] bool ready(const Goal&, const world::State&);
}  // namespace factory::service_scenarios
