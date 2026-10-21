#include "factory/geneva_drive_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/geneva_drive.hpp"

#include <optional>
#include <ostream>

namespace factory::geneva_drive {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "compact") { p.origin[0] = 8; p.radius = 6; p.slot_inner = 5; p.slot_outer = 11; }
    else if (name == "short-slot") p.slot_outer = 17;
    else if (name == "inner-miss") p.slot_inner = 11;
    else if (name == "no-lock") p.dwell_lock = false;
    else if (name == "shifted") p.origin[0] = 1;
    else if (name == "near-edge") p.origin[0] = g::maximum_coordinate - 2 * p.radius;
    else if (name != "standard" && name != "short-input" && name != "bad-slot") return {};
    return p;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: geneva_case <kit> slow|reverse|fast|stalled|off full|short\n"
               "Kits: standard, compact, short-slot, inner-miss, no-lock, shifted, short-input, bad-slot, near-edge.\n"
               "Goal: a complete finite six-slot engagement and declared locked dwell, with input speed magnitude 1/2.\n"
               "The wheel axis stays at (20,0,8); an actual native shaft must reach fixed +Z readout (20,0,32).\n"
               "Either input sense works. Standard and compact kits trade crank location, radius and radial slot length.\n"
               "Observe the mid-index readout, then require the whole-slot certificate. Output is intermittent, not constant speed.\n"
               "A constant-angular-input turn has 1/3 indexing and 2/3 dwell; a withdrawn pin needs the declared lock to hold the wheel.\n"
               "One caller owns the physical circle frame and its slot identity. Exact irrational boundary rays are never rounded into the rational chart.\n"
               "Native source/rates and real shaft connectivity remain explicit. No body/cam/roller clearance, force/contact, phase clock, graph, material or World adoption is established.\n";
        return finished(out);
    }
    if (args.size() != 3 || (args[2] != "full" && args[2] != "short")) { errors << "Choose a Geneva kit, source and full|short output shaft.\n"; return 2; }
    const auto selected = kit(args[0]); auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown Geneva kit or source.\n"; return 2; }
    if (args[1] == "off") source->sources.clear();
    g::Point old_output{};
    for (const auto& part : source->parts) if (part.id == "output") old_output = part.center;
    // These terminal kits share a proper +Z/+X mounting; model tests qualify
    // the other five frames. The actual input hub is behind the pin plane.
    for (auto& part : source->parts) for (std::size_t i = 0; i < 3; ++i) part.center[i] += selected->origin[i] - old_output[i] - (i == 2 ? 20 : 0);
    auto endpoint = selected->origin, midpoint = selected->origin; endpoint[2] -= 4; midpoint[2] -= 12;
    source->parts.push_back({"geneva-input", g::Kind::hub, endpoint, g::Axis::z});
    source->parts.push_back({"input-drive", g::Kind::shaft, midpoint, g::Axis::z, 0, args[0] == "short-input" ? 1 : 8});
    const auto supplied = g::evaluate(source->parts, source->sources);
    if (!supplied.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = supplied.motion.at("geneva-input");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << ".\n";
    Frame frame; if (args[0] == "bad-slot") frame.slot = 6;
    const auto reading = sample(*selected, frame, input);
    if (const auto* error = std::get_if<Refusal>(&reading)) { errors << "Current frame refused: " << error_name(error->reason) << ".\n"; return 2; }
    const auto& current = std::get<Sample>(reading);
    out << "Mid-index radial slot fit " << (current.radial_fits ? "yes" : "no") << "; wheel axis (" << current.wheel[0] << ',' << current.wheel[1] << ',' << current.wheel[2] << ").\n";
    if (!current.constraint) { out << "Goal unfinished: pin misses the finite radial slot.\n"; return finished(out); }
    const auto candidate = inspect(*selected);
    if (const auto* error = std::get_if<Refusal>(&candidate)) { errors << "Cycle refused: " << error_name(error->reason) << ".\n"; return 2; }
    const auto& cycle = std::get<Cycle>(candidate);
    out << "Whole active radial range squared: " << cycle.minimum_radius_squared << " to " << cycle.maximum_radius_squared << ".\n";
    if (!cycle.slot_covers) { out << "Goal unfinished: finite slot misses the full active radial range despite its fitting midpoint.\n"; return finished(out); }
    if (!selected->dwell_lock) { out << "Goal unfinished: missing dwell lock leaves the inactive wheel free.\n"; return finished(out); }
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no native readout is supplied.\n"; return finished(out);
    }
    const g::Point target{20, 0, 32}; midpoint = current.wheel; midpoint[2] = (current.wheel[2] + target[2]) / 2;
    const auto half_span = args[2] == "full" ? (target[2] - current.wheel[2]) / 2 : 1;
    const std::vector<g::Part> parts{{"geneva-out", g::Kind::hub, current.wheel, g::Axis::z},
        {"output-shaft", g::Kind::shaft, midpoint, g::Axis::z, 0, half_span}, {"readout", g::Kind::hub, target, g::Axis::z}};
    const auto native_output = g::evaluate(parts, {{"geneva-out", current.constraint->output.rate}});
    if (!native_output.accepted()) { errors << "Native output shaft refused.\n"; return 2; }
    const auto readout = native_output.motion.at("readout");
    out << "Actual MID-INDEX readout " << g::motion_state_name(readout.state) << ' ' << readout.rate.numerator << '/' << readout.rate.denominator << "; no constant output is claimed.\n";
    const auto dwell = sample(*selected, {{0, 1, 1}, frame.slot}, input);
    if (const auto* error = std::get_if<Refusal>(&dwell)) { errors << "Dwell frame refused: " << error_name(error->reason) << ".\n"; return 2; }
    out << "Declared locked dwell output " << g::motion_state_name(std::get<Sample>(dwell).constraint->output.state) << "; 1/6 index per input turn, with 2/3 locked dwell.\n";
    const bool speed = input.rate == Fraction{1, 2} || input.rate == Fraction{-1, 2};
    const bool midpoint_rate = readout.state == g::MotionState::rotating && (readout.rate == Fraction{1, 2} || readout.rate == Fraction{-1, 2});
    out << (speed && midpoint_rate ? "Goal matched: finite index and declared locked dwell.\n" : "Goal unfinished: connected mid-index readout and input speed magnitude 1/2 are required.\n");
    return finished(out);
}
}  // namespace factory::geneva_drive
