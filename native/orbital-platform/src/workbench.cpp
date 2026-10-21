#include "factory/orbital_platform_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/orbital_platform.hpp"

#include <optional>
#include <ostream>

namespace factory::orbital_platform {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "raised") p.origin[2] = 16;
    else if (name == "standard") {}
    else {
        p.radius = 1;
        if (name == "shifted") p.origin[1] = 8;
        else if (name == "wrong-span") p.spacing = 10;
        else if (name == "wrong-shaft") p.shaft = g::Axis::y;
        else if (name == "near-edge") p.origin[0] = g::maximum_coordinate - 13;
        else if (name != "compact" && name != "short-input" && name != "short-output") return {};
    }
    return p;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: orbital_case <kit> slow|reverse|fast|stalled|off\n"
               "Kits: standard, compact, raised, short-input, short-output, shifted, wrong-span, wrong-shaft, near-edge.\n"
               "Goal: declared guided branch, complete fixed-orientation tray clearance and +1/2 at (12,0,64) about +Z.\n"
               "A smaller orbit clears post 99; raising the larger orbit trades height for clearance.\n"
               "The long tray translates around a circle without rotating. Rotating-box clearance gives a different answer.\n"
               "All stationary boxes validate before the whole-circle existence result; no partial move or impact time is admitted.\n"
               "Both crank pins share one supplied direction. Collinear change points do not choose a bare linkage's branch.\n"
               "This fixture assumes guided same-phase retention; full crank/guide solids, forces and branch retention remain unestablished.\n"
               "Source and readout shafts terminate below/above the tray slab; neither borrows a remote unconnected rate.\n"
               "No live graph, phase/clock, material work, contact response or World adoption is inferred.\n";
        return finished(out);
    }
    if (args.size() != 2) { errors << "Choose an orbital kit and native source.\n"; return 2; }
    const auto selected = kit(args[0]);
    auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown orbital kit or source.\n"; return 2; }
    if (args[1] == "off") source->sources.clear();
    g::Point old_output{};
    for (const auto& part : source->parts) if (part.id == "output") old_output = part.center;
    const auto a = static_cast<std::size_t>(selected->shaft), u = static_cast<std::size_t>(selected->span), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    for (auto& part : source->parts) {
        const auto old = part.center;
        part.center = selected->origin;
        part.center[u] += old[0] - old_output[0];
        part.center[v] += handed * (old[1] - old_output[1]);
        part.center[a] += old[2] - old_output[2] - 20;
        part.axis = selected->shaft;  // Fixture's old +Z through a proper basis.
    }
    auto input_end = selected->origin, input_centre = selected->origin;
    input_end[a] -= 4; input_centre[a] -= 12;
    source->parts.push_back({"crank-input", g::Kind::hub, input_end, selected->shaft});
    source->parts.push_back({"input-drive", g::Kind::shaft, input_centre, selected->shaft, 0, args[0] == "short-input" ? 1 : 8});
    const auto supplied = g::evaluate(source->parts, source->sources);
    if (!supplied.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = supplied.motion.at("crank-input");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator
        << " about +" << "XYZ"[a] << "; input shaft ends four units behind the tray plane.\n";
    const auto reading = sample(*selected, {}, input);
    if (const auto* error = std::get_if<Refusal>(&reading)) { errors << "Pose refused: " << error_name(error->reason) << ".\n"; return 2; }
    const std::array<c::Obstacle, 1> obstacles{{{99, {{6, 2, 7}, {7, 3, 9}}}}};
    const auto candidate = inspect(*selected, obstacles);
    if (const auto* error = std::get_if<Refusal>(&candidate)) { errors << "Whole orbit refused: " << error_name(error->reason) << ".\n"; return 2; }
    const auto& setup = std::get<Setup>(candidate);
    if (setup.tray.contact) {
        out << "Goal unfinished: translating tray overlaps post " << setup.tray.contact->obstacle << " between the clear quarter-turn snapshots.\n";
        return finished(out);
    }
    out << "Whole orbit: the fixed-orientation tray clears post 99 for the declared guided branch.\n";
    if (selected->shaft != g::Axis::z) {
        out << "Goal unfinished: output shaft axis differs from the fixed +Z readout.\n";
        return finished(out);
    }
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no output drive is proposed.\n";
        return finished(out);
    }
    auto endpoint = setup.geometry.remote_axis;
    endpoint[2] += 4;  // Above the moving slab; the source ends below it.
    const g::Point target{12, 0, 64};
    auto centre = endpoint; centre[2] = (endpoint[2] + target[2]) / 2;
    const auto half_span = args[0] == "short-output" ? 1 : (target[2] - endpoint[2]) / 2;
    const std::vector<g::Part> parts{
        {"crank-output", g::Kind::hub, endpoint, g::Axis::z},
        {"output-drive", g::Kind::shaft, centre, g::Axis::z, 0, half_span},
        {"readout", g::Kind::hub, target, g::Axis::z},
    };
    const auto output = g::evaluate(parts, {{"crank-output", std::get<Sample>(reading).shafts[1].rate}});
    if (!output.accepted()) { errors << "Native output refused.\n"; return 2; }
    const auto readout = output.motion.at("readout");
    out << "Output shaft half-span " << half_span << "; readout " << g::motion_state_name(readout.state) << ' ' << readout.rate.numerator << '/' << readout.rate.denominator << ".\n";
    out << (readout.state == g::MotionState::rotating && readout.rate == g::Rate{1, 2}
        ? "Goal matched. Declared-branch tray geometry and native readout.\n" : "Goal unfinished: require a connected readout at +1/2 about +Z.\n");
    return finished(out);
}
}  // namespace factory::orbital_platform
