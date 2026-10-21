#include "factory/slider_crank_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/slider_crank.hpp"

#include <optional>
#include <ostream>

namespace factory::slider_crank {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "mirrored") { p.origin[0] = 10; p.branch = Branch::negative; }
    else if (name == "short-rod") p.rod_length = 2;
    else if (name == "tight-guide") p.upper = 7;
    else if (name == "low-guide") p.lower = 3;
    else if (name == "offset") p.guide_offset = 3;
    else if (name == "long-rod") p.rod_length = 6;
    else if (name == "singular") p.rod_length = 3;
    else if (name == "shifted") p.origin[0] = 1;
    else if (name == "wrong-travel") { p.shaft = g::Axis::y; p.travel = g::Axis::z; }
    else if (name == "near-edge") p.origin[0] = g::maximum_coordinate;
    else if (name != "standard" && name != "short-drive") return {};
    return p;
}
void coordinate(std::ostream& out, const Coordinate& c) {
    const auto view = std::get<std::optional<Fraction>>(rational_view(c));
    if (view) out << view->numerator << '/' << view->denominator;
    else out << '(' << c.base << (c.branch == Branch::positive ? "+sqrt(" : "-sqrt(") << c.radicand << "))/" << c.denominator;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: slider_case <kit> slow|reverse|fast|stalled|off\n"
               "Kits: standard, mirrored, short-rod, tight-guide, low-guide, offset, long-rod, singular, shifted, wrong-travel, short-drive, near-edge.\n"
               "Goal: a regular complete stroke on the fixed +X guide y=0,z=8, reaching x=2 and x=8, at input speed magnitude 1/2.\n"
               "Either input rotation sense may solve reciprocation. A mirrored assembly trades crank location and rod side.\n"
               "Rod length and guide offset control full-turn closure; current fit cannot prove the complete stroke fits.\n"
               "Nonsquare coordinates stay exact; only exact square roots receive a rational view.\n"
               "Zero longitudinal rod projection has no inferred derivative, unlike an ordinary zero slider speed at reversal.\n"
               "This is centreline and finite-guide geometry, without complete solids, body collision, forces or unique branch admission.\n"
               "Geometric derivatives are per radian; no native-unit conversion, live phase/clock, graph, material or World adoption is inferred.\n";
        return finished(out);
    }
    if (args.size() != 2) { errors << "Choose a slider-crank kit and native source.\n"; return 2; }
    const auto selected = kit(args[0]);
    auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown slider-crank kit or source.\n"; return 2; }
    if (args[1] == "off") source->sources.clear();
    g::Point old_output{};
    for (const auto& part : source->parts) if (part.id == "output") old_output = part.center;
    const auto a = static_cast<std::size_t>(selected->shaft), u = static_cast<std::size_t>(selected->travel), v = 3 - a - u;
    const Integer handed = (a + 1) % 3 == u ? 1 : -1;
    for (auto& part : source->parts) {
        const auto old = part.center;
        part.center = selected->origin;
        part.center[u] += old[0] - old_output[0];
        part.center[v] += handed * (old[1] - old_output[1]);
        part.center[a] += old[2] - old_output[2] - 20;
        part.axis = selected->shaft;
    }
    auto endpoint = selected->origin, centre = selected->origin;
    endpoint[a] -= 4; centre[a] -= 12;
    source->parts.push_back({"slider-input", g::Kind::hub, endpoint, selected->shaft});
    source->parts.push_back({"input-drive", g::Kind::shaft, centre, selected->shaft, 0, args[0] == "short-drive" ? 1 : 8});
    const auto supplied = g::evaluate(source->parts, source->sources);
    if (!supplied.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = supplied.motion.at("slider-input");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator
        << " about +" << "XYZ"[a] << "; input shaft terminates behind the crank plane.\n";
    const Direction first = args[0] == "short-rod" ? Direction{} : Direction{0, 1, 1};
    const auto reading = sample(*selected, first, input);
    if (const auto* error = std::get_if<Refusal>(&reading)) {
        if (error->reason == Error::unreachable) { out << "Goal unfinished: current rod cannot reach the guide.\n"; return finished(out); }
        errors << "Current pose refused: " << error_name(error->reason) << ".\n";
        return 2;
    }
    const auto& current = std::get<Sample>(reading);
    out << "Current slider coordinate: "; coordinate(out, current.slider);
    out << "; current guide fit " << (current.guide_fits ? "yes" : "no") << "; longitudinal projection " << (current.per_radian ? "nonzero" : "zero") << ".\n";
    const auto candidate = inspect(*selected);
    if (const auto* error = std::get_if<Refusal>(&candidate)) { errors << "Whole cycle refused: " << error_name(error->reason) << ".\n"; return 2; }
    const auto& cycle = std::get<Cycle>(candidate);
    if (!cycle.closed()) { out << "Goal unfinished: rod cannot close through a complete revolution.\n"; return finished(out); }
    if (!cycle.regular()) { out << "Goal unfinished: zero longitudinal rod projection prevents a regular complete cycle.\n"; return finished(out); }
    out << "Whole-cycle slider extrema: "; coordinate(out, (*cycle.extrema)[0]); out << " to "; coordinate(out, (*cycle.extrema)[1]); out << ".\n";
    if (selected->travel != g::Axis::x || current.guide_anchor[1] != 0 || current.guide_anchor[2] != 8) {
        out << "Goal unfinished: motion differs from the fixed +X guide line.\n";
        return finished(out);
    }
    if (!cycle.guide_fits) { out << "Goal unfinished: complete stroke escapes the finite guide.\n"; return finished(out); }
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no stroke is proposed.\n";
        return finished(out);
    }
    const auto irrational = sample(*selected, {3, 4, 5}, input);
    if (const auto* error = std::get_if<Refusal>(&irrational)) { errors << "Exact pose refused: " << error_name(error->reason) << ".\n"; return 2; }
    out << "Direction (3,4)/5 slider: "; coordinate(out, std::get<Sample>(irrational).slider); out << ". No rounding.\n";
    const bool stops = std::get<Order>(compare_to_grid((*cycle.extrema)[0], 2)) == Order::equal && std::get<Order>(compare_to_grid((*cycle.extrema)[1], 8)) == Order::equal;
    const bool speed = input.state == g::MotionState::rotating && (input.rate == g::Rate{1, 2} || input.rate == g::Rate{-1, 2});
    out << (stops && speed ? "Goal matched.\n" : "Goal unfinished: require both fixed stops and input speed magnitude 1/2.\n");
    return finished(out);
}
}  // namespace factory::slider_crank
