#include "factory/slotted_shuttle.hpp"
#include "factory/slotted_shuttle_workbench.hpp"

#include <array>
#include <iostream>
#include <sstream>
#include <string>

namespace factory::slotted_shuttle {
namespace b = slotted_bank;
namespace {
clearance::Box box(int x, int lane) { return {{x, lane, 0}, {x + 1, lane + 1, 1}}; }
bool original_home(const State& state) {
    return state.bank.pin == 0 && state.bank.followers[0].position == 0 && state.bank.followers[1].position == 0;
}
}  // namespace

int play(std::istream& input, std::ostream& output, std::ostream& errors) {
    State state{{0, {{3, 0}, {7, 0}}}, 0};
    std::string layout = "spread", slots = "delayed", stop_set = "short", frame = "off";
    bool powered = true, matched = false;
    Profile profile;
    const auto status = [&] {
        output << "Pin " << state.bank.pin << "; A " << state.bank.followers[0].position
               << "; B " << state.bank.followers[1].position << "; next " << state.cursor
               << "=" << profile.stops[state.cursor] << "; layout " << layout << "; slots " << slots
               << "; stops " << stop_set << "; power " << (powered ? "on" : "off") << ". Frame " << frame << ".\n";
    };
    const auto trace = [&](std::size_t bound, bool adopt) {
        const std::array<b::Link, 2> links{{{3, {0, 6, 2, 1}}, {7, {0, 6, 1, slots == "matched" ? 1 : 3}}}};
        const slotted_clearance::Rig rig{mechanics::Axis::x, box(0, -3),
            {{3, box(0, 0)}, {7, box(layout == "spread" ? 4 : 2, layout == "raised" ? 3 : 0)}}};
        const std::array<slotted_pairs::Pair, 1> pairs{{{3, 7}}};
        std::vector<clearance::Obstacle> stationary;
        if (frame != "off") stationary.push_back({11, box(frame == "near" ? 5 : 8, 0)});
        const auto report = inspect(profile, links, state, rig, pairs, bound, powered, stationary);
        if (adopt) {
            for (std::size_t index = 1; index < report.path.size(); ++index) {
                state = report.path[index];
                status();
            }
        } else output << "Projection only; no positions or next stop adopted.\n";
        if (report.hold) {
            output << "Hold " << stop_name(report.hold->reason) << "; bank and next stop retained at this hold.\n";
            if (report.hold->conflict) output << "Pair contact at " << report.hold->conflict->time.numerator
                << '/' << report.hold->conflict->time.denominator << ".\n";
            if (report.hold->stationary_contact) {
                const auto& contact = *report.hold->stationary_contact;
                output << "Frame " << contact.hit.obstacle << " blocks ";
                if (contact.member) output << "follower " << *contact.member;
                else output << "pin";
                output << " at " << contact.hit.time.numerator << '/' << contact.hit.time.denominator << ".\n";
            }
            if (report.hold->limit) output << "Limit " << report.hold->limit->id << "; target not reached.\n";
        } else if (report.refusal) output << "Refused: " << error_name(report.refusal->reason) << ".\n";
        else if (report.loop) {
            output << "Recurring interval: prefix " << report.loop->begin << ", period " << report.loop->period
                   << "; pin " << (report.loop->pin_moves ? "moves" : "parked") << ".\n";
            if (!report.loop->unmoved_followers.empty()) {
                output << "Parked within this loop:";
                for (const auto id : report.loop->unmoved_followers) output << ' ' << id;
                output << ". Startup motion does not count.\n";
            } else if (report.loop->pin_moves) {
                output << "BOTH retained followers move within this loop. No material work is claimed.\n";
                if (adopt) matched = true;
            }
        } else output << "Bound reached; no recurrence established.\n";
        if (adopt && matched) output << "Matched: a recurring interval moves the pin and both original followers.\n";
    };
    output << "Make BOTH followers move on the repeated cycle, not just during startup.\n"
              "The spacious delayed rig's short stroke eventually parks B. Long stops or matched clearances can help.\n"
              "An optional near frame also blocks the spread guide; raise that guide or use the farther frame.\n"
              "Commands: run 1..64, inspect, power on|off, stops short|long|overtravel|idle,\n"
              "layout crossed|spread|raised, slots delayed|matched, frame off|near|far, status, help, quit.\n";
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
        if ((verb == "quit" || verb == "status" || verb == "inspect" || verb == "help") && !(command >> extra)) {
            if (verb == "quit") break;
            if (verb == "status") status();
            else if (verb == "inspect") trace(16, false);
            else output << "Inspect predicts a bounded fixed-configuration trace. Run adopts each accepted native step.\n"
                           "A returned pin is insufficient: the full bank and next stop must recur, with BOTH followers moving.\n"
                           "Stop edits require power off and retain positions and cursor. Guides, slots and frames require all original members home.\n";
            continue;
        }
        if (verb == "run") {
            std::size_t count{};
            if (!(command >> count) || (command >> extra) || count == 0 || count > 64)
                output << "Refused: run requires 1..64.\n";
            else trace(count, true);
            continue;
        }
        if ((verb == "power" || verb == "stops" || verb == "layout" || verb == "slots" || verb == "frame") &&
            (command >> argument) && !(command >> extra)) {
            if (verb == "power" && (argument == "on" || argument == "off")) powered = argument == "on";
            else if (verb == "stops" && (argument == "short" || argument == "long" || argument == "overtravel" || argument == "idle")) {
                if (powered) { output << "Refused: power off before changing stops.\n"; continue; }
                stop_set = argument;
                profile.stops = {argument == "short" ? 4 : argument == "long" ? 5 : argument == "overtravel" ? 10 : 0, 0};
                matched = false;
            } else if ((verb == "layout" && (argument == "crossed" || argument == "spread" || argument == "raised")) ||
                       (verb == "slots" && (argument == "delayed" || argument == "matched")) ||
                       (verb == "frame" && (argument == "off" || argument == "near" || argument == "far"))) {
                if (!original_home(state)) {
                    output << "Refused: ALL original members must be home before changing "
                           << (verb == "frame" ? "frames.\n" : "guides or slots.\n");
                    continue;
                }
                if (verb == "layout") layout = argument;
                else if (verb == "slots") slots = argument;
                else frame = argument;
                matched = false;
            } else { output << "Refused: unknown configuration.\n"; continue; }
            status();
            continue;
        }
        output << "Refused: unknown or malformed command.\n";
    }
    if (!input.eof() && input.fail()) { errors << "Input stream failed.\n"; return 2; }
    return matched ? 0 : 1;
}
}  // namespace factory::slotted_shuttle
