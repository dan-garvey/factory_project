#include "factory/tusi_stroke_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/tusi_stroke.hpp"

#include <ostream>

namespace factory::tusi_stroke {
namespace g = mechanics;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "long-stroke") p.radius = 5;
    else if (name == "short-stroke") p.radius = 3;
    else if (name == "tilted") p.clocking = {3, 4, 5};
    else if (name == "vertical") p.clocking = {-1, 0, 1};
    else if (name == "shifted") p.origin[0] = 2;
    else if (name == "free-ring") p.ring_locked = false;
    else if (name == "near-edge") p.origin[0] = g::maximum_coordinate - 1;
    else if (name == "bad-clocking") p.clocking = {1, 1, 1};
    else if (name != "standard") return {};
    return p;
}
bool within(Fraction f, Integer lo, Integer hi) { return f.numerator >= lo * f.denominator && f.numerator <= hi * f.denominator; }
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: tusi_case <kit> slow|reverse|fast|stalled|off full|short\n"
               "Kits: standard, long-stroke, short-stroke, tilted, vertical, shifted, free-ring, near-edge, bad-clocking.\n"
               "Goal: both fixed end windows x=-10..-7 and x=7..10, y=-1..1, z=8, with a complete fitting guide stroke.\n"
               "Standard and long-stroke kits work. Supply the carrier through a real native shaft at speed magnitude 1/2.\n"
               "The declared ring restraint and 2:1 pitch radii produce opposite absolute planet spin; relative spin is minus twice the carrier.\n"
               "Every pin clocking produces a line, but it can be oblique and exceed the finite transverse guide.\n"
               "Pitch geometry and per-radian derivatives do not establish tooth/body clearance, force/contact, ring construction, native graph adoption, a clock or material production.\n";
        return finished(out);
    }
    if (args.size() != 3 || (args[2] != "full" && args[2] != "short")) { errors << "Choose a stroke kit, source and full|short input shaft.\n"; return 2; }
    auto p = kit(args[0]); auto scene = geared_cycle::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!p || !scene) { errors << "Unknown stroke kit or source.\n"; return 2; }
    if (args[1] == "off") scene->sources.clear();
    g::Point old{}; for (const auto& part : scene->parts) if (part.id == "output") old = part.center;
    for (auto& part : scene->parts) for (std::size_t i = 0; i < 3; ++i) part.center[i] += p->origin[i] - old[i] - (i == 2 ? 20 : 0);
    auto endpoint = p->origin, middle = p->origin; endpoint[2] -= 4; middle[2] -= 12;
    scene->parts.push_back({"carrier", g::Kind::hub, endpoint, g::Axis::z});
    scene->parts.push_back({"input-shaft", g::Kind::shaft, middle, g::Axis::z, 0, args[2] == "full" ? 8 : 1});
    const auto native = g::evaluate(scene->parts, scene->sources);
    if (!native.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = native.motion.at("carrier");
    out << "Carrier " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator << ".\n";
    const auto current = sample(*p, {}, input);
    if (const auto* error = std::get_if<Refusal>(&current)) { errors << "Current pose refused: " << error_name(error->reason) << ".\n"; return 2; }
    const auto& one = std::get<Sample>(current);
    out << "Absolute planet " << g::motion_state_name(one.planet.state) << ' ' << one.planet.rate.numerator << '/' << one.planet.rate.denominator << ".\n";
    const auto inspection = inspect(*p);
    if (const auto* error = std::get_if<Refusal>(&inspection)) { errors << "Whole stroke refused: " << error_name(error->reason) << ".\n"; return 2; }
    if (!std::get<Cycle>(inspection).guide_fits) { out << "Goal unfinished: complete stroke exceeds the finite guide.\n"; return finished(out); }
    const auto two = std::get<Sample>(sample(*p, {-1, 0, 1}, input));
    const bool windows = within(one.pin[0], 7, 10) && within(two.pin[0], -10, -7) && within(one.pin[1], -1, 1) &&
        within(two.pin[1], -1, 1) && within(one.pin[2], 8, 8) && within(two.pin[2], 8, 8);
    const bool speed = input.state == g::MotionState::rotating && (input.rate == Fraction{1, 2} || input.rate == Fraction{-1, 2});
    out << (windows && speed ? "Goal matched: fixed ring, two end windows and full guide travel.\n" : "Goal unfinished: both end windows and a connected carrier at speed magnitude 1/2 are required.\n");
    return finished(out);
}
}  // namespace factory::tusi_stroke
