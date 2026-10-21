#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::screw_drive {
// Standalone point-tip alignment fixture, not force or World-part custody.
// Exit 0 is aligned/list/help, 1 is unfinished, 2 is invalid startup/stream.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::istream&,
                            std::ostream&, std::ostream&);
}  // namespace factory::screw_drive
