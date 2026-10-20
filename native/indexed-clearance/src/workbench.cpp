#include "factory/indexed_clearance.hpp"

#include <array>
#include <charconv>
#include <istream>
#include <ostream>
#include <sstream>
#include <string>
#include <string_view>

namespace factory::indexed_clearance {
namespace {
void describe(const State& state, std::ostream& out) {
    out << "Phase " << phase_name(state.phase) << ", quarter " << state.quarter << ", route " << route_name(state.route) << ". Pending:";
    for (const auto& job : state.pending) out << ' ' << job.id;
    out << "; held:";
    if (const auto* job = std::get_if<indexing::Job>(&state.holder)) out << ' ' << job->id << " marked=" << unsigned(job->marked);
    else out << " empty";
    out << "; released:";
    for (const auto& job : state.completed) out << ' ' << job.id;
    out << ".\n";
}
void help(std::ostream& out) {
    out << "Commands: step; run 1..64; route short|detour|short_return; inspect; help; quit.\n"
           "One step loads, turns, marks, releases or returns. The corner lies between clear index stops.\n"
           "Finish all three original blanks and bring the empty holder back to intake.\n";
}
std::optional<Route> parse_route(const std::string& name) {
    if (name == "short") return Route::short_path;
    if (name == "detour") return Route::detour;
    if (name == "short_return") return Route::short_return;
    return std::nullopt;
}
}  // namespace

int play(const Profile& profile, Route route, std::istream& input, std::ostream& out, std::ostream& errors) {
    auto state = start(route);
    if (!valid(profile, state)) { errors << "Use a fixed height from zero to two and a real route.\n"; return 2; }
    out << "Indexed batch fixture, height " << profile.height << ". Mark the original X+ face at the work station.\n";
    help(out); describe(state, out);
    if (!out) return 2;
    auto apply = [&](Transition proposal) {
        if (const auto* refusal = std::get_if<Refusal>(&proposal)) {
            out << "Refused: " << error_name(refusal->error);
            if (refusal->obstacle) out << " by corner " << refusal->obstacle;
            out << ". Pose, work and cursor retained.\n";
            return false;
        }
        state = std::get<State>(std::move(proposal));
        return true;
    };
    for (unsigned lines = 0; lines < 512; ++lines) {
        if (!out) return 2;
        std::array<char, 257> buffer{};
        input.getline(buffer.data(), buffer.size());
        if (input.bad() || (input.fail() && !input.eof())) { errors << "Input failed or exceeded 256 characters.\n"; return 2; }
        if (input.gcount() == 0) return out ? (finished(profile, state) ? 0 : 1) : 2;
        std::istringstream parser(buffer.data());
        std::string command, argument, extra;
        parser >> command;
        if (command.empty()) continue;
        parser >> argument >> extra;
        if (!extra.empty()) { out << "Refused: too many command arguments.\n"; continue; }
        if (command == "quit" && argument.empty()) return out ? (finished(profile, state) ? 0 : 1) : 2;
        if (command == "help" && argument.empty()) { help(out); continue; }
        if (command == "inspect" && argument.empty()) { describe(state, out); continue; }
        if (command == "route") {
            const auto selected = parse_route(argument);
            if (!selected) { out << "Refused: choose short, detour or short_return.\n"; continue; }
            (void)apply(plan_route(profile, state, *selected));
        } else if ((command == "step" && argument.empty()) || command == "run") {
            unsigned count{1};
            if (command == "run") {
                const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), count);
                if (parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || count < 1 || count > 64) {
                    out << "Refused: run takes a count from one to 64.\n"; continue;
                }
            }
            for (unsigned step = 0; step < count && !finished(profile, state); ++step) if (!apply(plan_step(profile, state))) break;
        } else { out << "Refused: use help for commands; no reset or replacement is available.\n"; continue; }
        describe(state, out);
        if (finished(profile, state)) out << "Solved batch: 7 8 9; empty holder home.\n";
        if (!out) return 2;
    }
    errors << "The fixture input exceeded 512 lines.\n";
    return 2;
}
}  // namespace factory::indexed_clearance
