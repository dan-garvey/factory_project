#include "factory/cam_workbench.hpp"

#include "factory/cam_puzzles.hpp"

#include <charconv>
#include <ostream>
#include <string>

namespace factory::cam_puzzles {
namespace {
void usage(std::ostream& out) {
    out << "Stationary cam timing workbench\n"
           "Usage: cam_workbench list | <puzzle> [--feed N] [--ram N] [--offset N]\n"
           "Keys are zero-based tooth positions. Lobe widths are fixed for each puzzle.\n"
           "Change --offset to delay the second workstation in the paired puzzle.\n\n";
    for (const auto& challenge : catalogue()) {
        out << challenge.id << ": " << challenge.title << '\n' << "  " << challenge.goal << '\n';
    }
}

char stage_symbol(mechanisms::Stage stage) {
    switch (stage) {
        case mechanisms::Stage::dock: return 'D';
        case mechanisms::Stage::outward: return '>';
        case mechanisms::Stage::work: return 'W';
        case mechanisms::Stage::homeward: return '<';
    }
    return '?';
}

bool timeline(const Challenge& challenge, Keys keys, std::ostream& out) {
    Tooth length{};
    if (mechanisms::cycle_length(challenge.slide, length) != mechanisms::Error::none) return false;
    out << "Tooth     ";
    for (Tooth tooth = 0; tooth < length; ++tooth) out << (tooth % 10);
    out << '\n';
    for (unsigned i = 0; i < (challenge.paired ? 2U : 1U); ++i) {
        std::string slide, unload, feed, ram;
        for (Tooth tooth = 0; tooth < length; ++tooth) {
            Frame frame{};
            if (snapshot(challenge.id, keys, {tooth}, frame) != Error::none) return false;
            const auto& lane = frame.lanes[i];
            slide += stage_symbol(lane.carriage.stage);
            unload += lane.unloading ? 'U' : '.';
            feed += lane.feeding ? 'F' : '.';
            ram += lane.pressing ? 'P' : '.';
        }
        out << "Lane " << (i + 1) << "    " << slide << "  D=dock, W=work\n"
            << "Unload    " << unload << '\n' << "Feed      " << feed << '\n'
            << "Ram       " << ram << '\n';
    }
    return static_cast<bool>(out);
}
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        usage(out);
        return out ? 0 : 2;
    }
    const auto* challenge = find(args[0]);
    if (!challenge) {
        errors << "Unknown puzzle. Use cam_workbench list.\n";
        return 2;
    }
    Keys keys = challenge->initial;
    unsigned seen{};
    for (std::size_t i = 1; i < args.size(); i += 2) {
        Tooth* target{};
        unsigned bit{};
        if (args[i] == "--feed") { target = &keys.feed; bit = 1; }
        else if (args[i] == "--ram") { target = &keys.ram; bit = 2; }
        else if (args[i] == "--offset") { target = &keys.offset; bit = 4; }
        if (!target || (seen & bit) || i + 1 >= args.size()) {
            errors << "Each key option needs one unsigned integer and may appear once.\n";
            return 2;
        }
        const auto value = args[i + 1];
        if (value.empty()) {
            errors << "Each key option needs one unsigned integer and may appear once.\n";
            return 2;
        }
        const auto parsed = std::from_chars(value.data(), value.data() + value.size(), *target);
        if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size()) {
            errors << "Each key option needs one unsigned integer and may appear once.\n";
            return 2;
        }
        seen |= bit;
    }
    const auto report = inspect(challenge->id, keys);
    if (report.error != Error::none) {
        errors << "Cannot inspect this arrangement: " << error_name(report.error) << ".\n";
        return 2;
    }
    out << challenge->title << '\n' << challenge->goal << '\n'
        << "Feed key " << keys.feed << ", ram key " << keys.ram;
    if (challenge->paired) out << ", second workstation offset " << keys.offset;
    out << ". One repeating timing cycle:\n";
    if (!timeline(*challenge, keys, out)) return 2;
    if (report.solved()) out << "Solved: every timing constraint is satisfied.\n";
    else {
        out << "Conflict at tooth " << report.tooth;
        if (report.lane) out << ", lane " << report.lane;
        out << ": " << explanation(report.fault) << '\n';
    }
    return out ? (report.solved() ? 0 : 1) : 2;
}
}  // namespace factory::cam_puzzles
