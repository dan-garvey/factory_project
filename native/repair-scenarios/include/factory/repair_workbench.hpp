#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::repair_scenarios {
// One local native World per play invocation; no shadow stock, reset or save
// path. Flat text-host walking supplies explicit fixture observations, without
// claiming a physics body or the ordinary game's Session/Store integration.
// 0 = list/help or four retrieved plates, 1 = unfinished EOF/quit, 2 = entry,
// native transaction or I/O failure. Arguments exclude the executable name.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::istream&, std::ostream&, std::ostream&);
}  // namespace factory::repair_scenarios
