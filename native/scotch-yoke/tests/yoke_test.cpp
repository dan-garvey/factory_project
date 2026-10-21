#include "factory/scotch_yoke.hpp"
#include "factory/scotch_yoke_workbench.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <numeric>
#include <set>
#include <sstream>

namespace y = factory::scotch_yoke;
namespace g = factory::mechanics;
namespace c = factory::clearance;
namespace k = factory::geared_cycle;
using I = g::Integer;
using F = g::Rate;
namespace {
std::size_t assertions{}, frames{}, intersections{}, source_cases{}, caller_traces{};
void require(bool value, const char* message) {
    ++assertions;
    if (!value) { std::cerr << "Assertion " << assertions << " failed: " << message << '\n'; std::exit(1); }
}
F fraction(I n, I d = 1) {
    require(d != 0, "independent rational denominator is nonzero");
    if (d < 0) { n = -n; d = -d; }
    const auto divisor = std::gcd(n, d);
    return {n / divisor, d / divisor};
}
F add(F a, F b) { return fraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator); }
F scale(F a, I n) { return fraction(a.numerator * n, a.denominator); }
F square(F a) { return fraction(a.numerator * a.numerator, a.denominator * a.denominator); }
g::Motion moving(F rate = {1, 2}) { return {g::MotionState::rotating, rate}; }
bool refused(const y::Reading& value, y::Error reason) {
    const auto* error = std::get_if<y::Refusal>(&value);
    return error && error->reason == reason;
}
bool turn_refused(const y::TurnPlan& value, y::Error reason, std::optional<c::Error> geometry = {}) {
    const auto* error = std::get_if<y::Refusal>(&value);
    return error && error->reason == reason && error->geometry_error == geometry;
}
const std::array<c::Obstacle, 1> post{{{99, {{-1, 2, 7}, {1, 3, 9}}}}};

void circle_and_slot() {
    // Generate exact rational points by independently intersecting a line of
    // rational slope with the unit circle. The public pose remains a physical
    // cosine/sine direction, never that generator's half-angle parameter.
    std::set<std::array<I, 3>> points;
    for (I m = -8; m <= 8; ++m) for (I n = -8; n <= 8; ++n) {
        if (!m && !n) continue;
        I x = m * m - n * n, z = 2 * m * n, q = m * m + n * n;
        const auto divisor = std::gcd(std::gcd(x, z), q);
        points.insert({x / divisor, z / divisor, q / divisor});
    }
    const std::array<g::Point, 3> origins{{{0, 0, 8}, {-41, 72, -20}, {101, -57, 36}}};
    const std::array<g::Motion, 5> motions{{moving(), moving({-3, 7}), {g::MotionState::unpowered, {}}, {g::MotionState::stopped, {}}, {g::MotionState::stalled, {}}}};
    for (std::size_t a = 0; a < 3; ++a) for (std::size_t u = 0; u < 3; ++u) {
        if (a == u) continue;
        const auto v = 3 - a - u;
        // Obtain the second plane direction from shaft x travel, independently
        // of the production cyclic-index handedness condition.
        std::array<I, 3> shaft{}, travel{}, slot{};
        shaft[a] = 1; travel[u] = 1;
        slot = {shaft[1] * travel[2] - shaft[2] * travel[1], shaft[2] * travel[0] - shaft[0] * travel[2], shaft[0] * travel[1] - shaft[1] * travel[0]};
        require(slot[v] == 1 || slot[v] == -1, "all six shaft/travel frames have a proper third plane direction");
        ++frames;
        for (const auto origin : origins) for (I radius : {1, 6, 12}) {
            y::Profile p; p.origin = origin; p.shaft = static_cast<g::Axis>(a); p.travel = static_cast<g::Axis>(u);
            p.radius = radius; p.slot_half_length = radius + p.pin_radius;
            const auto full = std::get<y::Turn>(y::prepare_turn(p, {}));
            require(full.admitted(), "the exact finite pin fits the complete symmetric slot in every proper frame");
            for (const auto point : points) {
                const y::Direction direction{point[0], point[1], point[2]};
                const auto pin_u = fraction(radius * point[0], point[2]), pin_v = fraction(radius * point[1] * slot[v], point[2]);
                require(add(square(pin_u), square(pin_v)) == fraction(radius * radius), "independent pin lies on the declared crank circle");
                for (const auto input : motions) {
                    const auto reading = y::sample(p, direction, input);
                    require(std::holds_alternative<y::Sample>(reading), "exact circle/slot intersection is representable");
                    const auto& sample = std::get<y::Sample>(reading);
                    require(sample.profile == p && sample.direction == direction && sample.crank == input, "one owned input direction and native source observation remain unchanged");
                    for (std::size_t i = 0; i < 3; ++i) {
                        const auto expected_pin = add(fraction(origin[i]), i == u ? pin_u : i == v ? pin_v : F{});
                        const auto expected_yoke = add(fraction(origin[i]), i == u ? pin_u : F{});
                        require(sample.pin[i] == expected_pin && sample.yoke[i] == expected_yoke,
                            "the circular pin intersects the transverse slot through the independently guided yoke centre");
                    }
                    // Project (positive shaft axis x pin offset) onto travel.
                    // This uses the physical 3D angular derivative, not a copied
                    // sign condition or a multiplication by native tick units.
                    y::Point pin_offset{};
                    pin_offset[u] = pin_u; pin_offset[v] = pin_v;
                    const y::Point derivative{
                        add(scale(pin_offset[2], shaft[1]), scale(pin_offset[1], -shaft[2])),
                        add(scale(pin_offset[0], shaft[2]), scale(pin_offset[2], -shaft[0])),
                        add(scale(pin_offset[1], shaft[0]), scale(pin_offset[0], -shaft[1]))};
                    for (std::size_t i = 0; i < 3; ++i)
                        require(sample.yoke_per_radian[i] == (i == u ? derivative[u] : F{}), "only the guided projection of the angular derivative can move the yoke");
                    ++source_cases;
                }
                ++intersections;
            }
        }
    }
}

void walls_and_complete_turn() {
    y::Profile p;
    const auto full = std::get<y::Turn>(y::prepare_turn(p, post));
    require(!full.admitted() && full.pin_clearance.clear() && full.slot_fits == std::array<bool, 2>{true, true},
        "the obstruction belongs to the yoke walls, not the pin or its finite slot fit");
    require(full.walls[0].hit && full.walls[1].hit && full.walls[0].hit->obstacle == 99 && full.walls[2].clear() && full.walls[3].clear(),
        "the actual two moving side walls cross the post while the crossbars miss it");
    for (const auto direction : {y::Direction{}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}}) {
        const auto at = std::get<y::Sample>(y::sample(p, direction, moving()));
        for (std::size_t i = 0; i < 4; ++i) {
            auto box = full.wall_start[i];
            require(at.yoke[0].denominator == 1, "quarter-turn fixture displacement is exactly on grid");
            const auto offset = at.yoke[0].numerator - p.origin[0] + p.radius;
            box.minimum[0] += offset; box.maximum[0] += offset;
            require(c::sweep(box, {}, post).clear(), "all four frame walls clear at every quarter-turn snapshot");
        }
    }
    const auto missed = std::get<y::Sample>(y::sample(p, {5, 12, 13}, moving()));
    require(missed.yoke[0] == F{30, 13}, "an exact intermediate direction witnesses the missed crossing");
    require(30 - 2 * 13 < post[0].box.maximum[0] * 13 && 30 - 13 > post[0].box.minimum[0] * 13 &&
        -8 < post[0].box.maximum[1] && 8 > post[0].box.minimum[1] && 7 < post[0].box.maximum[2] && 9 > post[0].box.minimum[2],
        "independent rational left-wall/post interval overlap proves an actual unsampled frame hit");
    p.slot_half_width = 8;
    const auto wide = std::get<y::Turn>(y::prepare_turn(p, post));
    require(wide.admitted(), "a wider opening keeps the post inside the empty aperture throughout the complete stroke");
    const c::Box filled{{-15, -8, 7}, {3, 8, 9}};
    require(c::sweep(filled, {12, 0, 0}, post).hit.has_value(), "a filled frame AABB falsely rejects the working open-slot solution");
    p = {}; p.shaft = g::Axis::y;
    require(std::get<y::Turn>(y::prepare_turn(p, post)).admitted(), "the same narrow mechanism clears when mounted upright without changing the work line");
    p.slot_half_length = 6;
    require(std::holds_alternative<y::Sample>(y::sample(p, {}, moving())), "a short slot fits the starting pose");
    require(refused(y::sample(p, {0, 1, 1}, moving()), y::Error::outside_slot_length) && !std::get<y::Turn>(y::prepare_turn(p, post)).slot_fits[1],
        "the finite pin radius prevents a later pose and complete turn in that short slot");
    p.slot_half_length = 7; p.pin_radius = 2;
    require(refused(y::sample(p, {}, moving()), y::Error::outside_slot_width) && !std::get<y::Turn>(y::prepare_turn(p, {})).slot_fits[0],
        "a finite pin cannot fit through an undersized slot width even with its centre correctly aligned");
    p = {};
    std::vector<c::Obstacle> obstacles{post[0], {13, post[0].box}};
    const auto first = std::get<y::Turn>(y::prepare_turn(p, obstacles));
    std::reverse(obstacles.begin(), obstacles.end());
    require(first.walls == std::get<y::Turn>(y::prepare_turn(p, obstacles)).walls && first.walls[0].hit->obstacle == 13,
        "equal canonical traversal contacts select the opaque lowest ID independently of caller order");
    p.pin_radius = 2;
    obstacles.push_back({0, post[0].box});
    require(turn_refused(y::prepare_turn(p, obstacles), y::Error::query_refused, c::Error::invalid_id), "known body and slot failures cannot hide an invalid final obstacle");
    obstacles.back().id = 13;
    require(turn_refused(y::prepare_turn(p, obstacles), y::Error::query_refused, c::Error::duplicate_id), "duplicate final obstacle identities refuse the whole proposal");
    obstacles.back().id = 777; obstacles.back().box.minimum[0] = obstacles.back().box.maximum[0];
    require(turn_refused(y::prepare_turn(p, obstacles), y::Error::query_refused, c::Error::invalid_box), "bad final obstacle geometry never publishes an earlier hit");
    obstacles.assign(g::maximum_parts + 1, post[0]);
    require(turn_refused(y::prepare_turn(p, obstacles), y::Error::query_refused, c::Error::too_many_obstacles), "the complete obstacle set cannot be truncated");
    p = {}; p.slot_half_width = 8; p.origin[0] = g::maximum_coordinate - 8;
    require(turn_refused(y::prepare_turn(p, {}), y::Error::representation_limit, c::Error::invalid_motion), "bounded pin rotation cannot hide a later wall traversal escaping the grid");
    p = {}; p.origin[0] = g::maximum_coordinate - 7;
    require(turn_refused(y::prepare_turn(p, {}), y::Error::representation_limit, c::Error::invalid_motion), "initial on-grid pin box does not establish a bounded whole orbit");
    p = {}; p.origin[0] = g::maximum_coordinate;
    require(turn_refused(y::prepare_turn(p, {}), y::Error::representation_limit, c::Error::invalid_box), "a pin box already outside the grid refuses before publication");
    p = {};
    auto observations = std::vector<c::Obstacle>(post.begin(), post.end());
    const auto saved = std::get<y::Turn>(y::prepare_turn(p, observations));
    const auto sample = std::get<y::Sample>(y::sample(p, {-3, -4, 5}, moving()));
    p.origin = {}; observations[0].id = 1; observations.clear();
    require(saved.profile == y::Profile{} && saved.walls[0].hit->obstacle == 99 && sample.profile == y::Profile{} && sample.direction == y::Direction{-3, -4, 5},
        "owned proposals and observations survive caller mutation and deallocation");
}

void raw_validation() {
    const auto low = std::numeric_limits<I>::min(), high = std::numeric_limits<I>::max();
    y::Profile p;
    for (I bad : {low, high, I{-1}, I{0}, g::maximum_dimension + 1}) for (std::size_t field = 0; field < 6; ++field) {
        p = {};
        *std::array<I*, 6>{&p.radius, &p.pin_radius, &p.slot_half_width, &p.slot_half_length, &p.wall, &p.half_thickness}[field] = bad;
        require(refused(y::sample(p, {}, moving()), y::Error::invalid_profile) && turn_refused(y::prepare_turn(p, {}), y::Error::invalid_profile),
            "all raw dimension extrema refuse before products or offsets");
    }
    for (I bad : {low, high, -g::maximum_coordinate - 1, g::maximum_coordinate + 1}) for (std::size_t a = 0; a < 3; ++a) {
        p = {}; p.origin[a] = bad;
        require(refused(y::sample(p, {}, moving()), y::Error::invalid_profile) && turn_refused(y::prepare_turn(p, {}), y::Error::invalid_profile), "raw origins are bounded before any derived position");
    }
    for (unsigned which : {0, 1, 2}) {
        p = {}; if (which == 0) p.crank_id = 0; else if (which == 1) p.yoke_id = 0; else p.yoke_id = p.crank_id;
        require(refused(y::sample(p, {}, moving()), y::Error::invalid_profile), "positive distinct opaque body IDs are required");
    }
    for (auto bad : {g::Axis::z, static_cast<g::Axis>(-1), static_cast<g::Axis>(3)}) {
        p = {}; p.travel = bad;
        require(turn_refused(y::prepare_turn(p, {}), y::Error::invalid_axes), "travel must be a valid independent native coordinate axis");
    }
    p = {}; p.shaft = static_cast<g::Axis>(high);
    require(refused(y::sample(p, {}, moving()), y::Error::invalid_axes), "bad shaft enums never index geometry arrays");
    p = {};
    for (const auto bad : {y::Direction{0, 0, 1}, {1, 1, 1}, {6, 8, 10}, {3, 4, 0}, {1, 0, -1}, {257, 0, 257}, {low, 0, 1}, {0, high, 1}, {1, 0, high}})
        require(refused(y::sample(p, bad, moving()), y::Error::invalid_direction), "raw unit directions are bounded and primitive before squares or gcd");
    for (const F rate : {F{1, 0}, {0, -1}, {low, 1}, {high, 1}, {1, k::maximum_denominator + 1}, {257, 1}})
        require(refused(y::sample(p, {}, moving(rate)), y::Error::invalid_rate), "native rate limits retain exact refusal without clipping");
    require(refused(y::sample(p, {}, {g::MotionState::unpowered, {1, 0}}), y::Error::invalid_rate), "unpowered observations still validate their raw rate");
    require(refused(y::sample(p, {}, {static_cast<g::MotionState>(-1), {}}), y::Error::invalid_motion), "unknown native motion states refuse");
    for (auto state : {g::MotionState::unpowered, g::MotionState::stopped, g::MotionState::stalled}) {
        require(refused(y::sample(p, {}, {state, {1, 1}}), y::Error::invalid_motion), "a nonrotating state cannot carry nonzero speed");
        require(std::get<y::Sample>(y::sample(p, {0, -1, 1}, {state, {0, high}})).crank == g::Motion{state, {}}, "zero normalizes without losing unpowered/stopped/stalled identity");
    }
    require(refused(y::sample(p, {}, moving({0, 1})), y::Error::invalid_motion), "a rotating-zero state is inconsistent");
    for (const auto raw : {F{high, high}, F{low, I{1} << 62}, F{256, 1}, F{-256, 1}, F{1, k::maximum_denominator}}) {
        const auto expected = raw.numerator == low ? F{-2, 1} : fraction(raw.numerator, raw.denominator);
        require(std::get<y::Sample>(y::sample(p, {-3, 4, 5}, moving(raw))).crank == moving(expected), "reducible raw extrema normalize before exact native rate bounds");
    }
    p.origin[0] = g::maximum_coordinate;
    require(refused(y::sample(p, {}, moving()), y::Error::representation_limit), "derived current centres also stay inside the native grid");
    p = {}; p.radius = g::maximum_dimension; p.slot_half_length = g::maximum_dimension; p.pin_radius = 1;
    require(std::holds_alternative<y::Sample>(y::sample(p, {}, moving())) && !std::get<y::Turn>(y::prepare_turn(p, {})).slot_fits[1],
        "maximum dimensions remain bounded while the actual finite pin still needs additional slot travel");
}

void consumers() {
    struct Case { std::string_view kit, source, finding; bool matched; int exit; };
    const std::array<Case, 20> cases{{
        {"wide", "slow", "Goal matched.", true, 0}, {"wide", "reverse", "Goal matched.", true, 0},
        {"upright", "slow", "Goal matched.", true, 0}, {"upright", "reverse", "Goal matched.", true, 0},
        {"horizontal", "slow", "crosses post 99", false, 0}, {"short-slot", "slow", "complete slot length", false, 0},
        {"tight", "slow", "outside_slot_width", false, 0}, {"small", "slow", "fixed stroke endpoints", false, 0},
        {"shifted", "slow", "fixed stroke endpoints", false, 0}, {"wrong-travel", "slow", "fixed stroke endpoints", false, 0},
        {"wide", "fast", "speed magnitude 1/2", false, 0}, {"upright", "fast", "speed magnitude 1/2", false, 0},
        {"wide", "stalled", "source stalled", false, 0}, {"wide", "off", "source unpowered", false, 0},
        {"upright", "stalled", "source stalled", false, 0}, {"upright", "off", "source unpowered", false, 0},
        {"short-drive", "slow", "source unpowered", false, 0},
        {"horizontal", "off", "crosses post 99", false, 0}, {"near-edge", "slow", "representation_limit", false, 2},
        {"near-edge", "off", "representation_limit", false, 2},
    }};
    for (const auto& test : cases) {
        const std::array args{test.kit, test.source};
        std::ostringstream out, errors;
        require(y::workbench(args, out, errors) == test.exit, "real native fixture returns its observation/refusal status");
        require((out.str() + errors.str()).find(test.finding) != std::string::npos && (out.str().find("Goal matched.") != std::string::npos) == test.matched,
            "physical mount, actual source, complete frame clearance and fixed stroke decide the original puzzle");
        require(test.exit == 2 ? !errors.str().empty() : errors.str().empty(), "runtime refusal and unfinished mechanical traces use distinct error channels");
        if (test.matched) require(out.str().find(test.kit == "wide" ? "about +Z" : "about +Y") != std::string::npos,
            "the source gears are consumed on the actual horizontal or upright native shaft");
        ++caller_traces;
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{}, {"list"}, {"--help"}}) {
        std::ostringstream out, errors;
        require(y::workbench(args, out, errors) == 0 && errors.str().empty() && out.str().find("Either input rotation sense") != std::string::npos, "catalogue discloses reciprocal operation and both mount solutions");
    }
    for (const std::vector<std::string_view>& args : {std::vector<std::string_view>{"bogus", "slow"}, {"wide", "bogus"}, {"wide"}, {"wide", "slow", "extra"}, {"list", "extra"}}) {
        std::ostringstream out, errors;
        require(y::workbench(args, out, errors) == 2 && !errors.str().empty() && out.str().find("Goal matched.") == std::string::npos, "bad argv cannot claim a completed stroke");
    }
    std::ostringstream failed, errors; failed.setstate(std::ios::badbit);
    const std::array<std::string_view, 2> args{"upright", "slow"};
    require(y::workbench(args, failed, errors) == 2, "an unwritable observation stream is not a successful result");
}
}  // namespace

int main() {
    circle_and_slot(); walls_and_complete_turn(); raw_validation(); consumers();
    std::cout << "PASS " << assertions << " assertions; " << frames << " proper shaft/travel frames; " << intersections
        << " independent circle/slot intersections; " << source_cases << " source-state observations; " << caller_traces << " consumer traces.\n";
}
