#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::bevel_pair {
// An original fixed vertical-readout puzzle. Real native source gears, floor
// queries and a coaxial output shaft consume the explicit bevel proposal.
// Exit 0 is a valid trace/list, including an unfinished goal; 2 is caller refusal.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::bevel_pair
