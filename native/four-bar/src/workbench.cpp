#include "factory/four_bar_workbench.hpp"

#include "factory/four_bar.hpp"
#include "factory/geared_cycle_workbench.hpp"

#include <ostream>

namespace factory::four_bar {
namespace g = mechanics;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "long-arm") { p.crank = 3; p.coupler = 8; }
    else if (name == "short-arm") p.coupler = 6;
    else if (name == "locks-later") { p.coupler = 6; p.rocker = 3; }
    else if (name == "change-point") { p.coupler = 6; p.rocker = 4; }
    else if (name == "coincident") { p.ground = 2; p.coupler = 5; }
    else if (name == "shifted") p.origin[0] = 1;
    else if (name == "near-edge") p.origin[0] = g::maximum_coordinate - 7;
    else if (name != "standard") return {};
    return p;
}
bool within(const Coordinate& c, Integer lo, Integer hi) {
    return std::get<slider_crank::Order>(compare_to_grid(c, lo)) != slider_crank::Order::less &&
        std::get<slider_crank::Order>(compare_to_grid(c, hi)) != slider_crank::Order::greater;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: four_bar_case <kit> positive|negative slow|reverse|fast|stalled|off full|short\n"
               "Kits: standard, long-arm, short-arm, locks-later, change-point, coincident, shifted, near-edge.\n"
               "Goal: supply the crank through a real native shaft at speed magnitude 1/2.\n"
               "Keep one assembly branch over a regular complete input turn, then place its joint in both fixed work windows:\n"
               "positive input ray: x=6..10, y=4..6; opposite ray: x=4..5, y=3..4. Both lie in world plane z=8.\n"
               "Standard and long-arm kits are alternatives. A fitting current pose does not certify a whole input turn.\n"
               "Circle intersections, exact grid comparisons and geometric derivatives do not establish branch retention, body clearance, contact/forces, graph output rates, a phase clock, material or World adoption.\n";
        return finished(out);
    }
    if (args.size() != 4 || (args[1] != "positive" && args[1] != "negative") || (args[3] != "full" && args[3] != "short")) {
        errors << "Choose a four-bar kit, assembly branch, source and full|short input shaft.\n"; return 2;
    }
    auto p = kit(args[0]); auto scene = geared_cycle::fixture(args[2] == "off" ? "slow" : args[2]);
    if (!p || !scene) { errors << "Unknown four-bar kit or source.\n"; return 2; }
    p->branch = args[1] == "positive" ? Branch::positive : Branch::negative;
    if (args[2] == "off") scene->sources.clear();
    g::Point old{}; for (const auto& part : scene->parts) if (part.id == "output") old = part.center;
    for (auto& part : scene->parts) for (std::size_t i = 0; i < 3; ++i) part.center[i] += p->origin[i] - old[i] - (i == 2 ? 20 : 0);
    auto endpoint = p->origin, middle = p->origin; endpoint[2] -= 4; middle[2] -= 12;
    scene->parts.push_back({"crank-input", g::Kind::hub, endpoint, g::Axis::z});
    scene->parts.push_back({"input-shaft", g::Kind::shaft, middle, g::Axis::z, 0, args[3] == "full" ? 8 : 1});
    const auto native = g::evaluate(scene->parts, scene->sources);
    if (!native.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = native.motion.at("crank-input");
    out << "Crank input " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << ".\n";
    const auto first = sample(*p, {}, input);
    if (const auto* error = std::get_if<Refusal>(&first)) { errors << "Current pose refused: " << error_name(error->reason) << ".\n"; return 2; }
    const auto inspection = inspect(*p);
    if (const auto* error = std::get_if<Refusal>(&inspection)) { errors << "Cycle refused: " << error_name(error->reason) << ".\n"; return 2; }
    const auto& cycle = std::get<Cycle>(inspection);
    out << "Complete centre-distance range " << cycle.minimum_distance << ".." << cycle.maximum_distance
        << "; full closure " << (cycle.closed ? "yes" : "no") << "; regular " << (cycle.regular ? "yes" : "no") << ".\n";
    if (!cycle.regular) { out << "Goal unfinished: the selected input cannot complete a regular turn.\n"; return finished(out); }
    const auto second = sample(*p, {-1, 0, 1}, input);
    if (const auto* error = std::get_if<Refusal>(&second)) { errors << "Opposed pose refused: " << error_name(error->reason) << ".\n"; return 2; }
    const auto& one = std::get<Sample>(first).joint; const auto& two = std::get<Sample>(second).joint;
    const bool windows = within(one[0], 6, 10) && within(one[1], 4, 6) && within(one[2], 8, 8) &&
        within(two[0], 4, 5) && within(two[1], 3, 4) && within(two[2], 8, 8);
    out << "Both fixed work windows " << (windows ? "reached" : "missed") << ".\n";
    const bool powered = input.state == g::MotionState::rotating && (input.rate == Fraction{1, 2} || input.rate == Fraction{-1, 2});
    out << (windows && powered ? "Goal matched: same branch, two work positions and a regular input turn.\n" : "Goal unfinished: both work positions and a connected crank at speed magnitude 1/2 are required.\n");
    return finished(out);
}
}  // namespace factory::four_bar
