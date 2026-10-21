#include "factory/cardan_pair_workbench.hpp"

#include "factory/cardan_pair.hpp"
#include "factory/geared_cycle_workbench.hpp"

#include <optional>
#include <numeric>
#include <ostream>

namespace factory::cardan_pair {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
struct Kit { Profile profile; Integer span{12}; };
std::optional<Kit> kit(std::string_view name) {
    Kit result;
    if (name == "shallow") { result.profile.joints = {{{{4, 3, 5}, Mount::forward}, {{4, -3, 5}, Mount::compensating}}}; result.span = 16; }
    else if (name == "steep") { result.profile.joints = {{{{5, 12, 13}, Mount::forward}, {{5, -12, 13}, Mount::compensating}}}; result.span = 4; }
    else if (name == "lean") { result.profile.joints = {{{{7, 24, 25}, Mount::forward}, {{7, -24, 25}, Mount::compensating}}}; result.span = 2; }
    else if (name == "wrong-yokes") result.profile.joints[1].mount = Mount::forward;
    else if (name == "unequal") result.profile.joints[1].bend = {5, -12, 13};
    else if (name == "same-bend") result.profile.joints[1].bend.sine = 4;
    else if (name == "offset") result.span = 10;
    else if (name != "balanced") return {};
    return result;
}
g::Result bridge(const g::Point& endpoint, g::Rate rate, bool reverse, bool short_shaft) {
    const g::Point readout{4, 48, 96}, gear_point{0, endpoint[1], 96};
    const auto teeth = reverse ? 2 : 1;
    const auto half_span = short_shaft ? 1 : (gear_point[2] - endpoint[2]) / 2;
    const g::Point center{0, endpoint[1], (gear_point[2] + endpoint[2]) / 2};
    std::vector<g::Part> parts{
        {"joint-out", g::Kind::hub, endpoint, g::Axis::z},
        {"bridge-shaft", g::Kind::shaft, center, g::Axis::z, 0, half_span},
        {"bridge-in", g::Kind::hub, gear_point, g::Axis::z},
        {"bridge-gear", g::Kind::gear, gear_point, g::Axis::z, teeth},
        {"readout", g::Kind::hub, readout, g::Axis::z},
        {"readout-shaft", g::Kind::shaft, readout, g::Axis::z, 0, 1},
        {"readout-gear", g::Kind::gear, readout, g::Axis::z, teeth},
    };
    if (!reverse) parts.push_back({"bridge-idler", g::Kind::gear, {2, endpoint[1], 96}, g::Axis::z, 1});
    return g::evaluate(parts, {{"joint-out", rate}});
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: cardan_case balanced|shallow|steep|lean|wrong-yokes|unequal|same-bend|offset slow|reverse|fast|stalled|off same|reverse full|short\n"
               "Goal: constant +1/2 about a fixed +Z readout at (4,48,96).\n"
               "Choose matched bends and yoke mounting, actual native source gears, output gear sign and shaft reach.\n"
               "Matched kits trade bend for intermediate shaft shape and readout-shaft length.\n"
               "An exact composite-map certificate checks every dial direction; one speed reading or cycle average is insufficient.\n"
               "Constant candidates also admit every bounded primitive dial through both native rate checks.\n"
               "Steep and lean retain native precision refusal controls; that limit is not a mechanical gameplay rule.\n"
               "The nine printed directions are illustrations, not a time integration or a sampled proof.\n"
               "Ideal fixed yoke coordinates and axes do not adopt angled native Parts, dynamics, force/contact, a clock or World.\n";
        return finished(out);
    }
    if (args.size() != 4 || (args[2] != "same" && args[2] != "reverse") || (args[3] != "full" && args[3] != "short")) {
        errors << "Choose a kit, source, same|reverse output gears and full|short shaft.\n";
        return 2;
    }
    const auto selected = kit(args[0]);
    auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown joint kit or native source.\n"; return 2; }
    if (args[1] == "off") source->sources.clear();
    g::Point old_output{};
    for (const auto& part : source->parts) if (part.id == "output") old_output = part.center;
    for (auto& part : source->parts) for (std::size_t axis = 0; axis < 3; ++axis) part.center[axis] -= old_output[axis];
    const auto supplied = g::evaluate(source->parts, source->sources);
    if (!supplied.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = supplied.motion.at("output");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << " about +Z at (0,0,0).\n";
    const auto first = evaluate(selected->profile, {}, input);
    if (const auto* refusal = std::get_if<Refusal>(&first)) {
        errors << "Joint reading refused: " << error_name(refusal->reason) << ".\n";
        return 2;
    }
    const auto& geometry = std::get<Evaluation>(first);
    out << "Composite dial coefficients " << geometry.composite.x << ':' << geometry.composite.y << "; constant " << (geometry.composite.constant_rate() ? "yes" : "no") << ".\n";
    if (geometry.output_axis != AxisDirection{0, 1, 1}) {
        out << "Goal unfinished: the derived output axis is not the fixed +Z shaft axis.\n";
        return finished(out);
    }
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no output drive is admitted.\n";
        return finished(out);
    }
    if (geometry.composite.constant_rate()) {
        std::size_t admitted{};
        for (Integer x = -maximum_dial_component; x <= maximum_dial_component; ++x)
        for (Integer y = -maximum_dial_component; y <= maximum_dial_component; ++y) {
            if (std::gcd(x, y) != 1) continue;
            const auto reading = evaluate(selected->profile, {x, y}, input);
            if (const auto* refusal = std::get_if<Refusal>(&reading)) {
                errors << "Whole dial domain refused at (" << x << ',' << y << "): " << error_name(refusal->reason)
                    << ", stage " << refusal->stage << ". No full-domain claim is made.\n";
                return 2;
            }
            ++admitted;
        }
        out << "Bounded dial domain: " << admitted << " primitive directions admitted.\n";
    }
    const auto& bend = selected->profile.joints[0].bend;
    const g::Point endpoint{0, bend.sine * selected->span, bend.cosine * selected->span};
    out << "Joint endpoint (" << endpoint[0] << ',' << endpoint[1] << ',' << endpoint[2] << "); declared middle pitch length " << bend.scale * selected->span << "; output shaft half-span "
        << (args[3] == "short" ? 1 : (96 - endpoint[2]) / 2) << ".\n";
    const std::array<Dial, 9> dials{{{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}, {3, 5}}};
    bool target = geometry.composite.constant_rate();
    for (const auto dial : dials) {
        const auto reading = evaluate(selected->profile, dial, input);
        if (const auto* refusal = std::get_if<Refusal>(&reading)) {
            errors << "Joint reading refused: " << error_name(refusal->reason) << ".\n";
            return 2;
        }
        const auto& result = std::get<Evaluation>(reading);
        const auto output = bridge(endpoint, result.motion[2].rate, args[2] == "reverse", args[3] == "short");
        if (!output.accepted()) { errors << "Native output bridge refused.\n"; return 2; }
        const auto readout = output.motion.at("readout");
        target = target && readout.state == g::MotionState::rotating && readout.rate == g::Rate{1, 2};
        out << "Dial (" << dial.x << ',' << dial.y << "): middle " << result.motion[1].rate.numerator << '/' << result.motion[1].rate.denominator
            << "; joints " << result.motion[2].rate.numerator << '/' << result.motion[2].rate.denominator << "; readout "
            << g::motion_state_name(readout.state) << ' ' << readout.rate.numerator << '/' << readout.rate.denominator << ".\n";
    }
    out << (target ? "Goal matched: exact constant map and native readout.\n" : "Goal unfinished: require constant +1/2 and an actually connected readout.\n");
    return finished(out);
}
}  // namespace factory::cardan_pair
