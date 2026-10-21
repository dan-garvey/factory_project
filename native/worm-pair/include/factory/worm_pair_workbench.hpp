#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::worm_pair {
// Original native source -> finite worm pair -> real readout-shaft puzzle.
// Exit 0 is a valid trace/list, including unfinished; 2 is caller refusal.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::worm_pair
