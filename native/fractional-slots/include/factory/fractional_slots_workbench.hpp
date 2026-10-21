#pragma once

#include <iosfwd>

namespace factory::fractional_slots {
[[nodiscard]] int play(std::istream&, std::ostream&, std::ostream&);
}  // namespace factory::fractional_slots
