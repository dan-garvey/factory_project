#include "factory/slotted_cascade.hpp"
#include "factory/slotted_cascade_workbench.hpp"

#include <array>
#include <charconv>
#include <istream>
#include <ostream>
#include <sstream>
#include <string>

namespace factory::slotted_cascade {
namespace b = slotted_bank;
using I = mechanics::Integer;
namespace {
clearance::Box box(I x, I y) { return {{x, y, 0}, {x + 1, y + 1, 1}}; }
bool complete(const b::State& state) { return state == b::State{0, {{7, 2}, {11, 1}}}; }
std::array<b::Link, 2> chain(bool long_guide, bool tight) {
    return {{{7, {0, long_guide ? 5 : 3, 2, 1}}, {11, {0, 6, 1, tight ? 1 : 3}}}};
}
void help(std::ostream& output) {
    output << "Commands: move -32..32, guide short|long, coupler slack|tight, power on|off, status, help, quit.\n"
              "Stage 7 drives tip 11 through its own slot; it is not a second copy of the original pin.\n"
              "The short first guide ends at 3. Its front clearance is 1; the tip adds front clearance 3 (slack) or 1 (tight).\n"
              "The long guide ends at 5 and needs more travel. The tight coupler removes lost travel but must fit the current positions.\n"
              "Stop power for an edit. Valid edits retain every original position; an invalid tighter fit is refused.\n"
              "The fixed tip frame blocks positions above 1. A blocked stroke adopts no partial positions.\n"
              "This is a finite ideal-slot calibration, without connector-body or force simulation.\n";
}
}  // namespace

int play(std::istream& input, std::ostream& output, std::ostream& errors) {
    b::State state{0, {{7, 0}, {11, 0}}};
    bool long_guide = false, tight = false, powered = true;
    const slotted_clearance::Rig rig{mechanics::Axis::x, box(0, -3), {{7, box(0, 0)}, {11, box(0, 3)}}};
    const std::array<clearance::Obstacle, 1> frame{{{29, box(2, 3)}}};
    const auto status = [&] {
        output << "Pin " << state.pin << "; stage 7 " << state.followers[0].position << "; tip 11 " << state.followers[1].position
               << "; guide " << (long_guide ? "long" : "short") << "; coupler " << (tight ? "tight" : "slack")
               << "; power " << (powered ? "on" : "off") << ".\n";
        if (complete(state)) output << "Matched: original pin 0, stage 7 at 2 and tip 11 at 1.\n";
    };
    output << "Carry motion through BOTH slots, then return the original pin: goal pin 0, stage 7 at 2, tip 11 at 1.\n";
    help(output);
    status();
    while (output) {
        std::string line;
        bool present = false, oversized = false;
        char character{};
        while (input.get(character)) {
            present = true;
            if (character == '\n') break;
            if (line.size() < 512) line.push_back(character); else oversized = true;
        }
        if (input.bad() || (!input.eof() && input.fail())) { errors << "Input stream failed.\n"; return 2; }
        if (!present) break;
        if (oversized) { output << "Refused: command exceeds 512 bytes.\n"; continue; }
        std::istringstream command(line);
        std::string verb, argument, extra;
        if (!(command >> verb)) continue;
        if ((verb == "status" || verb == "help" || verb == "quit") && !(command >> extra)) {
            if (verb == "quit") break;
            if (verb == "status") status(); else help(output);
            continue;
        }
        if (!(command >> argument) || (command >> extra)) { output << "Refused: use the listed commands.\n"; continue; }
        if (verb == "power" && (argument == "on" || argument == "off")) {
            powered = argument == "on";
            status();
            continue;
        }
        if ((verb == "guide" && (argument == "short" || argument == "long")) ||
            (verb == "coupler" && (argument == "slack" || argument == "tight"))) {
            if (powered) { output << "Refused: stop power before editing the guide or coupler.\n"; continue; }
            const bool proposed_guide = verb == "guide" ? argument == "long" : long_guide;
            const bool proposed_tight = verb == "coupler" ? argument == "tight" : tight;
            const auto plan = prepare(chain(proposed_guide, proposed_tight), state, rig, {{state.pin, false}, frame}, {});
            if (!std::holds_alternative<b::Hold>(plan)) output << "Refused: the proposed guide/coupler does not fit the retained state and frame.\n";
            else { long_guide = proposed_guide; tight = proposed_tight; status(); }
            continue;
        }
        I destination{};
        const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), destination);
        if (verb != "move" || parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || destination < -32 || destination > 32) {
            output << "Refused: move needs a whole destination from -32 through 32.\n";
            continue;
        }
        const auto plan = prepare(chain(long_guide, tight), state, rig, {{destination, powered}, frame}, {});
        if (const auto* refused = std::get_if<Refusal>(&plan)) {
            errors << "Fixture refused: " << error_name(refused->reason) << ".\n"; return 2;
        }
        if (const auto* blocked = std::get_if<slotted_workcell::Blocked>(&plan)) {
            const auto& contact = std::get<slotted_workcell::StationaryContact>(blocked->contact);
            output << "Frame " << contact.hit.obstacle << " blocks tip " << *contact.member << " at " << contact.hit.time.numerator
                   << '/' << contact.hit.time.denominator << "; ALL original positions retained.\n";
        } else if (const auto* held = std::get_if<b::Hold>(&plan)) {
            output << "Hold " << (held->reason == b::Stop::unpowered ? "unpowered" : "rest or guide stop") << ".\n";
        } else {
            const auto& step = std::get<Advance>(plan);
            state = step.next;
            if (step.limit) output << "Guide " << step.limit->id << " binds at " << step.limit->stop.at.numerator << '/' << step.limit->stop.at.denominator << ".\n";
            for (const auto& trace : step.traces) if (trace.motion)
                output << "Stage " << trace.id << " moves from " << trace.motion->begin.numerator << '/' << trace.motion->begin.denominator
                       << " through " << trace.motion->end.numerator << '/' << trace.motion->end.denominator << " of the original stroke.\n";
        }
        status();
    }
    if (!output) { errors << "Output stream failed.\n"; return 2; }
    return complete(state) ? 0 : 1;
}
}  // namespace factory::slotted_cascade
