#include "factory/gantries.hpp"
#include "factory/gantry_workbench.hpp"

#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace g = factory::gantries;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

// Independent literal center sequences: no cycle sampler, swept-box query or
// relative-motion implementation participates in this oracle. Every interval
// moves 0, 2 or 8 units; centers are even integers and overlap limits are +/-2.
// Collision boundaries therefore lie on quarter-intervals. Any open overlap
// interval contains an eighth-step, so this finite oracle is exhaustive here.
constexpr std::array<int, 4> fast{{-4, -4, 4, 4}};
constexpr std::array<int, 12> regular{{-4, -4, -4, -2, 0, 2, 4, 4, 4, 2, 0, -2}};
constexpr std::array<int, 18> long_rail{{-6, -6, -6, -6, -6, -4, -2, 0, 2, 4, 6, 6, 6, 4, 2, 0, -2, -4}};

std::optional<factory::mechanisms::Tooth> oracle(g::Puzzle puzzle, g::Settings settings) {
    const std::span<const int> a = puzzle == g::Puzzle::bridge ? std::span<const int>(fast) : std::span<const int>(regular);
    const std::span<const int> b = puzzle == g::Puzzle::bridge ? std::span<const int>(fast) :
                                 puzzle == g::Puzzle::crossing ? std::span<const int>(regular) : std::span<const int>(long_rail);
    const unsigned period = puzzle == g::Puzzle::bridge ? 4 : puzzle == g::Puzzle::crossing ? 12 : 36;
    for (unsigned tick = 0; tick < period; ++tick) {
        const int a0 = a[tick % a.size()], a1 = a[(tick + 1) % a.size()];
        const int b0 = b[(tick + settings.offset) % b.size()], b1 = b[(tick + settings.offset + 1) % b.size()];
        for (int fraction = 0; fraction <= 8; ++fraction) {
            const auto x = 8 * a0 + (a1 - a0) * fraction;
            const auto z = 8 * b0 + (b1 - b0) * fraction;
            if (std::abs(x) < 16 && std::abs(z) < 16 && settings.height < 2) return tick;
        }
    }
    return std::nullopt;
}

void geometry() {
    check(g::catalogue().size() == 3 && !g::find("missing"), "The immutable catalogue is explicit and rejects unknown content.");
    const auto fast_crossing = g::evaluate(g::Puzzle::bridge, {});
    check(fast_crossing.period == 4 && fast_crossing.conflict == g::Conflict{1, {1, 4}, false},
          "Two fast moving bodies collide a quarter into travel although every endpoint is clear.");
    for (std::size_t index = 0; index < fast.size(); ++index)
        check(std::abs(fast[index]) >= 2, "Endpoint screenshots miss every fast crossing overlap.");
    check(!g::evaluate(g::Puzzle::bridge, {0, 1}).clear(), "One unit of lift still leaves positive vertical overlap.");
    check(g::evaluate(g::Puzzle::bridge, {0, 2}).clear(), "Two units of lift allow exact grazing without interior overlap.");
    const auto delayed = g::evaluate(g::Puzzle::freight, {});
    check(delayed.period == 36 && delayed.conflict && delayed.conflict->interval == 15,
          "The longer rail's first conflict occurs after an apparently clear first 12-tooth cycle.");
    for (const auto puzzle : {g::Puzzle::bridge, g::Puzzle::crossing, g::Puzzle::freight}) {
        const unsigned offsets = puzzle == g::Puzzle::bridge ? 1 : puzzle == g::Puzzle::crossing ? 12 : 18;
        for (unsigned offset = 0; offset < offsets; ++offset) for (int height = 0; height <= 2; ++height) {
            const g::Settings settings{offset, height};
            const auto expected = oracle(puzzle, settings);
            const auto report = g::evaluate(puzzle, settings);
            check(report.error == g::Error::none && report.conflict.has_value() == expected.has_value(),
                  "Every allowed layout agrees with the independent exhaustive substep oracle.");
            if (expected) check(report.conflict->interval == *expected, "The first reported conflicting interval agrees with the oracle.");
            check(g::evaluate(puzzle, settings) == report && settings == g::Settings{offset, height},
                  "Repeated analysis is deterministic and retains the caller's fixed settings.");
        }
    }
    unsigned compact_solutions{};
    for (unsigned offset = 0; offset < 12; ++offset) {
        const bool expected = offset == 2 || offset == 3 || offset == 4 || offset == 8 || offset == 9 || offset == 10;
        const bool clear = g::evaluate(g::Puzzle::crossing, {offset, 0}).clear();
        check(clear == expected, "Several phase keys permit compact same-level use of the crossing.");
        compact_solutions += clear;
    }
    check(compact_solutions == 6, "The compact puzzle has multiple solutions instead of a prescribed phase number.");
    for (unsigned offset = 0; offset < 18; ++offset)
        check(g::evaluate(g::Puzzle::freight, {offset, 0}).clear() == (offset % 6 == 1),
              "Three distinct keys coordinate the unequal fixed cycles for every repetition.");
}

void invalid_settings() {
    for (const auto puzzle : {g::Puzzle::bridge, g::Puzzle::crossing, g::Puzzle::freight}) {
        for (const auto height : {factory::clearance::Coordinate{-1}, factory::clearance::Coordinate{3},
                                  std::numeric_limits<factory::clearance::Coordinate>::min(),
                                  std::numeric_limits<factory::clearance::Coordinate>::max()}) {
            const auto report = g::evaluate(puzzle, {0, height});
            check(report.error == g::Error::invalid_settings && report.period == 0 && !report.conflict && !report.clear(),
                  "Invalid height cannot publish a successful or partial geometry result.");
        }
        check(g::evaluate(puzzle, {std::numeric_limits<factory::mechanisms::Tooth>::max(), 0}).error == g::Error::invalid_settings,
              "Oversized phase keys refuse before any interval arithmetic.");
    }
    check(g::evaluate(g::Puzzle::bridge, {1, 0}).error == g::Error::invalid_settings,
          "The introductory fixed-key kit cannot be solved by an unsupported phase adjustment.");
    check(g::evaluate(g::Puzzle::crossing, {12, 0}).error == g::Error::invalid_settings &&
          g::evaluate(g::Puzzle::freight, {18, 0}).error == g::Error::invalid_settings,
          "Out-of-range phase keys are not silently wrapped to another setting.");
    check(g::evaluate(static_cast<g::Puzzle>(-1), {}).error == g::Error::invalid_puzzle &&
          g::evaluate(static_cast<g::Puzzle>(3), {}).error == g::Error::invalid_puzzle,
          "Invalid puzzle tags cannot select a default profile.");
}

struct Result { int code; std::string out, errors; };
Result run(std::string_view puzzle, const std::string& commands) {
    const std::array<std::string_view, 2> arguments{"play", puzzle};
    std::istringstream input(commands);
    std::ostringstream output, errors;
    const auto code = g::workbench(arguments, input, output, errors);
    return {code, output.str(), errors.str()};
}

void terminal() {
    const auto bridge = run("bridge", "run\nheight 1\nrun\noffset 1\nheight 2\ninspect\nrun\n");
    check(bridge.code == 0 && bridge.errors.empty() && bridge.out.find("contact=1/4") != std::string::npos,
          "A person can inspect the fast swept conflict and correct it geometrically.");
    check(bridge.out.find("Unavailable setting. Settings unchanged.") != std::string::npos &&
          bridge.out.find("B: (0,2,-4) -> (0,2,4)") != std::string::npos &&
          bridge.out.find("Clear: all 4 intervals") != std::string::npos,
          "A refused key preserves configuration, and inspection displays the actual raised rail.");
    const auto crossing = run("crossing", "run\noffset 3\nhelp\nhint\ninspect\nrun\n");
    check(crossing.code == 0 && crossing.errors.empty() && crossing.out.find("Settings offset=3 height=0") != std::string::npos &&
          crossing.out.find("Clear: all 12 intervals") != std::string::npos,
          "Read-only commands retain a compact repeating same-level solution.");
    const auto freight = run("freight", "run\noffset 1\nrun\n");
    check(freight.code == 0 && freight.errors.empty() && freight.out.find("interval=15") != std::string::npos &&
          freight.out.find("Clear: all 36 intervals") != std::string::npos,
          "The terminal reports the delayed full-period defect and accepts a corrected key.");
    const auto corrected = run("crossing", "offset 4\noffset -1\noffset 18446744073709551616\nheight -1\nheight 3\n"
        "offset 2junk\nheight 1 extra\nreset\n" + std::string(257, 'x') + "\ninspect\nrun\n");
    check(corrected.code == 0 && corrected.errors.empty() && corrected.out.find("Settings offset=4 height=0") != std::string::npos,
          "Malformed integers, unsupported settings, extra tokens and nonexistent reset cannot overwrite a retained solution.");
    check(run("bridge", "run\nquit\n").code == 1 && run("bridge", "").code == 1 && run("freight", "offset 1\n").code == 1,
          "Quit and EOF remain unfinished, including a clear configuration that was never explicitly run.");
    check(run("missing", "").code == 2, "The terminal refuses unknown puzzle identities.");
    std::istringstream input;
    std::ostringstream output, errors;
    const std::array<std::string_view, 1> list{"list"};
    check(g::workbench(list, input, output, errors) == 0 && output.str().find("freight:") != std::string::npos,
          "The executable catalogue exposes every puzzle.");
    const std::array<std::string_view, 3> extra{"play", "bridge", "height=2"};
    check(g::workbench(extra, input, output, errors) == 2, "Unexpected entry arguments refuse.");
    const std::array<std::string_view, 2> play{"play", "bridge"};
    input.setstate(std::ios::badbit);
    check(g::workbench(play, input, output, errors) == 2, "Broken input is a failure rather than successful or ordinary EOF.");
    std::istringstream good_input("quit\n");
    std::ostream broken_output(nullptr);
    check(g::workbench(play, good_input, broken_output, errors) == 2 &&
          g::workbench(list, good_input, broken_output, errors) == 2,
          "Play and catalogue both report output failure.");
}
}  // namespace

int main() {
    try {
        geometry();
        invalid_settings();
        terminal();
        std::cout << checks << " crossing-gantry checks, 0 failures.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
