#pragma once

#include "factory/mechanics.hpp"

#include <array>
#include <optional>
#include <span>
#include <string_view>

namespace factory::gear_puzzles {
using Placements = std::array<std::optional<mechanics::Point>, 2>;

struct Slot {
    mechanics::Kind kind;
    mechanics::Integer teeth{}, half_span{};
};

struct Challenge {
    std::string_view id, title, goal;
    mechanics::Rate required;
    std::span<const mechanics::Part> fixed;
    std::array<std::optional<Slot>, 2> kit;
    Placements initial;
};

enum class Error { none, unknown_challenge, unavailable_part, outside_site, invalid_geometry };

struct Report {
    Error error{Error::none};
    mechanics::Result derivation{};
    mechanics::Motion actual{};
    mechanics::Rate required{};
    [[nodiscard]] bool solved() const noexcept {
        return error == Error::none && actual.state == mechanics::MotionState::rotating && actual.rate == required;
    }
};

// Original, revisable construction fixtures. Positions use the existing exact
// pitch units (gear radius = teeth). All shafts/gear axes are z in this workbench.
// Player choices move only their declared kit parts inside the inclusive site;
// there is no source/rate/edge input, live World, actor or quantity authority.
inline constexpr mechanics::Point site_minimum{-20, -60, -2};
inline constexpr mechanics::Point site_maximum{120, 60, 4};
[[nodiscard]] std::span<const Challenge> catalogue();
[[nodiscard]] const Challenge* find(std::string_view);
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] Report inspect(std::string_view, const Placements&);
}  // namespace factory::gear_puzzles
