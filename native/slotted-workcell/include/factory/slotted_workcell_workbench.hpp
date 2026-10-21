#pragma once

#include <iosfwd>

namespace factory::slotted_workcell {
[[nodiscard]] int play(std::istream&, std::ostream&, std::ostream&);
}  // namespace factory::slotted_workcell
