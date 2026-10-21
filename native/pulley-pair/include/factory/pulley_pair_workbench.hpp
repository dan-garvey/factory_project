#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::pulley_pair {
// Original ideal-pitch remote-readout puzzle. Valid unfinished traces exit 0;
// malformed callers or native observation/grid failures exit 2.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::pulley_pair
