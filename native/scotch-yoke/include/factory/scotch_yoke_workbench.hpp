#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::scotch_yoke {
// Original open-frame versus upright-mount puzzle. Valid unfinished traces exit
// zero; invalid argv/native representation or observation failure exits two.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::scotch_yoke
