#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::planetary {
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::planetary
