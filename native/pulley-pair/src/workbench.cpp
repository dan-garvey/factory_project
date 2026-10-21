#include "factory/pulley_pair_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/pulley_pair.hpp"

#include <optional>
#include <ostream>

namespace factory::pulley_pair {
namespace g = mechanics;
namespace c = clearance;
namespace s = slider_crank;
namespace k = geared_cycle;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "crossed") p.layout = Layout::crossed;
    else if (name == "reduction") { p.pulleys[0].radius = 1; p.pulleys[1].radius = 5; }
    else if (name == "mirrored") p.pulleys[0].center[0] = 40;
    else if (name == "raised") for (auto& pulley : p.pulleys) pulley.center[2] = 16;
    else if (name == "low") for (auto& pulley : p.pulleys) pulley.center[2] = 0;
    else if (name == "wrong-size") p.pulleys[0].radius = 3;
    else if (name == "skew") p.pulleys[1].center[2] = 9;
    else if (name == "nonparallel") p.pulleys[1].axis = g::Axis::y;
    else if (name == "crowded") p.pulleys[1].center[0] = 4;
    else if (name == "shifted") for (auto& pulley : p.pulleys) pulley.center[1] = 1;
    else if (name == "too-far") p.pulleys[1].center[0] = maximum_separation + 1;
    else if (name == "near-edge") { p.pulleys[0].center[0] = g::maximum_coordinate - 20; p.pulleys[1].center[0] = g::maximum_coordinate; }
    else if (name != "open" && name != "short-input") return {};
    return p;
}
void coordinate(std::ostream& out, const Coordinate& value) {
    const auto rational = std::get<std::optional<g::Rate>>(s::rational_view(value));
    if (rational) out << rational->numerator << '/' << rational->denominator;
    else out << '(' << value.base << (value.branch == s::Branch::positive ? "+sqrt(" : "-sqrt(") << value.radicand << "))/" << value.denominator;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: pulley_case <kit> slow|reverse|fast|stalled|off full|short\n"
               "Kits: open, crossed, reduction, mirrored, raised, low, wrong-size, skew, nonparallel, crowded, shifted, too-far, short-input, near-edge.\n"
               "Goal: ideal pitch transmission +1/2 about the fixed +Z readout at (20,0,32), above the z=0 floor.\n"
               "Open routing keeps rotation sense; crossed routing reverses it. Reduction trades pulley sizes for source speed.\n"
               "Actual native source gears and an input shaft supply the first pulley; a separate real shaft must reach the readout.\n"
               "Exact tangent endpoints retain radicals without rounding. Bare separated ordinary gears remain disconnected.\n"
               "This goal is ideal taut no-slip pitch kinematics only. A crossed centreline is not physical belt-crossing admission.\n"
               "Loop bounds include empty interior and are not filled-belt collision shapes.\n"
               "Belt length/stock, tension, traction, slip/sag/creep, full solids/contact, phase, live graph/clock and World adoption remain outside scope.\n";
        return finished(out);
    }
    if (args.size() != 3 || (args[2] != "full" && args[2] != "short")) { errors << "Choose a pulley kit, source and full|short output shaft.\n"; return 2; }
    const auto selected = kit(args[0]);
    auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown pulley kit or source.\n"; return 2; }
    if (args[1] == "off") source->sources.clear();
    const auto& input_pulley = selected->pulleys[0];
    g::Point old_output{};
    for (const auto& part : source->parts) if (part.id == "output") old_output = part.center;
    // These CLI kits have the proper +Z/+X frame. General proper frames are
    // qualified by the component; neither a camera nor a remote hub grants power.
    for (auto& part : source->parts) for (std::size_t i = 0; i < 3; ++i) part.center[i] += input_pulley.center[i] - old_output[i] - (i == 2 ? 20 : 0);
    auto input_hub = input_pulley.center, input_midpoint = input_pulley.center;
    input_hub[2] -= 4; input_midpoint[2] -= 12;
    source->parts.push_back({"pulley-input", g::Kind::hub, input_hub, g::Axis::z});
    source->parts.push_back({"input-drive", g::Kind::shaft, input_midpoint, g::Axis::z, 0, args[0] == "short-input" ? 1 : 8});
    const auto native_source = g::evaluate(source->parts, source->sources);
    if (!native_source.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = native_source.motion.at("pulley-input");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << "; shaft ends behind the belt plane.\n";
    std::vector<Drive> drives;
    if (input.state == g::MotionState::rotating || input.state == g::MotionState::stopped) drives.push_back({input_pulley.id, input.rate});
    const auto candidate = evaluate(*selected, drives);
    if (const auto* refusal = std::get_if<Refusal>(&candidate)) {
        if (refusal->reason == Error::representation_limit || refusal->reason == Error::unsupported_result || refusal->reason == Error::native_refused) {
            errors << "Pulley observation refused: " << error_name(refusal->reason) << ".\n"; return 2;
        }
        out << "Goal unfinished: " << error_name(refusal->reason) << ".\n"; return finished(out);
    }
    const auto& result = std::get<Evaluation>(candidate);
    const std::array<c::Obstacle, 1> floor{{{99, {{-8192, -8192, -8192}, {8192, 8192, 0}}}}};
    for (const auto& bounds : result.geometry.pitch_bounds) {
        const auto query = c::sweep(bounds, {}, floor);
        if (query.error != c::Error::none) { errors << "Floor query refused.\n"; return 2; }
        if (query.hit) { out << "Goal unfinished: pitch envelope overlaps the floor.\n"; return finished(out); }
    }
    out << "One exact pitch strand: ";
    for (std::size_t side = 0; side < 2; ++side) {
        out << '('; coordinate(out, result.geometry.strands[0][side][0]); out << ','; coordinate(out, result.geometry.strands[0][side][1]); out << ") ";
    }
    out << "; straight length squared " << result.geometry.straight_span_squared << ".\n";
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no pulley output is supplied.\n"; return finished(out);
    }
    const auto& output_pulley = selected->pulleys[1]; const auto output = result.motion[1];
    out << "Ideal second/first " << result.geometry.second_from_first.numerator << '/' << result.geometry.second_from_first.denominator << "; output "
        << g::motion_state_name(output.state) << ' ' << output.rate.numerator << '/' << output.rate.denominator << ".\n";
    const g::Point target{20, 0, 32};
    auto midpoint = output_pulley.center; midpoint[2] = (output_pulley.center[2] + target[2]) / 2;
    const auto half_span = args[2] == "full" ? (target[2] - output_pulley.center[2]) / 2 : 1;
    const std::vector<g::Part> output_parts{
        {"pulley-out", g::Kind::hub, output_pulley.center, output_pulley.axis},
        {"output-shaft", g::Kind::shaft, midpoint, g::Axis::z, 0, half_span},
        {"readout", g::Kind::hub, target, g::Axis::z},
    };
    const auto native_output = g::evaluate(output_parts, {{"pulley-out", output.rate}});
    if (!native_output.accepted()) { errors << "Native output shaft refused.\n"; return 2; }
    const auto readout = native_output.motion.at("readout");
    out << "Readout " << g::motion_state_name(readout.state) << ' ' << readout.rate.numerator << '/' << readout.rate.denominator << ".\n";
    out << (readout.state == g::MotionState::rotating && readout.rate == g::Rate{1, 2} ? "Goal matched: ideal pitch kinematics only.\n" : "Goal unfinished: fixed readout requires +1/2 about +Z.\n");
    return finished(out);
}
}  // namespace factory::pulley_pair
