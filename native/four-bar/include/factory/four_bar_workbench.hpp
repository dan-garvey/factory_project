#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::four_bar {
int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}
