#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::differential {
int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::differential
