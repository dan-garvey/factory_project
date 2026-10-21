#include "factory/slotted_link_workbench.hpp"

#include "factory/slotted_link.hpp"

#include <charconv>
#include <istream>
#include <ostream>
#include <sstream>

namespace factory::slotted_link {
namespace {
Profile kit(std::string_view name) { return {0, 4, name == "tight" ? 0 : 2, name == "compact" ? 0 : 1}; }
bool matched(const State& state) { return state.pin == 0 && state.follower == 2; }
void help(std::ostream& out) {
    out << "Usage: slotted_link_workbench play | list\n"
           "Commands: move <-32..32>; kit tight|return|compact; power on|off; status; help; quit.\n"
           "Return the original pin to 0 while leaving its original follower at 2.\n"
           "The pin first takes up clearance, then pushes a slot wall. Reversing takes up the opposite clearance.\n"
           "Replace the link only when BOTH positions are home. Each move is one prescribed linear stroke.\n";
}
void show(const Profile& profile, const State& state, std::string_view name, bool powered, std::ostream& out) {
    out << "Pin " << state.pin << "; follower " << state.follower << "; kit " << name << "; back " << profile.back
        << "; front " << profile.front << "; power " << (powered ? "on" : "off") << ".\n"
        << (matched(state) ? "Matched: pin home, same follower retained at 2.\n" : "Unfinished: return the pin while retaining the follower offset.\n");
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
    if (args.size() != 1 || args[0] != "play") { errors << "Choose slotted_link_workbench play or list.\n"; return 2; }
    std::string name = "tight";
    auto profile = kit(name);
    State state;
    bool powered{true};
    help(out);
    show(profile, state, name, powered, out);
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
        if (verb == "status" && !(command >> extra)) { show(profile, state, name, powered, out); continue; }
        if (verb == "help" && !(command >> extra)) { help(out); continue; }
        if (!(command >> argument) || (command >> extra)) { out << "Refused: use the listed commands.\n"; continue; }
        if (verb == "kit" && (argument == "tight" || argument == "return" || argument == "compact")) {
            if (state.pin != 0 || state.follower != 0) { out << "Refused: return BOTH original positions home before replacing the link.\n"; continue; }
            name = argument;
            profile = kit(name);
            show(profile, state, name, powered, out);
            continue;
        }
        if (verb == "power" && (argument == "on" || argument == "off")) {
            powered = argument == "on";
            show(profile, state, name, powered, out);
            continue;
        }
        if (verb != "move") { out << "Refused: use the listed commands.\n"; continue; }
        Coordinate destination{};
        const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), destination);
        if (parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || destination < -32 || destination > 32) {
            out << "Refused: move needs a whole destination from -32 through 32.\n";
            continue;
        }
        auto plan = prepare(profile, state, {destination, powered});
        if (const auto* error = std::get_if<Error>(&plan)) { errors << "Fixture refused: " << error_name(*error) << ".\n"; return 2; }
        if (const auto* held = std::get_if<Hold>(&plan)) out << "Hold " << stop_name(held->reason) << "; same pin and follower.\n";
        else {
            const auto& next = std::get<Advance>(plan);
            state = next.next;
            if (next.contact) {
                out << "Contact " << (next.contact->side == Side::positive ? "positive" : "negative") << " at ";
                fraction(out, next.contact->at); out << ".\n";
            }
            if (next.follower_motion) {
                out << "Follower motion from "; fraction(out, next.follower_motion->begin);
                out << " to "; fraction(out, next.follower_motion->end); out << ".\n";
            }
            if (next.endstop) {
                out << "Travel " << (next.endstop->side == Side::positive ? "upper" : "lower") << " at ";
                fraction(out, next.endstop->at); out << "; both positions held for the remainder.\n";
            }
        }
        show(profile, state, name, powered, out);
    }
    return 2;
}
}  // namespace factory::slotted_link
