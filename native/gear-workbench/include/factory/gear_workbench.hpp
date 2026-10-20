#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::gear_puzzles {
// 0 = solved/list/help, 1 = unfinished/conflicting layout, 2 = invalid command
// or output failure. Arguments exclude the executable name.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::gear_puzzles
