#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::cam_puzzles {
// Arguments exclude the executable name. Returns 0 for solved/list/help,
// 1 for a conflicting arrangement, and 2 for invalid input or output failure.
[[nodiscard]] int workbench(std::span<const std::string_view> arguments,
                            std::ostream& output, std::ostream& errors);
}  // namespace factory::cam_puzzles
