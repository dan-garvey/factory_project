#include "factory/slotted_rocker_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/slotted_rocker.hpp"

#include <ostream>

namespace factory::slotted_rocker {
namespace g = mechanics;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "compact") { p.origin[0] = 8; p.radius = 6; p.slot_inner = 5; p.slot_outer = 19; }
    else if (name == "short-slot") p.slot_outer = 18;
    else if (name == "inner-miss") p.slot_inner = 11;
    else if (name == "shifted") p.origin[0] = 1;
    else if (name == "near-edge") p.origin[0] = g::maximum_coordinate - 2 * p.radius;
    else if (name != "standard" && name != "short-input") return {};
    return p;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: rocker_case <kit> slow|reverse|fast|stalled|off full|short\n"
               "Kits: standard, compact, short-slot, inner-miss, shifted, short-input, near-edge.\n"
               "Goal: complete finite slot contact over both rocking strokes, with crank speed magnitude 1/2.\n"
               "A real output shaft must reach fixed +Z readout (20,0,32). Standard and compact kits work.\n"
               "Near-pose output reverses at magnitude 1/2; far-pose output returns at magnitude 1/6.\n"
               "Constant physical input speed divides the strokes into 1/3 and 2/3 of a turn, without a held dwell.\n"
               "This is a declared centreline observation; complete pin/slot solids, ram, forces/contact, phase clock, time-varying graph and material/World adoption remain separate.\n";
        return finished(out);
    }
    if (args.size() != 3 || (args[2] != "full" && args[2] != "short")) { errors << "Choose a rocker kit, source and full|short output shaft.\n"; return 2; }
    auto p = kit(args[0]); auto scene = geared_cycle::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!p || !scene) { errors << "Unknown rocker kit or source.\n"; return 2; }
    if (args[1] == "off") scene->sources.clear();
    g::Point old{}; for (const auto& part : scene->parts) if (part.id == "output") old = part.center;
    for (auto& part : scene->parts) for (std::size_t i = 0; i < 3; ++i) part.center[i] += p->origin[i] - old[i] - (i == 2 ? 20 : 0);
    auto endpoint = p->origin, middle = p->origin; endpoint[2] -= 4; middle[2] -= 12;
    scene->parts.push_back({"crank-input", g::Kind::hub, endpoint, g::Axis::z});
    scene->parts.push_back({"input-shaft", g::Kind::shaft, middle, g::Axis::z, 0, args[0] == "short-input" ? 1 : 8});
    const auto native = g::evaluate(scene->parts, scene->sources);
    if (!native.accepted()) { errors << "Native input refused.\n"; return 2; }
    const auto input = native.motion.at("crank-input");
    out << "Crank " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << ".\n";
    const auto near = sample(*p, {}, input);
    if (const auto* e = std::get_if<Refusal>(&near)) { errors << "Current pose refused: " << error_name(e->reason) << ".\n"; return 2; }
    if (!std::get<Sample>(near).slot_fits) { out << "Goal unfinished: current pin misses the finite slot.\n"; return finished(out); }
    const auto inspection = inspect(*p);
    if (const auto* e = std::get_if<Refusal>(&inspection)) { errors << "Whole stroke refused: " << error_name(e->reason) << ".\n"; return 2; }
    const auto& cycle = std::get<Cycle>(inspection);
    out << "Complete radial range " << cycle.minimum_distance << ".." << cycle.maximum_distance << ".\n";
    if (!cycle.slot_covers) { out << "Goal unfinished: a fitting near pose misses the complete return stroke.\n"; return finished(out); }
    const auto far = sample(*p, {-1, 0, 1}, input);
    if (const auto* e = std::get_if<Refusal>(&far)) { errors << "Return pose refused: " << error_name(e->reason) << ".\n"; return 2; }
    if (input.state != g::MotionState::rotating) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no native output is supplied.\n";
        return finished(out);
    }
    const g::Point target{20, 0, 32}; middle = cycle.pivot; middle[2] = 20;
    const std::vector<g::Part> output{{"lever", g::Kind::hub, cycle.pivot, g::Axis::z},
        {"output-shaft", g::Kind::shaft, middle, g::Axis::z, 0, args[2] == "full" ? 12 : 1}, {"readout", g::Kind::hub, target, g::Axis::z}};
    std::array<g::Motion, 2> readouts{};
    const std::array<Sample, 2> poses{std::get<Sample>(near), std::get<Sample>(far)};
    for (std::size_t i = 0; i < poses.size(); ++i) {
        const auto observation = g::evaluate(output, {{"lever", poses[i].constraint->output.rate}});
        if (!observation.accepted()) { errors << "Native output refused.\n"; return 2; }
        readouts[i] = observation.motion.at("readout");
        out << (i == 0 ? "Near" : "Far") << " readout " << g::motion_state_name(readouts[i].state) << ' ' << readouts[i].rate.numerator << '/' << readouts[i].rate.denominator << ".\n";
    }
    const bool speed = input.state == g::MotionState::rotating && (input.rate == Fraction{1, 2} || input.rate == Fraction{-1, 2});
    const bool readings = readouts[0].state == g::MotionState::rotating && readouts[1].state == g::MotionState::rotating &&
        readouts[0].rate == Fraction{-input.rate.numerator, input.rate.denominator} && readouts[1].rate == Fraction{input.rate.numerator, input.rate.denominator * 3};
    out << (speed && readings ? "Goal matched: full slot, opposite rocking senses and unequal return.\n" : "Goal unfinished: connected near/far readouts and input speed magnitude 1/2 are required.\n");
    return finished(out);
}
}  // namespace factory::slotted_rocker
