#pragma once

#include "factory/repair_scenarios.hpp"

#include <string>

namespace factory::spindle_scenarios {
enum class Mode { invalid, drive_off, incomplete_line, wrong_rate, calibrated };
inline constexpr mechanics::Rate required_rate{-2, 1};
struct Progress {
    Mode mode{Mode::invalid};
    mechanics::Rate rate{};
    materials::Quantity products{};
    bool known_actor{};
    [[nodiscard]] bool ready() const noexcept { return mode == Mode::calibrated; }
    [[nodiscard]] bool complete() const noexcept { return known_actor && products >= 4 && ready(); }
};

[[nodiscard]] const repair_scenarios::Definition& definition() noexcept;
[[nodiscard]] std::span<const repair_scenarios::Definition> catalogue() noexcept;
// Authored startup only, before a World exists; never a reset or import fallback.
[[nodiscard]] std::optional<repair_scenarios::Scenario> make(std::string_view);
[[nodiscard]] const char* mode_name(Mode) noexcept;
// Read the current validated World. This experimental spindle specification
// changes no material timing/yield and stores no persistent completion flag.
[[nodiscard]] Progress inspect(const world::State&, const std::string& actor = "P");
}  // namespace factory::spindle_scenarios
