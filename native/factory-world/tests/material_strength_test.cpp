#include "factory/world.hpp"

#include <iostream>
#include <stdexcept>

namespace {
namespace w = factory::world;
namespace m = factory::mechanics;
namespace s = factory::stationary;
namespace mat = factory::materials;

int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

void add(w::State& state, const char* id, mat::Component kind, m::Point center) {
    state.placed_components.emplace(id, w::PlacedComponent{kind, center, 1});
}

void unloaded_slide_shaft_is_native_drive_part() {
    w::Profile profile;
    w::State state;
    state.topology.drive_enabled = true;
    state.topology.parts = {
        {{"wheel", m::Kind::hub, {-4, 4, 0}, m::Axis::x, 0, 0}, 1, s::Role::waterwheel}};
    state.topology.sources = {{"wheel", {1, 1}}};
    add(state, "slide", mat::Component::wooden_slide, {0, 4, 0});
    const auto driven = w::drive_power(profile, state);
    check(driven.mechanical.accepted() && driven.mechanical.motion.contains("slide") &&
          driven.mechanical.motion.at("slide").state == m::MotionState::rotating &&
          driven.load.at("slide").capacity == 8 && driven.load.at("slide").impact == 4,
          "One placed slide supplies its own rated shaft to an external drive.");
    state.topology.drive_enabled = false;
    const auto stopped = w::drive_power(profile, state);
    check(stopped.mechanical.accepted() && stopped.mechanical.motion.at("slide").state !=
          m::MotionState::rotating,
          "Removing power stops the same unloaded slide without removing a part.");
}

void fitted_slide_accepts_same_height_external_route() {
    for (const m::Integer floor : {m::Integer{0}, m::Integer{4}}) {
        w::Profile profile;
        w::State state;
        state.topology.parts = {
            {{"external-shaft", m::Kind::shaft, {-4, floor + 2, 0},
                m::Axis::x, 0, 2}, 1, s::Role::shaft}};
        add(state, "anvil", mat::Component::anvil, {0, floor, 0});
        add(state, "head", mat::Component::flat_head, {0, floor + 1, 0});
        add(state, "slide", mat::Component::wooden_slide, {0, floor + 2, 0});
        const auto power = w::hand_crank_power(profile, state, "slide", {4, floor + 2, 0});
        check(power.mechanical.accepted() &&
              power.mechanical.motion.at("external-shaft").state == m::MotionState::rotating &&
              power.mechanical.motion.at("slide").state == m::MotionState::rotating &&
              power.mechanical.motion.at("slide").rate.numerator == 1 &&
              power.load.at("slide").capacity == 8 &&
              power.load.at("slide").impact == 8 &&
              state.placed_components.size() == 3,
            "A ground or raised crank drives the fitted slide and external H-layer shaft.");
        const auto stopped = w::drive_power(profile, state);
        check(stopped.mechanical.accepted() &&
              stopped.mechanical.motion.at("slide").state != m::MotionState::rotating &&
              stopped.mechanical.motion.at("external-shaft").state != m::MotionState::rotating,
            "Releasing the crank stops both independently placed parts.");
    }
}

void held_crank_uses_slide_input_graph() {
    w::Profile profile;
    w::State state;
    add(state, "slide", mat::Component::wooden_slide, {0, 2, 0});
    const auto idle = w::hand_crank_power(profile, state, "slide", {4, 2, 0});
    check(idle.mechanical.accepted() && idle.mechanical.motion.at("slide").state ==
              m::MotionState::rotating && idle.load.at("slide").capacity == 8 &&
          idle.load.at("slide").impact == 4,
          "The held crank engages the unchanged integral shaft through its exposed X port.");
    add(state, "anvil", mat::Component::anvil, {0, 0, 0});
    add(state, "head", mat::Component::flat_head, {0, 1, 0});
    const auto loaded = w::hand_crank_power(profile, state, "slide", {4, 2, 0});
    check(loaded.mechanical.accepted() && loaded.mechanical.motion.at("slide").state ==
              m::MotionState::rotating && loaded.load.at("slide").impact == 8 &&
          loaded.load.at("slide").capacity == 8,
          "Actual flat-head contact consumes the wooden slide's remaining rated load.");
    check(!w::hand_crank_power(profile, state, "slide", {0, 3, 0}).mechanical.accepted(),
          "A top face cannot impersonate the integral X-axis input.");
    state.placed_components.at("head").center[0] = 1;
    const auto detached = w::hand_crank_power(profile, state, "slide", {4, 2, 0});
    check(detached.load.at("slide").impact == 4,
          "A displaced head does not create invisible contact load.");
    state.placed_components.at("head").center[0] = 0;
    add(state, "linked-slide", mat::Component::wooden_slide, {4, 2, 0});
    const auto overloaded = w::hand_crank_power(profile, state, "slide", {-4, 2, 0});
    check(overloaded.mechanical.accepted() &&
          overloaded.mechanical.motion.at("slide").state == m::MotionState::stalled &&
          overloaded.load.at("slide").overloaded && overloaded.load.at("slide").impact == 12 &&
          overloaded.load.at("slide").capacity == 8,
          "The issued crank cannot bypass a wooden bottleneck on a second connected load.");
}

void carriage_phase_tracks_signed_fractional_shaft_travel() {
    w::State::SlidePhase phase;
    check(w::advance_slide_phase(phase, {1, 2}) && phase.subticks == 2048 &&
          phase.remainder == 0 && phase.denominator == 1,
          "Half a shaft revolution advances one eighth of the four-turn carriage cycle.");
    check(w::advance_slide_phase(phase, {-1, 3}) && phase.subticks == 682 &&
          phase.remainder == 2 && phase.denominator == 3,
          "Reverse fractional shaft travel retains exact phase rather than rounding a tick.");
    check(w::advance_slide_phase(phase, {1, 3}) && phase.subticks == 2048 &&
          phase.remainder == 0 && phase.denominator == 1,
          "Opposite signed travel restores the same exact carriage position.");
    check(w::advance_slide_phase(phase, {-1, 1}) &&
          phase.subticks == w::slide_cycle_subticks - 2048,
          "Reverse travel wraps through the start of the bounded cycle.");
    const auto before = phase;
    check(!w::advance_slide_phase(phase, {1, 0}) && phase == before,
          "An invalid drive denominator cannot mutate the carriage.");
}

}  // namespace

int main() {
    try {
        unloaded_slide_shaft_is_native_drive_part();
        fitted_slide_accepts_same_height_external_route();
        held_crank_uses_slide_input_graph();
        carriage_phase_tracks_signed_fractional_shaft_travel();
        std::cout << "material_strength_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "material_strength_test: " << error.what() << '\n';
        return 1;
    }
}
