#include "factory/orbital_platform.hpp"
#include "factory/orbital_platform_workbench.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <sstream>

namespace o = factory::orbital_platform;
namespace g = factory::mechanics;
namespace c = factory::clearance;
namespace k = factory::geared_cycle;
using I = g::Integer;
using F = g::Rate;
namespace {
std::size_t assertions{}, rectangles{}, poses{}, caller_traces{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
F fraction(I n, I d = 1) {
    require(d > 0, "independent rational oracle has a positive denominator");
    const auto divisor = std::gcd(n, d);
    return {n / divisor, d / divisor};
}
F add(F a, F b) { return fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator); }
F scale(F a, I n) { return fraction(a.numerator * n, a.denominator); }
g::Motion moving(F rate = {1, 2}) { return {g::MotionState::rotating, rate}; }
template<class T> bool refused(const T& result, o::Error reason, std::optional<c::Error> geometry = {}) {
    const auto* error = std::get_if<o::Refusal>(&result);
    return error && error->reason == reason && error->geometry_error == geometry;
}

// Independent exact boundary-witness oracle. It does NOT compute the rectangle's
// nearest/farthest radius. It checks cardinal points, circle/edge roots and
// corner entry directions, including second-order entry at cardinal tangencies.
bool positive_root_between(I squared, I lo, I hi) {
    if (!squared) return lo < 0 && hi > 0;
    return hi > 0 && (lo < 0 || lo * lo < squared) && squared < hi * hi;
}
bool circle_rectangle(I r, I lx, I hx, I ly, I hy) {
    for (const auto p : {std::array<I, 2>{r, 0}, {0, r}, {-r, 0}, {0, -r}})
        if (lx < p[0] && p[0] < hx && ly < p[1] && p[1] < hy) return true;
    for (unsigned axis = 0; axis < 2; ++axis) {
        const auto lo = axis ? ly : lx, hi = axis ? hy : hx, other_lo = axis ? lx : ly, other_hi = axis ? hx : hy;
        for (unsigned side = 0; side < 2; ++side) {
            const auto edge = side ? hi : lo;
            const auto squared = r * r - edge * edge;
            if (squared < 0) continue;
            const bool root_inside = positive_root_between(squared, other_lo, other_hi) || positive_root_between(squared, -other_hi, -other_lo);
            if (root_inside && (squared > 0 || (side == 0 ? edge == -r : edge == r))) return true;
        }
    }
    for (unsigned xside = 0; xside < 2; ++xside) for (unsigned yside = 0; yside < 2; ++yside) {
        const I x = xside ? hx : lx, y = yside ? hy : ly;
        if (x * x + y * y != r * r) continue;
        const std::array<I, 2> inward{xside ? -1 : 1, yside ? -1 : 1}, point{x, y}, tangent{-y, x};
        for (I sign : {-1, 1}) {
            bool enters = true;
            for (std::size_t a = 0; a < 2; ++a)
                enters = enters && inward[a] * (tangent[a] ? sign * tangent[a] : -point[a]) > 0;
            if (enters) return true;
        }
    }
    return false;
}

void independent_orbits() {
    for (std::size_t axis = 0; axis < 3; ++axis) for (I radius = 1; radius <= 6; ++radius)
    for (I lx = -8; lx <= 7; ++lx) for (I hx = lx + 2; hx <= 9; ++hx)
    for (I ly = -8; ly <= 7; ++ly) for (I hy = ly + 2; hy <= 9; ++hy) {
        const auto u = (axis + 1) % 3, v = (axis + 2) % 3;
        const c::Box body{{0, 0, 0}, {1, 1, 1}};
        c::Obstacle obstacle{731, {{-1, -1, -1}, {2, 2, 2}}};
        obstacle.box.minimum[u] = lx + 1; obstacle.box.maximum[u] = hx;
        obstacle.box.minimum[v] = ly + 1; obstacle.box.maximum[v] = hy;
        const std::array obstacles{obstacle};
        const auto query = o::orbit(body, static_cast<g::Axis>(axis), radius, obstacles);
        require(std::holds_alternative<o::Orbit>(query), "bounded circle-translation query is representable in every axis");
        const auto& actual = std::get<o::Orbit>(query);
        require(actual.clear() != circle_rectangle(radius, lx, hx, ly, hy), "whole-circle overlap agrees with independent exact circle-edge/corner witnesses");
        if (actual.contact) require(actual.contact->obstacle == 731 && actual.contact->minimum_squared < radius * radius && radius * radius < actual.contact->maximum_squared,
            "the returned displacement interval strictly contains the supplied orbit radius, without an impact-time claim");
        ++rectangles;
    }
    require(!circle_rectangle(5, 3, 6, 4, 7) && !circle_rectangle(5, -3, 3, -4, 4), "external and internal corner-only tangency are both clear");
    require(circle_rectangle(5, 0, 5, 0, 5) && circle_rectangle(5, -5, 5, -5, 5), "cardinal boundary points still allow open interior circle arcs");
    const c::Box body{{-1, -1, -1}, {1, 1, 1}};
    const std::array inside{c::Obstacle{33, body}};
    require(c::sweep(body, {}, inside).hit.has_value() && std::get<o::Orbit>(o::orbit(body, g::Axis::z, 10, inside)).clear(),
        "overlap at the untranslated reference is not an actual positive-radius orbit pose");
    const std::array tangent{c::Obstacle{33, {{3, -1, -1}, {4, 1, 1}}}};
    require(std::get<o::Orbit>(o::orbit(body, g::Axis::z, 2, tangent)).clear() && !std::get<o::Orbit>(o::orbit(body, g::Axis::z, 3, tangent)).clear(),
        "side-only tangency is clear while a slightly larger circle enters the obstacle");
    const std::array axial{c::Obstacle{33, {{-20, -20, 1}, {20, 20, 2}}}};
    require(std::get<o::Orbit>(o::orbit(body, g::Axis::z, 5, axial)).clear(), "axial-face contact alone remains clear throughout the orbit");
}

void declared_branch_poses() {
    const std::array<o::Direction, 12> directions{{{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}, {3, 4, 5}, {-3, 4, 5}, {3, -4, 5}, {-3, -4, 5}, {5, 12, 13}, {-5, 12, 13}, {8, 15, 17}, {20, -21, 29}}};
    const std::array<g::Motion, 5> motions{{moving(), moving({-7, 11}), {g::MotionState::unpowered, {}}, {g::MotionState::stopped, {}}, {g::MotionState::stalled, {}}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        const auto v = 3 - a - u;
        std::array<I, 3> normal{}, first{};
        normal[a] = 1; first[u] = 1;
        const std::array<I, 3> second{normal[1] * first[2] - normal[2] * first[1], normal[2] * first[0] - normal[0] * first[2], normal[0] * first[1] - normal[1] * first[0]};
        for (const auto origin : {g::Point{0, 0, 8}, {-42, 17, 39}}) for (I spacing : {1, 12, 64}) for (I radius : {1, 4, 16}) {
            o::Profile p; p.origin = origin; p.shaft = static_cast<g::Axis>(a); p.span = static_cast<g::Axis>(u); p.spacing = spacing; p.radius = radius;
            const auto setup = std::get<o::Setup>(o::inspect(p, {}));
            require(setup.tray.clear(), "bounded empty-observation declared branch has no stationary contact");
            for (std::size_t i = 0; i < 3; ++i) {
                const auto extent = i == a ? p.half_thickness : p.half_width;
                require(setup.geometry.reference.minimum[i] == origin[i] - extent &&
                    setup.geometry.reference.maximum[i] == origin[i] + (i == u ? spacing : 0) + extent,
                    "the untranslated tray has the literal complete pin-to-pin body bounds in every frame");
            }
            for (const auto direction : directions) for (const auto input : motions) {
                const auto reading = o::sample(p, direction, input);
                require(std::holds_alternative<o::Sample>(reading), "bounded declared same-phase branch pose is supported");
                const auto& sample = std::get<o::Sample>(reading);
                require(sample.geometry.profile == p && sample.direction == direction && sample.shafts == std::array<g::Motion, 2>{input, input}, "owned descriptors retain the single direction and all native source states");
                o::Point d{}, derivative{};
                d[u] = fraction(radius * direction.cosine, direction.scale); d[v] = fraction(radius * direction.sine * second[v], direction.scale);
                derivative = {add(scale(d[2], normal[1]), scale(d[1], -normal[2])), add(scale(d[0], normal[2]), scale(d[2], -normal[0])), add(scale(d[1], normal[0]), scale(d[0], -normal[1]))};
                require(sample.displacement == d && sample.per_radian == derivative, "orbit derivative follows the independent 3D angular cross product without native time-unit conversion");
                for (std::size_t i = 0; i < 3; ++i) {
                    const auto delta = add(sample.pins[1][i], scale(sample.pins[0][i], -1));
                    require(delta == fraction(i == u ? spacing : 0) && sample.pins[0][i] == add(fraction(origin[i]), d[i]),
                        "the two circular pins have a constant vector separation, preserving every tray orientation axis");
                }
                require(sample.change_point == (direction.sine == 0), "collinear branch change points remain visible instead of inferring bare-linkage retention");
                ++poses;
            }
        }
    }
    const std::vector<g::Part> plain{{"a", g::Kind::hub, {0, 0, 8}, g::Axis::z}, {"as", g::Kind::shaft, {0, 0, 8}, g::Axis::z, 0, 2},
        {"b", g::Kind::hub, {12, 0, 8}, g::Axis::z}, {"bs", g::Kind::shaft, {12, 0, 8}, g::Axis::z, 0, 2}};
    const auto native = g::evaluate(plain, {{"a", {1, 2}}});
    require(native.accepted() && native.motion.at("b").state == g::MotionState::unpowered, "ordinary native parallel shafts do not adopt this proposed guided branch");
}

void puzzle_and_validation() {
    o::Profile p;
    const std::array post{c::Obstacle{99, {{6, 2, 7}, {7, 3, 9}}}};
    const auto standard = std::get<o::Setup>(o::inspect(p, post));
    require(!standard.tray.clear(), "the larger low tray has a genuine whole-orbit post obstruction");
    for (const auto direction : {o::Direction{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}}) {
        const auto s = std::get<o::Sample>(o::sample(p, direction, moving()));
        auto box = s.geometry.reference;
        for (std::size_t i = 0; i < 3; ++i) {
            require(s.displacement[i].denominator == 1, "quarter-turn fixture translations are exact grid poses");
            box.minimum[i] += s.displacement[i].numerator; box.maximum[i] += s.displacement[i].numerator;
        }
        require(c::sweep(box, {}, post).clear(), "four clear quarter-turn snapshots miss the actual intermediate tray collision");
    }
    const auto missed = std::get<o::Sample>(o::sample(p, {3, 4, 5}, moving()));
    require(missed.displacement[0] == F{12, 5} && missed.displacement[1] == F{16, 5} &&
        12 - 5 < post[0].box.maximum[0] * 5 && 12 + 13 * 5 > post[0].box.minimum[0] * 5 &&
        16 - 5 < post[0].box.maximum[1] * 5 && 16 + 5 > post[0].box.minimum[1] * 5 &&
        missed.geometry.reference.minimum[2] < post[0].box.maximum[2] && missed.geometry.reference.maximum[2] > post[0].box.minimum[2],
        "an independently bounded rational pose witnesses real tray/post interior overlap");
    p.radius = 1;
    const auto compact = std::get<o::Setup>(o::inspect(p, post));
    require(compact.tray.clear(), "the compact orbit clears the same stationary post");
    require(c::full_turn({compact.geometry.reference, p.origin, p.shaft}, post).hit.has_value(), "rotating the long tray is a false-positive substitute for its orientation-preserving circular translation");
    p = {}; p.origin[2] = 16;
    require(std::get<o::Setup>(o::inspect(p, post)).tray.clear(), "raising the larger orbit gives a distinct working geometry");
    p = {};
    std::vector<c::Obstacle> observations{post[0], {13, post[0].box}};
    const auto saved = std::get<o::Setup>(o::inspect(p, observations));
    std::reverse(observations.begin(), observations.end());
    require(saved.tray.contact == std::get<o::Setup>(o::inspect(p, observations)).tray.contact && saved.tray.contact->obstacle == 13,
        "lowest obstructing identity is deterministic independent of observation order");
    observations.push_back({0, post[0].box});
    require(refused(o::inspect(p, observations), o::Error::query_refused, c::Error::invalid_id), "a known hit cannot hide the invalid final observation");
    observations.back().id = 13;
    require(refused(o::inspect(p, observations), o::Error::query_refused, c::Error::duplicate_id), "duplicate observations refuse the whole query");
    observations.back().id = 777; observations.back().box.maximum[0] = observations.back().box.minimum[0];
    require(refused(o::inspect(p, observations), o::Error::query_refused, c::Error::invalid_box), "invalid final boxes cannot produce partial contact evidence");
    observations.assign(g::maximum_parts + 1, post[0]);
    require(refused(o::inspect(p, observations), o::Error::query_refused, c::Error::too_many_obstacles), "oversized complete observations are never truncated");
    p.origin = {}; observations.clear();
    require(saved.geometry.profile == o::Profile{} && saved.tray.contact->obstacle == 13, "query output owns its geometry and selected contact after caller changes");
    const I low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    for (I bad : {low, high, I{-1}, I{0}, g::maximum_dimension + 1}) for (unsigned field = 0; field < 4; ++field) {
        p = {}; *std::array<I*, 4>{&p.spacing, &p.radius, &p.half_width, &p.half_thickness}[field] = bad;
        require(refused(o::sample(p, {}, moving()), o::Error::invalid_profile) && refused(o::inspect(p, {}), o::Error::invalid_profile), "raw profile dimensions are bounded before any differences/products");
    }
    for (I bad : {low, high, -g::maximum_coordinate - 1, g::maximum_coordinate + 1}) for (std::size_t a = 0; a < 3; ++a) {
        p = {}; p.origin[a] = bad;
        require(refused(o::sample(p, {}, moving()), o::Error::invalid_profile), "raw position extrema refuse before arithmetic");
    }
    p = {}; p.tray_id = p.input_id;
    require(refused(o::inspect(p, {}), o::Error::invalid_profile), "distinct positive opaque identities are required");
    p = {}; p.output_id = 0;
    require(refused(o::sample(p, {}, moving()), o::Error::invalid_profile), "a missing output identity cannot invent a remote coupling");
    p = {}; p.span = p.shaft;
    require(refused(o::inspect(p, {}), o::Error::invalid_axes), "shaft and span must be independent axes");
    p = {}; p.shaft = static_cast<g::Axis>(-1);
    require(refused(o::sample(p, {}, moving()), o::Error::invalid_axes), "unknown signed axes cannot index arrays");
    p = {};
    for (const auto d : {o::Direction{0, 0, 1}, {1, 1, 1}, {6, 8, 10}, {1, 0, 0}, {low, 1, 1}, {1, high, 1}, {1, 0, high}})
        require(refused(o::sample(p, d, moving()), o::Error::invalid_direction), "raw physical unit directions are primitive and bounded before squares/gcd");
    for (const F rate : {F{1, 0}, {0, -1}, {low, 1}, {high, 1}, {1, k::maximum_denominator + 1}, {257, 1}})
        require(refused(o::sample(p, {}, moving(rate)), o::Error::invalid_rate), "exact native rate bounds are retained");
    require(refused(o::sample(p, {}, {g::MotionState::unpowered, {1, 0}}), o::Error::invalid_rate), "paused sources still validate their rates");
    require(refused(o::sample(p, {}, moving({0, 1})), o::Error::invalid_motion), "rotating zero is inconsistent");
    require(refused(o::sample(p, {}, {static_cast<g::MotionState>(-1), {}}), o::Error::invalid_motion), "unknown native motion states refuse");
    for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled}) {
        require(refused(o::sample(p, {}, {state, {1, 1}}), o::Error::invalid_motion), "nonrotating states cannot carry nonzero speed");
        require(std::get<o::Sample>(o::sample(p, {}, {state, {0, high}})).shafts[1] == g::Motion{state, {}}, "native zero states normalize without conflation");
    }
    for (const auto raw : {F{high, high}, F{low, I{1} << 62}, F{256, 1}, F{-256, 1}}) {
        const auto expected = raw.numerator == low ? F{-2, 1} : fraction(raw.numerator, raw.denominator);
        require(std::get<o::Sample>(o::sample(p, {}, moving(raw))).shafts[1] == moving(expected), "reducible raw extrema normalize before limits and preserve 1:1 output");
    }
    const c::Box body{{0, 0, 0}, {1, 1, 1}};
    require(refused(o::orbit(body, static_cast<g::Axis>(-1), 1, {}), o::Error::invalid_axes), "direct orbit queries validate shaft enums");
    for (I radius : {low, high, I{0}, I{-1}, g::maximum_dimension + 1})
        require(refused(o::orbit(body, g::Axis::z, radius, {}), o::Error::invalid_profile), "direct orbit radii are bounded before arithmetic");
    require(refused(o::orbit({{low, 0, 0}, {high, 1, 1}}, g::Axis::z, 1, {}), o::Error::invalid_body, c::Error::invalid_box), "raw direct bodies reuse native validation before differences");
    require(refused(o::orbit({{g::maximum_coordinate - 1, 0, 0}, {g::maximum_coordinate, 1, 1}}, g::Axis::z, 1, {}), o::Error::representation_limit), "an on-grid reference can still have an escaping full orbit");
    p = {}; p.origin[0] = g::maximum_coordinate - 13; p.radius = 1;
    require(refused(o::sample(p, {}, moving()), o::Error::representation_limit), "derived current tray corners also retain native grid bounds");
}

void consumers() {
    struct Case { std::string_view kit, source, finding; bool matched; int exit; };
    const std::array<Case, 20> cases{{
        {"compact", "slow", "Goal matched.", true, 0}, {"raised", "slow", "Goal matched.", true, 0},
        {"standard", "slow", "tray overlaps post 99", false, 0}, {"compact", "reverse", "readout rotating -1/2", false, 0},
        {"raised", "reverse", "readout rotating -1/2", false, 0}, {"compact", "fast", "readout rotating 5/2", false, 0},
        {"raised", "fast", "readout rotating 5/2", false, 0}, {"compact", "stalled", "source stalled", false, 0},
        {"compact", "off", "source unpowered", false, 0}, {"raised", "stalled", "source stalled", false, 0},
        {"raised", "off", "source unpowered", false, 0}, {"short-input", "slow", "source unpowered", false, 0},
        {"short-output", "slow", "readout unpowered", false, 0}, {"shifted", "slow", "readout unpowered", false, 0},
        {"wrong-span", "slow", "readout unpowered", false, 0}, {"wrong-shaft", "slow", "axis differs", false, 0},
        {"standard", "off", "tray overlaps post 99", false, 0}, {"short-output", "reverse", "readout unpowered", false, 0},
        {"near-edge", "slow", "representation_limit", false, 2}, {"near-edge", "off", "representation_limit", false, 2},
    }};
    for (const auto& test : cases) {
        const std::array args{test.kit, test.source};
        std::ostringstream out, errors;
        require(o::workbench(args, out, errors) == test.exit, "native terminal consumer returns the declared trace/refusal status");
        require((out.str() + errors.str()).find(test.finding) != std::string::npos && (out.str().find("Goal matched.") != std::string::npos) == test.matched,
            "geometry, actual source/readout connectivity and signed rate determine the declared setup goal");
        require(test.exit == 2 ? !errors.str().empty() : errors.str().empty(), "native representation refusal is separate from a valid unfinished mechanism");
        ++caller_traces;
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{}, {"list"}, {"--help"}}) {
        std::ostringstream out, errors;
        require(o::workbench(args, out, errors) == 0 && errors.str().empty() && out.str().find("branch retention remain unestablished") != std::string::npos, "catalogue preserves declared-branch and full-solid limitations");
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{"bogus", "slow"}, {"compact", "bogus"}, {"compact"}, {"compact", "slow", "extra"}, {"list", "extra"}}) {
        std::ostringstream out, errors;
        require(o::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().find("Goal matched.") == std::string::npos, "malformed argv refuses without a goal result");
    }
    std::ostringstream failed, errors; failed.setstate(std::ios::badbit);
    const std::array<std::string_view, 2> args{"compact", "slow"};
    require(o::workbench(args, failed, errors) == 2, "an unwritable transcript is not a successful trace");
}
}  // namespace

int main() {
    independent_orbits(); declared_branch_poses(); puzzle_and_validation(); consumers();
    std::cout << "PASS " << assertions << " assertions; " << rectangles << " exact independent circle/rectangle cases; " << poses
        << " declared-branch poses; " << caller_traces << " consumer traces.\n";
}
