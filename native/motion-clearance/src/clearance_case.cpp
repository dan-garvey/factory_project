#include "factory/clearance.hpp"
#include "factory/cycle.hpp"

#include <array>
#include <iostream>

namespace c = factory::clearance;
namespace m = factory::mechanisms;

int main() {
    const m::Slide slide{2, 4, 2};
    const std::array<c::Obstacle, 1> obstruction{{{17, {{2, 0, 0}, {3, 1, 1}}}}};
    m::Phase phase;
    auto step = [&](std::span<const c::Obstacle> obstacles, bool expected_block) {
        auto proposed = phase;
        m::Pose before, after;
        if (m::advance(slide, proposed, true) != m::Error::none ||
            m::sample(slide, phase, before) != m::Error::none ||
            m::sample(slide, proposed, after) != m::Error::none) return false;
        const auto x = static_cast<c::Coordinate>(before.numerator);
        const c::Point displacement{{static_cast<c::Coordinate>(after.numerator) - x, 0, 0}};
        const auto clearance = c::sweep({{x, 0, 0}, {x + 1, 1, 1}}, displacement, obstacles);
        if (clearance.error != c::Error::none || clearance.hit.has_value() != expected_block) return false;
        const auto original = phase;
        const auto result = m::advance(slide, phase, true, clearance.hit.has_value());
        return expected_block ? result == m::Error::obstructed && phase == original
                              : result == m::Error::none && phase == proposed;
    };
    for (int i = 0; i < 3; ++i) if (!step(obstruction, false)) return 1;
    if (phase != m::Phase{3}) return 1;
    for (int i = 0; i < 5; ++i) if (!step(obstruction, true)) return 1;
    if (phase != m::Phase{3} || !step({}, false) || phase != m::Phase{4}) return 1;
    std::cout << "{\"status\":\"pass\",\"evidence\":\"native_swept_box_carriage_fixture\","
                 "\"obstacle_id\":17,\"held_phase\":3,\"blocked_steps\":5,\"resumed_phase\":4}\n";
    return std::cout ? 0 : 1;
}
