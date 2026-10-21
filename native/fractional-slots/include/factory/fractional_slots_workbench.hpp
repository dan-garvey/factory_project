#pragma once

#include <iosfwd>
#include <string_view>

namespace factory::fractional_slots {
// Select a finite original puzzle; default preserves the first calibration.
[[nodiscard]] int play(std::istream&, std::ostream&, std::ostream&, std::string_view puzzle = "calibration");
}  // namespace factory::fractional_slots
