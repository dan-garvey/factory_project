#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::slotted_rocker {
int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}
