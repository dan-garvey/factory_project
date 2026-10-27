#include "native/factory-godot-world/src/physical_geometry.hpp"
#include "factory/site_geometry_contract.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>

namespace {
namespace geometry = factory::godot_world::physical_geometry;
namespace site = factory::godot_world::site_geometry;
using factory::materials::Component;
using factory::mechanics::Axis;
using factory::mechanics::Kind;
using factory::mechanics::Part;
using factory::mechanics::Point;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
void near(double actual, double expected, const char* message) {
    check(std::abs(actual - expected) < 1e-9, message);
}

void face_contact_and_actor() {
    const geometry::Bounds fixed{{0, 0, 0}, {1, 1, 1}};
    check(!geometry::overlap(fixed, {{2, 0, 0}, {1, 1, 1}}),
          "Touching grid faces do not occupy the same volume.");
    check(geometry::overlap(fixed, {{1.999, 0, 0}, {1, 1, 1}}),
          "Actual penetration still blocks placement.");
    check(geometry::capsule_intersects({0, 0, 0}, {{0, 0.5, 0}, {0.1, 0.1, 0.1}}),
          "A worker body through a part blocks placement.");
    check(!geometry::capsule_intersects({1, 0, 0}, {{0, 0.5, 0}, {0.1, 0.1, 0.1}}),
          "A worker clear of the part does not block it.");
}

void support_and_site_shapes() {
    int terrain_calls = 0;
    const auto terrain = [&terrain_calls](double, double, double, double) {
        ++terrain_calls;
        return std::optional<std::pair<double, double>>{{0.0, 0.1}};
    };
    const auto feet = geometry::wheel_support_bounds({0, 4, 0}, Axis::x, terrain);
    check(feet && terrain_calls == 2, "Both wheel feet sample the actual terrain footprint.");
    near((*feet)[0].center[0], -0.5, "The first bearing stands outside the west disc face.");
    near((*feet)[1].center[0], 0.5, "The second bearing stands outside the east disc face.");
    near((*feet)[0].center[1] - (*feet)[0].half[1], -0.04,
         "A wheel foot seats slightly into the lowest terrain triangle.");
    check(!geometry::wheel_support_bounds({0, 4, 0}, Axis::y, terrain),
          "Vertical wheel axles have no admitted foot geometry.");
    check(!geometry::wheel_support_bounds({0, 4, 0}, Axis::x,
        [](double, double, double, double) {
            return std::optional<std::pair<double, double>>{{0.0, 2.5}};
        }), "Terrain above the wheel axle refuses the supports.");
    check(!geometry::overlaps_supports(*feet, {{0, 0, 0}, {0.1, 0.1, 0.1}}),
          "The wheel center remains clear of its outboard feet.");
    const auto floor = geometry::foundation_bounds({{4, 4, 8}, 1});
    near(floor.center[0], site::pitch, "The foundation uses the site pitch.");
    near(floor.center[1] - floor.half[1], site::pitch - site::foundation_depth,
         "The foundation reaches its authored lower face.");
    check(geometry::collector_intake_bounds({0, 0, 0}).has_value(),
          "The opening mineral cell has a physical pickup shoe.");
    check(geometry::collector_external_bounds({0, 4, 4}).size() == 9,
          "A raised collector includes its intake and carrier solids.");
    check(!geometry::collector_intake_bounds({4, 0, 0}),
          "A collector away from the fixed deposit has no invented intake.");
}

void component_fit_and_belts() {
    check(geometry::slide_head_fitting(Component::flat_head, {0, 0, 0},
                                      Component::wooden_slide, {0, 1, 0}),
          "The fitted slide and flat head may share their conservative boxes.");
    check(!geometry::slide_head_fitting(Component::flat_head, {0, 0, 0},
                                       Component::wooden_slide, {4, 1, 0}),
          "A displaced slide cannot borrow the fitted-head exception.");
    check(geometry::shaft_meets_component_cog(Component::wooden_cog, {0, 0, 0},
                                             {2, 0, 0}, Axis::x),
          "The fitted shaft end can enter its component cog hub.");
    check(!geometry::shaft_meets_component_cog(Component::wooden_cog, {0, 0, 0},
                                              {2, 0, 0}, Axis::z),
          "A perpendicular shaft cannot use the fitted-cog exception.");
    const Part lower{"lower", Kind::shaft, {0, 0, 0}, Axis::x, 0, 2};
    const Part upper{"upper", Kind::shaft, {0, 4, 4}, Axis::x, 0, 2};
    check(geometry::belt_bounds(lower, upper).size() == 16,
          "The 45-degree belt uses narrow sections across its complete loop.");
    const auto midpoint = geometry::Bounds{{0, site::anchor_height + 2 * site::height_step,
        2 * site::height_step}, {0.1, 0.1, 0.1}};
    check(geometry::belt_intersects(lower, upper, midpoint),
          "A part in the inclined loop blocks placement.");
    check(!geometry::belt_intersects(lower, upper,
        {{0, site::anchor_height, 2 * site::height_step}, {0.1, 0.1, 0.1}}),
          "The empty space below an incline remains usable.");
    check(geometry::transmission_intersects(
        {{0, site::anchor_height, 0}, {0.1, 0.1, 0.1}}, Point{0, 0, 0}, Axis::x, false),
        "A shaft axle blocks a part through its bearing center.");
}
}  // namespace

int main() {
    try {
        face_contact_and_actor();
        support_and_site_shapes();
        component_fit_and_belts();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"" << error.what() << "\"}\n";
        return 1;
    }
}
