#include "factory/repair_workbench.hpp"

#include <array>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace r = factory::repair_scenarios;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

struct Result { int code; std::string out, errors; };

Result run(std::string_view scenario, const std::string& commands) {
    const std::array<std::string_view, 2> arguments{"play", scenario};
    std::istringstream input(commands);
    std::ostringstream output, errors;
    const auto code = r::workbench(arguments, input, output, errors);
    return {code, output.str(), errors.str()};
}

bool contains(const Result& result, std::string_view text) { return result.out.find(text) != std::string::npos; }

std::size_t count(const std::string& text, std::string_view part) {
    std::size_t found{}, position{};
    while ((position = text.find(part, position)) != std::string::npos) { ++found; position += part.size(); }
    return found;
}

std::string plates(int number) {
    std::string actions;
    for (int plate = 0; plate < number; ++plate) actions += "wait 8\ncollect processor\n";
    return actions;
}

void solutions() {
    const auto coupling = run("coupling", "collect processor\nplace shaft 0 0 0 z 4\nwalk east 6\nwalk north 4\n" + plates(4));
    check(coupling.code == 0 && coupling.errors.empty(), "A complete coupling repair works through actual interactive commands.");
    check(contains(coupling, "Held: out_of_reach") && contains(coupling, "Accepted: ok (native-part-1)"),
          "A far retrieval refuses before a real finite-kit placement succeeds.");
    check(contains(coupling, "Power collector=0 belt=1 processor=1") && contains(coupling, "Power collector=1 belt=1 processor=1"),
          "The displayed drive changes only after the actual missing shaft is placed.");
    check(contains(coupling, "Cargo raw=0 products=4/4") && contains(coupling, "Complete: four plates retrieved"),
          "Four products are held by the bound actor before completion.");

    const auto link = run("link", "wait 8\nlink belt processor\nwalk north 4\nwalk east 4\nlink belt processor\n" + plates(4));
    check(link.code == 0 && link.errors.empty(), "The handoff scenario completes through native linking and finite production.");
    check(contains(link, "Stock source=14 collector=1 belt=1 input=0 output=0"),
          "Inspection exposes the real retained upstream blockage before repair.");
    check(contains(link, "Held: out_of_reach (belt)") && contains(link, "Accepted: ok (belt)"),
          "A link requires a corrected actor position within reach of both current endpoints.");
    check(count(link.out, "Complete:") == 1, "The same run completes once after four real collections.");

    const auto outlet = run("outlet", "walk east 6\nwalk north 4\nremove processor\nrecover processor\ninspect\n"
        "insert_work processor 7\ninspect\ninsert_work processor 7\ninsert_raw processor 1\n" + plates(3));
    check(outlet.code == 0 && outlet.errors.empty(), "Ready-work recovery and reinsertion can complete the outlet puzzle.");
    check(contains(outlet, "Held: occupied_target (processor)"), "Dismantling cannot discard the obstructing original billet.");
    check(contains(outlet, "Carried work=7 remaining=0 recipe_units=1 cycle=2") &&
          count(outlet.out, "Press work=7 remaining=0 recipe_units=1 cycle=2") >= 3,
          "The same original ready lot and recipe survive evacuation, inspection and reinsertion without a tick.");
    check(contains(outlet, "Held: unavailable_cargo (processor)"), "The inserted whole lot cannot be inserted twice.");
    check(contains(outlet, "Cargo raw=1 products=1/4") && contains(outlet, "Cargo raw=0 products=4/4"),
          "Recovered raw stock remains carried until explicitly inserted, and output remains product cargo.");
}

void retained_refusals() {
    const auto readonly = run("outlet", "help\nhint\ninspect\ninspect\nquit\n");
    check(readonly.code == 1 && readonly.errors.empty(), "Help, hints and inspection do not finish or run the puzzle.");
    check(count(readonly.out, "Stock source=11 collector=1 belt=1 input=1 output=1") == 3 &&
          count(readonly.out, "Press work=7 remaining=0 recipe_units=1 cycle=2") == 3,
          "Every read-only inspection sees the unchanged stock and ready work.");
    const auto bad = run("outlet", "reset\nwait 0\nwait 33\nwait 1x\nwalk east -1\nwalk up\nwalk east 9\n"
        "collect processor 0\ninsert_work processor 9223372036854775808\nplace shaft 0 0 2 q 2\n"
        "link no-part processor\n" + std::string(513, 'x') + "\ninspect\nquit\n");
    check(bad.code == 1 && bad.errors.empty() && count(bad.out, "Invalid command.") == 10,
          "Bad syntax, oversized integers and nonexistent reset are recoverable instead of replacing the World.");
    check(contains(bad, "No current part named no-part.") && contains(bad, "Command too long. Work unchanged."),
          "Unknown current selections and overlong input cannot create targets or run production.");
    check(count(bad.out, "Stock source=11 collector=1 belt=1 input=1 output=1") == 2 &&
          count(bad.out, "Press work=7 remaining=0 recipe_units=1 cycle=2") == 2,
          "All invalid actions preserve the original billet and every material holder.");

    const auto kit = run("coupling", "place shaft 0 0 0 z 4\nplace shaft 0 0 0 z 4\ninspect\nquit\n");
    check(kit.code == 1 && contains(kit, "Held: unavailable_part"), "A second placement cannot invent another carried coupling.");
    check(count(kit.out, "native-part-1 generation=1 shaft") == 1 && !contains(kit, "native-part-2 generation="),
          "A refused placement leaves only the original successfully allocated part.");

    const auto walking = run("outlet", "collect processor\nwalk east 8\nwalk east 8\nwalk north 4\ncollect processor\nquit\n");
    check(walking.code == 1 && contains(walking, "The walk leaves this workbench. Position unchanged.") &&
          contains(walking, "Position (8,0,4)") && contains(walking, "Cargo raw=0 products=1/4"),
          "A refused boundary crossing retains the actor position used by the next admitted collection.");

    const auto empty = run("coupling", "walk east 6\nwalk north 4\ncollect processor\nwait 8\ninspect\n");
    check(empty.code == 1 && contains(empty, "Held: unavailable_output (processor)"), "An empty output produces a retained native refusal.");
    check(count(empty.out, "Stock source=16 collector=0 belt=0 input=0 output=0") >= 4,
          "Waiting cannot produce through a drive that is still disconnected.");

    const auto paused = run("outlet", "walk east 6\nwalk north 4\ndrive wheel-processor off\ncollect processor\nwait 8\ninspect\nquit\n");
    check(paused.code == 1 && contains(paused, "Power collector=0 belt=0 processor=0") &&
          contains(paused, "Cargo raw=0 products=1/4") && contains(paused, "Press work=7 remaining=0"),
          "The declared coarse drive switch pauses work without destroying the finished held lot.");
}

void entry_and_streams() {
    check(run("missing", "").code == 2, "Unknown scenarios cannot select a fresh default.");
    check(run("coupling", "").code == 1 && run("outlet", "quit\n").code == 1,
          "EOF and quit remain unfinished before four retrieved products.");
    std::istringstream input;
    std::ostringstream output, errors;
    const std::array<std::string_view, 1> list{"list"};
    check(r::workbench(list, input, output, errors) == 0 && output.str().find("link:") != std::string::npos,
          "The binary catalogue exposes the three existing scenario choices.");
    const std::array<std::string_view, 3> extra{"play", "coupling", "reset"};
    check(r::workbench(extra, input, output, errors) == 2, "Unexpected entry arguments are rejected.");
    const std::array<std::string_view, 2> play{"play", "outlet"};
    input.setstate(std::ios::badbit);
    check(r::workbench(play, input, output, errors) == 2, "A broken input stream is a failure rather than a solved or normal EOF result.");
    std::istringstream good_input("quit\n");
    std::ostream broken_output(nullptr);
    check(r::workbench(play, good_input, broken_output, errors) == 2 &&
          r::workbench(list, good_input, broken_output, errors) == 2,
          "Both play and catalogue report output failure.");
    std::istringstream failed_input;
    failed_input.setstate(std::ios::failbit);
    check(r::workbench(play, failed_input, output, errors) == 2, "Non-EOF input failure cannot masquerade as an unfinished clean close.");
}
}  // namespace

int main() {
    try {
        solutions();
        retained_refusals();
        entry_and_streams();
        std::cout << checks << " interactive repair checks, 0 failures.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
