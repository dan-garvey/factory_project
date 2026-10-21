#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::slider_crank {
// Original positive/mirrored finite-guide fixture. Valid unfinished traces exit
// 0; malformed callers/native representation or observation failures exit 2.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::slider_crank
