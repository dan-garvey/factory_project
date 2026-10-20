#include "factory/index_drive.hpp"

#include <array>
#include <charconv>
#include <istream>
#include <ostream>
#include <sstream>
#include <string>

namespace factory::index_drive {
namespace {
constexpr indexing::FaceMask required = 0x33;  // Original X+/X-/Z+/Z- faces.
void describe(const State& state, const Pose& pose, Observation observation, indexing::FaceMask marks, std::ostream& out) {
    out << "Phase " << state.phase.tooth << ": carrier " << mechanisms::stage_name(pose.carrier.stage)
        << " at " << pose.carrier.numerator << '/' << pose.carrier.denominator
        << "; wheel turn " << pose.wheel.numerator << '/' << pose.wheel.denominator
        << "; work window " << (pose.work_window ? "open" : "closed") << "; marks " << unsigned(marks)
        << "/51; power " << (observation.powered ? "on" : "off") << ".\nWheel stop axes:";
    for (const auto face : pose.wheel.from.positive_axes) out << ' ' << indexing::face_name(face);
    out << (pose.wheel.turning ? " (next interval turns).\n" : " (held).\n");
}
void help(std::ostream& out) {
    out << "Commands: tick 1..64; power on|off; block carrier|wheel|none; stamp; release; inspect; help; quit.\n"
           "The working stroke turns the wheel; carrier return holds its indexed stop.\n"
           "Mark the four original side faces at far dwell, then dock the carrier with the wheel home.\n";
}
}  // namespace

int play(int direction, std::istream& input, std::ostream& out, std::ostream& errors) {
    Profile profile;
    profile.direction = direction;
    State state;
    Pose pose;
    if (sample(profile, state, pose) != Error::none) { errors << "Choose direction 1 or -1.\n"; return 2; }
    Observation observation;
    indexing::FaceMask marks{};  // No copied live pose: Job views use sample().
    out << "Fixed-cycle index drive; original work tag 7.\n";
    help(out); describe(state, pose, observation, marks, out);
    for (unsigned lines = 0; lines < 512; ++lines) {
        if (!out) return 2;
        std::array<char, 257> buffer{};
        input.getline(buffer.data(), buffer.size());
        if (input.bad() || (input.fail() && !input.eof())) { errors << "Input failed or exceeded 256 characters.\n"; return 2; }
        if (input.gcount() == 0) return out ? 1 : 2;
        std::istringstream parser(buffer.data());
        std::string command, argument, extra;
        parser >> command >> argument >> extra;
        if (command.empty()) continue;
        if (!extra.empty()) { out << "Refused: too many arguments.\n"; continue; }
        if (command == "quit" && argument.empty()) return out ? 1 : 2;
        if (command == "help" && argument.empty()) { help(out); continue; }
        if (command == "power" && (argument == "on" || argument == "off")) observation.powered = argument == "on";
        else if (command == "block" && (argument == "none" || argument == "carrier" || argument == "wheel")) {
            observation.carrier_obstructed = argument == "carrier";
            observation.wheel_obstructed = argument == "wheel";
        } else if (command == "tick") {
            unsigned count{};
            const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), count);
            if (parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || count < 1 || count > 64) {
                out << "Refused: tick takes a count from one to 64.\n"; continue;
            }
            for (unsigned tick = 0; tick < count; ++tick) {
                const auto error = advance(profile, state, observation);
                if (error != Error::none) { out << "Drive held: " << error_name(error) << ".\n"; break; }
            }
        } else if (command == "stamp" && argument.empty()) {
            if (sample(profile, state, pose) != Error::none) return 2;
            if (!observation.powered || !pose.work_window) out << "Refused: stamping needs powered far dwell.\n";
            else {
                const indexing::Job view{7, pose.wheel.from, required, marks};
                auto next = view;
                const auto error = indexing::plan_stamp(view, indexing::Face::positive_x, next);
                if (error == indexing::Error::none) marks = next.marked;
                else out << "Refused: " << indexing::error_name(error) << ". Original marks retained.\n";
            }
        } else if (command == "release" && argument.empty()) {
            if (sample(profile, state, pose) != Error::none) return 2;
            if (pose.carrier.stage != mechanisms::Stage::dock) out << "Refused: dock the carrier before releasing.\n";
            else {
                const indexing::Job view{7, pose.wheel.from, required, marks};
                const auto error = indexing::release_ready(view);
                if (error == indexing::Error::none) {
                    out << "Solved: original tag 7 has all four marks; carrier docked and wheel home.\n";
                    return out ? 0 : 2;
                }
                out << "Refused: " << indexing::error_name(error) << ". Original tag retained.\n";
            }
        } else if (command != "inspect" || !argument.empty()) {
            out << "Refused: use help; no reset or replacement is available.\n"; continue;
        }
        if (sample(profile, state, pose) != Error::none) return 2;
        describe(state, pose, observation, marks, out);
    }
    errors << "The fixture input exceeded 512 lines.\n";
    return 2;
}
}  // namespace factory::index_drive
