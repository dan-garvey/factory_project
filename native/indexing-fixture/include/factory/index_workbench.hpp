#pragma once

#include "factory/indexing.hpp"

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::indexing {
struct Challenge {
    std::string_view id, title, goal;
    FaceMask required{};
    std::array<bool, 3> allowed_axes;
};

[[nodiscard]] std::span<const Challenge> catalogue() noexcept;
// 0 = solved/list/help, 1 = retained unfinished/refused job, 2 = malformed
// command or output failure. Arguments exclude the executable name.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
// One retained fixture Job across input lines. Help/inspect do not advance it;
// correctable refusals remain in the same run. EOF/quit without release return 1.
[[nodiscard]] int play(std::string_view puzzle, std::istream&, std::ostream&, std::ostream&);
}  // namespace factory::indexing
