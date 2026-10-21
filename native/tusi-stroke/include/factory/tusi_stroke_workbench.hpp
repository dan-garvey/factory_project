#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::tusi_stroke {
int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}
