#include "factory/fractional_slots_workbench.hpp"

#include <array>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>

namespace f = factory::fractional_slots;
namespace {
std::size_t assertions{}, tandem_cases{}, original_cases{};
void require(bool condition, const char* message) {
    ++assertions;
    if (!condition) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
struct Result { int code; std::string output, errors; };
Result run(const std::string& commands, std::string_view puzzle = "tandem") {
    std::istringstream input(commands);
    std::ostringstream output, errors;
    const auto code = f::play(input, output, errors, puzzle);
    return {code, output.str(), errors.str()};
}
void contains(const Result& result, const char* text) { require(result.output.find(text) != std::string::npos, text); }
const std::string half_solution =
    "power off\ngear half\npower on\nstep 7\npower off\ndirection reverse\npower on\nstep 10\n"
    "power off\ndirection forward\npower on\nstep 6\nquit\n";
const std::string quarter_solution =
    "power off\ngear quarter\npower on\nstep 14\npower off\ndirection reverse\npower on\nstep 20\n"
    "power off\ndirection forward\npower on\nstep 12\nquit\n";
void tandem() {
    const auto half = run(half_solution);
    ++tandem_cases;
    require(half.code == 0 && half.errors.empty(), "half gearing solves the tandem challenge");
    contains(half, "Pin 7/2; tool 5/2; tool 9 1/2;");
    contains(half, "Pin -3/2; tool 1/2; tool 9 1/2;");
    contains(half, "Pin 3/2; tool 1/2; tool 9 1/2;");
    contains(half, "Matched: original pin 3/2 and both tools 1/2");
    contains(half, "Native output -1/2.");
    const auto quarter = run(quarter_solution);
    ++tandem_cases;
    require(quarter.code == 0 && quarter.errors.empty(), "quarter gearing offers a distinct exact stroke-count solution");
    contains(quarter, "Pin -3/2; tool 1/2; tool 9 1/2;");
    contains(quarter, "Native output -1/4.");
    const auto naive = run("power off\ngear half\npower on\nstep 3\nquit\n");
    ++tandem_cases;
    require(naive.code == 1 && naive.errors.empty() && naive.output.find("Matched:") == std::string::npos,
        "matching the first tool cannot falsely complete both tools");
    contains(naive, "Pin 3/2; tool 1/2; tool 9 0/1;");
    const auto blocked = run("step 5\nstep 1\nquit\n");
    ++tandem_cases;
    require(blocked.code == 1 && blocked.errors.empty(), "coarse blocked motion remains unfinished");
    contains(blocked, "Frame 11 blocks tool 7 at 0/1; all original positions retained.");
    contains(blocked, "Pin 4/1; tool 3/1; tool 9 1/1;");
    require(blocked.output.find("tool 9 2/1;") == std::string::npos, "blocked bank never publishes a speculative second-tool endpoint");
    for (const std::string gear : {"half", "quarter"}) {
        const auto reverse_steps = gear == "half" ? "15" : "30";
        const auto forward_steps = gear == "half" ? "10" : "20";
        const auto recovered = run("step 5\npower off\ngear " + gear + "\ndirection reverse\npower on\nstep " +
            reverse_steps + "\npower off\ndirection forward\npower on\nstep " + forward_steps + "\nquit\n");
        ++tandem_cases;
        require(recovered.code == 0 && recovered.errors.empty(), "overshot coarse positions recover under either fractional gear without reset");
        contains(recovered, "Frame 11 blocks tool 7 at 0/1;");
        contains(recovered, "Pin -7/2; tool -3/2; tool 9 1/2;");
        contains(recovered, "Matched: original pin 3/2 and both tools 1/2");
    }
    const auto wrong_history = run("step 5\npower off\ngear half\ndirection reverse\npower on\nstep 11\n"
        "power off\ndirection forward\npower on\nstep 6\nquit\n");
    ++tandem_cases;
    require(wrong_history.code == 1 && wrong_history.errors.empty() && wrong_history.output.find("Matched:") == std::string::npos,
        "the original pre-overshoot recovery length cannot erase a different second-tool history");
    contains(wrong_history, "Pin 3/2; tool 1/2; tool 9 1/1;");
    const auto paused = run("step 2\npower off\ngear half\ndirection reverse\nstep 32\nstatus\nquit\n");
    ++tandem_cases;
    require(paused.code == 1 && paused.errors.empty(), "paused changes retain both original tools");
    contains(paused, "Hold unpowered; all original positions retained.");
    contains(paused, "Pin 2/1; tool 1/1; tool 9 0/1; gear half; direction reverse; power off.");
    const auto lower = run("power off\ndirection reverse\npower on\nstep 32\nquit\n");
    ++tandem_cases;
    require(lower.code == 1 && lower.errors.empty(), "complete bank shares its real lower travel stop");
    contains(lower, "Pin -4/1; tool -2/1; tool 9 0/1;");
    const auto powered = run("gear half\ndirection reverse\nstep 1\nquit\n");
    ++tandem_cases;
    require(powered.code == 1 && powered.errors.empty(), "active edits do not change either drive or retained state");
    contains(powered, "Refused: stop power before changing the drive.");
    contains(powered, "Pin 1/1; tool 0/1; tool 9 0/1; gear direct; direction forward;");
    const auto malformed = run("step 0\nstep 33\nstep 2x\nstep 1 extra\ngear third\nquit extra\nstatus\nquit\n");
    ++tandem_cases;
    require(malformed.code == 1 && malformed.errors.empty(), "tandem rejects malformed commands without consumption");
    contains(malformed, "Pin 0/1; tool 0/1; tool 9 0/1;");
    const auto overflow = run(std::string(513, 'x') + "\nhelp\nstatus\nquit\n");
    ++tandem_cases;
    require(overflow.code == 1 && overflow.errors.empty(), "oversized command is drained before a following command");
    contains(overflow, "Refused: command exceeds 512 bytes.");
    contains(overflow, "Tool 9: front clearance 3, reverse clearance 4, frame blocks positions above 1.");
    const auto boundary = run("status" + std::string(506, ' ') + "\nquit\n");
    ++tandem_cases;
    require(boundary.code == 1 && boundary.output.find("Refused:") == std::string::npos, "512-byte complete command still fits");
    const auto unknown = run("step 1\n", "unknown");
    require(unknown.code == 2 && unknown.output.empty() && unknown.errors.find("Unknown fractional-slot puzzle") != std::string::npos,
        "unknown puzzle fails before consuming state or displaying another puzzle");
    const auto empty = run("");
    ++tandem_cases;
    require(empty.code == 1 && empty.errors.empty(), "initial EOF reports the actual unfinished bank");
}

void original_compatibility() {
    struct Case { const char* commands; int code; const char* witness; };
    const std::array<Case, 8> cases{{
        {"power off\ngear half\npower on\nstep 3\nquit\n", 0, "Matched: original pin 3/2 and tool 1/2"},
        {"power off\ngear quarter\npower on\nstep 6\nquit\n", 0, "Native output 1/4."},
        {"step 3\nquit\n", 1, "Frame 11 blocks tool 7 at 0/1;"},
        {"step 3\npower off\ngear half\ndirection reverse\npower on\nstep 7\npower off\ndirection forward\npower on\nstep 6\nquit\n", 0, "Matched: original pin 3/2 and tool 1/2"},
        {"power off\nstep 32\nquit\n", 1, "Hold unpowered; all original positions retained."},
        {"gear half\nquit\n", 1, "Refused: stop power before changing the drive."},
        {"step 0\nstep 33\nstep 2x\nquit\n", 1, "Pin 0/1; tool 0/1; gear direct;"},
        {"power off\ngear half\npower on\nstep 3", 0, "Pin 3/2; tool 1/2; gear half;"},
    }};
    for (const auto& value : cases) {
        ++original_cases;
        const auto result = run(value.commands, "calibration");
        require(result.code == value.code && result.errors.empty(), "original calibration remains a distinct compatible puzzle");
        contains(result, value.witness);
        require(result.output.find("tool 9") == std::string::npos, "original calibration has no phantom second live tool");
    }
    std::istringstream input("power off\ngear half\npower on\nstep 3\nquit\n");
    std::ostringstream output, errors;
    require(f::play(input, output, errors) == 0, "original three-argument API still selects calibration");
    std::istringstream broken;
    broken.setstate(std::ios::badbit);
    require(f::play(broken, output, errors, "tandem") == 2, "broken tandem input remains an operational failure");
    std::istringstream clean;
    output.setstate(std::ios::badbit);
    require(f::play(clean, output, errors, "tandem") == 2, "failed tandem output cannot report gameplay completion");
}
}  // namespace

int main() {
    tandem();
    original_compatibility();
    std::cout << "Passed " << assertions << " assertions; " << tandem_cases << " tandem consumer traces and "
              << original_cases << " original calibration compatibility traces. Native rule-model cases were not replayed.\n";
}
