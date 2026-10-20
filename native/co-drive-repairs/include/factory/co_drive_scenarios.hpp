#pragma once

#include "factory/repair_scenarios.hpp"

#include <cstddef>
#include <string>

namespace factory::co_drive_scenarios {
enum class Mode { invalid, drive_off, stalled, incomplete_line, choose_source, isolated, co_driven };
struct Progress {
    Mode mode{Mode::invalid};
    std::size_t sources{};
    materials::Quantity products{};
    bool known_actor{};
    [[nodiscard]] bool ready() const noexcept { return mode == Mode::isolated || mode == Mode::co_driven; }
    [[nodiscard]] bool complete() const noexcept { return known_actor && products >= 4 && ready(); }
};

[[nodiscard]] const repair_scenarios::Definition& definition() noexcept;
[[nodiscard]] std::span<const repair_scenarios::Definition> catalogue() noexcept;
// Trusted new-World content only. Never initialize over an existing run or
// recover a bad import. This module owns no live World, stock or progress store.
[[nodiscard]] std::optional<repair_scenarios::Scenario> make(std::string_view);
[[nodiscard]] const char* mode_name(Mode) noexcept;
// Read the caller's current validated World cut and individual cargo. Source
// count and coherent component membership are derived, never client progress.
// Signed rate affects the mechanical diagnosis, not material speed or yield.
[[nodiscard]] Progress inspect(const world::State&, const std::string& actor = "P");
}  // namespace factory::co_drive_scenarios
