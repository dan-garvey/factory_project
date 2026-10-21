#include "factory/pulley_loop.hpp"
#include "factory/pulley_loop_workbench.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <sstream>

namespace l = factory::pulley_loop;
namespace p = factory::pulley_pair;
namespace c = factory::clearance;
namespace g = factory::mechanics;
using I = g::Integer;
namespace {
std::size_t assertions{}, profiles{}, oracle_cases{}, traces{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
bool refused(const l::Inspection& value, l::Error reason) {
    const auto* error = std::get_if<l::Refusal>(&value); return error && error->reason == reason;
}
I square(I n) { return n * n; }

// Independent decomposition, without production's distance-to-SEGMENT routine:
// query two native straight boxes, then two outward-clipped circle annuli.
// Each cap finds exact closest/farthest circle distances from rectangle corners
// and explicit axis/edge candidates. No numerical square root is used.
bool decomposed(const l::Profile& profile, const c::Obstacle& obstacle) {
    const auto& first = profile.transmission.pulleys[0]; const auto& second = profile.transmission.pulleys[1];
    const auto a = static_cast<std::size_t>(first.axis), u = static_cast<std::size_t>(profile.transmission.span), v = 3 - a - u;
    const auto& box = obstacle.box;
    if (box.maximum[a] <= first.center[a] - profile.half_width || box.minimum[a] >= first.center[a] + profile.half_width) return false;
    const I left = std::min(first.center[u], second.center[u]), right = std::max(first.center[u], second.center[u]);
    const I inner = first.radius - profile.half_thickness, outer = first.radius + profile.half_thickness;
    for (I sign : {-1, 1}) {
        c::Box strap{first.center, first.center}; strap.minimum[u] = left; strap.maximum[u] = right;
        strap.minimum[a] -= profile.half_width; strap.maximum[a] += profile.half_width;
        strap.minimum[v] += sign > 0 ? inner : -outer; strap.maximum[v] += sign > 0 ? outer : -inner;
        const std::array one{obstacle};
        const auto query = c::sweep(strap, {}, one);
        require(query.error == c::Error::none, "independent straight-strap oracle uses valid native boxes");
        if (query.hit) return true;
    }
    for (std::size_t side = 0; side < 2; ++side) {
        const auto pivot = side ? right : left;
        const I low_u = side ? std::max(box.minimum[u], pivot) : box.minimum[u];
        const I high_u = side ? box.maximum[u] : std::min(box.maximum[u], pivot);
        if (low_u >= high_u) continue;
        const I x0 = low_u - pivot, x1 = high_u - pivot, y0 = box.minimum[v] - first.center[v], y1 = box.maximum[v] - first.center[v];
        std::vector<std::array<I, 2>> candidates{{x0, y0}, {x0, y1}, {x1, y0}, {x1, y1}};
        if (y0 <= 0 && y1 >= 0) { candidates.push_back({x0, 0}); candidates.push_back({x1, 0}); }
        if (x0 <= 0 && x1 >= 0) { candidates.push_back({0, y0}); candidates.push_back({0, y1}); }
        if (x0 <= 0 && x1 >= 0 && y0 <= 0 && y1 >= 0) candidates.push_back({0, 0});
        I low = std::numeric_limits<I>::max(), high{};
        for (const auto point : candidates) { const auto d = square(point[0]) + square(point[1]); low = std::min(low, d); high = std::max(high, d); }
        if (low < square(outer) && high > square(inner)) return true;
    }
    return false;
}

void finite_path_oracle() {
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        const auto v = 3 - a - u;
        for (I sign : {-1, 1}) for (const auto origin : {g::Point{0, 0, 8}, {-23, 17, 31}})
        for (I radius : {2, 4, 7}) for (std::size_t choice = 0; choice < (radius == 2 ? 1U : 2U); ++choice) {
            const I thickness = choice ? radius - 1 : 1;
            for (I extra : {3, 9}) for (I width : {1, 3}) {
                l::Profile profile; profile.half_thickness = thickness; profile.half_width = width; profile.transmission.span = static_cast<g::Axis>(u);
                for (auto& pulley : profile.transmission.pulleys) { pulley.center = origin; pulley.axis = static_cast<g::Axis>(a); pulley.radius = radius; pulley.half_width = width; }
                profile.transmission.pulleys[1].center[u] += sign * (2 * radius + extra);
                const auto empty = std::get<l::Geometry>(l::inspect(profile, {}));
                require(empty.clear() && empty.profile == profile && empty.inner_squared == square(radius - thickness) && empty.outer_squared == square(radius + thickness), "owned complete finite geometry preserves caller setup without a live material position");
                const I left = std::min(profile.transmission.pulleys[0].center[u], profile.transmission.pulleys[1].center[u]), right = std::max(profile.transmission.pulleys[0].center[u], profile.transmission.pulleys[1].center[u]);
                const I outer = radius + thickness;
                for (I x = -outer - 1; x <= right - left + outer + 1; x += 5) for (I y = -outer - 1; y <= outer + 1; y += 4)
                for (I size : {1, 4}) for (I axial : {-width - 2, I{0}, width}) {
                    c::Box box{origin, origin};
                    box.minimum[u] = left + x; box.maximum[u] = left + x + size;
                    box.minimum[v] += y; box.maximum[v] += y + size;
                    box.minimum[a] += axial; box.maximum[a] += axial + 2;
                    const c::Obstacle obstacle{81, box}; const std::array observations{obstacle};
                    const bool expected = decomposed(profile, obstacle);
                    const auto result = std::get<l::Geometry>(l::inspect(profile, observations));
                    require(result.clear() != expected, "exact centre-segment band agrees with separate straight boxes and clipped circle caps across frames, span signs and translations");
                    if (result.contact) require(result.contact->obstacle == 81 && result.contact->minimum_squared < result.outer_squared && result.contact->maximum_squared > result.inner_squared,
                        "a contact publishes a strict squared-distance existence interval, never a fabricated impact time");
                    ++oracle_cases;
                }
                ++profiles;
            }
        }
    }
}

void discriminators_and_validation() {
    l::Profile profile;
    auto inspect_box = [&](c::Box box) { const std::array<c::Obstacle, 1> observations{{{71, box}}}; return std::get<l::Geometry>(l::inspect(profile, observations)); };
    require(!inspect_box({{9, 2, 6}, {11, 4, 10}}).clear(), "a finite top strap really enters the service column");
    require(!inspect_box({{9, -4, 6}, {11, -2, 10}}).clear(), "the lower strap also participates");
    for (const auto box : {c::Box{{9, 3, 7}, {11, 4, 9}}, {{9, -4, 7}, {11, -3, 9}}, {{9, 0, 7}, {11, 1, 9}}, {{9, 2, 9}, {11, 3, 10}}, {{9, 2, 6}, {11, 3, 7}}})
        require(inspect_box(box).clear(), "outer, inner and either axial tangency are clear under the strict-interior policy");
    for (const auto box : {c::Box{{9, 1, 7}, {11, 2, 9}}, {{9, 2, 7}, {11, 3, 9}}, {{-3, -1, 7}, {-2, 1, 9}}, {{22, -1, 7}, {23, 1, 9}}})
        require(!inspect_box(box).clear(), "positive interior overlap at either band edge and either cap is detected without sampled poses");
    require(inspect_box({{1, -1, 7}, {3, 1, 9}}).clear(), "inward half-circles around the pulleys are not incorrectly filled into the open loop path");
    for (auto& pulley : profile.transmission.pulleys) pulley.radius = 4;
    require(inspect_box({{-4, 4, 7}, {-3, 5, 9}}).clear(), "an exact 3-4-5 corner tangency at the OUTER circular boundary is clear");
    for (auto& pulley : profile.transmission.pulleys) pulley.radius = 6;
    require(inspect_box({{-3, 0, 7}, {0, 4, 9}}).clear(), "an exact 3-4-5 corner tangency at the INNER cap boundary is clear");
    const std::array<c::Obstacle, 1> post{{{71, {{9, 2, 6}, {11, 4, 10}}}}};
    const auto wider = std::get<l::Geometry>(l::inspect(profile, post));
    require(wider.clear() && c::sweep(wider.bounds, {}, post).hit.has_value(), "the wider solution uses genuinely empty loop interior that a filled outer box would falsely obstruct");
    profile = {};
    const std::array<c::Obstacle, 3> mixed{{{3, {{9, 0, 7}, {11, 1, 9}}}, {81, {{9, 2, 7}, {11, 3, 9}}}, {7, {{-3, -1, 7}, {-2, 1, 9}}}}};
    for (std::size_t shift = 0; shift < mixed.size(); ++shift) {
        std::vector<c::Obstacle> observations(mixed.begin(), mixed.end()); std::rotate(observations.begin(), observations.begin() + shift, observations.end());
        require(std::get<l::Geometry>(l::inspect(profile, observations)).contact->obstacle == 7, "lowest actual obstructing identity wins independent of order, not the smaller false AABB hit");
    }
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    for (I value : {low, high, I{-1}, I{0}, p::maximum_radius}) { profile = {}; profile.half_thickness = value;
        require(refused(l::inspect(profile, {}), l::Error::invalid_loop), "raw thickness extrema validate before addition or squares"); }
    for (I value : {low, high, I{-1}, I{0}, p::maximum_half_width + 1}) { profile = {}; profile.half_width = value;
        require(refused(l::inspect(profile, {}), l::Error::invalid_loop), "raw axial width extrema validate before envelope arithmetic"); }
    profile = {}; profile.half_thickness = 2; require(refused(l::inspect(profile, {}), l::Error::invalid_loop), "a band must retain a nonempty inner opening");
    for (std::size_t side = 0; side < 2; ++side) { profile = {}; profile.half_width = 2; profile.transmission.pulleys[1 - side].half_width = 2;
        require(refused(l::inspect(profile, {}), l::Error::invalid_loop), "finite belt width must fit BOTH declared rims"); }
    profile = {}; profile.transmission.layout = p::Layout::crossed; require(refused(l::inspect(profile, {}), l::Error::unsupported_layout), "a crossed pitch line cannot acquire an invented finite crossing body");
    profile = {}; profile.transmission.pulleys[1].radius = 3; require(refused(l::inspect(profile, {}), l::Error::unsupported_layout), "unequal-radius bodies cannot be silently replaced by equal semicircles");
    profile = {}; profile.transmission.span = static_cast<g::Axis>(-1);
    const auto invalid_parent = l::inspect(profile, {});
    require(refused(invalid_parent, l::Error::parent_refused) && std::get<l::Refusal>(invalid_parent).parent_error->reason == p::Error::invalid_span, "parent raw/frame refusals propagate before new axis indexing");
    profile = {}; for (auto& pulley : profile.transmission.pulleys) { pulley.radius = 6; pulley.center[1] = g::maximum_coordinate - 6; }
    require(refused(l::inspect(profile, {}), l::Error::representation_limit), "the finite belt, not just the smaller pitch circle, must fit the entire grid");
    profile = {}; profile.transmission.pulleys[1].center[0] = g::maximum_coordinate;
    require(refused(l::inspect(profile, {}), l::Error::parent_refused), "unchanged parent separation/grid bounds remain active");
    profile = {}; for (auto& pulley : profile.transmission.pulleys) { pulley.radius = 127; pulley.half_width = 64; }
    profile.transmission.pulleys[1].center[0] = 256; profile.half_thickness = 126; profile.half_width = 64;
    require(std::holds_alternative<l::Geometry>(l::inspect(profile, {})), "largest supported equal pair and thick finite belt retain exact bounds");
    profile = {};
    for (const auto bad : {c::Obstacle{0, {{100, 100, 100}, {101, 101, 101}}}, {71, {{100, 100, 100}, {101, 101, 101}}}, {99, {{100, 100, 100}, {100, 101, 101}}}, {99, {{low, 100, 100}, {101, 101, 101}}}, {99, {{100, 100, 100}, {high, 101, 101}}}}) {
        std::vector<c::Obstacle> observations{{71, {{9, 2, 7}, {11, 3, 9}}}, bad};
        require(refused(l::inspect(profile, observations), l::Error::query_refused), "a visible early hit cannot conceal malformed, duplicate or out-of-grid far observations");
    }
    std::vector<c::Obstacle> too_many;
    for (std::size_t i = 0; i <= g::maximum_parts; ++i) too_many.push_back({i + 1, {{100, 100, 100}, {101, 101, 101}}});
    require(refused(l::inspect(profile, too_many), l::Error::query_refused), "unsupported complete sets refuse instead of truncating");
    const std::array<c::Obstacle, 1> huge{{{1, {{-g::maximum_coordinate, -g::maximum_coordinate, -g::maximum_coordinate}, {g::maximum_coordinate, g::maximum_coordinate, g::maximum_coordinate}}}}};
    require(!std::get<l::Geometry>(l::inspect(profile, huge)).clear(), "full native extreme distance squares remain bounded while detecting containment");
    auto copy = wider; copy.profile.half_thickness = 99; copy.bounds.minimum[0] = 99;
    require(copy.profile.half_thickness == 99 && wider.profile.half_thickness == 1 && std::get<l::Geometry>(l::inspect(profile, {})).clear(), "returned values have no hidden mutable geometry or observation owner");
}

void consumers() {
    struct Case { std::string_view kit, source, shaft, finding; bool matched; int exit; };
    const std::array<Case, 25> cases{{
        {"wide", "slow", "full", "Goal matched:", true, 0}, {"raised", "slow", "full", "Goal matched:", true, 0}, {"rerouted", "slow", "full", "Goal matched:", true, 0},
        {"tight", "slow", "full", "overlaps service obstacle 71", false, 0}, {"tight", "off", "full", "overlaps service obstacle 71", false, 0},
        {"wide", "reverse", "full", "Readout rotating -1/2", false, 0}, {"wide", "fast", "full", "Readout rotating 5/2", false, 0},
        {"wide", "off", "full", "source unpowered", false, 0}, {"wide", "stalled", "full", "source stalled", false, 0},
        {"short-input", "slow", "full", "source unpowered", false, 0}, {"wide", "slow", "short", "Readout unpowered", false, 0},
        {"raised", "slow", "short", "Readout unpowered", false, 0}, {"rerouted", "slow", "short", "Readout unpowered", false, 0},
        {"shifted", "slow", "full", "Readout unpowered", false, 0}, {"crossed", "slow", "full", "unsupported_layout", false, 0},
        {"unequal", "slow", "full", "unsupported_layout", false, 0}, {"raised", "reverse", "full", "Readout rotating -1/2", false, 0},
        {"rerouted", "fast", "full", "Readout rotating 5/2", false, 0}, {"rerouted", "stalled", "full", "source stalled", false, 0},
        {"near-edge", "slow", "full", "representation_limit", false, 2}, {"near-edge", "off", "full", "representation_limit", false, 2},
        {"belt-edge", "slow", "full", "representation_limit", false, 2}, {"belt-edge", "off", "full", "representation_limit", false, 2},
        {"bad-observation", "slow", "full", "query_refused", false, 2}, {"bad-observation", "off", "full", "query_refused", false, 2},
    }};
    for (const auto& test : cases) {
        const std::array args{test.kit, test.source, test.shaft}; std::ostringstream out, errors;
        require(l::workbench(args, out, errors) == test.exit, "the actual native routing consumer returns its declared trace/refusal status");
        require((out.str() + errors.str()).find(test.finding) != std::string::npos && (out.str().find("Goal matched:") != std::string::npos) == test.matched, "finite full-path geometry and actual source/readout connectivity decide the original routing puzzle");
        require(test.exit == 2 ? !errors.str().empty() : errors.str().empty(), "malformed observations/native bounds are separate from valid unfinished routing");
        if (test.matched) require(out.str().find("Complete finite loop path is clear") != std::string::npos, "every working arrangement qualifies the complete corridor, not snapshots or a filled outer box");
        ++traces;
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{}, {"list"}, {"--help"}}) {
        std::ostringstream out, errors; require(l::workbench(args, out, errors) == 0 && errors.str().empty() && out.str().find("usable empty interior") != std::string::npos, "the catalogue discloses the finite shape and adoption limits");
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{"bogus", "slow", "full"}, {"wide", "bogus", "full"}, {"wide", "slow", "bogus"}, {"wide"}, {"wide", "slow"}, {"wide", "slow", "full", "extra"}, {"list", "extra"}}) {
        std::ostringstream out, errors; require(l::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().find("Goal matched:") == std::string::npos, "malformed callers cannot publish a complete-path match");
    }
    std::ostringstream out, errors; out.setstate(std::ios::badbit);
    const std::array<std::string_view, 3> args{"wide", "slow", "full"};
    require(l::workbench(args, out, errors) == 2, "an unwritable transcript is not a successful observation");
}
}  // namespace

int main() {
    finite_path_oracle(); discriminators_and_validation(); consumers();
    std::cout << "PASS " << assertions << " assertions; " << profiles << " geometry profiles; " << oracle_cases << " independent four-piece path cases; " << traces << " consumer traces.\n";
}
