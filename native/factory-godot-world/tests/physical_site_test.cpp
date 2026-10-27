#include "factory/physical_site.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {
namespace policy = factory::godot_world::physical_site;
using factory::mechanics::Axis;
using factory::mechanics::Point;
using factory::materials::Component;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
void refused(const char* actual, const char* expected, const char* message) {
    check(actual && std::string(actual) == expected, message);
}

factory::godot_world::terrain_surface::Surface bank() {
    factory::godot_world::terrain_surface::Surface terrain;
    terrain.axis = {-128.0, -2.8, -2.0, 128.0};
    for (int row = 0; row < 4; ++row)
        terrain.heights.insert(terrain.heights.end(), {-1.65, -1.65, -0.02, -0.02});
    return terrain;
}

void physical_admission() {
    factory::world::Profile profile;
    profile.water.emplace(std::array<factory::mechanics::Integer, 2>{-8, 0},
        factory::waterwheel::Sample{-20, -400, 0, 200});
    auto terrain = bank();
    const policy::Site site{profile, terrain};
    factory::world::State state;

    check(policy::machine_refusal(site, state, {0, 0, 0}, false) == nullptr,
          "A machine can sit on the emitted dry ground without an invented foundation.");
    refused(policy::machine_refusal(site, state, {-8, 0, 0}, false), "foundation_required",
          "A machine cannot float above the actual riverbed.");
    check(policy::wheel_refusal(site, {-8, 4, 0}, Axis::x, 3) == nullptr,
          "The immersed wheel clears its bank and finds both ground-connected supports.");
    refused(policy::wheel_refusal(site, {-7, 4, 0}, Axis::x, 3), "not_at_stream",
          "A neighboring dry wheel position cannot borrow another cell's water sample.");
    check(policy::transmission_refusal(site, state, {0, 4, 0}, Axis::x, false) == nullptr,
          "A raised shaft clears the emitted ground at the dry worksite.");
    refused(policy::collector_refusal(site, {4, 0, 0}), "not_at_seam",
          "A collector outside the named mineral seam is refused before placement.");
    check(policy::collector_refusal(site, {0, 0, 0}) == nullptr,
          "The actual mineral face remains eligible at its admitted height.");
    check(policy::component_refusal(site, state, Component::wooden_workbench, {0, 0, 0}) == nullptr,
          "A workshop component can sit on clear, supported ground.");
    check(policy::component_space_refusal(site, state, Component::wooden_workbench, {0, 0, 0}) == nullptr,
          "The empty World has no separate component occupancy refusal.");

    state.placed_components.emplace("existing", factory::world::PlacedComponent{
        Component::wooden_workbench, {0, 0, 0}, 1});
    refused(policy::component_space_refusal(site, state, Component::wooden_workbench, {0, 0, 0}),
          "occupied", "A second component cannot reuse an occupied physical volume.");
    const std::string current = "existing";
    check(policy::component_space_refusal(site, state, Component::wooden_workbench,
          {0, 0, 0}, &current) == nullptr,
          "Rechecking the same component identity does not collide with itself.");
    state.placed_components.clear();

    terrain.obstacles.emplace_back(factory::authority::Point{-3.6, -1.0, -0.4},
        factory::authority::Point{-3.0, 3.0, 0.4});
    refused(policy::wheel_refusal(site, {-8, 4, 0}, Axis::x, 3), "site_occupied",
          "A trusted solid crossing the wheel shell blocks the otherwise valid stream site.");
    terrain.obstacles.clear();
    terrain.obstacles.emplace_back(factory::authority::Point{-0.3, 1.8, -0.3},
        factory::authority::Point{0.3, 3.0, 0.3});
    refused(policy::transmission_refusal(site, state, {0, 4, 0}, Axis::x, false),
          "site_occupied", "A rock crossing the shaft axle is a physical clearance refusal.");
    terrain.obstacles.clear();

    check(policy::supplied_space_refusal(site, state) == nullptr,
          "An arrival with no supplied solids has no invented occupancy.");
    state.landing_pod = factory::world::LandingPod{"pod", {0, 0, 0}, 1};
    check(policy::supplied_space_refusal(site, state) == nullptr,
          "One supplied landing pod does not collide with its own parts.");
    state.placed_components.emplace("under-pod", factory::world::PlacedComponent{
        Component::wooden_workbench, {0, 0, 0}, 1});
    refused(policy::supplied_space_refusal(site, state), "occupied",
          "The supplied pod refuses a separately placed component in its occupied volume.");
    check(profile.water.size() == 1 && terrain.obstacles.empty(),
          "Read-only admission leaves World inputs and trusted terrain unchanged.");
}
}  // namespace

int main() {
    try {
        physical_admission();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"" << error.what() << "\"}\n";
        return 1;
    }
}
