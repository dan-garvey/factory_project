#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::crank_clamp {
// Original fixed-centre/loading-aperture geometry with actual native gears and
// shaft power. Valid unfinished traces exit 0; caller/refused observation exits 2.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::crank_clamp
