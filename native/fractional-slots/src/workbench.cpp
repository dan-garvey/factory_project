#include "factory/fractional_slots.hpp"
#include "factory/fractional_slots_workbench.hpp"

#include <array>
#include <charconv>
#include <istream>
#include <numeric>
#include <ostream>
#include <sstream>
#include <string>

namespace factory::fractional_slots {
namespace g = mechanics;
using I = g::Integer;
namespace {
clearance::Box box(I x, I y) { return {{x, y, 0}, {x + 1, y + 1, 1}}; }
bool finished(const State& state) {
    return state.pin == Coordinate{3, 2} && state.followers[0].position == Coordinate{1, 2};
}
Coordinate add(Coordinate a, Coordinate b) {
    // Only canonical fixture positions in [-4,5] and rates +/-{1,1/2,1/4}
    // reach this terminal helper. Arbitrary raw fractions enter prepare instead.
    const I scale = std::lcm(a.denominator, b.denominator);
    const I numerator = a.numerator * (scale / a.denominator) + b.numerator * (scale / b.denominator);
    const I divisor = std::gcd(numerator, scale);
    return {numerator / divisor, scale / divisor};
}
g::Result gearing(const std::string& gear, bool reverse) {
    const I teeth = gear == "direct" ? 8 : gear == "half" ? 16 : 32;
    const I distance = 8 + teeth;
    const std::vector<g::Part> parts{
        {"source", g::Kind::hub, {0, 0, 0}, g::Axis::z},
        {"source-shaft", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 1},
        {"source-gear", g::Kind::gear, {0, 0, 0}, g::Axis::z, 8},
        {"output", g::Kind::hub, {distance, 0, 0}, g::Axis::z},
        {"output-shaft", g::Kind::shaft, {distance, 0, 0}, g::Axis::z, 0, 1},
        {"output-gear", g::Kind::gear, {distance, 0, 0}, g::Axis::z, teeth},
    };
    return g::evaluate(parts, {{"source", {reverse ? 1 : -1, 1}}});
}
void help(std::ostream& output) {
    output << "Commands: gear direct|half|quarter, direction forward|reverse, power on|off,\n"
              "step 1..32, status, help, quit. Stop power before changing gear or direction.\n"
              "The native 8-tooth input drives an 8-, 16- or 32-tooth output: travel 1, 1/2 or 1/4 per step.\n"
              "The slot's front clearance is 1 and reverse clearance is 2. The fixed frame blocks tool positions above 1.\n"
              "Changing the drive keeps every original position; reversing first takes up the slot's free play.\n"
              "This is a finite exact calibration puzzle; rate-to-travel units are experimental.\n";
}
}  // namespace

int play(std::istream& input, std::ostream& output, std::ostream& errors) {
    State state{{0, 1}, {{7, {0, 1}}}};
    std::string gear = "direct";
    bool reverse = false, powered = true;
    const std::array<slotted_bank::Link, 1> links{{{7, {-2, 4, 2, 1}}}};
    const slotted_clearance::Rig rig{g::Axis::x, box(0, -3), {{7, box(0, 0)}}};
    const std::array<clearance::Obstacle, 1> obstacles{{{11, box(2, 0)}}};
    const auto status = [&] {
        const auto follower = state.followers[0].position;
        output << "Pin " << state.pin.numerator << '/' << state.pin.denominator << "; tool "
               << follower.numerator << '/' << follower.denominator << "; gear " << gear
               << "; direction " << (reverse ? "reverse" : "forward") << "; power " << (powered ? "on" : "off") << ".\n";
        if (finished(state)) output << "Matched: original pin 3/2 and tool 1/2 at their calibration marks.\n";
    };
    output << "Align the same pin at 3/2 and tool at 1/2. Coarse gearing misses the marks; the frame remains fixed.\n";
    help(output);
    status();
    while (output) {
        std::string line;
        bool oversized = false, present = false;
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
        if ((verb == "quit" || verb == "status" || verb == "help") && !(command >> extra)) {
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
        if ((verb == "gear" && (argument == "direct" || argument == "half" || argument == "quarter")) ||
            (verb == "direction" && (argument == "forward" || argument == "reverse"))) {
            if (powered) output << "Refused: stop power before changing the drive.\n";
            else {
                if (verb == "gear") gear = argument; else reverse = argument == "reverse";
                status();
            }
            continue;
        }
        I count{};
        const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), count);
        if (verb != "step" || parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || count < 1 || count > 32) {
            output << "Refused: use the listed commands; step needs a whole count from 1 through 32.\n";
            continue;
        }
        const auto derived = gearing(gear, reverse);
        if (!derived.accepted() || derived.motion.at("output").state != g::MotionState::rotating) {
            errors << "Native gear fixture failed.\n"; return 2;
        }
        const auto rate = derived.motion.at("output").rate;
        output << "Native output " << rate.numerator << '/' << rate.denominator << ".\n";
        for (I step = 0; step < count; ++step) {
            const auto plan = prepare(links, state, rig, {add(state.pin, rate), powered, obstacles}, {});
            if (const auto* refused = std::get_if<Refusal>(&plan)) {
                errors << "Fixture proposal refused: " << error_name(refused->reason) << ".\n"; return 2;
            }
            if (const auto* blocked = std::get_if<Blocked>(&plan)) {
                const auto& contact = std::get<slotted_workcell::StationaryContact>(blocked->contact);
                output << "Frame " << contact.hit.obstacle << " blocks tool " << *contact.member << " at "
                       << contact.hit.time.numerator << '/' << contact.hit.time.denominator << "; all original positions retained.\n";
                break;
            }
            if (const auto* hold = std::get_if<Hold>(&plan)) {
                output << "Hold " << (hold->reason == slotted_bank::Stop::unpowered ? "unpowered" : "rest or endstop")
                       << "; all original positions retained.\n";
                break;
            }
            const auto& advance = std::get<Advance>(plan);
            state = advance.next;
            if (advance.limit) output << "Follower " << advance.limit->id << " reached its travel limit.\n";
        }
        status();
    }
    if (!output) { errors << "Output stream failed.\n"; return 2; }
    return finished(state) ? 0 : 1;
}
}  // namespace factory::fractional_slots
