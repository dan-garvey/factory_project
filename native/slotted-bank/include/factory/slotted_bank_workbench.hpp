#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::slotted_bank {
int workbench(std::span<const std::string_view>, std::istream&, std::ostream&, std::ostream&);
}  // namespace factory::slotted_bank
