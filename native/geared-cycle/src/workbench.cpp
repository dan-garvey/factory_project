#include "factory/geared_cycle_workbench.hpp"

#include "factory/cycle.hpp"

#include <charconv>
#include <ostream>

namespace factory::geared_cycle {
namespace g = mechanics;
namespace m = mechanisms;

std::optional<Fixture> fixture(std::string_view name) {
    if (name != "slow" && name != "fast" && name != "reverse" && name != "stalled") return std::nullopt;
    const Integer root_radius = name == "fast" ? 5 : 1;
    const bool reverse = name == "reverse";
    const Integer middle_x = root_radius + 1;
    const Integer output_x = reverse ? root_radius + 2 : middle_x + 3;
    Fixture result;
    result.parts = {
        {"source", g::Kind::hub, {0, 0, 0}, g::Axis::z},
        {"source-shaft", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 1},
        {"source-gear", g::Kind::gear, {0, 0, 0}, g::Axis::z, root_radius},
        {"output", g::Kind::hub, {output_x, 0, 0}, g::Axis::z},
        {"output-shaft", g::Kind::shaft, {output_x, 0, 0}, g::Axis::z, 0, 1},
        {"output-gear", g::Kind::gear, {output_x, 0, 0}, g::Axis::z, 2},
    };
    if (!reverse) result.parts.push_back({"idler", g::Kind::gear, {middle_x, 0, 0}, g::Axis::z, 1});
    result.sources = {{"source", {1, 1}}};
    if (name == "stalled") result.sources.push_back({"output", {1, 1}});
    return result;
}

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: geared_cycle_case slow|fast|reverse|stalled <0..256 ticks> [--paused]\n"
               "Actual native gears drive an ideal 10-tooth phase clock.\n"
               "Reached stops sample the existing carriage and its two-tooth work cam.\n"
               "This is a phase trace, not material production or continuous contact.\n";
        return out ? 0 : 2;
    }
    if (args.size() < 2 || args.size() > 3 || (args.size() == 3 && args[2] != "--paused")) {
        errors << "Choose a fixture, bounded tick count and optional --paused.\n";
        return 2;
    }
    auto scene = fixture(args[0]);
    Integer ticks{};
    const auto parsed = std::from_chars(args[1].data(), args[1].data() + args[1].size(), ticks);
    if (!scene || parsed.ec != std::errc{} || parsed.ptr != args[1].data() + args[1].size() || ticks < 0 || ticks > 256) {
        errors << "Unknown fixture or invalid tick count.\n";
        return 2;
    }
    const auto derivation = g::evaluate(scene->parts, scene->sources);
    if (!derivation.accepted()) { errors << "The declared gear fixture is invalid.\n"; return 2; }
    const auto output = derivation.motion.at("output");
    const auto rate = output.state == g::MotionState::rotating ? output.rate : g::Rate{};
    out << "Fixture " << args[0] << ": output " << g::motion_state_name(output.state)
        << ' ' << output.rate.numerator << '/' << output.rate.denominator << ".\n";
    const m::Slide slide{2, 3, 2};
    Phase phase;
    std::size_t crossings{}, hits{};
    for (Integer tick = 1; tick <= ticks; ++tick) {
        auto plan = prepare(10, phase, rate, args.size() != 3);
        if (const auto* error = std::get_if<Error>(&plan)) {
            errors << "Phase refused: " << error_name(*error) << ".\n";
            return 2;
        }
        const auto& prepared = std::get<Prepared>(plan);
        for (const auto& crossing : prepared.crossings) {
            bool cam{};
            m::Pose carrier;
            const m::Phase stop{static_cast<m::Tooth>(crossing.tooth)};
            if (m::cam_active(slide, stop, {5, 2}, cam) != m::Error::none ||
                m::sample(slide, stop, carrier) != m::Error::none) {
                errors << "The reached stop is outside the carriage cycle.\n";
                return 2;
            }
            ++crossings;
            if (cam) ++hits;
            out << "Tick " << tick << " tooth " << crossing.tooth << " at "
                << crossing.at.numerator << '/' << crossing.at.denominator << " direction "
                << crossing.direction << " cam " << (cam ? "on" : "off")
                << " carrier " << m::stage_name(carrier.stage) << ".\n";
        }
        phase = prepared.next;
        out << "Phase after tick " << tick << ": " << phase.numerator << '/' << phase.denominator << ".\n";
    }
    out << "Crossings=" << crossings << " cam_hits=" << hits << " final="
        << phase.numerator << '/' << phase.denominator << ".\n";
    return out ? 0 : 2;
}
}  // namespace factory::geared_cycle
