#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::geared_carriage {
// Standalone barrier-clearance puzzle. Phase and accumulated accepted crossings
// belong only to this caller; no game World, goods or native body is created.
// Exit 0 means a completed trace/list, 1 means unfinished, 2 means invalid startup
// or stream failure. Arguments exclude the executable name.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::istream&,
                            std::ostream&, std::ostream&);
}  // namespace factory::geared_carriage
