#pragma once

#include <iosfwd>
#include <span>
#include <string_view>

namespace factory::cam_windows {
// Actual native gears drive two geometric followers, one with the supplied key
// and width and one fixed at the existing work dwell. Exit 0 is a valid trace,
// including overlap or stopped-open geometry; 2 is refusal or stream failure.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::ostream&, std::ostream&);
}  // namespace factory::cam_windows
