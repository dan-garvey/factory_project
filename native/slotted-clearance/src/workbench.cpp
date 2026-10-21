#include "factory/slotted_clearance_workbench.hpp"

#include "factory/slotted_clearance.hpp"

#include <charconv>
#include <istream>
#include <ostream>
#include <sstream>
#include <string>

namespace factory::slotted_clearance {
namespace b = slotted_bank;
namespace {
struct Scene { Rig rig; std::vector<clearance::Obstacle> obstacles; };
Scene scene(std::string_view layout) {
    Rig rig{mechanics::Axis::x, {{0, -3, 0}, {1, -2, 1}},
            {{3, {{0, 0, 0}, {1, 1, 1}}}, {7, {{0, 3, 0}, {1, 4, 1}}}}};
    if (layout == "raised") rig.followers[0].at_zero = {{0, 6, 0}, {1, 7, 1}};
    const mechanics::Integer x = layout == "setback" ? 4 : 2;
    return {rig, {{11, {{x, 0, 0}, {x + 1, 1, 1}}}}};
}
bool home(const b::State& state) { return state.pin == 0 && state.followers[0].position == 0 && state.followers[1].position == 0; }
bool matched(const b::State& state) { return state.pin == 0 && state.followers[0].position == 2 && state.followers[1].position == 1; }
void help(std::ostream& out) {
    out << "Usage: slotted_clearance_workbench play | list\n"
           "Commands: move <-32..32>; layout blocked|raised|setback; power on|off; status; help; quit.\n"
           "Return the same shared pin to 0 with original followers A at 2 and B at 1.\n"
           "A crate obstructs A's path. Raise its guide or move the crate beyond the stroke.\n"
           "An obstructed stroke holds ALL positions. Change layout only when the pin and BOTH followers are at 0.\n"
           "Declared box proxies are tested continuously against the stationary crate; moving-member contact is outside this fixture.\n";
}
void show(const b::State& state, std::string_view layout, bool powered, std::ostream& out) {
    out << "Pin " << state.pin << "; A " << state.followers[0].position << "; B " << state.followers[1].position
        << "; layout " << layout << "; power " << (powered ? "on" : "off") << ".\n"
        << (matched(state) ? "Matched: original rig returned with follower offsets 2 and 1.\n" : "Unfinished: clear the spatial path and return the shared pin.\n");
}
enum class Read { line, end, too_long, failed };
Read read(std::istream& input, std::string& line) {
    line.clear();
    bool overflow{};
    char ch{};
    while (input.get(ch)) {
        if (ch == '\n') return overflow ? Read::too_long : Read::line;
        if (line.size() < 512) line.push_back(ch); else overflow = true;
    }
    if (input.bad() || (!input.eof() && input.fail())) return Read::failed;
    if (overflow) return Read::too_long;
    return line.empty() ? Read::end : Read::line;
}
}  // namespace
int workbench(std::span<const std::string_view> args, std::istream& input, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) { help(out); return out ? 0 : 2; }
    if (args.size() != 1 || args[0] != "play") { errors << "Choose slotted_clearance_workbench play or list.\n"; return 2; }
    const std::vector<b::Link> links{{3, {0, 4, 2, 1}}, {7, {-1, 2, 1, 2}}};
    b::State state{0, {{3, 0}, {7, 0}}};
    std::string layout = "blocked";
    bool powered{true};
    help(out);
    show(state, layout, powered, out);
    std::string line;
    while (out) {
        const auto read_result = read(input, line);
        if (read_result == Read::failed) { errors << "Input failed.\n"; return 2; }
        if (read_result == Read::end) return matched(state) ? 0 : 1;
        if (read_result == Read::too_long) { out << "Refused: command exceeds 512 bytes.\n"; continue; }
        std::istringstream command(line);
        std::string verb, argument, extra;
        if (!(command >> verb)) continue;
        if (verb == "quit" && !(command >> extra)) return matched(state) ? 0 : 1;
        if (verb == "status" && !(command >> extra)) { show(state, layout, powered, out); continue; }
        if (verb == "help" && !(command >> extra)) { help(out); continue; }
        if (!(command >> argument) || (command >> extra)) { out << "Refused: use the listed commands.\n"; continue; }
        if (verb == "layout" && (argument == "blocked" || argument == "raised" || argument == "setback")) {
            if (!home(state)) { out << "Refused: return the pin and BOTH original followers home before changing the layout.\n"; continue; }
            layout = argument;
            show(state, layout, powered, out);
            continue;
        }
        if (verb == "power" && (argument == "on" || argument == "off")) {
            powered = argument == "on";
            show(state, layout, powered, out);
            continue;
        }
        if (verb != "move") { out << "Refused: use the listed commands.\n"; continue; }
        mechanics::Integer destination{};
        const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), destination);
        if (parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || destination < -32 || destination > 32) {
            out << "Refused: move needs a whole destination from -32 through 32.\n";
            continue;
        }
        const auto geometry = scene(layout);
        const auto plan = prepare(links, state, geometry.rig, {{destination, powered}, geometry.obstacles});
        if (const auto* error = std::get_if<Refusal>(&plan)) { errors << "Fixture refused: " << error_name(error->reason) << ".\n"; return 2; }
        if (const auto* blocked = std::get_if<Blocked>(&plan)) {
            out << "Blocked ";
            if (blocked->follower) out << "follower " << *blocked->follower; else out << "pin";
            out << " by obstacle " << blocked->hit.obstacle << " at " << blocked->hit.time.numerator << '/' << blocked->hit.time.denominator
                << "; all positions retained.\n";
        } else if (const auto* held = std::get_if<b::Hold>(&plan)) {
            out << "Hold " << (held->reason == b::Stop::unpowered ? "unpowered" : held->reason == b::Stop::rest ? "rest" : "limit")
                << "; all positions retained.\n";
        } else {
            const auto& next = std::get<b::Advance>(plan);
            state = next.next;
            out << "Admitted complete shared stroke.\n";
            if (next.limit) out << "Limit " << next.limit->id << " at " << next.limit->stop.at.numerator << '/' << next.limit->stop.at.denominator << ".\n";
        }
        show(state, layout, powered, out);
    }
    return 2;
}
}  // namespace factory::slotted_clearance
