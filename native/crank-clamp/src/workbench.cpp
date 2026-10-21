#include "factory/crank_clamp_workbench.hpp"

#include "factory/crank_clamp.hpp"
#include "factory/geared_cycle_workbench.hpp"

#include <optional>
#include <ostream>

namespace factory::crank_clamp {
namespace g = mechanics;
namespace s = slider_crank;
namespace k = geared_cycle;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "wide") { p.origin[0] = -2; p.spacing = 24; p.radius = 4; p.rod_length = 6; }
    else if (name == "compact") { p.radius = 2; p.rod_length = 6; }
    else if (name == "wrong-clock") p.clocking = Clocking::same_reference;
    else if (name == "tight") p.rod_length = 6;
    else if (name == "loose") p.rod_length = 4;
    else if (name == "singular") p.rod_length = 3;
    else if (name == "short-rod") p.rod_length = 2;
    else if (name == "shifted") p.origin[0] = 1;
    else if (name == "wrong-travel") { p.shaft = g::Axis::y; p.travel = g::Axis::z; }
    else if (name == "near-edge") p.origin[0] = g::maximum_coordinate - p.spacing;
    else if (name != "standard" && name != "short-source" && name != "short-right" && name != "wrong-gear") return {};
    return p;
}
void coordinate(std::ostream& out, const Coordinate& c) {
    const auto view = std::get<std::optional<Fraction>>(s::rational_view(c));
    if (view) out << view->numerator << '/' << view->denominator;
    else out << '(' << c.base << (c.branch == s::Branch::positive ? "+sqrt(" : "-sqrt(") << c.radicand << "))/" << c.denominator;
}
bool equals(const Coordinate& c, Integer target) { return std::get<s::Order>(s::compare_to_grid(c, target)) == s::Order::equal; }
int finished(std::ostream& out) { return out ? 0 : 2; }
void error(std::ostream& errors, const Refusal& refusal) {
    errors << error_name(refusal.reason);
    if (refusal.parent_error) errors << '/' << s::error_name(*refusal.parent_error);
    errors << ".\n";
}
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: clamp_case <kit> slow|reverse|fast|stalled|off\n"
               "Kits: standard, wide, compact, wrong-clock, tight, loose, singular, short-rod, shifted, wrong-travel, short-source, short-right, wrong-gear, near-edge.\n"
               "Goal: keep work centre (10,0,8) fixed along +X for the complete stroke, close at x=8 and x=12, and open at least 16.\n"
               "Both actual native crank sources must counter-rotate at speed magnitude 1/2. Either input sense works.\n"
               "Wider hardware trades footprint for loading access; a compact assembly may close yet fail to admit the work.\n"
               "One centred snapshot cannot certify a fixed centre. Mounting is explicit; native gears supply rates, not a phase clock.\n"
               "Exact centreline geometry reuses finite rods and nonsquare coordinates without rounding.\n"
               "No complete solids, contact/gripping, force, material processing, live phase, graph or World adoption is established.\n"
               "Parent derivatives keep their own local per-radian angles; no native angular-unit conversion is implied.\n";
        return finished(out);
    }
    if (args.size() != 2) { errors << "Choose a clamp kit and native source.\n"; return 2; }
    const auto selected = kit(args[0]);
    auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown clamp kit or source.\n"; return 2; }
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
    auto point = [&](Integer across, Integer axial) {
        auto at = selected->origin; at[u] += across; at[a] += axial; return at;
    };
    source->parts.push_back({"pair-left", g::Kind::hub, point(0, -12), selected->shaft});
    source->parts.push_back({"pair-right", g::Kind::hub, point(selected->spacing, -12), selected->shaft});
    source->parts.push_back({"left-gear", g::Kind::gear, point(0, -12), selected->shaft, selected->spacing / 2});
    source->parts.push_back({"right-gear", g::Kind::gear, point(selected->spacing, -12), selected->shaft, selected->spacing / 2 - (args[0] == "wrong-gear" ? 1 : 0)});
    source->parts.push_back({"source-bridge", g::Kind::shaft, point(0, -16), selected->shaft, 0, args[0] == "short-source" ? 1 : 4});
    source->parts.push_back({"left-crank", g::Kind::hub, point(0, -4), selected->shaft});
    source->parts.push_back({"right-crank", g::Kind::hub, point(selected->spacing, -4), selected->shaft});
    source->parts.push_back({"left-drive", g::Kind::shaft, point(0, -8), selected->shaft, 0, 4});
    source->parts.push_back({"right-drive", g::Kind::shaft, point(selected->spacing, -8), selected->shaft, 0, args[0] == "short-right" ? 1 : 4});
    const auto supplied = g::evaluate(source->parts, source->sources);
    if (!supplied.accepted()) { errors << "Native source refused: " << g::error_name(supplied.error) << ".\n"; return 2; }
    const std::array inputs{supplied.motion.at("left-crank"), supplied.motion.at("right-crank")};
    out << "Source " << args[1] << ": left " << g::motion_state_name(inputs[0].state) << ' ' << inputs[0].rate.numerator << '/' << inputs[0].rate.denominator
        << "; right " << g::motion_state_name(inputs[1].state) << ' ' << inputs[1].rate.numerator << '/' << inputs[1].rate.denominator << ".\n";
    out << "Actual gears and coaxial bridges supply the crank hubs; shafts end behind the rod plane.\n";
    const auto reading = sample(*selected, args[0] == "short-rod" ? Direction{} : Direction{0, 1, 1}, inputs);
    if (const auto* refusal = std::get_if<Refusal>(&reading)) { errors << "Current pose refused: "; error(errors, *refusal); return 2; }
    const auto& current = std::get<Sample>(reading);
    out << "Current centre: ";
    for (const auto& value : current.centre) out << value.numerator << '/' << value.denominator << ' ';
    out << "; gap "; coordinate(out, current.gap); out << ".\n";
    const auto candidate = inspect(*selected);
    if (const auto* refusal = std::get_if<Refusal>(&candidate)) { errors << "Whole cycle refused: "; error(errors, *refusal); return 2; }
    const auto& cycle = std::get<Cycle>(candidate);
    if (!cycle.closed()) { out << "Goal unfinished: rods cannot close through a complete revolution.\n"; return finished(out); }
    if (!cycle.regular()) { out << "Goal unfinished: zero rod projection prevents a regular cycle.\n"; return finished(out); }
    out << "Whole-cycle gap: "; coordinate(out, (*cycle.gap_extrema)[0]); out << " to "; coordinate(out, (*cycle.gap_extrema)[1]); out << ".\n";
    if (!cycle.centre.fixed()) { out << "Goal unfinished: work centre moves despite this centred snapshot.\n"; return finished(out); }
    if (selected->travel != g::Axis::x || cycle.centre.reference != Point{Fraction{10, 1}, Fraction{}, Fraction{8, 1}}) {
        out << "Goal unfinished: assembly differs from the fixed work centre and +X line.\n"; return finished(out);
    }
    if (!equals((*cycle.gap_extrema)[0], 4)) { out << "Goal unfinished: closed jaws miss the two fixed working planes.\n"; return finished(out); }
    if (std::get<s::Order>(s::compare_to_grid((*cycle.gap_extrema)[1], 16)) == s::Order::less) {
        out << "Goal unfinished: loading aperture is smaller than 16.\n"; return finished(out);
    }
    if (!current.powered) { out << "Goal unfinished: both crank hubs need rotating native power.\n"; return finished(out); }
    const auto exact = sample(*selected, {3, 4, 5}, inputs);
    if (const auto* refusal = std::get_if<Refusal>(&exact)) { errors << "Exact pose refused: "; error(errors, *refusal); return 2; }
    out << "Direction (3,4)/5 exact gap: "; coordinate(out, std::get<Sample>(exact).gap); out << ".\n";
    const bool speed = inputs[0].rate == Fraction{1, 2} || inputs[0].rate == Fraction{-1, 2};
    out << (speed ? "Goal matched.\n" : "Goal unfinished: crank speed magnitude must be 1/2.\n");
    return finished(out);
}
}  // namespace factory::crank_clamp
