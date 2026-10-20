#pragma once

#include "factory/gravity.hpp"

#include <iosfwd>
#include <string_view>

namespace factory::gravity {
struct Challenge {
    std::string_view id, title, goal;
    Site site;
    std::span<const Route> initial;
};

[[nodiscard]] std::span<const Challenge> catalogue() noexcept;
[[nodiscard]] const Challenge* find(std::string_view) noexcept;
// Returns 0 for solved/list/help, 1 for a refused layout and 2 for invalid syntax
// or output failure. Arguments exclude the executable name.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::gravity
