#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::oldham_pair {
// Original full-turn slot/body puzzle with actual native source/readout parts.
// Exit 0 is a valid trace/list, including unfinished; 2 is caller refusal.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::oldham_pair
