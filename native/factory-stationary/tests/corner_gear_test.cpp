#include "factory/stationary.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace s = factory::stationary;
namespace m = factory::mechanics;

namespace {
int checks = 0;
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

s::Topology fixture(int input_axis, int output_axis, int input_offset, int output_offset) {
    m::Point a{0, 0, 0}, b{0, 0, 0};
    b[input_axis] = input_offset;
    b[output_axis] = output_offset;
    const auto ax = static_cast<m::Axis>(input_axis);
    const auto bx = static_cast<m::Axis>(output_axis);
    s::Topology t;
    t.parts = {
        {{"source", m::Kind::hub, a, ax, 0, 0}, 1, s::Role::waterwheel},
        {{"a-shaft", m::Kind::shaft, a, ax, 0, 1}, 1, s::Role::shaft},
        {{"a-gear", m::Kind::gear, a, ax, 4, 0}, 1, s::Role::gear},
        {{"b-gear", m::Kind::gear, b, bx, 4, 0}, 1, s::Role::gear},
        {{"b-shaft", m::Kind::shaft, b, bx, 0, 1}, 1, s::Role::shaft},
        {{"sink", m::Kind::hub, b, bx, 0, 0}, 1, s::Role::belt},
    };
    t.sources = {{"source", {3, 2}}};
    t.drive_enabled = true;
    return t;
}

void corner_cases() {
    for (int a = 0; a < 3; ++a) for (int b = 0; b < 3; ++b) {
        if (a == b) continue;
        for (const int da : {-4, 4}) for (const int db : {-4, 4}) {
            auto topology = fixture(a, b, da, db);
            auto power = s::power_view(topology);
            check(power.mechanical.accepted(), "Corner gear topology must be accepted.");
            // Equal-sign offsets preserve the signed coordinate rate; opposite
            // signs reverse it. This is independent of axis ordering.
            const m::Rate expected{da * db > 0 ? 3 : -3, 2};
            check(power.mechanical.motion.at("sink") == m::Motion{m::MotionState::rotating, expected},
                  "A corner mesh transmits the expected signed 1:1 rotation.");
            check(power.mechanical.engagements.size() == 5, "The corner train has one physical mesh and four shaft contacts.");

            topology.sources = {{"sink", expected}};
            // Use a second waterwheel as the reversed source.
            topology.parts.back().role = s::Role::waterwheel;
            power = s::power_view(topology);
            check(power.mechanical.accepted() && power.mechanical.motion.at("source") ==
                  m::Motion{m::MotionState::rotating, {3, 2}}, "The same mesh transmits backwards.");
            topology.sources.push_back({"source", {-3, 2}});
            power = s::power_view(topology);
            check(power.mechanical.accepted() && power.mechanical.motion.at("source").state == m::MotionState::stalled,
                  "Incompatible sources stall their connected train.");

            topology = fixture(a, b, da, db);
            topology.parts[3].geometry.teeth = 2;
            check(s::power_view(topology).mechanical.motion.at("sink").state == m::MotionState::unpowered,
                  "A small cog does not form this right-angle large-cog mesh.");
            topology = fixture(a, b, da, db);
            topology.parts[3].geometry.center[a] += da > 0 ? 1 : -1;
            topology.parts[4].geometry.center = topology.parts[3].geometry.center;
            topology.parts[5].geometry.center = topology.parts[3].geometry.center;
            check(s::power_view(topology).mechanical.motion.at("sink").state == m::MotionState::unpowered,
                  "A displaced corner does not transmit.");
            topology = fixture(a, b, da, db);
            const auto third = 3 - a - b;
            topology.parts[3].geometry.center[third] = 1;
            topology.parts[4].geometry.center = topology.parts[3].geometry.center;
            topology.parts[5].geometry.center = topology.parts[3].geometry.center;
            check(s::power_view(topology).mechanical.motion.at("sink").state == m::MotionState::unpowered,
                  "An offset outside both shaft axes does not form a corner mesh.");
            topology = fixture(a, b, da, db);
            topology.parts.erase(topology.parts.begin() + 3);
            check(s::power_view(topology).mechanical.motion.at("sink").state == m::MotionState::unpowered,
                  "Removing the second cog disconnects the sink.");
        }
    }
}

void mixed_cog_cases() {
    for (int axis = 0; axis < 3; ++axis) {
        const int first = (axis + 1) % 3;
        const int second = (axis + 2) % 3;
        for (const int d1 : {-4, 4}) for (const int d2 : {-4, 4}) {
            auto topology = fixture(axis, first, 4, 4);
            m::Point position{0, 0, 0};
            position[first] = d1;
            position[second] = d2;
            topology.parts[2].geometry.teeth = 2;
            for (int i : {3, 4, 5}) {
                topology.parts[i].geometry.center = position;
                topology.parts[i].geometry.axis = static_cast<m::Axis>(axis);
            }
            auto result = s::power_view(topology);
            check(result.mechanical.accepted(), "Diagonal small and large cogs must be accepted.");
            check(result.mechanical.motion.at("sink") == m::Motion{m::MotionState::rotating, {-3, 4}},
                  "Small-to-large diagonal transmission reverses and halves the rate.");
            topology.parts.back().role = s::Role::waterwheel;
            topology.sources = {{"sink", {3, 2}}};
            result = s::power_view(topology);
            check(result.mechanical.accepted() && result.mechanical.motion.at("source") ==
                  m::Motion{m::MotionState::rotating, {-3, 1}}, "Large-to-small diagonal transmission doubles and reverses the rate.");

            topology.sources = {{"source", {3, 2}}};
            position[first] = 6;
            position[second] = 0;
            for (int i : {3, 4, 5}) topology.parts[i].geometry.center = position;
            result = s::power_view(topology);
            check(result.mechanical.accepted() && result.mechanical.motion.at("sink").state == m::MotionState::unpowered,
                  "The old straight pitch-radius tangency no longer connects mixed cog sizes.");
            position[first] = d1 > 0 ? 5 : -5;
            position[second] = d2;
            for (int i : {3, 4, 5}) topology.parts[i].geometry.center = position;
            result = s::power_view(topology);
            check(result.mechanical.accepted() && result.mechanical.motion.at("sink").state == m::MotionState::unpowered,
                  "An off-grid mixed pair does not connect.");
        }
    }
}
} // namespace

int main() {
    try {
        corner_cases();
        mixed_cog_cases();
        std::cout << "corner gear stationary checks: " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
