#include "factory/oldham_pair_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/oldham_pair.hpp"

#include <optional>
#include <ostream>

namespace factory::oldham_pair {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile profile;
    if (name == "other-side") profile.input.center[0] = 16;
    else if (name == "compact") profile.disc_radius = 1;
    else if (name == "short-input") { profile.disc_radius = 1; profile.input_travel = 7; }
    else if (name == "short-output") { profile.disc_radius = 1; profile.output_travel = 7; }
    else if (name == "shifted") { profile.disc_radius = 1; profile.input.center[1] = 4; profile.output.center[1] = 4; }
    else if (name == "parallel-miss") profile.output.axis = g::Axis::x;
    else if (name == "gap") profile.output.center[2] = 1;
    else if (name == "half-grid") { profile.disc_radius = 1; profile.output.center[2] = 5; }
    else if (name != "wide") return {};
    return profile;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: oldham_case <kit> slow|reverse|fast|stalled|off full|short\n"
               "Kits: wide, compact, other-side, short-input, short-output, shifted, parallel-miss, gap, half-grid.\n"
               "Goal: +1/2 about the fixed +Z readout at (8,0,64), with a complete turn admitted.\n"
               "Two perpendicular sliding keys transfer 1:1 rotation between parallel offset shafts.\n"
               "Choose smaller disc radius or route the input on the other side of post 99.\n"
               "A fitting current pose or four clear quarter-turn stops does not prove a full turn.\n"
               "Disc spin is 1:1; its centre orbits the shaft midpoint twice per input revolution.\n"
               "Effective slot travel and the conservative circular-disc envelope are checked continuously.\n"
               "Half-grid is a native integer-proxy refusal, not a mechanical impossibility.\n"
               "Keys, grooves, flanges, housings, force/contact, phase/time and World adoption remain outside this ideal adapter.\n";
        return finished(out);
    }
    if (args.size() != 3 || (args[2] != "full" && args[2] != "short")) {
        errors << "Choose a kit, native source and full|short output shaft.\n";
        return 2;
    }
    const auto selected = kit(args[0]);
    auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown Oldham kit or source.\n"; return 2; }
    if (args[1] == "off") source->sources.clear();
    g::Point original_output{};
    for (const auto& part : source->parts) if (part.id == "output") original_output = part.center;
    // Move the actual source hubs, shafts and gears to the coupling input.
    // The adapter does not borrow a registered drive from a remote component.
    for (auto& part : source->parts) for (std::size_t axis = 0; axis < 3; ++axis)
        part.center[axis] += selected->input.center[axis] - original_output[axis];
    const auto supplied = g::evaluate(source->parts, source->sources);
    if (!supplied.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = supplied.motion.at("output");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator
        << " about +Z at (" << selected->input.center[0] << ',' << selected->input.center[1] << ',' << selected->input.center[2] << ").\n";
    const auto reading = sample(*selected, {1, 1}, input);
    if (const auto* refusal = std::get_if<Refusal>(&reading)) {
        if (refusal->reason == Error::representation_limit || refusal->reason == Error::invalid_rate) {
            errors << "Current reading refused: " << error_name(refusal->reason) << ".\n";
            return 2;
        }
        out << "Goal unfinished: " << error_name(refusal->reason) << ".\n";
        return finished(out);
    }
    const auto& current = std::get<Sample>(reading);
    out << "Initial dial (1,1): disc centre (";
    for (std::size_t axis = 0; axis < 3; ++axis)
        out << (axis ? "," : "") << current.centre[axis].numerator << '/' << current.centre[axis].denominator;
    out << "); slide distances squared " << current.travel_squared[0].numerator << '/' << current.travel_squared[0].denominator << " and "
        << current.travel_squared[1].numerator << '/' << current.travel_squared[1].denominator << ".\n";
    const std::array<c::Obstacle, 1> obstacles{{{99, {{2, -8, 1}, {6, -6, 3}}}}};
    const auto candidate = prepare_turn(*selected, obstacles);
    if (const auto* refusal = std::get_if<Refusal>(&candidate)) {
        errors << "Complete turn refused: " << error_name(refusal->reason) << ". No turn is admitted.\n";
        return 2;
    }
    const auto& turn = std::get<Turn>(candidate);
    if (!turn.travel_fits[0] || !turn.travel_fits[1]) {
        out << "Goal unfinished: " << (!turn.travel_fits[0] ? "input" : "output") << " slot fits this pose but runs out of travel during a turn.\n";
        return finished(out);
    }
    if (turn.clearance.hit) {
        out << "Goal unfinished: complete disc envelope overlaps post " << turn.clearance.hit->obstacle
            << "; clear index stops are insufficient. No partial turn is admitted.\n";
        return finished(out);
    }
    out << "Complete turn: both finite slots and the circular-disc proxy clear.\n";
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no output drive is admitted.\n";
        return finished(out);
    }
    const g::Point target{8, 0, 64};
    auto centre = selected->output.center;
    centre[2] = (target[2] + selected->output.center[2]) / 2;
    const auto half_span = args[2] == "short" ? 1 : (target[2] - selected->output.center[2]) / 2;
    const std::vector<g::Part> parts{
        {"coupling-out", g::Kind::hub, selected->output.center, g::Axis::z},
        {"readout-shaft", g::Kind::shaft, centre, g::Axis::z, 0, half_span},
        {"readout", g::Kind::hub, target, g::Axis::z},
    };
    const auto output = g::evaluate(parts, {{"coupling-out", current.rotation[2].rate}});
    if (!output.accepted()) { errors << "Native output shaft refused.\n"; return 2; }
    const auto readout = output.motion.at("readout");
    out << "Output shaft half-span " << half_span << "; readout " << g::motion_state_name(readout.state) << ' '
        << readout.rate.numerator << '/' << readout.rate.denominator << ".\n";
    out << (readout.state == g::MotionState::rotating && readout.rate == g::Rate{1, 2}
        ? "Goal matched.\n" : "Goal unfinished: require a connected readout rotating at +1/2 about +Z.\n");
    return finished(out);
}
}  // namespace factory::oldham_pair
