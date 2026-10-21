#include "factory/scotch_yoke_workbench.hpp"

#include "factory/geared_cycle_workbench.hpp"
#include "factory/scotch_yoke.hpp"

#include <optional>
#include <ostream>

namespace factory::scotch_yoke {
namespace g = mechanics;
namespace c = clearance;
namespace k = geared_cycle;
namespace {
std::optional<Profile> kit(std::string_view name) {
    Profile p;
    if (name == "wide") p.slot_half_width = 8;
    else if (name == "horizontal") {}
    else {
        p.shaft = g::Axis::y;
        if (name == "short-slot") p.slot_half_length = 6;
        else if (name == "tight") p.pin_radius = 2;
        else if (name == "small") p.radius = 4;
        else if (name == "shifted") p.origin[2] = 12;
        else if (name == "wrong-travel") p.travel = g::Axis::z;
        else if (name == "near-edge") p.origin[0] = g::maximum_coordinate - 5;
        else if (name != "upright" && name != "short-drive") return {};
    }
    return p;
}
int finished(std::ostream& out) { return out ? 0 : 2; }
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        out << "Usage: yoke_case <kit> slow|reverse|fast|stalled|off\n"
               "Kits: horizontal, wide, upright, short-drive, short-slot, tight, small, shifted, wrong-travel, near-edge.\n"
               "Goal: full reciprocation between (-6,0,8) and (6,0,8), from shaft speed magnitude 1/2.\n"
               "Either input rotation sense may solve the repeating stroke.\n"
               "A wide opening can enclose post 99 throughout the turn; an upright mount routes the narrow frame past it.\n"
               "Clear stroke endpoints do not prove the intervening travel is clear.\n"
               "The actual four frame walls are tested separately; the open slot is not a solid box.\n"
               "Pin clearance uses a conservative circular-pin envelope. Crank arm and guide/housing solids remain outside it.\n"
               "Printed directions are geometric observations, not a clock or per-tick velocity integration.\n"
               "No force/contact response, body/graph adoption, material work or World is established.\n";
        return finished(out);
    }
    if (args.size() != 2) { errors << "Choose a yoke kit and native source.\n"; return 2; }
    const auto selected = kit(args[0]);
    auto source = k::fixture(args[1] == "off" ? "slow" : args[1]);
    if (!selected || !source) { errors << "Unknown yoke kit or source.\n"; return 2; }
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
        // This fixture's parts all rotate about its old +Z. The proper basis
        // maps +Z to the actual new +shaft, preserving the registered sign.
        part.axis = selected->shaft;
    }
    auto shaft_end = selected->origin, shaft_centre = selected->origin;
    shaft_end[a] -= 4; shaft_centre[a] -= 12;
    source->parts.push_back({"crank-input", g::Kind::hub, shaft_end, selected->shaft});
    source->parts.push_back({"crank-drive", g::Kind::shaft, shaft_centre, selected->shaft, 0, args[0] == "short-drive" ? 1 : 8});
    const auto supplied = g::evaluate(source->parts, source->sources);
    if (!supplied.accepted()) { errors << "Native source refused.\n"; return 2; }
    const auto input = supplied.motion.at("crank-input");
    out << "Source " << args[1] << ": " << g::motion_state_name(input.state) << ' ' << input.rate.numerator << '/' << input.rate.denominator
        << " about +" << "XYZ"[a] << " at shaft end (" << shaft_end[0] << ',' << shaft_end[1] << ',' << shaft_end[2] << ").\n";
    const auto reading = sample(*selected, {}, input);
    if (const auto* refusal = std::get_if<Refusal>(&reading)) {
        if (refusal->reason == Error::representation_limit || refusal->reason == Error::invalid_rate) {
            errors << "Current pose refused: " << error_name(refusal->reason) << ".\n";
            return 2;
        }
        out << "Goal unfinished: " << error_name(refusal->reason) << ".\n";
        return finished(out);
    }
    const std::array<c::Obstacle, 1> obstacles{{{99, {{-1, 2, 7}, {1, 3, 9}}}}};
    const auto candidate = prepare_turn(*selected, obstacles);
    if (const auto* refusal = std::get_if<Refusal>(&candidate)) {
        errors << "Complete turn refused: " << error_name(refusal->reason) << ". No movement is admitted.\n";
        return 2;
    }
    const auto& turn = std::get<Turn>(candidate);
    if (!turn.slot_fits[0] || !turn.slot_fits[1]) {
        out << "Goal unfinished: finite pin does not fit the complete " << (!turn.slot_fits[0] ? "slot width" : "slot length") << ".\n";
        return finished(out);
    }
    if (!turn.admitted()) {
        if (turn.pin_clearance.hit) out << "Goal unfinished: rotating pin envelope overlaps post " << turn.pin_clearance.hit->obstacle << ".\n";
        else for (std::size_t i = 0; i < 4; ++i) if (turn.walls[i].hit) {
            out << "Goal unfinished: frame wall " << i << " crosses post " << turn.walls[i].hit->obstacle << " between clear stroke endpoints.\n";
            break;
        }
        return finished(out);
    }
    out << "Complete turn: finite pin and all four separate frame walls clear post 99.\n";
    if (input.state == g::MotionState::unpowered || input.state == g::MotionState::stalled) {
        out << "Goal unfinished: source " << g::motion_state_name(input.state) << "; no stroke is admitted.\n";
        return finished(out);
    }
    for (const Direction direction : {Direction{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}, {3, 4, 5}}) {
        const auto pose = sample(*selected, direction, input);
        if (const auto* refusal = std::get_if<Refusal>(&pose)) { errors << "Pose refused: " << error_name(refusal->reason) << ".\n"; return 2; }
        const auto& result = std::get<Sample>(pose);
        out << "Direction (" << direction.cosine << ',' << direction.sine << ")/" << direction.scale << ": yoke (";
        for (std::size_t i = 0; i < 3; ++i) out << (i ? "," : "") << result.yoke[i].numerator << '/' << result.yoke[i].denominator;
        out << ").\n";
    }
    const bool work_line = selected->travel == g::Axis::x && selected->origin == g::Point{0, 0, 8} && selected->radius == 6;
    const bool speed = input.state == g::MotionState::rotating && (input.rate == g::Rate{1, 2} || input.rate == g::Rate{-1, 2});
    out << (work_line && speed ? "Goal matched.\n" : "Goal unfinished: require the fixed stroke endpoints and input speed magnitude 1/2.\n");
    return finished(out);
}
}  // namespace factory::scotch_yoke
