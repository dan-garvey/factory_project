#include "factory/coupling_puzzles.hpp"

namespace factory::coupling_puzzles {
namespace g = mechanics;
namespace {
void hub(Puzzle& puzzle, const char* id, g::Point at) {
    puzzle.parts.push_back({id, g::Kind::hub, at, g::Axis::z});
}
void shaft(Puzzle& puzzle, const char* id, g::Point at, g::Integer span = 1) {
    puzzle.parts.push_back({id, g::Kind::shaft, at, g::Axis::z, 0, span});
}
void gear(Puzzle& puzzle, const char* id, g::Point at) {
    puzzle.parts.push_back({id, g::Kind::gear, at, g::Axis::z, 2});
}
void branch(Puzzle& puzzle) {
    hub(puzzle, "wheel", {0, 0, 0});
    shaft(puzzle, "wheel-shaft", {0, 0, 0});
    gear(puzzle, "wheel-gear", {0, 0, 0});
    hub(puzzle, "useful", {-4, 0, 0});
    shaft(puzzle, "useful-shaft", {-4, 0, 0});
    gear(puzzle, "useful-gear", {-4, 0, 0});
    shaft(puzzle, "branch-shaft", {4, 0, 0});
    gear(puzzle, "branch-gear", {4, 0, 0});
    hub(puzzle, "held", {4, 0, 4});
    shaft(puzzle, "held-shaft", {4, 0, 4});
    shaft(puzzle, "lower", {4, 0, 2});
    puzzle.sources = {{"wheel", {1, 1}}, {"held", {0, 1}}};
    puzzle.slots = {{"lower", {4, 0, 2}, {4, 0, 1}}};
    puzzle.goals = {{"useful", {g::MotionState::rotating, {-1, 1}}},
                   {"held", {g::MotionState::stopped, {0, 1}}}};
}
}  // namespace

std::optional<Puzzle> make(std::string_view id) {
    Puzzle puzzle;
    puzzle.id = id;
    if (id == "branch" || id == "bypass") {
        branch(puzzle);
        if (id == "branch") {
            puzzle.title = "Keep the useful branch turning";
            puzzle.instruction = "Isolate the held branch while useful turns at -1/1.";
        } else {
            puzzle.title = "Find the second route around the coupling";
            puzzle.instruction = "The held branch has two drive paths. Keep useful turning at -1/1.";
            shaft(puzzle, "riser", {0, 0, 4}, 4);
            gear(puzzle, "upper-wheel-gear", {0, 0, 8});
            gear(puzzle, "upper-branch-gear", {4, 0, 8});
            shaft(puzzle, "upper-branch-shaft", {4, 0, 8});
            shaft(puzzle, "upper", {4, 0, 6});
            puzzle.slots.push_back({"upper", {4, 0, 6}, {4, 0, 7}});
        }
    } else if (id == "selector") {
        puzzle.title = "Choose a forward line-shaft source";
        puzzle.instruction = "Run output at +1/1 while reverse remains free to turn at -1/1.";
        hub(puzzle, "forward", {0, 0, 0});
        shaft(puzzle, "forward-shaft", {0, 0, 0});
        hub(puzzle, "output", {0, 0, 4});
        shaft(puzzle, "output-shaft", {0, 0, 4});
        hub(puzzle, "reverse", {0, 0, 8});
        shaft(puzzle, "reverse-shaft", {0, 0, 8});
        shaft(puzzle, "front", {0, 0, 2});
        shaft(puzzle, "back", {0, 0, 6});
        puzzle.sources = {{"forward", {1, 1}}, {"reverse", {-1, 1}}};
        puzzle.slots = {{"front", {0, 0, 2}, {0, 0, 1}},
                        {"back", {0, 0, 6}, {0, 0, 7}}};
        puzzle.goals = {{"output", {g::MotionState::rotating, {1, 1}}},
                       {"reverse", {g::MotionState::rotating, {-1, 1}}}};
    } else return std::nullopt;
    return puzzle;
}

bool solved(const Puzzle& puzzle, const g::Result& result) noexcept {
    if (!result.accepted() || puzzle.goals.empty()) return false;
    for (const auto& goal : puzzle.goals) {
        const auto found = result.motion.find(goal.hub);
        if (found == result.motion.end() || found->second != goal.motion) return false;
    }
    return true;
}
}  // namespace factory::coupling_puzzles
