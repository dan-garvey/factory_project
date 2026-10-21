#include "factory/pulley_pair.hpp"
#include "factory/pulley_pair_workbench.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace p = factory::pulley_pair;
namespace g = factory::mechanics;
namespace s = factory::slider_crank;
namespace c = factory::clearance;
namespace k = factory::geared_cycle;
using I = g::Integer;
using F = g::Rate;
namespace {
std::size_t assertions{}, profiles{}, contact_witnesses{}, drive_cases{}, traces{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
F fraction(I n, I d = 1) { if (d < 0) { n = -n; d = -d; } const auto divisor = std::gcd(n, d); return {n / divisor, d / divisor}; }
F add(F a, F b) { return fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator); }
F scale(F a, I n) { return fraction(a.numerator * n, a.denominator); }
F multiply(F a, F b) { return fraction(a.numerator * b.numerator, a.denominator * b.denominator); }
F divide(F a, F b) { require(b.numerator != 0, "independent velocity projection is nonzero"); return fraction(a.numerator * b.denominator, a.denominator * b.numerator); }
template<class T> bool refused(const T& value, p::Error reason) {
    const auto* error = std::get_if<p::Refusal>(&value); return error && error->reason == reason;
}
F along(const p::Coordinate& coordinate, I origin) {
    require(coordinate.radicand == 0, "span direction stays rational");
    return fraction(coordinate.base - origin * coordinate.denominator, coordinate.denominator);
}
F transverse(const p::Coordinate& coordinate, I origin, I radical, I handed) {
    require(coordinate.base == origin * coordinate.denominator && coordinate.radicand % radical == 0, "transverse coordinate uses only one shared exact root");
    I factor{};
    for (I candidate = 1; candidate <= p::maximum_radius; ++candidate) if (candidate * candidate == coordinate.radicand / radical) factor = candidate;
    require(factor != 0, "independent bounded square enumeration exactly decodes the coordinate coefficient");
    return fraction(handed * factor * (coordinate.branch == s::Branch::positive ? 1 : -1), coordinate.denominator);
}

void geometry_and_sources() {
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        const auto v = 3 - a - u;
        const I handed = (a + 1) % 3 == u ? 1 : -1;
        for (I sign : {-1, 1}) for (const auto origin : {g::Point{0, 0, 8}, {-42, 17, 36}})
        for (I first_radius : {1, 2, 3, 5, 8}) for (I second_radius : {1, 2, 3, 5, 8})
        for (I distance : {first_radius + second_radius + 1, first_radius + second_radius + 7, I{40}})
        for (auto layout : {p::Layout::open, p::Layout::crossed}) {
            p::Profile profile; profile.span = static_cast<g::Axis>(u); profile.layout = layout;
            for (auto& pulley : profile.pulleys) { pulley.center = origin; pulley.axis = static_cast<g::Axis>(a); }
            profile.pulleys[0].radius = first_radius; profile.pulleys[1].radius = second_radius;
            profile.pulleys[1].center[u] += sign * distance;
            const auto unpowered = std::get<p::Evaluation>(p::evaluate(profile, {})); const auto& geometry = unpowered.geometry;
            require(geometry.profile == profile && geometry.separation == distance && geometry.straight_span_squared > 0, "owned geometry preserves descriptor order, signed layout and separation");
            require(unpowered.motion == std::array{g::Motion{}, g::Motion{}} && !unpowered.prescribed[0] && !unpowered.prescribed[1], "absent prescriptions do not invent power");
            F ratio{};
            for (std::size_t strand = 0; strand < 2; ++strand) {
                std::array<F, 2> radial_u{}, radial_v{};
                for (std::size_t side = 0; side < 2; ++side) {
                    const auto& pulley = profile.pulleys[side]; const auto& point = geometry.strands[strand][side];
                    radial_u[side] = along(point[u], pulley.center[u]);
                    radial_v[side] = transverse(point[v], pulley.center[v], geometry.straight_span_squared, handed);
                    const auto square = add(multiply(radial_u[side], radial_u[side]), scale(multiply(radial_v[side], radial_v[side]), geometry.straight_span_squared));
                    require(square == fraction(pulley.radius * pulley.radius), "independent exact 3D pitch-circle equation holds at each tangent point");
                    require(std::get<std::optional<F>>(s::rational_view(point[a])) == std::optional<F>{fraction(origin[a])}, "both strands stay in the actual common shaft plane");
                    for (std::size_t i = 0; i < 3; ++i) require(std::get<s::Order>(s::compare_to_grid(point[i], geometry.pitch_bounds[side].minimum[i])) != s::Order::less &&
                        std::get<s::Order>(s::compare_to_grid(point[i], geometry.pitch_bounds[side].maximum[i])) != s::Order::greater, "exact endpoints fit their conservative native envelopes without rounded roots");
                }
                const auto du = add(fraction(sign * distance), add(radial_u[1], scale(radial_u[0], -1)));
                const auto dv = add(radial_v[1], scale(radial_v[0], -1));
                require(add(multiply(du, du), scale(multiply(dv, dv), geometry.straight_span_squared)) == fraction(geometry.straight_span_squared), "the actual endpoint difference has the declared exact straight pitch length");
                std::array<F, 2> velocity_projection{};
                for (std::size_t side = 0; side < 2; ++side) {
                    require(add(multiply(du, radial_u[side]), scale(multiply(dv, radial_v[side]), geometry.straight_span_squared)) == F{}, "each strand is perpendicular to BOTH actual radius vectors, rather than merely joining arbitrary circle points");
                    // In the proper shaft/span frame, omega cross radius is
                    // (-b*sqrt(K), a)*omega. Its tangent projection has the
                    // common sqrt(K) factor; cancel it without numerical roots.
                    velocity_projection[side] = add(scale(multiply(radial_v[side], du), -1), multiply(radial_u[side], dv));
                    ++contact_witnesses;
                }
                const auto inferred = divide(velocity_projection[0], velocity_projection[1]);
                require(inferred == geometry.second_from_first, "matching actual signed surface velocities independently derives the transmission ratio without the production virtual-gear routine");
                if (strand) require(inferred == ratio, "both pitch strands constrain the same global rotation relation");
                ratio = inferred;
                require((ratio.numerator > 0) == (layout == p::Layout::open), "open and crossed tangency geometry independently fixes direction");
            }
            const F input{3, 2}, output = multiply(input, ratio), backwards = divide(F{-5, 3}, ratio);
            const std::array<std::vector<p::Drive>, 8> drives{{{{7, input}}, {{7, {-3, 2}}}, {{11, {-5, 3}}}, {{7, {}}},
                {{7, input}, {11, output}}, {{11, output}, {7, input}}, {{7, input}, {11, add(output, {1, 1})}}, {{7, {}}, {11, {1, 1}}}}};
            for (std::size_t index = 0; index < drives.size(); ++index) {
                const auto result = std::get<p::Evaluation>(p::evaluate(profile, drives[index]));
                require(result.geometry.strands == geometry.strands && result.geometry.profile == profile, "source arrangements cannot mutate geometric observations");
                for (const auto& drive : drives[index]) require(result.prescribed[drive.pulley == 7 ? 0 : 1] == std::optional<F>{drive.rate}, "normalized caller prescriptions survive conflicts and argument order");
                if (index >= 6) require(result.motion[0].state == g::MotionState::stalled && result.motion[1].state == g::MotionState::stalled && result.motion[0].rate == F{} && result.motion[1].rate == F{}, "incompatible prescriptions stall the connected ideal pair without partial rates");
                else if (index == 3) require(result.motion == std::array{g::Motion{g::MotionState::stopped, {}}, g::Motion{g::MotionState::stopped, {}}}, "an explicit zero stops both members instead of making them unpowered");
                else {
                    const F first_rate = index == 1 ? F{-3, 2} : index == 2 ? backwards : input;
                    require(result.motion[0] == g::Motion{g::MotionState::rotating, first_rate} && result.motion[1] == g::Motion{g::MotionState::rotating, multiply(first_rate, ratio)}, "either driven port and both prescription orders satisfy the independent surface-velocity witness");
                }
                ++drive_cases;
            }
            auto swapped = profile; std::swap(swapped.pulleys[0], swapped.pulleys[1]);
            const auto reversed = std::get<p::Evaluation>(p::evaluate(swapped, {}));
            require(reversed.geometry.second_from_first == divide(F{1, 1}, ratio), "descriptor reversal inverts the same physical relation");
            for (std::size_t strand = 0; strand < 2; ++strand) for (std::size_t side = 0; side < 2; ++side)
                require(reversed.geometry.strands[strand][side] == geometry.strands[layout == p::Layout::open ? 1 - strand : strand][1 - side], "reversing descriptors preserves actual tangent points, with the correct external/internal strand ordering");
            ++profiles;
        }
    }
}

void bounds_and_raw() {
    p::Profile profile;
    const auto original = std::get<p::Evaluation>(p::evaluate(profile, {}));
    const std::array<c::Obstacle, 1> middle{{{91, {{9, -1, 7}, {11, 1, 9}}}}};
    require(c::sweep(original.geometry.loop_bounds, {}, middle).hit.has_value() && c::sweep(original.geometry.pitch_bounds[0], {}, middle).clear() && c::sweep(original.geometry.pitch_bounds[1], {}, middle).clear(), "a filled loop AABB falsely occupies the genuinely empty middle between pulley envelopes");
    for (const auto& strand : original.geometry.strands) for (const auto& point : strand)
        require(std::get<s::Order>(s::compare_to_grid(point[1], 1)) == s::Order::greater || std::get<s::Order>(s::compare_to_grid(point[1], -1)) == s::Order::less, "both straight constant-height pitch strands also clear that middle post; loop bounds are not the belt solid");
    const std::vector<g::Part> bare{{"a", g::Kind::hub, {0, 0, 8}, g::Axis::z}, {"as", g::Kind::shaft, {0, 0, 8}, g::Axis::z, 0, 1}, {"ag", g::Kind::gear, {0, 0, 8}, g::Axis::z, 2},
        {"b", g::Kind::hub, {20, 0, 8}, g::Axis::z}, {"bs", g::Kind::shaft, {20, 0, 8}, g::Axis::z, 0, 1}, {"bg", g::Kind::gear, {20, 0, 8}, g::Axis::z, 2}};
    const auto ordinary = g::evaluate(bare, {{"a", {1, 2}}});
    require(ordinary.accepted() && ordinary.motion.at("b").state == g::MotionState::unpowered, "the explicit adapter never gives bare separated ordinary gears a fictitious engagement");
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    for (std::size_t side = 0; side < 2; ++side) {
        for (I value : {low, high, I{-1}, I{0}, p::maximum_radius + 1}) { profile = {}; profile.pulleys[side].radius = value;
            require(refused(p::evaluate(profile, {}), p::Error::invalid_pulley), "raw radius extrema refuse before tangent products"); }
        for (I value : {low, high, I{-1}, I{0}, p::maximum_half_width + 1}) { profile = {}; profile.pulleys[side].half_width = value;
            require(refused(p::evaluate(profile, {}), p::Error::invalid_pulley), "raw axial width extrema refuse before envelope arithmetic"); }
        for (std::size_t axis = 0; axis < 3; ++axis) for (I value : {low, high, -g::maximum_coordinate - 1, g::maximum_coordinate + 1}) { profile = {}; profile.pulleys[side].center[axis] = value;
            require(refused(p::evaluate(profile, {}), p::Error::invalid_pulley), "every raw centre validates before subtraction"); }
        profile = {}; profile.pulleys[side].id = 0; require(refused(p::evaluate(profile, {}), p::Error::invalid_pulley), "both opaque identities must be nonzero");
        profile = {}; profile.pulleys[side].axis = static_cast<g::Axis>(-1); require(refused(p::evaluate(profile, {}), p::Error::invalid_pulley), "raw shaft enums refuse before indexing");
    }
    profile = {}; profile.pulleys[1].id = 7; require(refused(p::evaluate(profile, {}), p::Error::duplicate_id), "duplicate IDs cannot alias outputs");
    profile = {}; profile.layout = static_cast<p::Layout>(-1); require(refused(p::evaluate(profile, {}), p::Error::invalid_layout), "unknown routing cannot default to a sign");
    for (auto axis : {static_cast<g::Axis>(-1), static_cast<g::Axis>(3), g::Axis::z}) { profile = {}; profile.span = axis;
        require(refused(p::evaluate(profile, {}), p::Error::invalid_span), "the declared span frame is valid and perpendicular before indexing"); }
    profile = {}; profile.pulleys[1].axis = g::Axis::x; require(refused(p::evaluate(profile, {}), p::Error::nonparallel), "nonparallel shafts do not acquire a quarter-turn belt model");
    for (std::size_t i : {1U, 2U}) { profile = {}; ++profile.pulleys[1].center[i]; require(refused(p::evaluate(profile, {}), p::Error::skew), "both axial and transverse offsets invalidate this coplanar span"); }
    for (I distance : {I{0}, p::maximum_separation + 1, -p::maximum_separation - 1}) { profile = {}; profile.pulleys[1].center[0] = distance;
        require(refused(p::evaluate(profile, {}), p::Error::spacing_limit), "zero or unsupported separation refuses without rounded tangent denominators"); }
    for (I distance : {1, 3, 4}) { profile = {}; profile.pulleys[1].center[0] = distance;
        for (auto layout : {p::Layout::open, p::Layout::crossed}) { profile.layout = layout; require(refused(p::evaluate(profile, {}), p::Error::pitch_overlap), "touching and overlapping pulleys cannot claim a free pitch strand"); } }
    profile = {};
    for (const std::vector<p::Drive>& drives : {std::vector<p::Drive>{{99, {1, 1}}}, {{7, {}}, {7, {1, 2}}}, {{7, {}}, {11, {}}, {13, {}}}}) {
        const auto expected = drives.size() == 1 ? p::Error::unknown_pulley : drives.size() == 2 ? p::Error::duplicate_drive : p::Error::too_many_drives;
        require(refused(p::evaluate(profile, drives), expected), "all prescription identities and count are validated");
    }
    for (const F rate : {F{1, 0}, {0, -1}, {low, 1}, {high, 1}, {1, k::maximum_denominator + 1}, {257, 1}}) {
        profile = {}; profile.pulleys[1].center[2] = 9;
        const std::array<p::Drive, 2> drives{{{7, {1, 2}}, {11, rate}}};
        require(refused(p::evaluate(profile, drives), p::Error::invalid_rate), "the full second raw source validates even when geometry is skew");
    }
    for (auto layout : {p::Layout::open, p::Layout::crossed}) {
        profile = {}; profile.layout = layout;
        for (const F rate : {F{high, high}, {low, I{1} << 62}, {0, high}}) {
            const std::array<p::Drive, 1> drives{{{11, rate}}};
            const auto result = std::get<p::Evaluation>(p::evaluate(profile, drives));
            const F expected = rate.numerator == low ? F{-2, 1} : rate.numerator == 0 ? F{} : F{1, 1};
            require(result.prescribed[1] == std::optional<F>{expected} && result.motion[1].rate == expected, "raw signed extrema and zero reduce BEFORE the second local-axis sign change");
        }
        profile.pulleys[0].radius = 128; profile.pulleys[1].radius = 127; profile.pulleys[1].center[0] = 256;
        require(std::holds_alternative<p::Evaluation>(p::evaluate(profile, {})), "largest supported tangent coefficients and denominators remain exact in both layouts");
    }
    profile = {}; profile.pulleys[0].radius = 128; profile.pulleys[1].radius = 1; profile.pulleys[1].center[0] = 256;
    const std::array<p::Drive, 1> too_fast{{{7, {256, 1}}}};
    require(refused(p::evaluate(profile, too_fast), p::Error::unsupported_result), "unsupported inferred speed returns no partial geometry or motion");
    profile.pulleys[0].radius = 1; profile.pulleys[1].radius = 127;
    const std::array<p::Drive, 1> precision{{{7, {1, 1000000}}}};
    require(refused(p::evaluate(profile, precision), p::Error::unsupported_result), "unsupported inferred denominator refuses instead of rounding");
    for (std::size_t axis = 0; axis < 3; ++axis) { profile = {}; for (auto& pulley : profile.pulleys) pulley.center[axis] = g::maximum_coordinate; if (axis == 0) profile.pulleys[0].center[axis] -= 20;
        require(refused(p::evaluate(profile, {}), p::Error::representation_limit), "full radial and finite-width envelopes retain all native grid bounds"); }
    auto copy = original; copy.geometry.profile.pulleys[0].center[0] = 99; copy.geometry.strands[0][0][0].base = 99;
    require(std::get<p::Evaluation>(p::evaluate(p::Profile{}, {})).geometry.profile == p::Profile{} && original.geometry.profile == p::Profile{}, "owned result changes cannot mutate descriptors or future evaluations");
}

void consumers() {
    struct Case { std::string_view kit, source, shaft, finding; bool matched; int exit; };
    const std::array<Case, 25> cases{{
        {"open", "slow", "full", "Goal matched:", true, 0}, {"mirrored", "slow", "full", "Goal matched:", true, 0},
        {"raised", "slow", "full", "Goal matched:", true, 0}, {"crossed", "reverse", "full", "Goal matched:", true, 0},
        {"reduction", "fast", "full", "Goal matched:", true, 0}, {"open", "reverse", "full", "output rotating -1/2", false, 0},
        {"crossed", "slow", "full", "output rotating -1/2", false, 0}, {"reduction", "slow", "full", "output rotating 1/10", false, 0},
        {"open", "fast", "full", "output rotating 5/2", false, 0}, {"wrong-size", "slow", "full", "output rotating 3/4", false, 0},
        {"low", "slow", "full", "pitch envelope overlaps", false, 0}, {"skew", "slow", "full", "Goal unfinished: skew", false, 0},
        {"nonparallel", "slow", "full", "Goal unfinished: nonparallel", false, 0}, {"crowded", "slow", "full", "pitch_overlap", false, 0},
        {"too-far", "slow", "full", "spacing_limit", false, 0}, {"shifted", "slow", "full", "Readout unpowered", false, 0},
        {"short-input", "slow", "full", "source unpowered", false, 0}, {"open", "slow", "short", "Readout unpowered", false, 0},
        {"crossed", "reverse", "short", "Readout unpowered", false, 0}, {"reduction", "fast", "short", "Readout unpowered", false, 0},
        {"open", "stalled", "full", "source stalled", false, 0}, {"open", "off", "full", "source unpowered", false, 0},
        {"crossed", "off", "full", "source unpowered", false, 0}, {"near-edge", "slow", "full", "representation_limit", false, 2},
        {"near-edge", "off", "full", "representation_limit", false, 2},
    }};
    for (const auto& test : cases) {
        const std::array args{test.kit, test.source, test.shaft}; std::ostringstream out, errors;
        require(p::workbench(args, out, errors) == test.exit, "the actual native pulley consumer returns the declared trace/refusal status");
        require((out.str() + errors.str()).find(test.finding) != std::string::npos && (out.str().find("Goal matched:") != std::string::npos) == test.matched, "real source/readout shafts and ideal pitch geometry decide the original remote transmission goal");
        require(test.exit == 2 ? !errors.str().empty() : errors.str().empty(), "valid unfinished pitch setups stay distinct from native representation refusal");
        if (test.matched) require(out.str().find("ideal pitch kinematics only") != std::string::npos, "an ideal crossed arrangement never claims physical crossing or contact admission");
        if (test.kit == "reduction" && test.matched) require(out.str().find("sqrt(") != std::string::npos, "the actual successful reduction retains nonsquare tangencies");
        ++traces;
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{}, {"list"}, {"--help"}}) {
        std::ostringstream out, errors; require(p::workbench(args, out, errors) == 0 && errors.str().empty() && out.str().find("not filled-belt collision shapes") != std::string::npos, "the catalogue discloses crossing, bounds and physical-adoption limits");
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{"bogus", "slow", "full"}, {"open", "bogus", "full"}, {"open", "slow", "bogus"}, {"open"}, {"open", "slow"}, {"open", "slow", "full", "extra"}, {"list", "extra"}}) {
        std::ostringstream out, errors; require(p::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().find("Goal matched:") == std::string::npos, "malformed callers cannot publish an ideal transmission match");
    }
    std::ostringstream out, errors; out.setstate(std::ios::badbit);
    const std::array<std::string_view, 3> args{"open", "slow", "full"};
    require(p::workbench(args, out, errors) == 2, "an unwritable transcript is not a successful observation");
}
}  // namespace

int main() {
    geometry_and_sources(); bounds_and_raw(); consumers();
    std::cout << "PASS " << assertions << " assertions; " << profiles << " geometry profiles; " << contact_witnesses << " independent tangent/surface-velocity contacts; "
        << drive_cases << " source arrangements; " << traces << " consumer traces.\n";
}
