#include "factory/clearance.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

namespace c = factory::clearance;
namespace m = factory::mechanics;
using I = c::Coordinate;
using XY = std::array<I, 2>;
using Polygon = std::array<XY, 4>;
namespace {
int checks{};
std::size_t oracle_pairs{}, witnessed_pairs{}, continuous_hits{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
c::FullTurnResult query(const c::Rotor& rotor, std::vector<c::Obstacle> obstacles = {}) {
    return c::full_turn(rotor, obstacles);
}
const c::Rotor arm{{{2, -1, -1}, {3, 1, 1}}, {0, 0, 0}, m::Axis::y};
const c::Obstacle corner{7, {{1, -1, 1}, {2, 1, 2}}};

// Independent pose oracle: explicitly rotate the four vertices by an exact
// rational rotation, then use polygon separating axes. It does not calculate
// radial ranges. Finite sampled poses witness collision, never continuous absence.
bool pose_overlap(const c::Rotor& rotor, const c::Obstacle& obstacle, I cosine, I sine, I denominator) {
    const auto& b = rotor.box;
    Polygon moving{{{b.minimum[0], b.minimum[2]}, {b.maximum[0], b.minimum[2]},
                    {b.maximum[0], b.maximum[2]}, {b.minimum[0], b.maximum[2]}}};
    for (auto& p : moving) {
        const auto x = p[0] - rotor.pivot[0], z = p[1] - rotor.pivot[2];
        p = {rotor.pivot[0] * denominator + cosine * x - sine * z,
             rotor.pivot[2] * denominator + sine * x + cosine * z};
    }
    const auto& o = obstacle.box;
    Polygon fixed{{{o.minimum[0], o.minimum[2]}, {o.maximum[0], o.minimum[2]},
                   {o.maximum[0], o.maximum[2]}, {o.minimum[0], o.maximum[2]}}};
    for (auto& p : fixed) { p[0] *= denominator; p[1] *= denominator; }
    if (b.maximum[1] <= o.minimum[1] || b.minimum[1] >= o.maximum[1]) return false;
    for (const auto* polygon : {&moving, &fixed}) {
        for (std::size_t edge = 0; edge < 4; ++edge) {
            const auto a = (*polygon)[edge], next = (*polygon)[(edge + 1) % 4];
            const XY normal{next[1] - a[1], a[0] - next[0]};
            auto interval = [&](const Polygon& shape) {
                I low = std::numeric_limits<I>::max(), high = std::numeric_limits<I>::min();
                for (const auto& p : shape) {
                    const auto dot = p[0] * normal[0] + p[1] * normal[1];
                    low = std::min(low, dot); high = std::max(high, dot);
                }
                return XY{low, high};
            };
            const auto a_range = interval(moving), b_range = interval(fixed);
            if (a_range[1] <= b_range[0] || b_range[1] <= a_range[0]) return false;
        }
    }
    return true;
}

void between_stops() {
    const auto saved = arm;
    for (const auto angle : std::array<std::array<I, 3>, 4>{{{1, 0, 1}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}}}) {
        check(!pose_overlap(arm, corner, angle[0], angle[1], angle[2]), "All four literal index stops clear the corner.");
    }
    check(pose_overlap(arm, corner, 4, 3, 5), "An exact non-index pose penetrates the corner between clear stops.");
    const auto result = query(arm, {corner});
    check(result.error == c::Error::none && result.hit == c::FullTurnHit{7, 4, 8},
          "The complete turn blocks with a strict squared-radius witness, not a sampled contact time.");
    for (const I height : {-2, 2}) {
        auto raised = arm;
        raised.box.minimum[1] += height; raised.box.maximum[1] += height; raised.pivot[1] += height;
        check(query(raised, {corner}).clear(), "Changing the actual axial separation clears the same rotating arm.");
    }
    check(arm == saved, "The query does not mutate a caller-owned pose or advance a phase.");
}

void radial_and_axial_contacts() {
    const c::Rotor hollow{{{3, -1, 4}, {4, 1, 5}}};
    check(query(hollow, {{1, {{0, -1, 0}, {3, 1, 4}}}}).clear(), "Inner-radius tangency is clear; a hollow sweep is not a filled disk.");
    check(query(hollow, {{1, {{4, -1, 5}, {5, 1, 6}}}}).clear(), "Outer-radius tangency is clear.");
    check(query(hollow, {{1, {{-1, -1, -1}, {1, 1, 1}}}}).clear(), "An obstacle wholly in the central hole is clear.");
    const c::Rotor centered{{{-1, -1, -1}, {1, 1, 1}}};
    check(query(centered, {{1, centered.box}}).hit == c::FullTurnHit{1, 0, 2}, "A box crossing its axis sweeps the central disk.");
    check(query(arm, {{1, {{1, 1, 1}, {2, 2, 2}}}}).clear(), "Axial face tangency is clear.");
    check(!query(arm, {{1, {{1, 0, 1}, {2, 2, 2}}}}).clear(), "Positive axial penetration blocks when radii overlap.");
    check(query(arm).clear(), "An empty complete obstacle set accepts a bounded turn.");
    const auto selected = query(arm, {{99, arm.box}, corner});
    check(selected.hit && selected.hit->obstacle == 7, "Selection uses lowest identity, not initial overlap or inferred time order.");
    check(query(arm, {corner, {99, arm.box}}) == selected, "Observation order does not alter the selected obstruction.");
}

void validation_and_bounds() {
    auto bad = arm;
    bad.box.maximum[0] = bad.box.minimum[0];
    check(query(bad).error == c::Error::invalid_box, "A degenerate body is refused.");
    bad = arm; bad.box.minimum[0] = std::numeric_limits<I>::min();
    check(query(bad).error == c::Error::invalid_box, "Unbounded body coordinates are refused before subtraction.");
    bad = arm; bad.axis = static_cast<m::Axis>(-1);
    check(query(bad).error == c::Error::invalid_motion, "Invalid axis input is refused before indexing.");
    bad = arm; bad.pivot[2] = std::numeric_limits<I>::max();
    check(query(bad).error == c::Error::invalid_motion, "Unbounded pivots are refused before arithmetic.");
    constexpr auto bound = m::maximum_coordinate;
    bad = {{{bound - 2, -1, -1}, {bound, 1, 1}}, {bound - 1, 0, 0}};
    check(query(bad).error == c::Error::invalid_motion, "A valid starting box whose circle leaves the grid is refused.");
    const c::Rotor near_edge{{{bound - 3, -1, -1}, {bound - 2, 1, 1}}, {bound - 5, 0, 0}};
    check(query(near_edge).clear(), "A nearby pivot with a complete turn inside the grid is accepted.");
    const c::Rotor large{{{-bound / 2, -1, -bound / 2}, {bound / 2, 1, bound / 2}}};
    check(query(large, {{1, {{bound / 2, -1, bound / 2}, {bound, 1, bound}}}}).clear(),
          "Large squared-radius tangency remains exact without floating-point conversion or overflow.");
    auto error = query(arm, {corner, {0, corner.box}});
    check(error.error == c::Error::invalid_id && !error.hit, "A later invalid identity rejects the entire observation, including earlier hits.");
    error = query(arm, {corner, corner});
    check(error.error == c::Error::duplicate_id && !error.hit, "Duplicate identities do not publish partial results.");
    error = query(arm, {corner, {9, {{0, 0, 0}, {0, 1, 1}}}});
    check(error.error == c::Error::invalid_box && !error.hit, "A later malformed obstacle is not hidden by an earlier obstruction.");
    std::vector<c::Obstacle> many;
    for (std::size_t i = 0; i < m::maximum_parts; ++i) many.push_back({i + 1, {{0, 10, 0}, {1, 11, 1}}});
    check(query(arm, many).clear(), "The complete supported obstacle limit is accepted.");
    many.push_back({many.size() + 1, corner.box});
    error = query(arm, many);
    check(error.error == c::Error::too_many_obstacles && !error.hit, "Oversized observation is refused rather than truncated.");
}

c::Point permute(const c::Point& p, const std::array<std::size_t, 3>& order) {
    return {p[order[0]], p[order[1]], p[order[2]]};
}
void spatial_invariance() {
    const auto expected = query(arm, {corner});
    std::array<std::size_t, 3> order{0, 1, 2};
    do {
        auto moved = arm;
        auto obstacle = corner;
        moved.box = {permute(arm.box.minimum, order), permute(arm.box.maximum, order)};
        moved.pivot = permute(arm.pivot, order);
        moved.axis = static_cast<m::Axis>(std::find(order.begin(), order.end(), 1) - order.begin());
        obstacle.box = {permute(corner.box.minimum, order), permute(corner.box.maximum, order)};
        const c::Point offset{17, -5, 23};
        for (std::size_t axis = 0; axis < 3; ++axis) {
            moved.box.minimum[axis] += offset[axis]; moved.box.maximum[axis] += offset[axis]; moved.pivot[axis] += offset[axis];
            obstacle.box.minimum[axis] += offset[axis]; obstacle.box.maximum[axis] += offset[axis];
        }
        check(query(moved, {obstacle}) == expected, "All axis permutations and translated pivots preserve the physical obstruction/witness.");
    } while (std::next_permutation(order.begin(), order.end()));
}

void independent_small_pose_oracle() {
    std::vector<std::array<I, 3>> angles{{1, 0, 1}, {0, 1, 1}, {-1, 0, 1}, {0, -1, 1}};
    for (const auto triple : std::array<std::array<I, 3>, 2>{{{3, 4, 5}, {5, 12, 13}}}) {
        for (const I sign_x : {-1, 1}) for (const I sign_z : {-1, 1}) {
            angles.push_back({sign_x * triple[0], sign_z * triple[1], triple[2]});
            angles.push_back({sign_x * triple[1], sign_z * triple[0], triple[2]});
        }
    }
    for (I x = -3; x <= 3; ++x) for (I z = -3; z <= 3; ++z) {
        const c::Rotor body{{{x, -1, z}, {x + 1, 1, z + 1}}};
        for (I ox = -3; ox <= 3; ++ox) for (I oz = -3; oz <= 3; ++oz) {
            const c::Obstacle obstacle{1, {{ox, -1, oz}, {ox + 1, 1, oz + 1}}};
            const auto result = query(body, {obstacle});
            bool witnessed = false;
            for (const auto angle : angles) witnessed = witnessed || pose_overlap(body, obstacle, angle[0], angle[1], angle[2]);
            ++oracle_pairs;
            witnessed_pairs += witnessed;
            continuous_hits += result.hit.has_value();
            check(result.error == c::Error::none && (!witnessed || result.hit.has_value()),
                  "A continuous-clear result cannot contradict an independently constructed exact rotated-polygon collision.");
        }
    }
}
}  // namespace

int main() {
    try {
        between_stops();
        radial_and_axial_contacts();
        validation_and_bounds();
        spatial_invariance();
        independent_small_pose_oracle();
        std::cout << checks << " native rotary-clearance checks, 0 failures; " << oracle_pairs
                  << " small geometry pairs, " << witnessed_pairs << " exact sampled collision witnesses, "
                  << continuous_hits << " continuous obstructions; engine_calls=0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
