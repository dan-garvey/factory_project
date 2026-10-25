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

struct Fixture { w::Profile profile; w::State state; };

Fixture connected_line() {
    Fixture fixture;
    auto& [profile, state] = fixture;
    profile.collector_faces = {{{0, 4, 0}, {-1, 0, 0}},
                               {{100, 4, 0}, {-1, 0, 0}}};
    state.topology.drive_enabled = true;
    state.topology.parts = {
        {{"main-wheel", m::Kind::hub, {-4, 4, 0}, m::Axis::x, 0, 0}, 1, s::Role::waterwheel},
        {{"main-shaft", m::Kind::shaft, {4, 4, 0}, m::Axis::x, 0, 2}, 1, s::Role::shaft},
        {{"light-wheel", m::Kind::hub, {96, 4, 0}, m::Axis::x, 0, 0}, 1, s::Role::waterwheel}};
    state.topology.sources = {{"main-wheel", {1, 1}}, {"light-wheel", {1, 1}}};

    add(state, "collector-frame", mat::Component::wooden_frame, {0, 4, 0});
    add(state, "collector-mount", mat::Component::tool_mount, {-1, 4, 0});
    add(state, "collector-edge", mat::Component::cutting_edge, {-2, 4, 0});
    add(state, "collector-tray", mat::Component::receiver_tray, {0, 4, 1});
    add(state, "collector-shaft", mat::Component::copper_shaft, {1, 4, 0});

    add(state, "press-frame", mat::Component::wooden_frame, {8, 0, 0});
    add(state, "press-anvil", mat::Component::anvil, {8, 1, 0});
    add(state, "press-ram", mat::Component::ram_face, {8, 2, 0});
    add(state, "press-guide", mat::Component::sliding_guide, {8, 3, 0});
    add(state, "press-mount", mat::Component::tool_mount, {8, 4, 0});
    add(state, "press-shaft", mat::Component::copper_shaft, {7, 4, 0});
    add(state, "press-cog", mat::Component::wooden_cog, {6, 4, 0});

    add(state, "light-frame", mat::Component::wooden_frame, {100, 4, 0});
    add(state, "light-mount", mat::Component::tool_mount, {99, 4, 0});
    add(state, "light-edge", mat::Component::cutting_edge, {98, 4, 0});
    add(state, "light-tray", mat::Component::receiver_tray, {100, 4, 1});
    add(state, "light-shaft", mat::Component::wooden_shaft, {101, 4, 0});
    return fixture;
}

void mixed_material_bottleneck_and_isolation() {
    auto fixture = connected_line();
    const auto stopped = w::drive_power(fixture.profile, fixture.state);
    check(stopped.mechanical.accepted() && stopped.mechanical.motion.at("press-frame").state ==
              m::MotionState::stalled && stopped.mechanical.motion.at("collector-frame").state ==
              m::MotionState::stalled && stopped.load.at("press-cog").overloaded &&
              stopped.load.at("press-cog").limiting_part == "press-cog" &&
              stopped.load.at("press-cog").capacity == 8 && stopped.load.at("press-cog").impact == 12,
          "One real wooden cog stalls the connected collector and press at combined load.");
    check(stopped.mechanical.motion.at("light-frame").state == m::MotionState::rotating &&
              !stopped.load.at("light-shaft").overloaded &&
              stopped.load.at("light-shaft").impact == 4,
          "An independent wooden branch keeps turning below its own material rating.");

    fixture.state.placed_components.at("press-cog").kind = mat::Component::copper_cog;
    const auto upgraded = w::drive_power(fixture.profile, fixture.state);
    check(upgraded.mechanical.accepted() &&
              upgraded.mechanical.motion.at("press-frame").state == m::MotionState::rotating &&
              upgraded.mechanical.motion.at("collector-frame").state == m::MotionState::rotating &&
              upgraded.load.at("press-cog").capacity == 24 &&
              upgraded.load.at("press-cog").impact == 12 &&
              !upgraded.load.at("press-cog").overloaded,
          "Replacing only the limiting cog with copper runs the same connected line.");
    check(upgraded.mechanical.motion.at("light-frame") == stopped.mechanical.motion.at("light-frame") &&
              upgraded.load.at("light-shaft") == stopped.load.at("light-shaft"),
          "The separate light branch is unchanged by the main-line substitution.");

    fixture.state.placed_components.at("collector-shaft").kind = mat::Component::wooden_shaft;
    const auto second_bottleneck = w::drive_power(fixture.profile, fixture.state);
    check(second_bottleneck.mechanical.motion.at("press-frame").state == m::MotionState::stalled &&
              second_bottleneck.load.at("collector-shaft").limiting_part == "collector-shaft",
          "A wooden shaft is a separate real bottleneck even with the upgraded press cog.");
}

void collector_and_press_share_one_frame() {
    auto fixture = connected_line();
    auto& placed = fixture.state.placed_components;
    placed.erase("press-frame");
    placed.at("press-anvil").center = {0, 5, 0};
    placed.at("press-ram").center = {0, 6, 0};
    placed.at("press-guide").center = {0, 7, 0};
    placed.at("press-mount").center = {0, 8, 0};
    placed.at("press-shaft").center = {0, 8, -1};
    placed.at("press-cog").center = {0, 8, -2};
    add(fixture.state, "projected-press-hub-0", mat::Component::wooden_cog, {60, 4, 0});
    const auto power = w::drive_power(fixture.profile, fixture.state);
    check(power.mechanical.accepted() && power.mechanical.motion.contains("collector-frame") &&
              power.mechanical.motion.contains("projected-press-hub-1") &&
              power.mechanical.motion.contains("press-shaft") &&
              power.mechanical.motion.contains("press-cog"),
          "One issued frame supports both fittings, and an issued ID cannot collide with its projected press hub.");
}

void unloaded_slide_shaft_is_native_drive_part() {
    w::Profile profile;
    w::State state;
    state.topology.drive_enabled = true;
    state.topology.parts = {
        {{"wheel", m::Kind::hub, {-1, 4, 0}, m::Axis::x, 0, 0}, 1, s::Role::waterwheel}};
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

void held_crank_uses_slide_input_graph() {
    w::Profile profile;
    w::State state;
    add(state, "slide", mat::Component::wooden_slide, {0, 2, 0});
    const auto idle = w::hand_slide_power(profile, state, "slide", {1, 2, 0});
    check(idle.mechanical.accepted() && idle.mechanical.motion.at("slide").state ==
              m::MotionState::rotating && idle.load.at("slide").capacity == 8 &&
          idle.load.at("slide").impact == 4,
          "The held crank engages the unchanged integral shaft through its exposed X port.");
    add(state, "anvil", mat::Component::anvil, {0, 0, 0});
    add(state, "head", mat::Component::flat_head, {0, 1, 0});
    const auto loaded = w::hand_slide_power(profile, state, "slide", {1, 2, 0});
    check(loaded.mechanical.accepted() && loaded.mechanical.motion.at("slide").state ==
              m::MotionState::rotating && loaded.load.at("slide").impact == 8 &&
          loaded.load.at("slide").capacity == 8,
          "Actual flat-head contact consumes the wooden slide's remaining rated load.");
    check(!w::hand_slide_power(profile, state, "slide", {0, 3, 0}).mechanical.accepted(),
          "A top face cannot impersonate the integral X-axis input.");
    state.placed_components.at("head").center[0] = 1;
    const auto detached = w::hand_slide_power(profile, state, "slide", {1, 2, 0});
    check(detached.load.at("slide").impact == 4,
          "A displaced head does not create invisible contact load.");
    state.placed_components.at("head").center[0] = 0;
    add(state, "linked-slide", mat::Component::wooden_slide, {2, 2, 0});
    const auto overloaded = w::hand_slide_power(profile, state, "slide", {-1, 2, 0});
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
        mixed_material_bottleneck_and_isolation();
        collector_and_press_share_one_frame();
        unloaded_slide_shaft_is_native_drive_part();
        held_crank_uses_slide_input_graph();
        carriage_phase_tracks_signed_fractional_shaft_travel();
        std::cout << "material_strength_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "material_strength_test: " << error.what() << '\n';
        return 1;
    }
}
