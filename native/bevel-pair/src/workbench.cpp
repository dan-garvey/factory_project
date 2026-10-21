#include "factory/bevel_pair_workbench.hpp"

#include "factory/bevel_pair.hpp"
#include "factory/geared_cycle_workbench.hpp"

#include <optional>
#include <ostream>

namespace factory::bevel_pair {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
struct Layout { Gear first, second; };
std::optional<Layout> layout(std::string_view name) {
    Layout pair{{7, {24, 32, 0}, g::Axis::x, 24}, {11, {0, 56, 0}, g::Axis::y, 24}};
    if (name == "low") { pair.first.center[1] = 0; pair.second.center[1] = 24; }
    else if (name == "lower") pair.second.center[1] = 8;
    else if (name == "reduction") pair = {{7, {60, 32, 0}, g::Axis::x, 12}, {11, {0, 20, 0}, g::Axis::y, 60}};
    else if (name == "skew") pair.second.center[2] = 1;
    else if (name == "pitch-miss") pair.second.center[1] = 55;
    else if (name == "parallel") pair.second.axis = g::Axis::x;
    else if (name != "upper") return {};
    return pair;
}
g::Point rotate(const g::Point& point, std::size_t shift) {
    g::Point result{};
    for (std::size_t axis = 0; axis < 3; ++axis) result[(axis + shift) % 3] = point[axis];
    return result;
}
k::Fixture source_fixture(std::string_view name, const Gear& input) {
    auto fixture = *k::fixture(name == "off" ? "slow" : name);
    if (name == "off") fixture.sources.clear();
    // Cyclic coordinate permutations are proper rotations, preserving signed
    // angular rates. A reflection or merely changing the axis label would not.
    const auto shift = (static_cast<std::size_t>(input.axis) + 1) % 3;
    g::Point old_output{};
    for (const auto& part : fixture.parts) if (part.id == "output") old_output = rotate(part.center, shift);
    for (auto& part : fixture.parts) {
        part.center = rotate(part.center, shift);
        part.axis = static_cast<g::Axis>((static_cast<std::size_t>(part.axis) + shift) % 3);
        for (std::size_t axis = 0; axis < 3; ++axis) part.center[axis] += input.center[axis] - old_output[axis];
    }
    return fixture;
}
void point(std::ostream& out, const g::Point& value) { out << '(' << value[0] << ',' << value[1] << ',' << value[2] << ')'; }
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: bevel_case upper|lower|reduction|low|skew|pitch-miss|parallel slow|reverse|fast|stalled|off full|short\n"
               "Goal: +1/2 about a fixed +Y readout at (0,64,0), above the y=0 floor.\n"
               "Choose a bevel mounting, actual native source gears and an output shaft.\n"
               "Upper and lower mountings trade direction and shaft length; reduction trades footprint for speed.\n"
               "Full spans both hubs; short leaves a disconnected shaft between them.\n"
               "Units are native pitch units. Ideal common-apex cones and conservative pitch envelopes\n"
               "do not model tooth profiles, housings, torque, contact response, phase or a live World.\n";
        return finished(out);
    }
    if (args.size() != 3 || (args[2] != "full" && args[2] != "short")) {
        errors << "Choose a mounting, source and full|short shaft.\n";
        return 2;
    }
    const auto pair = layout(args[0]);
    if (!pair || (args[1] != "off" && !k::fixture(args[1]))) {
        errors << "Unknown bevel mounting or source.\n";
        return 2;
    }
    const auto source = source_fixture(args[1], pair->first);
    const auto native_source = g::evaluate(source.parts, source.sources);
    if (!native_source.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = native_source.motion.at("output");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << " about +X at ";
    point(out, pair->first.center);
    out << ".\n";
    std::vector<Drive> drives;
    if (input.state == g::MotionState::rotating || input.state == g::MotionState::stopped) drives.push_back({pair->first.id, input.rate});
    const auto candidate = evaluate(pair->first, pair->second, drives);
    if (const auto* refusal = std::get_if<Refusal>(&candidate)) {
        out << "Goal unfinished: " << error_name(refusal->reason) << " (gear " << refusal->subject << ").\n";
        return finished(out);
    }
    const auto& result = std::get<Evaluation>(candidate);
    const std::array<c::Obstacle, 1> floor{{{99, {{-8192, -8192, -8192}, {8192, 0, 8192}}}}};
    for (std::size_t index = 0; index < 2; ++index) {
        const auto clearance = c::sweep(result.geometry.pitch_bounds[index], {}, floor);
        if (clearance.error != c::Error::none) { errors << "Floor query refused.\n"; return 2; }
        if (clearance.hit) {
            out << "Goal unfinished: gear " << result.geometry.gears[index].id << " pitch envelope overlaps floor " << clearance.hit->obstacle << ".\n";
            return finished(out);
        }
    }
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no output drive is admitted.\n";
        return finished(out);
    }
    out << "Common apex "; point(out, result.geometry.apex);
    out << "; pitch contact "; point(out, result.geometry.contact);
    out << "; second/first " << result.geometry.second_from_first.numerator << '/' << result.geometry.second_from_first.denominator << ".\n";
    const auto output = result.motion[1];
    out << "Bevel output: " << g::motion_state_name(output.state) << ' ' << output.rate.numerator << '/' << output.rate.denominator << " about +Y.\n";
    const g::Point target{0, 64, 0};
    const auto distance = target[1] - pair->second.center[1];
    const auto half_span = args[2] == "full" ? distance / 2 : 1;
    const g::Point midpoint{0, (target[1] + pair->second.center[1]) / 2, 0};
    const std::vector<g::Part> output_parts{
        {"bevel-out", g::Kind::hub, pair->second.center, g::Axis::y},
        {"output-shaft", g::Kind::shaft, midpoint, g::Axis::y, 0, half_span},
        {"readout", g::Kind::hub, target, g::Axis::y},
    };
    const auto transmission = g::evaluate(output_parts, {{"bevel-out", output.rate}});
    if (!transmission.accepted()) { errors << "Native output shaft refused.\n"; return 2; }
    const auto readout = transmission.motion.at("readout");
    out << "Output shaft half-span " << half_span << "; readout " << g::motion_state_name(readout.state) << ' ' << readout.rate.numerator << '/' << readout.rate.denominator << ".\n";
    out << (readout.state == g::MotionState::rotating && readout.rate == g::Rate{1, 2} ? "Goal matched.\n" : "Goal unfinished: readout must rotate at +1/2 about +Y.\n");
    return finished(out);
}
}  // namespace factory::bevel_pair
