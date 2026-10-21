#include "factory/cam_windows_workbench.hpp"

#include "factory/cam_windows.hpp"
#include "factory/geared_cycle_workbench.hpp"

#include <charconv>
#include <ostream>

namespace factory::cam_windows {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
std::optional<k::Fixture> fixture(std::string_view name) {
    if (name != "burst") return k::fixture(name);
    k::Fixture result;
    result.parts = {
        {"source", g::Kind::hub, {0, 0, 0}, g::Axis::z},
        {"source-shaft", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 1},
        {"source-gear", g::Kind::gear, {0, 0, 0}, g::Axis::z, 20},
        {"idler", g::Kind::gear, {21, 0, 0}, g::Axis::z, 1},
        {"output", g::Kind::hub, {24, 0, 0}, g::Axis::z},
        {"output-shaft", g::Kind::shaft, {24, 0, 0}, g::Axis::z, 0, 1},
        {"output-gear", g::Kind::gear, {24, 0, 0}, g::Axis::z, 2},
    };
    result.sources = {{"source", {1, 1}}};
    return result;
}
bool parse(std::string_view text, g::Integer& result) {
    if (text.empty()) return false;
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), result);
    return parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size();
}
void fraction(std::ostream& out, Fraction value) { out << value.numerator << '/' << value.denominator; }
void intervals(std::ostream& out, const std::vector<Span>& spans) {
    if (spans.empty()) out << " none";
    for (const auto& span : spans) {
        out << " (";
        fraction(out, span.begin);
        out << ',';
        fraction(out, span.end);
        out << ')';
    }
}
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: cam_windows_case slow|fast|reverse|burst|stalled <key 0..9> <width 0..10> <ticks 0..256> [--paused]\n"
               "Cam 1 uses the supplied lobe; cam 2 marks the existing work dwell at teeth 5..7.\n"
               "Coverage measures geometric open time within each tick, without granting work.\n"
               "Positive-duration overlaps are reported and remain valid traces.\n";
        return out ? 0 : 2;
    }
    if (args.size() < 4 || args.size() > 5 || (args.size() == 5 && args[4] != "--paused")) {
        errors << "Choose a gear fixture, key, width, bounded tick count and optional --paused.\n";
        return 2;
    }
    g::Integer key{}, width{}, ticks{};
    const auto scene = fixture(args[0]);
    if (!scene || !parse(args[1], key) || !parse(args[2], width) || !parse(args[3], ticks) ||
        key < 0 || key >= 10 || width < 0 || width > 10 || ticks < 0 || ticks > 256) {
        errors << "Unknown fixture or invalid key, width or tick count.\n";
        return 2;
    }
    const auto derived = g::evaluate(scene->parts, scene->sources);
    if (!derived.accepted()) { errors << "The declared native gear fixture is invalid.\n"; return 2; }
    const auto output = derived.motion.at("output");
    const auto rate = output.state == g::MotionState::rotating ? output.rate : g::Rate{};
    out << "Native output " << g::motion_state_name(output.state) << ' ';
    fraction(out, output.rate);
    out << ". Geometric intervals do not grant work.\n";
    const mechanisms::Slide slide{2, 3, 2};
    const Cam cams[]{{1, {static_cast<mechanisms::Tooth>(key), static_cast<mechanisms::Tooth>(width)}}, {2, {5, 2}}};
    k::Phase phase;
    for (g::Integer tick = 1; tick <= ticks; ++tick) {
        auto plan = prepare(slide, phase, rate, args.size() != 5, cams);
        if (const auto* refusal = std::get_if<Refusal>(&plan)) {
            errors << "Cam schedule refused: " << error_name(refusal->reason) << ".\n";
            return 2;
        }
        const auto& prepared = std::get<Prepared>(plan);
        out << "Tick " << tick << " phase " << phase.numerator << '/' << phase.denominator
            << " -> " << prepared.motion.next.numerator << '/' << prepared.motion.next.denominator
            << "; shaft advances " << (prepared.shaft_advances ? "yes" : "no") << ".\n";
        for (const auto& window : prepared.windows) {
            out << "Cam " << window.id << " start " << (window.at_start ? "on" : "off")
                << " end " << (window.at_end ? "on" : "off") << " coverage ";
            fraction(out, window.coverage);
            out << "; open";
            intervals(out, window.active);
            out << ".\n";
        }
        for (const auto& overlap : prepared.overlaps) {
            out << "Overlap " << overlap.first << '+' << overlap.second << " coverage ";
            fraction(out, overlap.coverage);
            out << "; open";
            intervals(out, overlap.active);
            out << ".\n";
        }
        phase = prepared.motion.next;
    }
    return out ? 0 : 2;
}
}  // namespace factory::cam_windows
