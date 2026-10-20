#include "factory/clearance.hpp"
#include "native/motion-clearance/src/arc_math.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace c = factory::clearance;
namespace d = factory::clearance::detail;
namespace m = factory::mechanics;
using I = c::Coordinate;
using XY = std::array<I, 2>;
using Polygon = std::array<XY, 4>;
namespace {
int checks{};
std::size_t pairs{}, sampled_witnesses{}, quarter_hits{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
template<class F> bool limited(F&& f) {
    try { f(); return false; } catch (const d::Limit&) { return true; }
}
c::QuarterTurnResult query(const c::Rotor& rotor, c::TurnDirection direction, std::vector<c::Obstacle> obstacles = {}) {
    return c::quarter_turn(rotor, direction, obstacles);
}
const c::Rotor arm{{{2, -1, -1}, {3, 1, 1}}, {0, 0, 0}, m::Axis::y};
const c::Obstacle corner{7, {{1, -1, 1}, {2, 1, 2}}};

void exact_math_controls() {
    const d::Wide one(1);
    check((d::Wide(UINT64_MAX) + one).compare(one.shifted(64)) == 0, "Carry crosses both initial machine words exactly.");
    check((d::Wide(UINT64_MAX).squared() + one.shifted(65)).compare(one.shifted(128) + one) == 0,
          "Multiword squaring retains all cross terms and carries.");
    check((one.shifted(192) + one).squared().compare(one.shifted(384) + one.shifted(193) + one) == 0,
          "The largest isolator numerator squares exactly beyond native integer widths.");
    check(limited([&] { (void)(one.shifted(511) + one.shifted(511)); }) &&
          limited([&] { (void)one.shifted(511).scaled(2); }) &&
          limited([&] { (void)one.shifted(256).squared(); }), "Checked wide overflow refuses rather than wrapping.");
    for (I value = 0; value <= 100; ++value) {
        const auto root = d::floor_sqrt(value);
        check(root * root <= value && (root + 1) * (root + 1) > value, "Integer square-root boundaries are exact.");
    }
    check(d::floor_sqrt(std::numeric_limits<I>::max()) == 3037000499, "Integer square root handles the int64 boundary without squaring overflow.");
    std::array<d::Root, 2> roots;
    check(d::roots({2, 0, -1}, roots) == 2 && !roots[1].rational &&
          roots[1].compare({d::Wide(1), 1}) > 0 && roots[1].compare({d::Wide(1), 0}) < 0,
          "A genuine irrational root is ordered against exact rational cuts.");
    constexpr I n = 1000000;
    check(d::roots({n, -n, 1}, roots) == 2, "The close-root polynomial is admitted under the real coefficient bound.");
    const auto right = d::rational_root(n - 2, n - 1);
    check(d::compare_roots(roots[1], right) < 0, "A rational and irrational event near one, separated by about 10^-18, retain their order.");
    const auto middle = d::between(roots[1], right);
    check(middle.bits > 50 && roots[1].compare(middle) < 0 && right.compare(middle) > 0,
          "A strict rational witness exists inside a gap narrower than ordinary floating-point spacing near one.");
    std::array<d::Polynomial, 8> conditions;
    conditions.fill({0, 0, 1});
    conditions[0] = {0, -(n - 1), n - 2}; conditions[1] = {n, -n, 1}; conditions[2] = {0, 2, -1};
    check(d::positive_somewhere(conditions), "The isolator finds a feasible interval only about 10^-18 wide.");
    conditions.fill({0, 0, 1}); conditions[0] = {2, 0, -1}; conditions[1] = {-6, 0, 3};
    check(!d::positive_somewhere(conditions), "Opposite constraints sharing an irrational root cannot turn tangency into overlap.");
    conditions[0] = {0, 0, 4000001};
    check(limited([&] { (void)d::positive_somewhere(conditions); }), "Coefficient proof violations are explicit arithmetic refusals.");
    check(std::string_view(c::error_name(c::Error::arithmetic_limit)) == "arithmetic_limit", "The new refusal has an explicit public name.");
}

c::Rotor rotate_y_positive(c::Rotor rotor) {
    const auto& b = rotor.box;
    rotor.box = {{b.minimum[2], b.minimum[1], -b.maximum[0]}, {b.maximum[2], b.maximum[1], -b.minimum[0]}};
    return rotor;
}
void short_and_detour() {
    const auto saved = arm;
    check(query(arm, c::TurnDirection::negative, {corner}).obstacle == 7, "The short negative turn strikes the corner between its clear stops.");
    check(arm == saved, "A blocked proposal holds the original fixture pose.");
    check(query(arm, c::TurnDirection::positive, {corner}).clear(), "The opposite requested quarter is clear despite a blocked full circle.");
    check(!c::full_turn(arm, std::array{corner}).clear(), "The full-turn control remains deliberately more conservative.");
    auto detour = arm;
    for (int step = 0; step < 3; ++step) {
        check(query(detour, c::TurnDirection::positive, {corner}).clear(), "Every individual detour quarter is continuously clear.");
        detour = rotate_y_positive(detour);
    }
    const c::Box target{{-1, -1, 2}, {1, 1, 3}};
    check(detour.box == target, "Three positive quarters reach the same target pose as one negative quarter.");
    auto raised = arm;
    raised.box.minimum[1] += 2; raised.box.maximum[1] += 2; raised.pivot[1] += 2;
    check(query(raised, c::TurnDirection::negative, {corner}).clear(), "Lifting the actual fixture two grid units permits the short turn.");
    const c::Rotor tangent{{{2, -4, -1}, {3, -3, 1}}, {}, m::Axis::z};
    const c::Obstacle edge{1, {{5, -1, -1}, {6, 1, 1}}};
    check(query(tangent, c::TurnDirection::positive, {edge}).clear(), "A double quadratic root at the 3-4-5 radial extremum is tangency, not penetration.");
    const auto selected = query(arm, c::TurnDirection::negative, {{99, arm.box}, corner});
    check(selected.obstacle == 7 && selected == query(arm, c::TurnDirection::negative, {corner, {99, arm.box}}),
          "Selection is lowest obstruction identity regardless of observation or impact order.");
}

void validation_and_grid() {
    auto bad = arm;
    bad.box.minimum[0] = std::numeric_limits<I>::min();
    check(query(bad, c::TurnDirection::positive).error == c::Error::invalid_box, "Malformed body refuses before plane arithmetic.");
    bad = arm; bad.pivot[0] = std::numeric_limits<I>::max();
    check(query(bad, c::TurnDirection::positive).error == c::Error::invalid_motion, "Unbounded pivot refuses before subtraction.");
    bad = arm; bad.axis = static_cast<m::Axis>(77);
    check(query(bad, c::TurnDirection::positive).error == c::Error::invalid_motion, "Invalid axis refuses before indexing.");
    check(query(arm, static_cast<c::TurnDirection>(77)).error == c::Error::invalid_motion, "Invalid signed direction is refused.");
    auto result = query(arm, c::TurnDirection::negative, {corner, {0, corner.box}});
    check(result.error == c::Error::invalid_id && !result.obstacle, "A later invalid identity suppresses every partial obstruction.");
    result = query(arm, c::TurnDirection::negative, {corner, corner});
    check(result.error == c::Error::duplicate_id && !result.obstacle, "Duplicate observations are refused.");
    result = query(arm, c::TurnDirection::negative, {corner, {9, {{0, 0, 0}, {0, 1, 1}}}});
    check(result.error == c::Error::invalid_box && !result.obstacle, "A later malformed box cannot be hidden by an earlier collision.");
    std::vector<c::Obstacle> many;
    for (std::size_t i = 0; i < m::maximum_parts; ++i) many.push_back({i + 1, {{0, 10, 0}, {1, 11, 1}}});
    check(query(arm, c::TurnDirection::negative, many).clear(), "The entire supported observation limit is accepted.");
    many.push_back({many.size() + 1, corner.box});
    result = query(arm, c::TurnDirection::negative, many);
    check(result.error == c::Error::too_many_obstacles && !result.obstacle, "An oversized observation is never truncated.");
    constexpr auto b = m::maximum_coordinate;
    const c::Rotor away{{{b - 4, 1, -1}, {b - 3, 2, 1}}, {b - 1, 0, 0}, m::Axis::z};
    check(query(away, c::TurnDirection::positive).clear() && c::full_turn(away, {}).error == c::Error::invalid_motion,
          "The requested quarter may fit the grid even when the enclosing full circle does not.");
    check(query(away, c::TurnDirection::negative).error == c::Error::invalid_motion, "The reversed quarter that exits the grid is refused.");
    const c::Rotor bulge{{{b - 2, -4, -1}, {b - 1, -3, 1}}, {b - 4, 0, 0}, m::Axis::z};
    check(query(bulge, c::TurnDirection::positive).error == c::Error::invalid_motion,
          "Valid start/end boxes cannot hide an out-of-grid intermediate radial extremum.");
}

c::Point permute(const c::Point& p, const std::array<std::size_t, 3>& order) { return {p[order[0]], p[order[1]], p[order[2]]}; }
void spatial_invariance() {
    std::array<std::size_t, 3> order{0, 1, 2};
    do {
        auto moved = arm; auto obstacle = corner;
        moved.box = {permute(arm.box.minimum, order), permute(arm.box.maximum, order)};
        moved.pivot = permute(arm.pivot, order);
        moved.axis = static_cast<m::Axis>(std::find(order.begin(), order.end(), 1) - order.begin());
        obstacle.box = {permute(corner.box.minimum, order), permute(corner.box.maximum, order)};
        int inversions{};
        for (int i = 0; i < 3; ++i) for (int j = i + 1; j < 3; ++j) inversions += order[i] > order[j];
        const auto clear_direction = inversions % 2 ? c::TurnDirection::negative : c::TurnDirection::positive;
        const auto blocked_direction = inversions % 2 ? c::TurnDirection::positive : c::TurnDirection::negative;
        const c::Point offset{17, -5, 23};
        for (std::size_t axis = 0; axis < 3; ++axis) {
            moved.box.minimum[axis] += offset[axis]; moved.box.maximum[axis] += offset[axis]; moved.pivot[axis] += offset[axis];
            obstacle.box.minimum[axis] += offset[axis]; obstacle.box.maximum[axis] += offset[axis];
        }
        check(query(moved, clear_direction, {obstacle}).clear() && query(moved, blocked_direction, {obstacle}).obstacle == 7,
              "Every axis permutation preserves the signed physical path, including handedness and translated pivots.");
    } while (std::next_permutation(order.begin(), order.end()));
}

// This separate polygon oracle rotates explicit XY vertices by an exact
// rational angle and projects polygon edges. It shares no arc inequalities or
// root isolation. Samples prove presence only, never continuous absence.
bool pose_overlap(const c::Box& b, const c::Box& o, I cosine, I sine, I denominator) {
    Polygon moving{{{b.minimum[0], b.minimum[1]}, {b.maximum[0], b.minimum[1]},
                    {b.maximum[0], b.maximum[1]}, {b.minimum[0], b.maximum[1]}}};
    for (auto& p : moving) { const auto x = p[0], y = p[1]; p = {cosine * x - sine * y, sine * x + cosine * y}; }
    Polygon fixed{{{o.minimum[0] * denominator, o.minimum[1] * denominator}, {o.maximum[0] * denominator, o.minimum[1] * denominator},
                   {o.maximum[0] * denominator, o.maximum[1] * denominator}, {o.minimum[0] * denominator, o.maximum[1] * denominator}}};
    for (const auto* polygon : {&moving, &fixed}) for (std::size_t edge = 0; edge < 4; ++edge) {
        const auto a = (*polygon)[edge], next = (*polygon)[(edge + 1) % 4];
        const XY normal{next[1] - a[1], a[0] - next[0]};
        auto interval = [&](const Polygon& shape) {
            I low = std::numeric_limits<I>::max(), high = std::numeric_limits<I>::min();
            for (const auto& p : shape) { const auto dot = p[0] * normal[0] + p[1] * normal[1]; low = std::min(low, dot); high = std::max(high, dot); }
            return XY{low, high};
        };
        const auto left = interval(moving), right = interval(fixed);
        if (left[1] <= right[0] || right[1] <= left[0]) return false;
    }
    return true;
}
c::Rotor rotate_z_positive(c::Rotor rotor) {
    const auto& b = rotor.box;
    rotor.box = {{-b.maximum[1], b.minimum[0], b.minimum[2]}, {-b.minimum[1], b.maximum[0], b.maximum[2]}};
    return rotor;
}
void independent_oracles() {
    const std::array<std::array<I, 3>, 12> angles{{{1, 0, 1}, {0, 1, 1}, {3, 4, 5}, {4, 3, 5}, {5, 12, 13}, {12, 5, 13},
                                               {8, 15, 17}, {15, 8, 17}, {7, 24, 25}, {24, 7, 25}, {20, 21, 29}, {21, 20, 29}}};
    for (I x = -2; x <= 2; ++x) for (I y = -2; y <= 2; ++y) {
        const c::Rotor body{{{x, y, -1}, {x + 1, y + 1, 1}}, {}, m::Axis::z};
        for (I ox = -2; ox <= 2; ++ox) for (I oy = -2; oy <= 2; ++oy) {
            const c::Obstacle obstacle{1, {{ox, oy, -1}, {ox + 1, oy + 1, 1}}};
            const bool full = c::full_turn(body, std::array{obstacle}).hit.has_value();
            for (const auto direction : {c::TurnDirection::positive, c::TurnDirection::negative}) {
                const auto result = query(body, direction, {obstacle});
                bool witnessed{};
                for (const auto angle : angles) witnessed = witnessed || pose_overlap(body.box, obstacle.box, angle[0], direction == c::TurnDirection::positive ? angle[1] : -angle[1], angle[2]);
                ++pairs; sampled_witnesses += witnessed; quarter_hits += result.obstacle.has_value();
                check(result.error == c::Error::none && (!witnessed || result.obstacle.has_value()) && (full || result.clear()),
                      "Exact pose witnesses cannot contradict a continuous-clear quarter, and a quarter hit must lie inside its full-circle sweep.");
            }
            auto rotated = body;
            bool any{};
            for (int quarter = 0; quarter < 4; ++quarter) {
                const auto result = query(rotated, c::TurnDirection::positive, {obstacle});
                check(result.error == c::Error::none, "Every quarter in the bounded full-circle decomposition is admitted.");
                any = any || result.obstacle.has_value(); rotated = rotate_z_positive(rotated);
            }
            check(any == full, "Four exact quarter queries agree with the independent annular full-circle algorithm, without using sampled absence.");
        }
    }
}
}  // namespace

int main() {
    try {
        exact_math_controls(); short_and_detour(); validation_and_grid(); spatial_invariance(); independent_oracles();
        std::cout << checks << " native quarter-turn checks, 0 failures; " << pairs << " signed small-pose cases, "
                  << sampled_witnesses << " exact sampled witnesses, " << quarter_hits
                  << " continuous quarter obstructions; 625 exact full-circle decompositions; engine_calls=0.\n";
        return 0;
    } catch (const d::Limit&) {
        std::cerr << "FAIL after " << checks << " checks: unexpected bounded arithmetic refusal\n"; return 1;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n'; return 1;
    }
}
