#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::gantries {
// Standalone configuration puzzles. 0 = help/list or clear full repeating
// cycle, 1 = unfinished EOF/quit, 2 = entry or I/O failure. No game state changes.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::istream&, std::ostream&, std::ostream&);
}  // namespace factory::gantries
