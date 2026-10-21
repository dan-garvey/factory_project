#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::pulley_loop {
// Original service-column routing fixture. Valid unfinished traces exit 0;
// malformed callers or complete native observation/grid refusals exit 2.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::pulley_loop
