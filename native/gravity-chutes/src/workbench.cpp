#include "factory/gravity_workbench.hpp"

#include <array>
#include <charconv>
#include <ostream>
#include <vector>

namespace factory::gravity {
namespace {
// Original geometry fixtures informed by ft-01 elevation budgets and shapez2-03
// crossings. Their fixed slopes and kit sizes are experimental choices.
constexpr std::array<Point, 1> obstruction{{{1, 3, 0}}};
constexpr std::array<Point, 5> slope{{{0, 4, 0}, {1, 3, 0}, {2, 2, 0}, {3, 1, 0}, {3, 0, 0}}};
constexpr std::array<Route, 1> slope_routes{{{slope, {0, 4, 0}, {3, 0, 0}}}};
constexpr std::array<Point, 5> crossing_a{{{-2, 4, 0}, {-1, 3, 0}, {0, 2, 0}, {1, 1, 0}, {2, 0, 0}}};
constexpr std::array<Point, 6> crossing_b{{{0, 5, -2}, {0, 4, -1}, {0, 3, 0}, {0, 2, 0}, {0, 1, 1}, {0, 0, 2}}};
constexpr std::array<Route, 2> crossing_routes{{
    {crossing_a, {-2, 4, 0}, {2, 0, 0}}, {crossing_b, {0, 5, -2}, {0, 0, 2}},
}};
constexpr std::array<Point, 4> clearance_a{{{0, 3, 0}, {1, 2, 0}, {1, 1, 0}, {1, 0, 0}}};
constexpr std::array<Point, 4> clearance_b{{{1, 3, 0}, {0, 2, 0}, {0, 1, 0}, {0, 0, 0}}};
constexpr std::array<Route, 2> clearance_routes{{
    {clearance_a, {0, 3, 0}, {1, 0, 0}}, {clearance_b, {1, 3, 0}, {0, 0, 0}},
}};
constexpr std::array<Challenge, 3> challenges{{
    {"slope", "Spend the last level",
     "Route around the occupied anchor using the four available levels of descent.",
     {{0, 0, -1}, {3, 4, 1}, obstruction, 5}, slope_routes},
    {"crossing", "Keep the upper route high",
     "Separate the crossing streams. Spend the upper route's extra level after the crossing.",
     {{-2, 0, -2}, {2, 5, 2}, {}, 6}, crossing_routes},
    {"clearance", "Anchors do not tell the whole story",
     "The two sloping pieces cross between anchors. Use the side clearance to separate them.",
     {{0, 0, 0}, {1, 3, 1}, {}, 4}, clearance_routes},
}};

void point(std::ostream& out, Point p) { out << '(' << p.x << ',' << p.y << ',' << p.z << ')'; }

void usage(std::ostream& out) {
    out << "Gravity chute construction workbench\n"
           "Usage: gravity_workbench list | <puzzle> [--route1 PATH] [--route2 PATH]\n"
           "A PATH is x,y,z/x,y,z/... with fixed inlet and outlet. Quote it in a shell.\n"
           "Each piece descends one level and moves at most one cell along x or z.\n\n";
    for (const auto& challenge : challenges) out << challenge.id << ": " << challenge.title << '\n';
}

bool parse(std::string_view text, std::size_t limit, std::vector<Point>& points) {
    if (text.empty()) return false;
    auto* cursor = text.data();
    const auto* end = cursor + text.size();
    while (cursor != end) {
        if (points.size() == limit) return false;
        Point p;
        const std::array<std::int32_t*, 3> components{{&p.x, &p.y, &p.z}};
        for (unsigned axis = 0; axis < components.size(); ++axis) {
            const auto number = std::from_chars(cursor, end, *components[axis]);
            if (number.ec != std::errc{}) return false;
            cursor = number.ptr;
            if (axis < 2) {
                if (cursor == end || *cursor != ',') return false;
                ++cursor;
            }
        }
        points.push_back(p);
        if (cursor == end) return true;
        if (*cursor != '/' || ++cursor == end) return false;
    }
    return false;
}
}  // namespace

std::span<const Challenge> catalogue() noexcept { return challenges; }

const Challenge* find(std::string_view id) noexcept {
    for (const auto& challenge : challenges) if (challenge.id == id) return &challenge;
    return nullptr;
}

int workbench(std::span<const std::string_view> args, std::ostream& out, std::ostream& errors) {
    if (args.empty() || (args.size() == 1 && (args[0] == "list" || args[0] == "--help"))) {
        usage(out);
        return out ? 0 : 2;
    }
    const auto* challenge = find(args[0]);
    if (!challenge) { errors << "Unknown puzzle. Use gravity_workbench list.\n"; return 2; }
    std::array<std::vector<Point>, 2> edited;
    std::array<Route, 2> routes{};
    unsigned seen{};
    for (std::size_t i = 1; i < args.size(); i += 2) {
        const unsigned index = args[i] == "--route1" ? 0 : args[i] == "--route2" ? 1 : 2;
        if (index >= challenge->initial.size() || (seen & (1U << index)) || i + 1 >= args.size() ||
            !parse(args[i + 1], challenge->site.max_points, edited[index])) {
            errors << "Each available route option needs one bounded x,y,z/... path and may appear once.\n";
            return 2;
        }
        seen |= 1U << index;
    }
    for (std::size_t i = 0; i < challenge->initial.size(); ++i) {
        routes[i] = challenge->initial[i];
        if (seen & (1U << i)) routes[i].points = edited[i];
    }
    const auto active = std::span<const Route>{routes.data(), challenge->initial.size()};
    const auto report = inspect(challenge->site, active);
    out << challenge->title << '\n' << challenge->goal << '\n' << "Site ";
    point(out, challenge->site.minimum); out << " through "; point(out, challenge->site.maximum);
    out << "; at most " << challenge->site.max_points << " points per route.\n";
    for (const auto blocked : challenge->site.blocked) { out << "Occupied "; point(out, blocked); out << '\n'; }
    for (std::size_t i = 0; i < active.size(); ++i) {
        out << "Route " << (i + 1) << " inlet "; point(out, routes[i].inlet);
        out << ", outlet "; point(out, routes[i].outlet); out << "\n  ";
        for (std::size_t j = 0; j < routes[i].points.size(); ++j) {
            if (j) out << " -> ";
            point(out, routes[i].points[j]);
        }
        out << '\n';
    }
    if (report.solved()) out << "Solved: " << explanation(report.fault) << '\n';
    else {
        out << "Conflict on route " << (report.route + 1) << ", point " << (report.point + 1)
            << ": " << explanation(report.fault) << '\n';
        if (report.fault == Fault::shared_anchor || report.fault == Fault::crossing_segments) {
            out << "Meets route " << (report.other_route + 1) << ", point " << (report.other_point + 1) << ".\n";
        }
    }
    return out ? (report.solved() ? 0 : 1) : 2;
}
}  // namespace factory::gravity
