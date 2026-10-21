#include "factory/differential_workbench.hpp"

#include "factory/differential.hpp"
#include "factory/geared_cycle_workbench.hpp"

#include <ostream>
#include <vector>

namespace factory::differential {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
std::optional<Port> port(std::string_view name) {
    for (const auto value : {Port::left, Port::carrier, Port::right})
        if (name == port_name(value)) return value;
    return std::nullopt;
}
bool source_name(std::string_view name) {
    return name == "free" || name == "lock" || name == "slow" || name == "fast" || name == "reverse" || name == "stalled";
}
void help(std::ostream& out) {
    out << "Usage: differential_case <left> <carrier> <right> <readout> | list\n"
           "Each port: free | lock | slow | fast | reverse | stalled. Readout: left | carrier | right.\n"
           "Keep the readout free and make its inferred speed exactly +1.\n"
           "The same-axis constraint is 2 * carrier = left + right. A free port is not a lock.\n"
           "Slow, fast and reverse come from actual native gears; lock is an explicit zero-speed constraint.\n"
           "This is a kinematic setup puzzle; torque, loads and live factory adoption are unselected.\n";
}
}  // namespace
int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) { help(out); return out ? 0 : 2; }
    if (args.size() != 4 || !port(args[3]) || !source_name(args[0]) || !source_name(args[1]) || !source_name(args[2])) {
        errors << "Choose three listed port conditions and a valid readout.\n";
        return 2;
    }
    const auto readout = *port(args[3]);
    if (args[static_cast<std::size_t>(readout)] != "free") {
        errors << "Keep the measured output free; do not prescribe its answer.\n";
        return 2;
    }
    std::vector<Constraint> constraints;
    bool blocked{};
    for (std::size_t index = 0; index < 3; ++index) {
        const auto here = static_cast<Port>(index);
        const auto name = args[index];
        if (name == "free") { out << port_name(here) << " free.\n"; continue; }
        if (name == "lock") {
            constraints.push_back({here, {0, 1}});
            out << port_name(here) << " explicitly locked.\n";
            continue;
        }
        const auto scene = *k::fixture(name);
        const auto mechanical = g::evaluate(scene.parts, scene.sources);
        if (!mechanical.accepted()) { errors << "The declared native gear fixture is invalid.\n"; return 2; }
        const auto motion = mechanical.motion.at("output");
        out << port_name(here) << " native " << name << ' ' << g::motion_state_name(motion.state)
            << ' ' << motion.rate.numerator << '/' << motion.rate.denominator << ".\n";
        blocked = blocked || motion.state == g::MotionState::stalled;
        if (motion.state == g::MotionState::rotating || motion.state == g::MotionState::stopped)
            constraints.push_back({here, motion.rate});
    }
    if (!out) return 2;
    if (blocked) { out << "Unfinished: a native source component is stalled; no output speed is admitted.\n"; return out ? 1 : 2; }
    const auto result = evaluate(constraints);
    if (const auto* refusal = std::get_if<Refusal>(&result)) {
        if (refusal->reason == Error::underdetermined) {
            out << "Unfinished: underdetermined. Prescribe two ports; free does not mean locked.\n";
            return out ? 1 : 2;
        }
        errors << "Differential refused: " << error_name(refusal->reason) << ".\n";
        return 2;
    }
    const auto& solved = std::get<Evaluation>(result);
    for (std::size_t index = 0; index < 3; ++index) {
        const auto& motion = solved.motion[index];
        out << port_name(static_cast<Port>(index)) << " result " << g::motion_state_name(motion.state)
            << ' ' << motion.rate.numerator << '/' << motion.rate.denominator << ".\n";
    }
    const bool matched = solved.outcome == Outcome::solved && solved.motion[static_cast<std::size_t>(readout)].rate == Fraction{1, 1};
    out << (matched ? "Matched: the free readout runs at exactly +1.\n" : "Unfinished: the free readout does not match +1.\n");
    return out ? (matched ? 0 : 1) : 2;
}
}  // namespace factory::differential
