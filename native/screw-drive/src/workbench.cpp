#include "factory/screw_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/screw_drive.hpp"

#include <algorithm>
#include <charconv>
#include <istream>
#include <ostream>
#include <sstream>

namespace factory::screw_drive {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
Profile kit(std::string_view name) {
    const bool fine = name == "fine";
    return {fine ? 2 : 1, {{1, {0, 0, 0}, g::Axis::x, fine ? 1 : 2},
                           {2, {9, 0, 0}, g::Axis::x, name == "coarse" ? -6 : -3}}};
}
std::optional<g::Motion> drive(std::string_view name) {
    const auto scene = k::fixture(name);
    if (!scene) return std::nullopt;
    const auto result = g::evaluate(scene->parts, scene->sources);
    if (!result.accepted()) return std::nullopt;
    return result.motion.at("output");
}
bool aligned(const std::vector<NutPose>& poses) {
    const auto first = std::find_if(poses.begin(), poses.end(), [](const auto& pose) { return pose.id == 1; });
    const auto second = std::find_if(poses.begin(), poses.end(), [](const auto& pose) { return pose.id == 2; });
    return first != poses.end() && second != poses.end() && first->position[0] == Fraction{2, 1} && second->position[0] == Fraction{3, 1};
}
void help(std::ostream& out) {
    out << "Usage: screw_workbench play | list\n"
           "Commands: tick <1..64>; kit fine|coarse|mixed; drive slow|fast|reverse|stalled; power on|off; status; help; quit.\n"
           "Match the two original tip positions to fixed datum faces 2 and 3.\n"
           "Replace the screw pair only at home; end stops preserve partial-tick travel.\n"
           "This is a point-tip alignment fixture, not force or part custody.\n";
}
void show(const Profile& profile, Turns turns, const std::vector<NutPose>& poses, std::string_view name,
          std::string_view source, bool powered, std::ostream& out) {
    out << "Turns " << turns.numerator << '/' << turns.denominator << "; limit " << profile.limit_turns
        << "; kit " << name << "; drive " << source << "; power " << (powered ? "on" : "off") << ".\n";
    for (const auto& pose : poses) out << "Tip " << pose.id << " at " << pose.position[0].numerator << '/' << pose.position[0].denominator << ".\n";
    out << (aligned(poses) ? "Aligned: both original tips match datum faces 2 and 3.\n"
                           : "Unfinished: choose compatible leads and move the same spindle.\n");
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

int workbench(std::span<const std::string_view> args, std::istream& input,
              std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) { help(out); return out ? 0 : 2; }
    if (args.size() != 1 || args[0] != "play") { errors << "Choose screw_workbench play or list.\n"; return 2; }
    std::string name = "mixed", source = "slow";
    auto profile = kit(name);
    Turns turns;
    auto current = std::get<std::vector<NutPose>>(sample(profile, turns));
    bool powered{true};
    help(out);
    show(profile, turns, current, name, source, powered, out);
    std::string line;
    while (out) {
        const auto read_result = read(input, line);
        if (read_result == Read::failed) { errors << "Input failed.\n"; return 2; }
        if (read_result == Read::end) return aligned(current) ? 0 : 1;
        if (read_result == Read::too_long) { out << "Refused: command exceeds 512 bytes.\n"; continue; }
        std::istringstream command(line);
        std::string verb, argument, extra;
        if (!(command >> verb)) continue;
        if (verb == "quit" && !(command >> extra)) return aligned(current) ? 0 : 1;
        if (verb == "status" && !(command >> extra)) { show(profile, turns, current, name, source, powered, out); continue; }
        if (verb == "help" && !(command >> extra)) { help(out); continue; }
        if (!(command >> argument) || (command >> extra)) { out << "Refused: use the listed commands.\n"; continue; }
        if (verb == "kit" && (argument == "fine" || argument == "coarse" || argument == "mixed")) {
            if (turns.numerator != 0) { out << "Refused: return the same spindle home before replacing screws.\n"; continue; }
            name = argument;
            profile = kit(name);
            current = std::get<std::vector<NutPose>>(sample(profile, turns));
            show(profile, turns, current, name, source, powered, out);
            continue;
        }
        if (verb == "drive" && drive(argument)) {
            source = argument;
            show(profile, turns, current, name, source, powered, out);
            continue;
        }
        if (verb == "power" && (argument == "on" || argument == "off")) {
            powered = argument == "on";
            show(profile, turns, current, name, source, powered, out);
            continue;
        }
        if (verb != "tick") { out << "Refused: use the listed commands.\n"; continue; }
        Integer ticks{};
        const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), ticks);
        if (parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || ticks < 1 || ticks > 64) {
            out << "Refused: tick needs a whole count from 1 through 64.\n";
            continue;
        }
        for (Integer tick = 0; tick < ticks; ++tick) {
            const auto mechanical = *drive(source);
            const auto rate = mechanical.state == g::MotionState::rotating ? mechanical.rate : Fraction{};
            out << "Native output " << g::motion_state_name(mechanical.state) << ' ' << mechanical.rate.numerator << '/' << mechanical.rate.denominator << ".\n";
            auto plan = prepare(profile, turns, {rate, powered});
            if (const auto* refusal = std::get_if<Refusal>(&plan)) { errors << "Fixture refused: " << error_name(refusal->reason) << ".\n"; return 2; }
            if (const auto* held = std::get_if<Hold>(&plan)) { out << "Hold " << stop_name(held->reason) << "; same turns and tips retained.\n"; break; }
            auto next = std::get<Advance>(std::move(plan));
            turns = next.next;
            current = std::move(next.poses);
            for (const auto& crossing : next.crossings) out << "Reached turn " << crossing.turn << " at " << crossing.at.numerator << '/' << crossing.at.denominator << ".\n";
            if (next.endstop) {
                out << "End " << (next.endstop->end == End::upper ? "upper" : "lower") << " at "
                    << next.endstop->at.numerator << '/' << next.endstop->at.denominator << "; held for the remaining tick.\n";
                break;
            }
        }
        show(profile, turns, current, name, source, powered, out);
    }
    return 2;
}
}  // namespace factory::screw_drive
