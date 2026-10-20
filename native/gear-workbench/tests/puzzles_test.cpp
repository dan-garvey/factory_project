#include "factory/gear_puzzles.hpp"
#include "factory/gear_workbench.hpp"

#include <initializer_list>
#include <iostream>
#include <limits>
#include <sstream>

namespace p = factory::gear_puzzles;
namespace m = factory::mechanics;
namespace {
int checks{};
int failures{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}

void literal_arrangements() {
    check(p::catalogue().size() == 3 && !p::find("missing"), "The workbench exposes three named geometry challenges.");
    for (const auto& challenge : p::catalogue()) {
        const auto report = p::inspect(challenge.id, challenge.initial);
        check(!report.solved() && report.error == p::Error::none && report.derivation.accepted() &&
              report.actual.state == m::MotionState::unpowered,
              "Each initial arrangement is legal geometry with a visibly unpowered target.");
    }
    const p::Placements idler{{m::Point{40, 0, 0}, std::nullopt}};
    const auto forward = p::inspect("idler", idler);
    check(forward.solved() && forward.actual.rate == m::Rate{1, 2},
          "The real intermediate gear adds two external meshes and yields forward half speed.");
    for (const auto sign : {-1, 1}) {
        const p::Placements bend{{m::Point{24, sign * 32, 0}, m::Point{64, sign * 32, 0}}};
        const auto reverse = p::inspect("bend", bend);
        check(reverse.solved() && reverse.actual.rate == m::Rate{-1, 1},
              "Both mirrored three-mesh routes reverse the target at exactly equal speed.");
        const p::Placements swapped{{bend[1], bend[0]}};
        check(p::inspect("bend", swapped).solved(), "Equal carried gears may exchange slots without creating a hidden ordering rule.");
    }
    const p::Placements compound{{m::Point{60, 0, 1}, std::nullopt}};
    const auto bridged = p::inspect("compound", compound);
    check(bridged.solved() && bridged.actual.rate == m::Rate{1, 2},
          "A real shaft joins the large and small gears across two planes at the correct compound ratio.");
    for (m::Integer z = -2; z <= 4; ++z) {
        check(p::inspect("compound", {m::Point{60, 0, z}, std::nullopt}).solved() == (z == 1),
              "Only the correct axial center reaches both compound gears with the finite shaft span.");
    }
}

void exhaustive_idler() {
    unsigned solutions{};
    for (m::Integer x = -20; x <= 120; ++x) {
        for (m::Integer y = -5; y <= 5; ++y) {
            const p::Placements placement{{m::Point{x, y, 0}, std::nullopt}};
            const auto report = p::inspect("idler", placement);
            // The fixed centers are 100 apart. The two pitch sums are 40 and
            // 60, so equality in the triangle bound requires the center (40,0).
            check(report.solved() == (x == 40 && y == 0),
                  "Every tested integer idler position agrees with the independent exact tangency constraint.");
            solutions += report.solved();
        }
    }
    check(solutions == 1, "The constrained idler fixture has one center in this complete planar search strip.");
}

void refusals() {
    const auto unknown = p::inspect("missing", {});
    check(!unknown.solved() && unknown.error == p::Error::unknown_challenge,
          "Unknown content cannot silently choose or solve a default fixture.");
    const auto extra = p::inspect("idler", {m::Point{40, 0, 0}, m::Point{0, 40, 0}});
    check(!extra.solved() && extra.error == p::Error::unavailable_part && extra.derivation.motion.empty(),
          "A player cannot submit a second part absent from the fixture kit.");
    for (const auto point : {m::Point{121, 0, 0}, m::Point{40, -61, 0}, m::Point{40, 0, 5},
                             m::Point{std::numeric_limits<m::Integer>::max(), 0, 0}}) {
        const auto outside = p::inspect("idler", {point, std::nullopt});
        check(!outside.solved() && outside.error == p::Error::outside_site && outside.derivation.motion.empty(),
              "Out-of-site placements are refused before any geometric result is published.");
    }
    const auto overlap = p::inspect("idler", {m::Point{39, 0, 0}, std::nullopt});
    check(!overlap.solved() && overlap.error == p::Error::invalid_geometry &&
          overlap.derivation.error == m::Error::overlapping_gears && overlap.derivation.motion.empty(),
          "Overlapping pitch circles cannot become a shortcut to a positive ratio.");
    const auto off_plane = p::inspect("idler", {m::Point{40, 0, 1}, std::nullopt});
    check(!off_plane.solved() && off_plane.error == p::Error::none && off_plane.actual.state == m::MotionState::unpowered,
          "A nearby gear on the wrong plane cannot acquire an invisible mesh.");
    const auto absent = p::inspect("bend", {});
    check(!absent.solved() && absent.error == p::Error::none && absent.actual.state == m::MotionState::unpowered,
          "Removing both kit parts leaves the target unpowered without altering fixed geometry.");
}

void cli(std::initializer_list<std::string_view> args, int code, std::string_view expected) {
    std::ostringstream output, errors;
    const auto result = p::workbench({args.begin(), args.size()}, output, errors);
    check(result == code && (output.str() + errors.str()).find(expected) != std::string::npos,
          "The actual terminal parser preserves the expected outcome and explanation.");
}

void command_cases() {
    cli({}, 0, "gear_workbench list");
    cli({"list"}, 0, "missing axial bridge");
    cli({"idler"}, 1, "actual unpowered");
    cli({"bend"}, 1, "Keep building");
    cli({"compound"}, 1, "Keep building");
    cli({"idler", "--one", "40,0,0"}, 0, "Solved:");
    cli({"bend", "--one", "24,32,0", "--two", "64,32,0"}, 0, "actual rotating -1/1");
    cli({"bend", "--one", "24,-32,0", "--two", "64,-32,0"}, 0, "Solved:");
    cli({"compound", "--one", "60,0,1"}, 0, "actual rotating 1/2");
    cli({"compound", "--one", "none"}, 1, "actual unpowered");
    cli({"idler", "--one", "39,0,0"}, 1, "overlapping_gears");
    cli({"idler", "--one", "121,0,0"}, 1, "outside_site");
    cli({"missing"}, 2, "Unknown puzzle");
    cli({"idler", "--two", "40,0,0"}, 2, "Each available kit option");
    cli({"idler", "--one"}, 2, "Each available kit option");
    cli({"idler", "--other", "40,0,0"}, 2, "Each available kit option");
    cli({"idler", "--one", "40,0,0", "--one", "40,0,0"}, 2, "Each available kit option");
    for (const auto value : {"", "40,0", "40,0,0,0", "40,0,0x", "+40,0,0", "40,0.5,0", "9223372036854775808,0,0"}) {
        cli({"idler", "--one", value}, 2, "Each available kit option");
    }
    std::ostringstream output, errors;
    output.setstate(std::ios::badbit);
    const std::array<std::string_view, 1> args{{"list"}};
    check(p::workbench(args, output, errors) == 2, "An output failure cannot report successful command completion.");
}
}  // namespace

int main() {
    literal_arrangements();
    exhaustive_idler();
    refusals();
    command_cases();
    std::cout << checks << " geometric gear puzzle checks, " << failures << " failures.\n";
    return failures == 0 ? 0 : 1;
}
