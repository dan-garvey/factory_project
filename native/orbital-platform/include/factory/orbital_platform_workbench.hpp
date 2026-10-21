#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::orbital_platform {
// Original declared-branch tray/readout setup. Valid unfinished traces exit 0;
// malformed argv, unrepresentable geometry or an observation failure exits 2.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::orbital_platform
