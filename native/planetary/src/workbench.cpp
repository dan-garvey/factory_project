#include "factory/planetary.hpp"
#include "factory/planetary_workbench.hpp"

#include <ostream>
#include <vector>

namespace factory::planetary {
namespace g = mechanics;
namespace {
std::optional<Port> port(std::string_view name) {
    for (const auto value : {Port::sun, Port::carrier, Port::ring}) if (name == port_name(value)) return value;
    return {};
}
std::optional<Profile> profile(std::string_view name) {
    if (name == "compact") return Profile{};
    if (name == "large-sun") return Profile{36, 18, 72};
    if (name == "mismatched") return Profile{24, 24, 71};
    if (name == "narrow") return Profile{254, 1, 256};
    return {};
}
bool condition(std::string_view name) {
    return name == "free" || name == "lock" || name == "unit" || name == "double" || name == "quarter" ||
           name == "two-thirds" || name == "reverse" || name == "stalled" || name == "off";
}
g::Result source(std::string_view name) {
    using I = g::Integer;
    const I input = name == "double" ? 48 : name == "quarter" ? 12 : 24;
    const I output = name == "quarter" ? 48 : name == "two-thirds" ? 36 : 24;
    const I distance = input + output;
    const std::vector<g::Part> parts{
        {"source", g::Kind::hub, {0, 0, 0}, g::Axis::z},
        {"source-shaft", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 1},
        {"source-gear", g::Kind::gear, {0, 0, 0}, g::Axis::z, input},
        {"output", g::Kind::hub, {distance, 0, 0}, g::Axis::z},
        {"output-shaft", g::Kind::shaft, {distance, 0, 0}, g::Axis::z, 0, 1},
        {"output-gear", g::Kind::gear, {distance, 0, 0}, g::Axis::z, output},
    };
    std::vector<g::Drive> drives{{"source", {name == "reverse" ? 1 : -1, 1}}};
    if (name == "stalled") drives.push_back({"output", {-1, 1}});
    if (name == "off") drives.clear();
    return g::evaluate(parts, drives);
}
void help(std::ostream& out) {
    out << "Usage: planetary_case <profile> <sun> <carrier> <ring> <readout> | list\n"
           "Profiles: compact (24/24/72), large-sun (36/18/72), mismatched (24/24/71), narrow (254/1/256).\n"
           "Conditions: free | lock | unit | double | quarter | two-thirds | reverse | stalled | off.\n"
           "Readout: sun | carrier | ring. Keep it free and infer exactly -1/3.\n"
           "Unit/double/quarter/two-thirds/reverse come from actual native spur gears. Lock is an explicit zero; off is unpowered, not locked.\n"
           "Ring teeth must equal sun + twice planet teeth; carrier-relative meshes determine the signed rates.\n"
           "Planet readback is ABSOLUTE spin; it includes carrier rotation.\n"
           "This is one ideal planet and bounded exact kinematics, without tooth-profile clearance, torque or World adoption.\n";
}
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) { help(out); return out ? 0 : 2; }
    if (args.size() != 5 || !profile(args[0]) || !port(args[4]) || !condition(args[1]) || !condition(args[2]) || !condition(args[3])) {
        errors << "Choose a listed profile, three port conditions and an external readout.\n"; return 2;
    }
    const auto selected = *profile(args[0]);
    const auto readout = *port(args[4]);
    if (args[1 + static_cast<std::size_t>(readout)] != "free") {
        errors << "Keep the measured output free; do not prescribe its answer.\n"; return 2;
    }
    out << "Pitch pattern: sun " << selected.sun << ", planet " << selected.planet << ", ring " << selected.ring << ".\n";
    std::vector<Constraint> constraints;
    bool blocked = false;
    for (std::size_t index = 0; index < 3; ++index) {
        const auto here = static_cast<Port>(index);
        const auto name = args[index + 1];
        if (name == "free") { out << port_name(here) << " free.\n"; continue; }
        if (name == "lock") { constraints.push_back({here, {0, 1}}); out << port_name(here) << " explicitly locked.\n"; continue; }
        const auto actual = source(name);
        if (!actual.accepted()) { errors << "The native source fixture is invalid.\n"; return 2; }
        const auto value = actual.motion.at("output");
        out << port_name(here) << " native " << name << ' ' << g::motion_state_name(value.state) << ' '
            << value.rate.numerator << '/' << value.rate.denominator << ".\n";
        if (value.state == g::MotionState::stalled) blocked = true;
        if (value.state == g::MotionState::rotating || value.state == g::MotionState::stopped) constraints.push_back({here, value.rate});
    }
    if (blocked) { out << "Unfinished: a native source is stalled; no planetary motion is admitted.\n"; return out ? 1 : 2; }
    const auto result = evaluate(selected, constraints);
    if (const auto* refusal = std::get_if<Refusal>(&result)) {
        out << "Unfinished: " << error_name(refusal->reason);
        if (refusal->reason == Error::unsupported_result) out << " at " << port_name(refusal->subject) << " (native representation limit)";
        out << ". Free and unpowered ports do not imply a brake.\n";
        return out ? 1 : 2;
    }
    const auto& solved = std::get<Evaluation>(result);
    for (std::size_t index = 0; index < solved.motion.size(); ++index) {
        const auto& value = solved.motion[index];
        out << port_name(static_cast<Port>(index)) << " result " << g::motion_state_name(value.state)
            << ' ' << value.rate.numerator << '/' << value.rate.denominator << ".\n";
    }
    const bool matched = solved.outcome == Outcome::solved && solved.motion[static_cast<std::size_t>(readout)].rate == Fraction{-1, 3};
    out << (matched ? "Matched: the free readout is exactly -1/3.\n" : "Unfinished: the free readout does not match -1/3.\n");
    return out ? (matched ? 0 : 1) : 2;
}
}  // namespace factory::planetary
