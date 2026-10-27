#include "factory/physical_support.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
namespace support = factory::godot_world::physical_support;
using factory::authority::Point;
using factory::mechanics::Axis;
using factory::mechanics::Kind;
using factory::stationary::Role;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
void near(double actual, double expected, const char* message) {
    check(std::abs(actual - expected) < 1e-9, message);
}

factory::world::State one_shaft() {
    factory::world::State state;
    factory::stationary::PlacedPart shaft;
    shaft.geometry = {"shaft-a", Kind::shaft, {0, 4, 0}, Axis::x, 0, 2};
    shaft.generation = 1;
    shaft.role = Role::shaft;
    state.topology.parts.push_back(shaft);
    return state;
}

void route_identity_and_refusal() {
    const factory::world::Profile profile;
    const support::TerrainObstacles empty;
    const support::Site flat{profile, empty,
        [](double, double, double, double) {
            return std::optional<std::pair<double, double>>{{0.0, 0.0}};
        },
        [](const Point&, const Point&) { return false; }};
    const auto before = one_shaft();
    const auto first = support::layout(flat, before);
    check(first.size() == 1 && first.contains("shaft-a") && first.at("shaft-a").route == 0,
          "A shaft chooses its first clear physical post route.");
    near(first.at("shaft-a").foot[0], 0.55,
         "The bearing foot stands beyond the end of the horizontal shaft.");
    near(first.at("shaft-a").foot[1], 0.0,
         "The post seats on the confirmed flat terrain.");
    check(first.at("shaft-a").boxes.size() == 4,
          "The confirmed post includes its column, bearing and connecting arm.");
    const support::Routes pinned{{"shaft-a", 1}};
    const auto retained = support::layout(flat, before, &pinned);
    check(retained.size() == 1 && retained.at("shaft-a").route == 1,
          "A saved route remains pinned even when an earlier route is free.");
    near(retained.at("shaft-a").foot[2], 0.4,
         "The second route moves the post while keeping the bearing coaxial.");
    near(retained.at("shaft-a").bearing[2], 0.0,
         "A route choice does not move the shaft bearing.");
    check(support::change_refusal(flat, before, before, pinned,
        [](const Point&, const Point&) { return true; }) == nullptr,
        "An unchanged support does not refuse because a worker later stands nearby.");

    auto after = before;
    after.placed_components.emplace("new-part", factory::world::PlacedComponent{
        factory::materials::Component::wooden_shaft, {1, 0, 1}, 1});
    check(!support::layout(flat, after, &pinned).contains("shaft-a") &&
          support::layout(flat, after).contains("shaft-a"),
          "The new component blocks only the saved post route; a new free route exists.");
    const char* held = support::change_refusal(flat, before, after, pinned,
        [](const Point&, const Point&) { return false; });
    check(held && std::string(held) == "stand_in_use",
          "A neighboring edit cannot silently relocate the built support.");

    const factory::world::State vacant;
    const char* actor = support::change_refusal(flat, vacant, before, {},
        [](const Point&, const Point&) { return true; });
    check(actor && std::string(actor) == "actor_occupied",
          "A new physical support refuses a worker inside any of its boxes.");

    support::TerrainObstacles raised{{Point{0.4, -0.1, -0.1}, Point{0.7, 3.0, 0.1}}};
    const support::Site blocked{profile, raised, flat.terrain_range, flat.site_blocked};
    const auto alternative = support::layout(blocked, before);
    check(alternative.contains("shaft-a") && alternative.at("shaft-a").route == 1,
          "A real obstacle beneath the first post selects the next clear route.");
    const support::Site no_terrain{profile, empty,
        [](double, double, double, double) {
            return std::optional<std::pair<double, double>>{};
        }, flat.site_blocked};
    check(support::layout(no_terrain, before).empty(),
          "No support is invented without a terrain sample.");
    const char* missing = support::change_refusal(no_terrain, vacant, before, {},
        [](const Point&, const Point&) { return false; });
    check(missing && std::string(missing) == "support_required",
          "A machine with no physical seat is refused before World receives the edit.");
    check(before.topology.parts.size() == 1 && before.placed_components.empty(),
          "Layout and refusal reads never mutate the World state supplied by Host.");
}
}  // namespace

int main() {
    try {
        route_identity_and_refusal();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"" << error.what() << "\"}\n";
        return 1;
    }
}
