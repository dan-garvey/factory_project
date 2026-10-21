#include "factory/worm_pair_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/worm_pair.hpp"

#include <optional>
#include <ostream>

namespace factory::worm_pair {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
struct Layout { Worm worm; Wheel wheel; };
std::optional<Layout> layout(std::string_view name, Pattern pattern) {
    Layout result{{7, {0, 32, 0}, g::Axis::x, 4, 16, 1, pattern}, {11, {0, 32, 28}, g::Axis::y, 24, 2}};
    if (name == "flipped") result.worm.center[2] = 56;
    else if (name == "multi") { result.worm.starts = 2; result.worm.center[2] = -24; result.wheel.teeth = 48; }
    else if (name == "short-body" || name == "long-body") { result.worm.center[0] = 24; if (name == "long-body") result.worm.half_span = 32; }
    else if (name == "edge-body") result.worm.center[0] = 16;
    else if (name == "outside-face") result.worm.center[1] = 35;
    else if (name == "pitch-miss") result.wheel.center[2] = 27;
    else if (name == "parallel") result.wheel.axis = g::Axis::x;
    else if (name == "shifted") { result.worm.center[2] += 12; result.wheel.center[2] += 12; }
    else if (name == "low") { result.worm.center[1] = 0; result.wheel.center[1] = 0; }
    else if (name != "standard") return {};
    return result;
}
k::Fixture source_fixture(std::string_view name, const Worm& worm) {
    auto scene = *k::fixture(name == "off" ? "slow" : name);
    if (name == "off") scene.sources.clear();
    g::Point old_output{};
    for (const auto& part : scene.parts) if (part.id == "output") old_output = part.center;
    // Proper cyclic rotation: old x->y, y->z, z->x. Rates keep their global
    // signs, while the actual hub/shaft/gear geometry is rotated and translated.
    for (auto& part : scene.parts) {
        const auto old = part.center;
        part.center = {old[2], old[0], old[1]};
        part.axis = static_cast<g::Axis>((static_cast<std::size_t>(part.axis) + 1) % 3);
        const g::Point output{old_output[2], old_output[0], old_output[1]};
        for (std::size_t axis = 0; axis < 3; ++axis) part.center[axis] += worm.center[axis] - output[axis];
    }
    return scene;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: worm_case <layout> axial+|axial- slow|reverse|fast|stalled|off full|short\n"
               "Layouts: standard, flipped, multi, short-body, long-body, edge-body, outside-face, pitch-miss, parallel, shifted, low.\n"
               "Goal: +1/48 about a fixed +Y readout at (0,64,28), above the y=0 floor.\n"
               "Pattern axial+ advances along +X for positive worm rotation; axial- reverses that pattern.\n"
               "Choose input direction, mounting side, finite worm length and a real output shaft.\n"
               "The two-start/larger-wheel kit trades footprint for the same reduction.\n"
               "Floor checks cover conservative pair pitch envelopes only. Units are native pitch units.\n"
               "Ideal thread travel is not tooth-profile, housing, friction, torque or contact admission.\n"
               "No automatic self-locking, phase, clock or live World is inferred.\n";
        return finished(out);
    }
    if (args.size() != 4 || (args[1] != "axial+" && args[1] != "axial-") || (args[3] != "full" && args[3] != "short")) {
        errors << "Choose a layout, axial+|axial- pattern, source and full|short shaft.\n";
        return 2;
    }
    const auto pair = layout(args[0], args[1] == "axial+" ? Pattern::positive : Pattern::negative);
    if (!pair || (args[2] != "off" && !k::fixture(args[2]))) {
        errors << "Unknown worm layout or source.\n";
        return 2;
    }
    const auto scene = source_fixture(args[2], pair->worm);
    const auto native_source = g::evaluate(scene.parts, scene.sources);
    if (!native_source.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = native_source.motion.at("output");
    out << "Source " << args[2] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << " about +X; pattern " << args[1] << ".\n";
    std::vector<Drive> drives;
    if (input.state == g::MotionState::rotating || input.state == g::MotionState::stopped) drives.push_back({pair->worm.id, input.rate});
    const auto candidate = evaluate(pair->worm, pair->wheel, drives);
    if (const auto* refusal = std::get_if<Refusal>(&candidate)) {
        out << "Goal unfinished: " << error_name(refusal->reason) << " (part " << refusal->subject << ").\n";
        return finished(out);
    }
    const auto& result = std::get<Evaluation>(candidate);
    const std::array<c::Obstacle, 1> floor{{{99, {{-8192, -8192, -8192}, {8192, 0, 8192}}}}};
    for (std::size_t index = 0; index < 2; ++index) {
        const auto clearance = c::sweep(result.geometry.pitch_bounds[index], {}, floor);
        if (clearance.error != c::Error::none) { errors << "Floor query refused.\n"; return 2; }
        if (clearance.hit) {
            out << "Goal unfinished: " << (index == 0 ? "worm" : "wheel") << " pitch envelope overlaps floor 99.\n";
            return finished(out);
        }
    }
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no wheel drive is admitted.\n";
        return finished(out);
    }
    out << "Contact (" << result.geometry.contact[0] << ',' << result.geometry.contact[1] << ',' << result.geometry.contact[2]
        << "); starts " << pair->worm.starts << "; radius " << pair->worm.radius << "; worm half-span " << pair->worm.half_span << ".\n";
    out << "Wheel/worm " << result.geometry.wheel_from_worm.numerator << '/' << result.geometry.wheel_from_worm.denominator << "; wheel "
        << g::motion_state_name(result.motion[1].state) << ' ' << result.motion[1].rate.numerator << '/' << result.motion[1].rate.denominator << " about +Y.\n";
    const g::Point target{0, 64, 28};
    const auto half_span = args[3] == "full" ? (target[1] - pair->wheel.center[1]) / 2 : 1;
    auto shaft_center = pair->wheel.center;
    shaft_center[1] = (target[1] + pair->wheel.center[1]) / 2;
    const std::vector<g::Part> output_parts{
        {"wheel-out", g::Kind::hub, pair->wheel.center, g::Axis::y},
        {"output-shaft", g::Kind::shaft, shaft_center, g::Axis::y, 0, half_span},
        {"readout", g::Kind::hub, target, g::Axis::y},
    };
    const auto output = g::evaluate(output_parts, {{"wheel-out", result.motion[1].rate}});
    if (!output.accepted()) { errors << "Native output shaft refused.\n"; return 2; }
    const auto readout = output.motion.at("readout");
    out << "Output shaft half-span " << half_span << "; readout " << g::motion_state_name(readout.state) << ' ' << readout.rate.numerator << '/' << readout.rate.denominator << ".\n";
    out << (readout.state == g::MotionState::rotating && readout.rate == g::Rate{1, 48} ? "Goal matched.\n" : "Goal unfinished: readout must rotate at +1/48 about +Y.\n");
    return finished(out);
}
}  // namespace factory::worm_pair
