#include "factory/world.hpp"

#include <array>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
namespace a = factory::assembly;
namespace g = factory::mechanics;
namespace m = factory::materials;
namespace s = factory::stationary;
namespace w = factory::world;

int checks{};

void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

void one_slide_broad_load() {
    const std::vector<a::Part> placed{
        {"broad-bed", m::Component::broad_anvil, {0, 0, 0}, 1},
        {"broad-head", m::Component::broad_flat_head, {0, 1, 0}, 1},
        {"slide", m::Component::broad_slide, {0, 4, 0}, 1},
    };
    const a::Layout layout(placed);
    const auto inspected = layout.inspect_broad_sliding_press({0, 0, 0});
    check(inspected.status == a::PressStatus::ready && inspected.press &&
          inspected.press->work_centers == std::array<g::Point, 4>{
              g::Point{0, 0, 0}, g::Point{4, 0, 0},
              g::Point{0, 0, 4}, g::Point{4, 0, 4}},
        "One broad support, matching face and central slide cover four contiguous workcells.");
    w::Profile profile;
    w::State state;
    for (const auto& part : placed)
        state.placed_components.emplace(part.id,
            w::PlacedComponent{part.kind, part.center, part.generation});
    const auto power = w::hand_crank_power(profile, state, "slide", {-2, 4, 0});
    check(power.mechanical.accepted(), "The broad slide graph is mechanically valid.");
    check(power.mechanical.motion.contains("slide"),
        "The shared housing appears in the actual mechanical graph.");
    check(power.mechanical.motion.at("slide").state == g::MotionState::rotating,
        "The fitted crank rotates the central piston through its tile shaft.");
    check(power.load.contains("slide") && !power.load.at("slide").overloaded &&
          power.load.at("slide").impact == 12 && power.load.at("slide").capacity == 12,
        "One broad slide carries the broad head at the crank's real capacity.");
    for (const auto& port : {g::Point{-2, 4, 0}, g::Point{6, 4, 0},
             g::Point{-2, 4, 4}, g::Point{6, 4, 4}}) {
        const auto driven = w::hand_crank_power(profile, state, "slide", port);
        check(driven.mechanical.accepted() &&
              driven.mechanical.motion.at("slide").state == g::MotionState::rotating &&
              driven.mechanical.components.size() == 1 &&
              driven.load.at("slide").impact == 12,
            "Every outer tile-center port reaches the same central piston and load.");
    }
    check(!w::hand_crank_power(profile, state, "slide", {3, 4, 2}).mechanical.accepted(),
        "The former seam-center input cannot drive the full-tile housing.");
    for (const auto& [external, source] : {
             std::pair{g::Point{-4, 4, 0}, g::Point{-8, 4, 0}},
             std::pair{g::Point{8, 4, 0}, g::Point{12, 4, 0}},
             std::pair{g::Point{-4, 4, 4}, g::Point{-8, 4, 4}},
             std::pair{g::Point{8, 4, 4}, g::Point{12, 4, 4}}}) {
        state.topology.drive_enabled = true;
        state.topology.parts = {
            {{"external-shaft", g::Kind::shaft, external, g::Axis::x, 0, 2},
                1, s::Role::shaft},
            {{"wheel", g::Kind::hub, source, g::Axis::x, 0, 0},
                1, s::Role::waterwheel},
        };
        state.topology.sources = {{"wheel", {1, 1}}};
        const auto routed = w::drive_power(profile, state);
        check(routed.mechanical.accepted() &&
              routed.mechanical.motion.at("slide").state == g::MotionState::rotating &&
              !routed.load.at("slide").overloaded,
            "An external tile-center shaft on either row and side drives the one broad piston.");
    }
}
}  // namespace

int main() {
    try {
        one_slide_broad_load();
        std::cout << "broad_press_drive_world_test: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "broad_press_drive_world_test: " << error.what() << '\n';
        return 1;
    }
}
