#include "factory/index_workbench.hpp"

#include <array>
#include <iostream>
#include <sstream>

namespace i = factory::indexing;
namespace {
int checks{};
int failures{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}

struct Run {
    int code{};
    std::string output, errors;
};

Run play(std::string_view puzzle, const std::string& commands) {
    std::istringstream input(commands);
    std::ostringstream output, errors;
    const auto code = i::play(puzzle, input, output, errors);
    return {code, output.str(), errors.str()};
}

std::string last_state(const std::string& output) {
    const auto start = output.rfind("Workpiece ");
    if (start == std::string::npos) return {};
    return output.substr(start, output.find('\n', start) - start);
}

void persistent_interaction() {
    const auto run = play("opposites", "inspect\nstamp\nx-\nstamp\nstamp\ninspect\nx-\nx-\nstamp\nx-\nrelease\n");
    check(run.code == 0 && run.output.find("not part of this job") != std::string::npos &&
          run.output.find("already marked") != std::string::npos && run.errors.empty(),
          "A person can correct wrong and repeated strokes across input lines and complete the original fixture.");
    check(last_state(run.output) == "Workpiece 7, upward face Y+, marked Z+ Z-; local axes point to X+ Y+ Z+.",
          "The same original work identity, both marks and home pose survive the complete terminal conversation.");
    check(run.output.find("Solved: original workpiece 7 released complete at home.") != std::string::npos,
          "Only the explicit successful release completes the interactive puzzle.");
    const auto inspection = play("opposites", "x-\nstamp\nhelp\ninspect\nreset\nnew_work\ninspect\nquit\n");
    check(inspection.code == 1 && inspection.errors.find("Unknown action") != std::string::npos,
          "Reset and replacement commands remain unavailable without terminating the retained fixture.");
    check(last_state(inspection.output) == "Workpiece 7, upward face Z+, marked Z+; local axes point to X+ Z- Y+.",
          "Help, inspection and syntax refusals preserve the exact previous mark and indexed pose.");
    check(inspection.output.find("Solved:") == std::string::npos,
          "Quitting a partly marked piece cannot create completion credit.");
    const auto corrected_syntax = play("opposites", "x2\nx- stamp x- x- stamp x- release\n");
    check(corrected_syntax.code == 0 && corrected_syntax.errors.find("Unknown action") != std::string::npos,
          "A malformed token may be corrected within the same original run.");
}

void all_puzzles() {
    const auto corner = play("corner", "release\ny+\nstamp\nz+\nstamp\nx-\nstamp\nx+\nz-\nrelease");
    check(corner.code == 0 && corner.output.find("Complete every required face") != std::string::npos &&
          corner.output.find("axis is locked") != std::string::npos,
          "Premature release and a locked-axis attempt can be corrected before a successful final line without a newline.");
    check(last_state(corner.output) == "Workpiece 7, upward face Y+, marked X+ Y+ Z+; local axes point to X+ Y+ Z+.",
          "The corner puzzle completes its exact original face set and holder home.");
    const auto all = play("all_faces", "stamp\nx- stamp\nx- stamp\nx- stamp\nx- z+ stamp\nz- z- stamp\nz+ release\n");
    check(all.code == 0 && all.errors.empty(), "The full six-face fixture works with both individual and grouped terminal commands.");
    check(last_state(all.output) == "Workpiece 7, upward face Y+, marked X+ X- Y+ Y- Z+ Z-; local axes point to X+ Y+ Z+.",
          "No original work face is lost, duplicated or renamed during the complete six-face run.");
}

void incomplete_and_io() {
    const auto dry = play("opposites", "\n   \ninspect\n");
    check(dry.code == 1 && dry.output.find("Fixture ended before a completed release") != std::string::npos,
          "Blank input and ordinary end-of-file leave the fixture unsolved.");
    const auto ready = play("opposites", "x- stamp x- x- stamp x-\n");
    check(ready.code == 1 && ready.output.find("Solved:") == std::string::npos &&
          last_state(ready.output) == "Workpiece 7, upward face Y+, marked Z+ Z-; local axes point to X+ Y+ Z+.",
          "A ready workpiece does not silently release at end-of-file.");
    const auto quit_ready = play("opposites", "x- stamp x- x- stamp x- quit\n");
    check(quit_ready.code == 1 && quit_ready.output.find("Solved:") == std::string::npos,
          "Quitting also preserves the requirement for an explicit successful release.");
    std::istringstream input("stamp\n");
    std::ostringstream output, errors;
    check(i::play("missing", input, output, errors) == 2 && input.tellg() == 0,
          "An unknown puzzle cannot consume commands into a silently substituted default fixture.");
    input.setstate(std::ios::badbit);
    check(i::play("opposites", input, output, errors) == 2,
          "A read error is distinct from a normal unfinished end-of-file.");
    std::istringstream failed("stamp\n");
    failed.setstate(std::ios::failbit);
    check(i::play("opposites", failed, output, errors) == 2,
          "A failed stream without end-of-file cannot be mislabeled as an ordinary quit.");
    std::istringstream available("stamp\n");
    std::ostringstream broken;
    broken.setstate(std::ios::badbit);
    check(i::play("opposites", available, broken, errors) == 2 && available.tellg() == 0,
          "Failed output prevents waiting for or consuming another terminal command.");
}

void legacy_batch() {
    std::ostringstream output, errors;
    const std::array<std::string_view, 8> opposite{{"opposites", "x-", "stamp", "x-", "x-", "stamp", "x-", "release"}};
    check(i::workbench(opposite, output, errors) == 0 && output.str().find("Solved:") != std::string::npos,
          "The original argument-sequence mode preserves successful opposite-face behavior.");
    output.str(""); errors.str("");
    const std::array<std::string_view, 9> corner{{"corner", "stamp", "z+", "stamp", "x-", "stamp", "x+", "z-", "release"}};
    check(i::workbench(corner, output, errors) == 0,
          "The original corner argument sequence remains compatible with the shared action handler.");
    output.str(""); errors.str("");
    const std::array<std::string_view, 16> all{{"all_faces", "stamp", "x-", "stamp", "x-", "stamp", "x-", "stamp", "x-",
        "z+", "stamp", "z-", "z-", "stamp", "z+", "release"}};
    check(i::workbench(all, output, errors) == 0,
          "The original six-face argument sequence remains compatible.");
    const std::array<std::string_view, 9> trailing{{"opposites", "x-", "stamp", "x-", "x-", "stamp", "x-", "release", "stamp"}};
    check(i::workbench(trailing, output, errors) == 2,
          "Batch mode still refuses declared actions after release.");
    const std::array<std::string_view, 2> invalid{{"opposites", "reset"}};
    check(i::workbench(invalid, output, errors) == 2,
          "Batch syntax errors remain fatal to that submitted sequence.");
}
}  // namespace

int main() {
    persistent_interaction();
    all_puzzles();
    incomplete_and_io();
    legacy_batch();
    std::cout << checks << " interactive indexing checks, " << failures << " failures.\n";
    return failures == 0 ? 0 : 1;
}
