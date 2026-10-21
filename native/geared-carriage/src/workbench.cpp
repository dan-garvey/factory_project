#include "factory/geared_carriage_workbench.hpp"

#include "factory/geared_carriage.hpp"
#include "factory/geared_cycle_workbench.hpp"

#include <charconv>
#include <istream>
#include <ostream>
#include <sstream>

namespace factory::geared_carriage {
namespace g = mechanics;
namespace k = geared_cycle;
namespace {
std::optional<k::Fixture> source(std::string_view name) {
    if (name != "burst") return k::fixture(name);
    k::Fixture scene;
    scene.parts = {
        {"source", g::Kind::hub, {0, 0, 0}, g::Axis::z},
        {"source-shaft", g::Kind::shaft, {0, 0, 0}, g::Axis::z, 0, 1},
        {"source-gear", g::Kind::gear, {0, 0, 0}, g::Axis::z, 20},
        {"idler", g::Kind::gear, {21, 0, 0}, g::Axis::z, 1},
        {"output", g::Kind::hub, {24, 0, 0}, g::Axis::z},
        {"output-shaft", g::Kind::shaft, {24, 0, 0}, g::Axis::z, 0, 1},
        {"output-gear", g::Kind::gear, {24, 0, 0}, g::Axis::z, 2},
    };
    scene.sources = {{"source", {1, 1}}};
    return scene;
}
void help(std::ostream& out) {
    out << "Usage: geared_carriage_workbench play slow|fast|reverse|burst|stalled | list\n"
           "Commands: tick <1..64>; barrier low|grazing|raised; power on|off; status; help; quit.\n"
           "Return the same carriage home after ten accepted tooth visits.\n"
           "A blocked tick retains its original phase and publishes no partial visits.\n"
           "This is an exact envelope/phase puzzle, without game bodies or material.\n";
}
bool complete(k::Phase phase, std::size_t visits) noexcept { return visits >= 10 && phase == k::Phase{}; }
void show(k::Phase phase, std::size_t visits, int height, bool powered, std::ostream& out) {
    out << "Phase " << phase.numerator << '/' << phase.denominator << "; accepted visits " << visits
        << "; barrier " << (height == 0 ? "low" : height == 1 ? "grazing" : "raised")
        << "; power " << (powered ? "on" : "off") << ".\n";
    out << (complete(phase, visits) ? "Complete: ten accepted visits and the same carriage returned home.\n"
                                  : "Unfinished: give the carriage a clear route and return home.\n");
}
enum class Read { line, end, too_long, failed };
Read read(std::istream& input, std::string& line) {
    line.clear();
    bool overflow{};
    char ch{};
    while (input.get(ch)) {
        if (ch == '\n') return overflow ? Read::too_long : Read::line;
        if (line.size() < 512) line.push_back(ch); else overflow = true;
    }
    if (input.bad() || (!input.eof() && input.fail())) return Read::failed;
    if (overflow) return Read::too_long;
    return line.empty() ? Read::end : Read::line;
}
}  // namespace

int workbench(std::span<const std::string_view> args, std::istream& input,
              std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        help(out);
        return out ? 0 : 2;
    }
    if (args.size() != 2 || args[0] != "play") { errors << "Choose play <gear fixture> or list.\n"; return 2; }
    const auto scene = source(args[1]);
    if (!scene) { errors << "Unknown gear fixture.\n"; return 2; }
    const auto derived = g::evaluate(scene->parts, scene->sources);
    if (!derived.accepted()) { errors << "The declared gear fixture is invalid.\n"; return 2; }
    const auto output = derived.motion.at("output");
    const auto rate = output.state == g::MotionState::rotating ? output.rate : g::Rate{};
    out << "Native output " << g::motion_state_name(output.state) << ' '
        << output.rate.numerator << '/' << output.rate.denominator << ".\n";
    help(out);
    const Profile profile;
    k::Phase phase;
    std::size_t visits{};
    int height{};
    bool powered{true};
    show(phase, visits, height, powered, out);
    std::string line;
    while (out) {
        const auto read_result = read(input, line);
        if (read_result == Read::failed) { errors << "Input failed.\n"; return 2; }
        if (read_result == Read::end) return complete(phase, visits) ? 0 : 1;
        if (read_result == Read::too_long) { out << "Refused: command exceeds 512 bytes.\n"; continue; }
        std::istringstream command(line);
        std::string verb, argument, extra;
        if (!(command >> verb)) continue;
        if (verb == "quit" && !(command >> extra)) return complete(phase, visits) ? 0 : 1;
        if (verb == "status" && !(command >> extra)) { show(phase, visits, height, powered, out); continue; }
        if (verb == "help" && !(command >> extra)) { help(out); continue; }
        if (!(command >> argument) || (command >> extra)) { out << "Refused: use the listed commands.\n"; continue; }
        if (verb == "barrier" && (argument == "low" || argument == "grazing" || argument == "raised")) {
            height = argument == "low" ? 0 : argument == "grazing" ? 1 : 2;
            show(phase, visits, height, powered, out);
            continue;
        }
        if (verb == "power" && (argument == "on" || argument == "off")) {
            powered = argument == "on";
            show(phase, visits, height, powered, out);
            continue;
        }
        g::Integer ticks{};
        if (verb != "tick") { out << "Refused: use the listed commands.\n"; continue; }
        const auto parsed = std::from_chars(argument.data(), argument.data() + argument.size(), ticks);
        if (parsed.ec != std::errc{} || parsed.ptr != argument.data() + argument.size() || ticks < 1 || ticks > 64) {
            out << "Refused: tick needs a whole count from 1 through 64.\n";
            continue;
        }
        for (g::Integer tick = 0; tick < ticks; ++tick) {
            const clearance::Obstacle barrier{7, {{3, height, 0}, {4, height + 1, 1}}};
            auto plan = prepare(profile, phase, {rate, powered, {&barrier, 1}});
            if (const auto* refusal = std::get_if<Refusal>(&plan)) {
                errors << "Fixture proposal refused: " << error_name(refusal->reason) << ".\n";
                return 2;
            }
            if (const auto* held = std::get_if<Hold>(&plan)) {
                out << "Hold " << stop_name(held->reason);
                if (held->contact) out << " against obstacle " << held->contact->obstacle << " at tooth "
                    << held->contact->tooth << " + " << held->contact->fraction.numerator << '/' << held->contact->fraction.denominator;
                out << "; original phase and visits retained.\n";
                break;
            }
            auto proposed = std::get<Step>(std::move(plan)).proposed;
            phase = proposed.next;
            visits += proposed.crossings.size();
        }
        show(phase, visits, height, powered, out);
    }
    return 2;
}
}  // namespace factory::geared_carriage
