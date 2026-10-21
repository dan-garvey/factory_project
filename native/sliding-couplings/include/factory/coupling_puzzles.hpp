#pragma once

#include "factory/sliding_couplings.hpp"

#include <iosfwd>
#include <optional>
#include <string_view>

namespace factory::coupling_puzzles {
struct Slot {
    std::string shaft;
    mechanics::Point engaged;
    mechanics::Point withdrawn;
};

struct Goal {
    std::string hub;
    mechanics::Motion motion;
};

struct Puzzle {
    std::string id;
    std::string title;
    std::string instruction;
    std::vector<mechanics::Part> parts;
    std::vector<mechanics::Drive> sources;
    std::vector<Slot> slots;
    std::vector<Goal> goals;
};

[[nodiscard]] std::optional<Puzzle> make(std::string_view);
[[nodiscard]] bool solved(const Puzzle&, const mechanics::Result&) noexcept;

// Standalone layout caller. No game World, material owner or construction
// authority is created. Exit 0 means solved/list/help, 1 means unfinished at EOF
// or quit, and 2 means invalid startup or stream failure. Refused commands retain
// the same layout and can be corrected in the same input stream.
[[nodiscard]] int workbench(std::span<const std::string_view>, std::istream&,
                            std::ostream&, std::ostream&);
}  // namespace factory::coupling_puzzles
