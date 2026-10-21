#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::cardan_pair {
// Native source -> ideal fixed joint readings -> real shaft/gear readout.
// Exit 0 is a valid trace/list, including unfinished; 2 is caller refusal.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::cardan_pair
