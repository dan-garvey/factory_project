#include "factory/slotted_bank_workbench.hpp"

#include "factory/slotted_bank.hpp"

#include <charconv>
#include <istream>
#include <ostream>
#include <sstream>

namespace factory::slotted_bank {
namespace {
std::vector<Link> kit(std::string_view name) {
    return {{3, {0, 4, 2, name == "compact" ? 0 : 1}}, {7, {-1, 2, 1, name == "delay" ? 2 : 0}}};
}
bool home(const State& state) { return state.pin == 0 && state.followers[0].position == 0 && state.followers[1].position == 0; }
bool matched(const State& state) { return state.pin == 0 && state.followers[0].position == 2 && state.followers[1].position == 1; }
void help(std::ostream& out) {
    out << "Usage: slotted_bank_workbench play | list\n"
           "Commands: move <-32..32>; kit tight|delay|compact; power on|off; status; help; quit.\n"
           "Return the common pin to 0 with original followers A at 2 and B at 1.\n"
           "A stops in [0,4]; B stops in [-1,2]. The first stop halts the WHOLE shared stroke.\n"
           "Back clearances are A=2 and B=1. Kit tight has fronts A=1,B=0; delay has A=1,B=2; compact has A=0,B=0.\n"
           "Replace the kit only when the pin and BOTH followers are at 0. Negative service travel can recover the tight kit.\n";
}
void show(const State& state, std::string_view name, bool powered, std::ostream& out) {
    out << "Pin " << state.pin << "; A " << state.followers[0].position << "; B " << state.followers[1].position
        << "; kit " << name << "; power " << (powered ? "on" : "off") << ".\n"
        << (matched(state) ? "Matched: same pin home, same followers at 2 and 1.\n" : "Unfinished: coordinate the two followers on their shared pin.\n");
}
void fraction(std::ostream& out, Fraction value) { out << value.numerator << '/' << value.denominator; }
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
    if (args.size() != 1 || args[0] != "play") { errors << "Choose slotted_bank_workbench play or list.\n"; return 2; }
    std::string name = "tight";
    auto links = kit(name);
    State state{0, {{3, 0}, {7, 0}}};
    bool powered{true};
    help(out);
    show(state, name, powered, out);
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
        if (verb == "status" && !(command >> extra)) { show(state, name, powered, out); continue; }
        if (verb == "help" && !(command >> extra)) { help(out); continue; }
        if (!(command >> argument) || (command >> extra)) { out << "Refused: use the listed commands.\n"; continue; }
        if (verb == "kit" && (argument == "tight" || argument == "delay" || argument == "compact")) {
            if (!home(state)) { out << "Refused: return the pin and BOTH original followers home before replacing the kit.\n"; continue; }
            name = argument;
            links = kit(name);
            show(state, name, powered, out);
            continue;
        }
        if (verb == "power" && (argument == "on" || argument == "off")) {
            powered = argument == "on";
            show(state, name, powered, out);
            continue;
        }
        if (verb != "move") { out << "Refused: use the listed commands.\n"; continue; }
        Coordinate destination{};
        const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), destination);
        if (parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || destination < -32 || destination > 32) {
            out << "Refused: move needs a whole destination from -32 through 32.\n";
            continue;
        }
        const auto plan = prepare(links, state, {destination, powered});
        if (const auto* error = std::get_if<Refusal>(&plan)) { errors << "Fixture refused: " << error_name(error->reason) << ".\n"; return 2; }
        if (const auto* held = std::get_if<Hold>(&plan)) {
            out << "Hold " << (held->reason == Stop::unpowered ? "unpowered" : held->reason == Stop::rest ? "rest" : "limit");
            if (held->limit) out << " link " << held->limit->id;
            out << "; all three positions retained.\n";
        } else {
            const auto& next = std::get<Advance>(plan);
            state = next.next;
            for (const auto& trace : next.traces) {
                if (trace.contact) {
                    out << "Link " << trace.id << " contact " << (trace.contact->side == slotted_link::Side::positive ? "positive" : "negative") << " at ";
                    fraction(out, trace.contact->at); out << ".\n";
                }
                if (trace.follower_motion) {
                    out << "Link " << trace.id << " motion from "; fraction(out, trace.follower_motion->begin);
                    out << " to "; fraction(out, trace.follower_motion->end); out << ".\n";
                }
            }
            if (next.limit) {
                out << "Limit " << next.limit->id << ' ' << (next.limit->stop.side == slotted_link::Side::positive ? "upper" : "lower") << " at ";
                fraction(out, next.limit->stop.at); out << "; all branches held for the remainder.\n";
            }
        }
        show(state, name, powered, out);
    }
    return 2;
}
}  // namespace factory::slotted_bank
