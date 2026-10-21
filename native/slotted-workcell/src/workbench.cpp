#include "factory/slotted_workcell.hpp"
#include "factory/slotted_workcell_workbench.hpp"

#include <array>
#include <iostream>
#include <sstream>
#include <string>

namespace factory::slotted_workcell {
namespace b = slotted_bank;
namespace {
using I = mechanics::Integer;
clearance::Box box(I x, I y) { return {{x, y, 0}, {x + 1, y + 1, 1}}; }
bool home(const b::State& state) {
    return state.pin == 0 && state.followers[0].position == 0 && state.followers[1].position == 0;
}
bool finished(const b::State& state) {
    return state.pin == 0 && state.followers[0].position == 2 && state.followers[1].position == 1;
}
}  // namespace

int play(std::istream& input, std::ostream& output, std::ostream& errors) {
    b::State state{0, {{3, 0}, {7, 0}}};
    std::string layout = "crossed", slots = "delayed", frame = "near";
    bool powered = true;
    const auto status = [&] {
        output << "Pin " << state.pin << "; A " << state.followers[0].position
               << "; B " << state.followers[1].position << "; layout " << layout
               << "; slots " << slots << "; frame " << frame << "; power " << (powered ? "on" : "off") << ".\n";
        if (finished(state)) output << "Matched: both original tools advanced and the common pin returned home.\n";
    };
    output << "Separate the moving tools AND clear the stationary frame. Goal: pin 0, A 2, B 1.\n"
              "Spreading the tools alone sends B through the near frame. Raise its guide or set that frame farther back.\n"
              "Commands: move -32..32, layout crossed|spread|raised, frame near|far, slots delayed|matched,\n"
              "power on|off, status, help, quit.\n";
    status();
    while (true) {
        std::string line;
        bool oversized = false, present = false;
        char character{};
        while (input.get(character)) {
            present = true;
            if (character == '\n') break;
            if (line.size() < 512) line.push_back(character);
            else oversized = true;
        }
        if (!present) break;
        if (oversized) { output << "Refused: command exceeds 512 bytes.\n"; continue; }
        std::istringstream command(line);
        std::string verb, argument, extra;
        if (!(command >> verb)) continue;
        if ((verb == "quit" || verb == "status" || verb == "help") && !(command >> extra)) {
            if (verb == "quit") break;
            if (verb == "status") status();
            else output << "A stroke must clear every declared stationary frame and every forbidden moving pair.\n"
                           "A collision keeps ALL original positions. Return every original member home before changing the arrangement.\n"
                           "The raised guide keeps the near frame; spreading plus a farther frame uses more space.\n";
            continue;
        }
        if (verb == "power" && (command >> argument) && !(command >> extra) &&
            (argument == "on" || argument == "off")) {
            powered = argument == "on";
            status();
            continue;
        }
        if ((verb == "layout" || verb == "frame" || verb == "slots") && (command >> argument) && !(command >> extra)) {
            const bool known = verb == "layout" ? argument == "crossed" || argument == "spread" || argument == "raised"
                : verb == "frame" ? argument == "near" || argument == "far" : argument == "delayed" || argument == "matched";
            if (!known) output << "Refused: unknown arrangement.\n";
            else if (!home(state)) output << "Refused: ALL original members must be home before an edit.\n";
            else {
                if (verb == "layout") layout = argument;
                else if (verb == "frame") frame = argument;
                else slots = argument;
                status();
            }
            continue;
        }
        I destination{};
        if (verb != "move" || !(command >> destination) || (command >> extra) || destination < -32 || destination > 32) {
            output << "Refused: unknown or malformed command.\n";
            continue;
        }
        const std::array<b::Link, 2> links{{{3, {0, 6, 2, 1}}, {7, {0, 6, 1, slots == "matched" ? 1 : 3}}}};
        const slotted_clearance::Rig rig{mechanics::Axis::x, box(0, -3),
            {{3, box(0, 0)}, {7, box(layout == "spread" ? 4 : 2, layout == "raised" ? 3 : 0)}}};
        const std::array<clearance::Obstacle, 1> obstacles{{{11, box(frame == "near" ? 5 : 6, 0)}}};
        const std::array<slotted_pairs::Pair, 1> pairs{{{3, 7}}};
        const auto plan = prepare(links, state, rig, {{destination, powered}, obstacles}, pairs);
        if (const auto* blocked = std::get_if<Blocked>(&plan)) {
            if (const auto* fixed = std::get_if<StationaryContact>(&blocked->contact)) {
                output << "Blocked ";
                if (fixed->member) output << "follower " << *fixed->member;
                else output << "pin";
                output << " by frame " << fixed->hit.obstacle << " at " << fixed->hit.time.numerator
                       << '/' << fixed->hit.time.denominator;
            } else {
                const auto& moving = std::get<MovingContact>(blocked->contact);
                output << "Blocked followers 3 and 7 at " << moving.time.numerator << '/' << moving.time.denominator;
            }
            output << "; all positions retained.\n";
        } else if (const auto* refused = std::get_if<Refusal>(&plan)) output << "Refused: " << error_name(refused->reason) << ".\n";
        else if (const auto* advancing = std::get_if<b::Advance>(&plan)) {
            state = advancing->next;
            output << "Admitted complete bank proposal.\n";
            if (advancing->limit) output << "Limit " << advancing->limit->id << ".\n";
        } else {
            const auto& hold = std::get<b::Hold>(plan);
            output << "Hold " << (hold.reason == b::Stop::unpowered ? "unpowered" : "rest or limit")
                   << "; all positions retained.\n";
        }
        status();
    }
    if (!input.eof() && input.fail()) { errors << "Input stream failed.\n"; return 2; }
    return finished(state) ? 0 : 1;
}
}  // namespace factory::slotted_workcell
