#include "factory/clearance.hpp"
#include "factory/cycle.hpp"

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <numeric>
#include <vector>

namespace c = factory::clearance;
namespace m = factory::mechanisms;
namespace {
int checks{};
int failures{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}

c::Box unit(c::Coordinate x, c::Coordinate y, c::Coordinate z) {
    return {{x, y, z}, {x + 1, y + 1, z + 1}};
}

c::Result one(const c::Box& box, c::Point move, c::Box obstacle, std::uint64_t id = 7) {
    const std::array<c::Obstacle, 1> obstacles{{{id, obstacle}}};
    return c::sweep(box, move, obstacles);
}

void literal_contacts() {
    const c::Box box{{0, 0, 0}, {2, 2, 2}};
    for (unsigned axis = 0; axis < 3; ++axis) {
        auto obstacle = box;
        obstacle.minimum[axis] = 5; obstacle.maximum[axis] = 7;
        c::Point move{};
        move[axis] = 6;
        check(one(box, move, obstacle) == c::Result{c::Error::none, c::Hit{7, {1, 2}, false}},
              "Each axis reports the exact reduced half-stroke incoming contact.");
        move[axis] = 3;
        check(one(box, move, obstacle).clear(), "A stroke ending exactly at the obstacle face remains nonpenetrating.");
        move[axis] = 4;
        check(one(box, move, obstacle).hit == c::Hit{7, {3, 4}, false},
              "A longer stroke reports its literal three-quarter contact time.");
        move[axis] = 10;
        check(one(box, move, obstacle).hit == c::Hit{7, {3, 10}, false},
              "A box cannot tunnel through an obstacle when both sampled endpoints are clear.");
        obstacle.minimum[axis] = -5; obstacle.maximum[axis] = -3;
        move[axis] = -6;
        check(one(box, move, obstacle).hit == c::Hit{7, {1, 2}, false},
              "Negative translation preserves the exact half-stroke contact.");
    }
    check(one(box, {6, 6, 6}, {{5, 5, 5}, {7, 7, 7}}).hit == c::Hit{7, {1, 2}, false},
          "A full three-dimensional diagonal uses the common exact entry interval.");
    const auto touch = unit(1, 0, 0);
    check(one(unit(0, 0, 0), {1, 0, 0}, touch).hit == c::Hit{7, {0, 1}, false},
          "Touch followed by penetration blocks at time zero without pretending it began overlapped.");
    check(one(unit(0, 0, 0), {-1, 0, 0}, touch).clear(), "A touching box may move away from the shared face.");
    check(one(unit(0, 0, 0), {0, 3, 0}, touch).clear(), "A box may slide along a touching face without interior collision.");
    check(one(unit(0, 0, 0), {}, touch).clear(), "Stationary surface contact is distinct from penetration.");
    check(one(unit(0, 0, 0), {4, 4, 0}, {{3, 0, 0}, {4, 2, 1}}).clear(),
          "A single corner-graze instant cannot become an interval of interior overlap.");
    check(one(box, {}, unit(1, 1, 1)).hit == c::Hit{7, {0, 1}, true},
          "An existing positive-volume overlap is reported for a stationary query.");
    check(one(box, {-5, 0, 0}, unit(1, 1, 1)).hit == c::Hit{7, {0, 1}, true},
          "An escape proposal cannot silently accept an initially penetrating shape.");
}

void deterministic_identity() {
    const c::Box box{{0, 0, 0}, {2, 2, 2}};
    std::array<c::Obstacle, 2> obstacles{{{50, {{5, 0, 0}, {7, 2, 2}}}, {12, {{5, 0, 0}, {8, 2, 2}}}}};
    const auto expected = c::Result{c::Error::none, c::Hit{12, {1, 2}, false}};
    check(c::sweep(box, {6, 0, 0}, obstacles) == expected, "Equal contact times choose the lowest stable opaque identity.");
    std::reverse(obstacles.begin(), obstacles.end());
    check(c::sweep(box, {6, 0, 0}, obstacles) == expected, "Input order cannot alter the selected contact or its exact fraction.");
    obstacles = {{{1, {{6, 0, 0}, {7, 2, 2}}}, {99, {{4, 0, 0}, {5, 2, 2}}}}};
    check(c::sweep(box, {8, 0, 0}, obstacles).hit == c::Hit{99, {1, 4}, false},
          "An earlier contact wins even when its identity is larger.");
    const c::Point offset{{-7, 11, 3}};
    auto shifted_box = box;
    auto shifted = obstacles;
    for (unsigned axis = 0; axis < 3; ++axis) {
        shifted_box.minimum[axis] += offset[axis]; shifted_box.maximum[axis] += offset[axis];
        for (auto& obstacle : shifted) {
            obstacle.box.minimum[axis] += offset[axis]; obstacle.box.maximum[axis] += offset[axis];
        }
    }
    check(c::sweep(shifted_box, {8, 0, 0}, shifted) == c::sweep(box, {8, 0, 0}, obstacles),
          "Moving the entire fixture in three dimensions preserves contact identity and time.");
}

bool sampled_overlap(const c::Box& box, const c::Point& move, const c::Box& obstacle, int numerator) {
    for (unsigned axis = 0; axis < 3; ++axis) {
        const auto minimum = box.minimum[axis] * 12 + move[axis] * numerator;
        const auto maximum = box.maximum[axis] * 12 + move[axis] * numerator;
        if (maximum <= obstacle.minimum[axis] * 12 || minimum >= obstacle.maximum[axis] * 12) return false;
    }
    return true;
}

void exhaustive_small_motion() {
    // Here every nonzero motion denominator is 1, 2 or 3. Interval boundaries
    // lie on sixths; sampling twelfths includes a witness inside every possible
    // nonempty overlap interval. This independent oracle uses positions only.
    for (int x = -3; x <= 3; ++x) for (int y = -3; y <= 3; ++y) {
        for (int dx = -3; dx <= 3; ++dx) for (int dy = -3; dy <= 3; ++dy) {
            const auto box = unit(0, 0, 0), obstacle = unit(x, y, 0);
            const c::Point move{{dx, dy, 0}};
            int first = -1;
            for (int step = 0; step <= 12; ++step) if (sampled_overlap(box, move, obstacle, step)) { first = step; break; }
            const auto result = one(box, move, obstacle);
            check(result.error == c::Error::none && result.hit.has_value() == (first >= 0),
                  "Every small-grid sweep agrees with an independent exhaustive interior-position oracle.");
            if (result.hit) {
                const auto time = result.hit->time;
                check(time.denominator > 0 && time.numerator >= 0 && time.numerator < time.denominator &&
                      std::gcd(time.numerator, time.denominator) == 1,
                      "Every published contact is a canonical fraction inside the proposed stroke.");
                check(time.numerator * 12 <= first * time.denominator &&
                      (first == 0 || time.numerator * 12 >= (first - 1) * time.denominator),
                      "The exact contact lies between the independently observed last-clear and first-overlap samples.");
            }
        }
    }
}

void refusals_and_bounds() {
    const auto box = unit(0, 0, 0);
    constexpr auto limit = factory::mechanics::maximum_coordinate;
    const std::array<c::Box, 4> invalid{{{{0, 0, 0}, {0, 1, 1}}, {{2, 0, 0}, {1, 1, 1}},
        {{-limit - 1, 0, 0}, {1, 1, 1}}, {{0, 0, 0}, {std::numeric_limits<c::Coordinate>::max(), 1, 1}}}};
    for (const auto& bad : invalid) {
        const auto result = c::sweep(bad, {}, {});
        check(result.error == c::Error::invalid_box && !result.hit && !result.clear(),
              "Degenerate, reversed and out-of-grid moving boxes cannot be mistaken for clear motion.");
    }
    for (const auto delta : {std::numeric_limits<c::Coordinate>::max(), std::numeric_limits<c::Coordinate>::min(),
                             c::Coordinate{2 * limit + 1}}) {
        const auto result = c::sweep(box, {delta, 0, 0}, {});
        check(result.error == c::Error::invalid_motion && !result.clear(),
              "Extreme displacement refuses before any coordinate addition or fraction arithmetic.");
    }
    check(c::sweep(box, {limit, 0, 0}, {}).error == c::Error::invalid_motion,
          "A modest center motion cannot carry a box endpoint outside the bounded grid.");
    std::array<c::Obstacle, 2> malformed{{{1, unit(2, 0, 0)}, {2, {{6, 0, 0}, {6, 1, 1}}}}};
    auto result = c::sweep(box, {8, 0, 0}, malformed);
    check(result.error == c::Error::invalid_box && !result.hit && !result.clear(),
          "A later malformed observation prevents publishing an earlier otherwise valid hit.");
    malformed[1] = {1, unit(4, 0, 0)};
    result = c::sweep(box, {8, 0, 0}, malformed);
    check(result.error == c::Error::duplicate_id && !result.hit && !result.clear(),
          "Duplicate obstacle identities cannot silently merge distinct physical observations.");
    malformed[1].id = 0;
    check(c::sweep(box, {8, 0, 0}, malformed).error == c::Error::invalid_id,
          "An absent opaque obstacle identity is refused.");
    std::vector<c::Obstacle> many;
    for (std::size_t n = 0; n < factory::mechanics::maximum_parts; ++n) {
        many.push_back({n + 1, unit(10 + static_cast<c::Coordinate>(n), 0, 0)});
    }
    check(c::sweep(box, {}, many).clear(), "The full declared obstacle budget is supported.");
    many.push_back({999, unit(900, 0, 0)});
    result = c::sweep(box, {}, many);
    check(result.error == c::Error::too_many_obstacles && !result.hit && !result.clear(),
          "An excessive observation set refuses instead of truncating possible hazards.");
    const auto maximum_id = std::numeric_limits<std::uint64_t>::max();
    const c::Box edge{{-limit, -1, -1}, {-limit + 1, 0, 0}};
    check(one(edge, {2 * limit - 1, 0, 0}, {{0, -1, -1}, {1, 0, 0}}, maximum_id).hit ==
          c::Hit{maximum_id, {limit - 1, 2 * limit - 1}, false},
          "Maximum legal traversal and opaque identity retain their exact rational contact without overflow.");
    const c::Box reverse{{limit - 1, -1, -1}, {limit, 0, 0}};
    check(one(reverse, {-(2 * limit - 1), 0, 0}, {{-1, -1, -1}, {0, 0, 0}}).hit ==
          c::Hit{7, {limit - 1, 2 * limit - 1}, false}, "The maximum negative traversal has the same exact bounded arithmetic.");
}

void carriage_continuation() {
    const m::Slide slide{2, 4, 2};
    const std::array<c::Obstacle, 1> obstruction{{{17, unit(2, 0, 0)}}};
    m::Phase phase{3};
    const auto saved = phase;
    for (int i = 0; i < 5; ++i) {
        const auto result = c::sweep(unit(1, 0, 0), {1, 0, 0}, obstruction);
        check(result.hit == c::Hit{17, {0, 1}, false} &&
              m::advance(slide, phase, true, !result.clear()) == m::Error::obstructed && phase == saved,
              "The actual native carriage retains its exact indexed phase through repeated geometric refusals.");
    }
    const auto cleared = c::sweep(unit(1, 0, 0), {1, 0, 0}, {});
    check(cleared.clear() && m::advance(slide, phase, true, !cleared.clear()) == m::Error::none && phase == m::Phase{4},
          "Removing the obstruction resumes the original refused carriage step without a reset or catch-up.");
}
}  // namespace

int main() {
    literal_contacts();
    deterministic_identity();
    exhaustive_small_motion();
    refusals_and_bounds();
    carriage_continuation();
    std::cout << checks << " motion-clearance checks, " << failures << " failures.\n";
    return failures == 0 ? 0 : 1;
}
