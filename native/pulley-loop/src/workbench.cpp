#include "factory/pulley_loop_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/pulley_loop.hpp"

#include <optional>
#include <ostream>

namespace factory::pulley_loop {
namespace g = mechanics;
namespace c = clearance;
namespace p = pulley_pair;
namespace k = geared_cycle;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile result;
    if (name == "wide" || name == "short-input" || name == "shifted" || name == "bad-observation" || name == "near-edge" || name == "belt-edge") {
        for (auto& pulley : result.transmission.pulleys) pulley.radius = 6;
        if (name == "shifted") for (auto& pulley : result.transmission.pulleys) pulley.center[1] = 1;
        if (name == "near-edge") { result.transmission.pulleys[0].center[0] = g::maximum_coordinate - 20; result.transmission.pulleys[1].center[0] = g::maximum_coordinate; }
        if (name == "belt-edge") for (auto& pulley : result.transmission.pulleys) pulley.center[1] = g::maximum_coordinate - 6;
    } else if (name == "raised") for (auto& pulley : result.transmission.pulleys) pulley.center[2] = 16;
    else if (name == "rerouted") result.transmission.pulleys[0].center[0] = 40;
    else if (name == "crossed") result.transmission.layout = p::Layout::crossed;
    else if (name == "unequal") result.transmission.pulleys[1].radius = 3;
    else if (name != "tight") return {};
    return result;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
void refusal(std::ostream& out, const Refusal& error) {
    out << error_name(error.reason);
    if (error.parent_error) out << '/' << p::error_name(error.parent_error->reason);
    if (error.geometry_error) out << '/' << c::error_name(*error.geometry_error);
    out << ".\n";
}
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: loop_case <kit> slow|reverse|fast|stalled|off full|short\n"
               "Kits: tight, wide, raised, rerouted, shifted, short-input, crossed, unequal, bad-observation, near-edge, belt-edge.\n"
               "Goal: clear service column (9,2,6)..(11,4,10) and supply +1/2 about fixed +Z readout (20,0,32).\n"
               "Widen the loop, raise it or move the input to the other side. These trade footprint, height and source placement.\n"
               "The complete finite path has two straight straps and two outward semicircular caps, with a usable empty interior.\n"
               "Strict inner/outer/axial tangency is clear. Enclosing boxes do not fill the loop or certify its path.\n"
               "Actual native source/input/output shafts still decide power. Ideal taut no-slip rates come from the published pulley adapter.\n"
               "Crossed/unequal belt corridors are unsupported. A clear declared corridor establishes no manufactured belt, groove, housing, force/contact, tension or slip behavior.\n"
               "No length/stock, live phase/graph/clock, material or World adoption, or full mechanism-body acceptance is implied.\n";
        return finished(out);
    }
    if (args.size() != 3 || (args[2] != "full" && args[2] != "short")) { errors << "Choose a loop kit, source and full|short output shaft.\n"; return 2; }
    const auto selected = kit(args[0]); auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown loop kit or source.\n"; return 2; }
    if (args[1] == "off") source->sources.clear();
    const auto& input_pulley = selected->transmission.pulleys[0];
    g::Point old_output{};
    for (const auto& part : source->parts) if (part.id == "output") old_output = part.center;
    for (auto& part : source->parts) for (std::size_t i = 0; i < 3; ++i) part.center[i] += input_pulley.center[i] - old_output[i] - (i == 2 ? 20 : 0);
    auto endpoint = input_pulley.center, midpoint = input_pulley.center; endpoint[2] -= 4; midpoint[2] -= 12;
    source->parts.push_back({"loop-input", g::Kind::hub, endpoint, g::Axis::z});
    source->parts.push_back({"input-drive", g::Kind::shaft, midpoint, g::Axis::z, 0, args[0] == "short-input" ? 1 : 8});
    const auto native_source = g::evaluate(source->parts, source->sources);
    if (!native_source.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = native_source.motion.at("loop-input");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << ".\n";
    std::vector<c::Obstacle> obstacles{{71, {{9, 2, 6}, {11, 4, 10}}}};
    if (args[0] == "bad-observation") obstacles.push_back({0, {{100, 100, 100}, {101, 101, 101}}});
    const auto candidate = inspect(*selected, obstacles);
    if (const auto* error = std::get_if<Refusal>(&candidate)) {
        if (error->reason == Error::unsupported_layout) { out << "Goal unfinished: "; refusal(out, *error); return finished(out); }
        errors << "Loop query refused: "; refusal(errors, *error); return 2;
    }
    const auto& geometry = std::get<Geometry>(candidate);
    if (geometry.contact) { out << "Goal unfinished: belt corridor overlaps service obstacle " << geometry.contact->obstacle << ".\n"; return finished(out); }
    out << "Complete finite loop path is clear; its interior remains available.\n";
    std::vector<p::Drive> drives;
    if (input.state == g::MotionState::rotating || input.state == g::MotionState::stopped) drives.push_back({input_pulley.id, input.rate});
    const auto transmission = p::evaluate(selected->transmission, drives);
    if (const auto* error = std::get_if<p::Refusal>(&transmission)) { errors << "Native pitch observation refused: " << p::error_name(error->reason) << ".\n"; return 2; }
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no loop output is supplied.\n"; return finished(out);
    }
    const auto& output_pulley = selected->transmission.pulleys[1]; const auto output = std::get<p::Evaluation>(transmission).motion[1];
    const g::Point target{20, 0, 32};
    midpoint = output_pulley.center; midpoint[2] = (output_pulley.center[2] + target[2]) / 2;
    const auto half_span = args[2] == "full" ? (target[2] - output_pulley.center[2]) / 2 : 1;
    const std::vector<g::Part> parts{{"loop-out", g::Kind::hub, output_pulley.center, g::Axis::z},
        {"output-shaft", g::Kind::shaft, midpoint, g::Axis::z, 0, half_span}, {"readout", g::Kind::hub, target, g::Axis::z}};
    const auto native_output = g::evaluate(parts, {{"loop-out", output.rate}});
    if (!native_output.accepted()) { errors << "Native output shaft refused.\n"; return 2; }
    const auto readout = native_output.motion.at("readout");
    out << "Readout " << g::motion_state_name(readout.state) << ' ' << readout.rate.numerator << '/' << readout.rate.denominator << ".\n";
    out << (readout.state == g::MotionState::rotating && readout.rate == g::Rate{1, 2} ? "Goal matched: finite corridor and ideal pitch kinematics.\n" : "Goal unfinished: fixed readout requires +1/2 about +Z.\n");
    return finished(out);
}
}  // namespace factory::pulley_loop
