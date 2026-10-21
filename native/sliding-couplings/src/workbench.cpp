#include "factory/coupling_puzzles.hpp"

#include <algorithm>
#include <istream>
#include <ostream>
#include <sstream>

namespace factory::coupling_puzzles {
namespace s = sliding_couplings;
namespace {
void help(std::ostream& out) {
    out << "Usage: coupling_workbench play branch|bypass|selector | list\n"
           "Commands: status; shift <shaft> in|out; help; quit.\n"
           "The same original shafts slide to their declared endpoint poses.\n"
           "A zero-rate fixture hub holds a branch; contact is not simulated.\n"
           "This is an instantaneous geometric layout prototype.\n";
}
void show(const Puzzle& puzzle, const mechanics::Result& motion, std::ostream& out) {
    out << puzzle.title << '\n' << puzzle.instruction << '\n';
    for (const auto& slot : puzzle.slots) {
        const auto part = std::find_if(puzzle.parts.begin(), puzzle.parts.end(),
            [&](const auto& item) { return item.id == slot.shaft; });
        out << "Coupling " << slot.shaft << " is "
            << (part->center == slot.engaged ? "in" : "out") << " at "
            << part->center[0] << ',' << part->center[1] << ',' << part->center[2] << ".\n";
    }
    for (const auto& [id, current] : motion.motion) {
        const auto part = std::find_if(puzzle.parts.begin(), puzzle.parts.end(),
            [&](const auto& item) { return item.id == id; });
        if (part->kind == mechanics::Kind::hub)
            out << "Hub " << id << ": " << mechanics::motion_state_name(current.state)
                << ' ' << current.rate.numerator << '/' << current.rate.denominator << ".\n";
    }
    out << (solved(puzzle, motion) ? "Solved: the current shaft layout meets every target.\n"
                                 : "Unfinished: inspect the drive paths and shift the same shafts.\n");
}

// Bound malformed terminal input without allocating an unbounded line. Drain a
// long line completely so its tail cannot become a second accidental command.
enum class Read { line, end, too_long, failed };
Read read(std::istream& in, std::string& line) {
    line.clear();
    bool overflow{};
    char ch{};
    while (in.get(ch)) {
        if (ch == '\n') return overflow ? Read::too_long : Read::line;
        if (line.size() < 512) line.push_back(ch);
        else overflow = true;
    }
    if (in.bad() || (!in.eof() && in.fail())) return Read::failed;
    if (overflow) return Read::too_long;
    return line.empty() ? Read::end : Read::line;
}
}  // namespace

int workbench(std::span<const std::string_view> args, std::istream& in,
              std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        help(out);
        out << "branch: one held branch\nbypass: two paths to the same held branch\n"
               "selector: opposing registered sources\n";
        return out ? 0 : 2;
    }
    if (args.size() != 2 || args[0] != "play") {
        errors << "Choose coupling_workbench play <puzzle> or list.\n";
        return 2;
    }
    auto puzzle = make(args[1]);
    if (!puzzle) { errors << "Unknown puzzle. Use coupling_workbench list.\n"; return 2; }
    auto motion = mechanics::evaluate(puzzle->parts, puzzle->sources);
    if (!motion.accepted()) { errors << "The declared fixture is invalid.\n"; return 2; }
    help(out);
    show(*puzzle, motion, out);
    std::string line;
    while (out) {
        const auto read_result = read(in, line);
        if (read_result == Read::failed) { errors << "Input failed.\n"; return 2; }
        if (read_result == Read::end) return solved(*puzzle, motion) ? 0 : 1;
        if (read_result == Read::too_long) { out << "Refused: command exceeds 512 bytes.\n"; continue; }
        std::istringstream command(line);
        std::string verb, id, pose, extra;
        if (!(command >> verb)) continue;
        if (verb == "quit" && !(command >> extra)) return solved(*puzzle, motion) ? 0 : 1;
        if (verb == "status" && !(command >> extra)) { show(*puzzle, motion, out); continue; }
        if (verb == "help" && !(command >> extra)) { help(out); continue; }
        if (verb != "shift" || !(command >> id >> pose) || (command >> extra) ||
            (pose != "in" && pose != "out")) {
            out << "Refused: use shift <shaft> in|out, status, help or quit.\n";
            continue;
        }
        const auto slot = std::find_if(puzzle->slots.begin(), puzzle->slots.end(),
            [&](const auto& item) { return item.shaft == id; });
        if (slot == puzzle->slots.end()) { out << "Refused: that shaft is not a sliding coupling.\n"; continue; }
        const s::Shift shift{id, pose == "in" ? slot->engaged : slot->withdrawn};
        auto plan = s::prepare(puzzle->parts, puzzle->sources, std::span(&shift, 1));
        if (const auto* refusal = std::get_if<s::Refusal>(&plan)) {
            out << "Refused: " << s::error_name(refusal->reason) << ".\n";
            continue;
        }
        auto prepared = std::get<s::Prepared>(std::move(plan));
        puzzle->parts = std::move(prepared.parts);
        motion = std::move(prepared.motion);
        out << "Shifted " << id << ' ' << pose << ".\n";
        show(*puzzle, motion, out);
    }
    return 2;
}
}  // namespace factory::coupling_puzzles
