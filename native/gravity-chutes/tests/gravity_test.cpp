#include "factory/gravity_workbench.hpp"

#include <array>
#include <initializer_list>
#include <iostream>
#include <limits>
#include <sstream>
#include <vector>

namespace g = factory::gravity;
namespace {
int checks{};
int failures{};

void check(bool condition, std::string_view message) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}

void literal_puzzles() {
    check(g::catalogue().size() == 3 && !g::find("missing"), "The catalogue contains three distinct original route puzzles.");
    const auto* slope = g::find("slope");
    const auto obstruction = g::inspect(slope->site, slope->initial);
    check(obstruction.fault == g::Fault::blocked_anchor && obstruction.route == 0 && obstruction.point == 1,
          "The initial slope reaches the literal occupied second anchor.");
    const std::array<g::Point, 5> lower{{{0, 4, 0}, {0, 3, 0}, {1, 2, 0}, {2, 1, 0}, {3, 0, 0}}};
    const std::array<g::Route, 1> lower_route{{{lower, {0, 4, 0}, {3, 0, 0}}}};
    check(g::inspect(slope->site, lower_route).solved(), "Spending the spare level before the obstruction solves the slope.");
    const auto* crossing = g::find("crossing");
    const auto contact = g::inspect(crossing->site, crossing->initial);
    check(contact.fault == g::Fault::shared_anchor && contact.route == 1 && contact.point == 3 &&
          contact.other_route == 0 && contact.other_point == 2,
          "The premature vertical drop collides with the lower route at the exact crossing anchor.");
    const std::array<g::Point, 6> high{{{0, 5, -2}, {0, 4, -1}, {0, 3, 0}, {0, 2, 1}, {0, 1, 2}, {0, 0, 2}}};
    const std::array<g::Point, 6> alternate{{{0, 5, -2}, {0, 4, -1}, {0, 3, 0}, {0, 2, 1}, {0, 1, 1}, {0, 0, 2}}};
    for (const auto& points : {high, alternate}) {
        std::array<g::Route, 2> routes{{crossing->initial[0], {points, {0, 5, -2}, {0, 0, 2}}}};
        check(g::inspect(crossing->site, routes).solved(), "Either legal late drop preserves height until after crossing.");
    }
    const auto* clearance = g::find("clearance");
    const auto midpoint = g::inspect(clearance->site, clearance->initial);
    check(midpoint.fault == g::Fault::crossing_segments && midpoint.route == 1 && midpoint.point == 1 &&
          midpoint.other_route == 0 && midpoint.other_point == 1,
          "Distinct anchors still expose the first pair of intersecting descending pieces.");
    const std::array<g::Point, 4> side{{{0, 3, 0}, {0, 2, 1}, {1, 1, 1}, {1, 0, 0}}};
    const std::array<g::Route, 2> side_routes{{{side, {0, 3, 0}, {1, 0, 0}}, clearance->initial[1]}};
    check(g::inspect(clearance->site, side_routes).solved(), "Using the third dimension clears the sloping-piece collision.");
}

// Independent general intersection calculation. Equal y intervals require the
// same interpolation fraction on both segments; solve the two x/z equations.
bool intersect(const std::array<g::Point, 2>& a, const std::array<g::Point, 2>& b) {
    const auto sx = static_cast<std::int64_t>(a[0].x) - b[0].x;
    const auto sz = static_cast<std::int64_t>(a[0].z) - b[0].z;
    const auto dx = (static_cast<std::int64_t>(a[1].x) - a[0].x) -
                    (static_cast<std::int64_t>(b[1].x) - b[0].x);
    const auto dz = (static_cast<std::int64_t>(a[1].z) - a[0].z) -
                    (static_cast<std::int64_t>(b[1].z) - b[0].z);
    if (dx == 0 && dz == 0) return sx == 0 && sz == 0;
    auto numerator = dx != 0 ? -sx : -sz;
    auto denominator = dx != 0 ? dx : dz;
    if (denominator < 0) { denominator = -denominator; numerator = -numerator; }
    return numerator >= 0 && numerator <= denominator &&
           sx * denominator + numerator * dx == 0 && sz * denominator + numerator * dz == 0;
}

void exhaustive_crossings(std::int32_t offset_x, std::int32_t offset_z) {
    std::vector<std::array<g::Point, 2>> segments;
    const std::array<std::array<int, 2>, 5> moves{{{{0, 0}}, {{1, 0}}, {{-1, 0}}, {{0, 1}}, {{0, -1}}}};
    for (int x = 0; x <= 2; ++x) {
        for (int z = 0; z <= 2; ++z) {
            for (const auto move : moves) {
                const int next_x = x + move[0], next_z = z + move[1];
                if (next_x < 0 || next_x > 2 || next_z < 0 || next_z > 2) continue;
                segments.push_back({g::Point{offset_x + x, 1, offset_z + z},
                                    g::Point{offset_x + next_x, 0, offset_z + next_z}});
            }
        }
    }
    const g::Site site{{offset_x, 0, offset_z}, {offset_x + 2, 1, offset_z + 2}, {}, 2};
    for (const auto& a : segments) {
        for (const auto& b : segments) {
            const std::array<g::Route, 2> routes{{{a, a.front(), a.back()}, {b, b.front(), b.back()}}};
            check(g::inspect(site, routes).solved() == !intersect(a, b),
                  "All local piece pairs agree with an independent exact intersection equation.");
        }
    }
}

g::Report single(std::span<const g::Point> points, g::Site site = {{-4, -4, -4}, {4, 4, 4}, {}, 8}) {
    const std::array<g::Route, 1> routes{{{points, points.front(), points.back()}}};
    return g::inspect(site, routes);
}

void refusals_and_limits() {
    const std::array<g::Point, 3> valid{{{0, 2, 0}, {1, 1, 0}, {1, 0, 0}}};
    check(single(valid).solved(), "A literal vertical-plus-sloped route is legal.");
    check(single(valid, {{-4, -4, -4}, {4, 4, 4}, {}, 2}).fault == g::Fault::too_long,
          "A point budget is enforced instead of silently granting extra pieces.");
    check(single(valid, {{0, 0, 0}, {0, 2, 0}, {}, 8}).fault == g::Fault::outside_site,
          "A route cannot bypass the fixture bounds.");
    check(single(valid, {{1, 0, 0}, {0, 2, 0}, {}, 8}).fault == g::Fault::invalid_site,
          "Reversed site bounds are refused.");
    check(single(valid, {{-4, -4, -4}, {4, 4, 4}, {}, 1}).fault == g::Fault::invalid_site,
          "A site budget cannot omit its required inlet and outlet.");
    const std::array<g::Point, 1> invalid_block{{{9, 9, 9}}};
    check(single(valid, {{-4, -4, -4}, {4, 4, 4}, invalid_block, 8}).fault == g::Fault::invalid_site,
          "Out-of-site obstructions cannot be silently discarded.");
    const g::Site site{{-4, -4, -4}, {4, 4, 4}, {}, 8};
    check(g::inspect(site, {}).fault == g::Fault::no_routes, "An empty layout cannot be solved vacuously.");
    const std::array<g::Route, 1> empty{{{{}, {0, 2, 0}, {0, 0, 0}}}};
    check(g::inspect(site, empty).fault == g::Fault::too_short, "An empty route is refused before accessing its endpoints.");
    std::array<g::Route, 1> wrong{{{valid, {1, 2, 0}, {1, 0, 0}}}};
    check(g::inspect(site, wrong).fault == g::Fault::wrong_inlet, "Moving the fixed inlet cannot solve a puzzle.");
    wrong[0] = {valid, {0, 2, 0}, {0, 0, 0}};
    check(g::inspect(site, wrong).fault == g::Fault::wrong_outlet, "Moving the fixed outlet cannot solve a puzzle.");
    const std::array<g::Point, 3> flat{{{0, 2, 0}, {0, 2, 0}, {0, 0, 0}}};
    check(single(flat).fault == g::Fault::invalid_drop, "A horizontal or duplicate step cannot invent a flat gravity conveyor.");
    const std::array<g::Point, 3> skipped{{{0, 3, 0}, {0, 1, 0}, {0, 0, 0}}};
    check(single(skipped).fault == g::Fault::invalid_drop, "A piece cannot silently skip a vertical construction level.");
    const std::array<g::Point, 3> diagonal{{{0, 2, 0}, {1, 1, 1}, {0, 0, 0}}};
    check(single(diagonal).fault == g::Fault::invalid_horizontal_step, "Diagonal horizontal shortcuts require additional pieces.");
    const std::array<g::Point, 2> impossible{{{0, 1, 0}, {2, 0, 0}}};
    check(single(impossible).fault == g::Fault::insufficient_elevation, "Height must cover the required horizontal distance.");
    constexpr auto low = std::numeric_limits<std::int32_t>::min();
    constexpr auto high = std::numeric_limits<std::int32_t>::max();
    const std::array<g::Point, 2> extremes{{{low, 1, low}, {high, 0, high}}};
    check(single(extremes, {{low, low, low}, {high, high, high}, {}, 2}).fault == g::Fault::insufficient_elevation,
          "Extreme signed coordinates cannot overflow into a legal shortcut.");
    const std::array<g::Point, 2> shallow{{{high, high, high}, {high, high - 1, high}}};
    check(single(shallow, {{low, low, low}, {high, high, high}, {}, 2}).solved(),
          "Legitimate one-level construction works at the largest signed coordinates.");
}

void cli(std::initializer_list<std::string_view> args, int code, std::string_view expected) {
    std::ostringstream output, errors;
    const auto result = g::workbench({args.begin(), args.size()}, output, errors);
    check(result == code && (output.str() + errors.str()).find(expected) != std::string::npos,
          "The actual terminal parser returns the expected result and useful explanation.");
}

void command_cases() {
    cli({}, 0, "gravity_workbench list");
    cli({"list"}, 0, "Keep the upper route high");
    cli({"slope"}, 1, "occupied by the site obstruction");
    cli({"crossing"}, 1, "same construction anchor");
    cli({"clearance"}, 1, "cross between anchors");
    cli({"slope", "--route1", "0,4,0/0,3,0/1,2,0/2,1,0/3,0,0"}, 0, "Solved:");
    cli({"crossing", "--route2", "0,5,-2/0,4,-1/0,3,0/0,2,1/0,1,2/0,0,2"}, 0, "Solved:");
    cli({"clearance", "--route1", "0,3,0/0,2,1/1,1,1/1,0,0"}, 0, "Solved:");
    cli({"missing"}, 2, "Unknown puzzle");
    cli({"slope", "--route2", "0,4,0/3,0,0"}, 2, "Each available route option");
    cli({"slope", "--route1"}, 2, "Each available route option");
    cli({"slope", "--other", "0,4,0/3,0,0"}, 2, "Each available route option");
    cli({"slope", "--route1", "0,4,0/3,0,0", "--route1", "0,4,0/3,0,0"}, 2, "Each available route option");
    for (const auto bad : {"", "0,4", "0,4,0/", "0,4,0x/3,0,0", "0,4,0,1", "0,4,0//3,0,0",
                            "+0,4,0/3,0,0", "2147483648,4,0/3,0,0", "0,4,0/0,3,0/0,2,0/1,1,0/2,0,0/3,-1,0"}) {
        cli({"slope", "--route1", bad}, 2, "Each available route option");
    }
    std::ostringstream output, errors;
    output.setstate(std::ios::badbit);
    const std::array<std::string_view, 1> args{{"list"}};
    check(g::workbench(args, output, errors) == 2, "An output failure cannot report successful workbench completion.");
}
}  // namespace

int main() {
    literal_puzzles();
    exhaustive_crossings(0, 0);
    exhaustive_crossings(std::numeric_limits<std::int32_t>::max() - 2,
                        std::numeric_limits<std::int32_t>::min());
    refusals_and_limits();
    command_cases();
    std::cout << checks << " gravity route checks, " << failures << " failures.\n";
    return failures == 0 ? 0 : 1;
}
