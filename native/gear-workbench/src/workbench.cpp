#include "factory/gear_workbench.hpp"

#include "factory/gear_puzzles.hpp"

#include <charconv>
#include <ostream>

namespace factory::gear_puzzles {
namespace {
void point(std::ostream& out, const mechanics::Point& p) { out << p[0] << ',' << p[1] << ',' << p[2]; }

void usage(std::ostream& out) {
    out << "Geometric gear workbench\n"
           "Usage: gear_workbench list | <puzzle> [--one x,y,z|none] [--two x,y,z|none]\n"
           "Coordinates use exact pitch units. A gear's pitch radius equals its tooth count.\n"
           "Move only the declared kit parts; the input and output stay fixed.\n\n";
    for (const auto& challenge : catalogue()) out << challenge.id << ": " << challenge.title << '\n';
}

bool parse(std::string_view text, mechanics::Point& result) {
    if (text.empty()) return false;
    const auto* cursor = text.data();
    const auto* end = cursor + text.size();
    mechanics::Point point{};
    for (std::size_t axis = 0; axis < point.size(); ++axis) {
        const auto value = std::from_chars(cursor, end, point[axis]);
        if (value.ec != std::errc{}) return false;
        cursor = value.ptr;
        if (axis != 2) {
            if (cursor == end || *cursor != ',') return false;
            ++cursor;
        }
    }
    if (cursor != end) return false;
    result = point;
    return true;
}
}  // namespace

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        usage(out);
        return out ? 0 : 2;
    }
    const auto* challenge = find(args[0]);
    if (!challenge) { errors << "Unknown puzzle. Use gear_workbench list.\n"; return 2; }
    auto placements = challenge->initial;
    unsigned seen{};
    for (std::size_t i = 1; i < args.size(); i += 2) {
        const unsigned index = args[i] == "--one" ? 0 : args[i] == "--two" ? 1 : 2;
        if (index >= placements.size() || !challenge->kit[index] || (seen & (1U << index)) || i + 1 >= args.size()) {
            errors << "Each available kit option needs one x,y,z position or none and may appear once.\n";
            return 2;
        }
        if (args[i + 1] == "none") placements[index].reset();
        else {
            mechanics::Point parsed{};
            if (!parse(args[i + 1], parsed)) {
                errors << "Each available kit option needs one x,y,z position or none and may appear once.\n";
                return 2;
            }
            placements[index] = parsed;
        }
        seen |= 1U << index;
    }
    const auto report = inspect(challenge->id, placements);
    out << challenge->title << '\n' << challenge->goal << '\n' << "Site ";
    point(out, site_minimum); out << " through "; point(out, site_maximum); out << ".\n";
    for (const auto& part : challenge->fixed) {
        out << "Fixed " << part.id << " at "; point(out, part.center); out << '\n';
    }
    for (std::size_t i = 0; i < challenge->kit.size(); ++i) {
        if (!challenge->kit[i]) continue;
        const auto slot = *challenge->kit[i];
        out << "Part " << (i + 1) << (slot.kind == mechanics::Kind::gear ? " gear, teeth " : " shaft, half-span ")
            << (slot.kind == mechanics::Kind::gear ? slot.teeth : slot.half_span) << " at ";
        if (placements[i]) point(out, *placements[i]); else out << "none";
        out << '\n';
    }
    if (report.error != Error::none) {
        out << "Layout refused: " << error_name(report.error);
        if (report.error == Error::invalid_geometry) out << " (" << mechanics::error_name(report.derivation.error) << ')';
        out << ".\n";
    } else {
        out << "Target output " << report.required.numerator << '/' << report.required.denominator
            << "; actual " << mechanics::motion_state_name(report.actual.state) << ' '
            << report.actual.rate.numerator << '/' << report.actual.rate.denominator << ".\n";
        for (const auto& contact : report.derivation.engagements) out << "Contact " << contact.a << " <-> " << contact.b << '\n';
        out << (report.solved() ? "Solved: the geometric gear route meets the target.\n" : "Keep building: match the required output direction and ratio.\n");
    }
    return out ? (report.solved() ? 0 : 1) : 2;
}
}  // namespace factory::gear_puzzles
