#include "factory/cam_puzzles.hpp"
#include "factory/cam_workbench.hpp"

#include <initializer_list>
#include <iostream>
#include <limits>
#include <sstream>

namespace p = factory::cam_puzzles;
namespace m = factory::mechanisms;
namespace {
int checks{};
int failures{};

void check(bool condition, std::string_view message) {
    ++checks;
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << message << '\n';
    }
}

void puzzle_cases() {
    check(p::catalogue().size() == 3 && !p::find("missing"), "The workbench exposes exactly three named fixtures.");
    const auto dock = p::inspect("dock", p::find("dock")->initial);
    check(!dock.solved() && dock.error == p::Error::none && dock.fault == p::Fault::dock_overlap &&
          dock.tooth == 1 && dock.lane == 1, "The impatient feeder first overlaps the discharge at tooth one.");
    const auto ram = p::inspect("ram", p::find("ram")->initial);
    check(!ram.solved() && ram.error == p::Error::none && ram.fault == p::Fault::ram_offsite &&
          ram.tooth == 12 && ram.lane == 1, "The long ram stroke first obstructs the returning carriage at tooth twelve.");
    const auto paired = p::inspect("paired", p::find("paired")->initial);
    check(!paired.solved() && paired.error == p::Error::none && paired.fault == p::Fault::drive_overload &&
          paired.tooth == 11 && paired.lane == 0, "The second workstation first overloads the common drive at tooth eleven.");
    check(p::inspect("dock", {2, 11, 0}).solved(), "Unloading then feeding solves the dock fixture.");
    check(p::inspect("ram", {1, 8, 0}).solved(), "The complete ram lobe fits exactly into four work teeth.");
    check(p::inspect("paired", {2, 10, 4}).solved(), "A four-tooth lane offset lets the two rams share one drive.");
    const auto seam = p::inspect("paired", {2, 10, 19});
    check(seam.fault == p::Fault::drive_overload && seam.tooth == 10,
          "A near-full-turn offset is one tooth early and still conflicts across the cycle seam.");
    const auto late_feed = p::inspect("dock", {5, 11, 0});
    check(late_feed.fault == p::Fault::feed_offsite && late_feed.tooth == 6,
          "Moving just the feed start into dock is insufficient when its end crosses departure.");
}

void exhaustive_keys() {
    unsigned dock_solutions{}, ram_solutions{}, paired_solutions{};
    for (m::Tooth feed = 0; feed < 20; ++feed) {
        for (m::Tooth ram = 0; ram < 20; ++ram) {
            const bool solved = p::inspect("dock", {feed, ram, 0}).solved();
            check(solved == (feed >= 2 && feed <= 4 && ram >= 10 && ram <= 13),
                  "Every dock setup agrees with the literal disjoint dock and work intervals.");
            dock_solutions += solved;
            for (m::Tooth offset = 0; offset < 20; ++offset) {
                const bool both = p::inspect("paired", {feed, ram, offset}).solved();
                check(both == (feed >= 2 && feed <= 4 && ram >= 10 && ram <= 12 &&
                               offset >= 4 && offset <= 16),
                      "Every paired setup agrees with independently derived disjoint four-tooth press arcs.");
                paired_solutions += both;
            }
        }
    }
    for (m::Tooth feed = 0; feed < 16; ++feed) {
        for (m::Tooth ram = 0; ram < 16; ++ram) {
            const bool solved = p::inspect("ram", {feed, ram, 0}).solved();
            check(solved == ((feed == 1 || feed == 2) && ram == 8),
                  "The short dwell has exactly one ram alignment and two legal feed alignments.");
            ram_solutions += solved;
        }
    }
    check(dock_solutions == 12 && ram_solutions == 2 && paired_solutions == 117,
          "Each puzzle has the declared finite solution space and supports multiple valid arrangements.");
}

void projection_and_refusal() {
    p::Frame frame{};
    check(p::snapshot("paired", {2, 10, 10}, {}, frame) == p::Error::none &&
          frame.lane_count == 2 && frame.lanes[0].phase == m::Phase{} &&
          frame.lanes[0].carriage == m::Pose{m::Stage::dock, 0, 4} && frame.lanes[0].unloading &&
          frame.lanes[1].phase == m::Phase{10} &&
          frame.lanes[1].carriage == m::Pose{m::Stage::work, 4, 4} && frame.lanes[1].pressing,
          "A delayed workstation projects the exact literal phase and cam signals across the seam.");
    const auto before = frame;
    check(p::snapshot("paired", {2, 10, 10}, {}, frame) == p::Error::none && frame == before,
          "Repeated projections cannot advance either workstation.");
    check(p::snapshot("paired", {2, 10, 10}, {20}, frame) == p::Error::invalid_phase && frame == before,
          "An invalid imported phase cannot partially replace a projected frame.");
    for (const auto keys : {p::Keys{20, 10, 0}, p::Keys{2, 20, 0}, p::Keys{2, 10, 20},
                            p::Keys{2, 10, std::numeric_limits<m::Tooth>::max()}}) {
        check(p::snapshot("paired", keys, {}, frame) == p::Error::invalid_key && frame == before,
              "Out-of-cycle keys refuse without aliasing or changing prior projections.");
        const auto report = p::inspect("paired", keys);
        check(!report.solved() && report.error == p::Error::invalid_key,
              "A malformed arrangement cannot receive a solved report.");
    }
    check(p::snapshot("dock", {2, 11, 1}, {}, frame) == p::Error::invalid_key && frame == before,
          "A single-workstation puzzle refuses a misleading second-lane offset.");
    check(p::snapshot("missing", {}, {}, frame) == p::Error::unknown_challenge && frame == before &&
          !p::inspect("missing", {}).solved(), "An unknown puzzle cannot overwrite a frame or pass inspection.");
}

void cli(std::initializer_list<std::string_view> args, int code, std::string_view expected) {
    std::ostringstream output, errors;
    const auto result = p::workbench({args.begin(), args.size()}, output, errors);
    check(result == code && (output.str() + errors.str()).find(expected) != std::string::npos,
          "The actual command parser reports the expected outcome and explanation.");
}

void command_cases() {
    cli({}, 0, "cam_workbench list");
    cli({"list"}, 0, "One drive, two workstations");
    cli({"--help"}, 0, "--feed N");
    cli({"dock"}, 1, "Conflict at tooth 1, lane 1");
    cli({"ram"}, 1, "Conflict at tooth 12, lane 1");
    cli({"paired"}, 1, "Conflict at tooth 11:");
    cli({"dock", "--feed", "2"}, 0, "Solved:");
    cli({"ram", "--ram", "8"}, 0, "Solved:");
    cli({"paired", "--offset", "4"}, 0, "Solved:");
    cli({"paired", "--offset", "4"}, 0, "DDDDDD>>>>WWWWWW<<<<");
    cli({"missing"}, 2, "Unknown puzzle");
    cli({"dock", "--feed"}, 2, "Each key option");
    cli({"dock", "--feed", "1", "--feed", "2"}, 2, "Each key option");
    cli({"dock", "--other", "1"}, 2, "Each key option");
    for (const auto value : {"-1", "+1", "1.5", "1x", "", "18446744073709551616"}) {
        cli({"dock", "--feed", value}, 2, "Each key option");
    }
    cli({"dock", "--feed", "20"}, 2, "invalid_key");
    cli({"dock", "--offset", "1"}, 2, "invalid_key");
    std::ostringstream output, errors;
    output.setstate(std::ios::badbit);
    const std::array<std::string_view, 1> args{{"list"}};
    check(p::workbench(args, output, errors) == 2, "A failed output stream cannot report successful command completion.");
}
}  // namespace

int main() {
    puzzle_cases();
    exhaustive_keys();
    projection_and_refusal();
    command_cases();
    std::cout << checks << " cam puzzle checks, " << failures << " failures.\n";
    return failures == 0 ? 0 : 1;
}
