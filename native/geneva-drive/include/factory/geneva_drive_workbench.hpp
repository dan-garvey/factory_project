#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::geneva_drive {
// Original finite-slot/dwell-lock setup fixture. Valid unfinished traces exit 0;
// malformed callers or native representation/observation refusal exits 2.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::geneva_drive
