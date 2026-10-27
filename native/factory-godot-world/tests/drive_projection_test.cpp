#include "native/factory-godot-world/src/drive_projection.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <variant>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
namespace drive = factory::godot_world::drive_projection;
namespace mechanics = factory::mechanics;
namespace stationary = factory::stationary;
namespace world = factory::world;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const Object& object, const char* key) {
    return std::get<T>(object.at(key).storage());
}

stationary::PlacedPart part(const char* id, stationary::Role role,
                           mechanics::Point center, mechanics::Axis axis,
                           Integer half_span = 0) {
    return {{id, role == stationary::Role::shaft ? mechanics::Kind::shaft : mechanics::Kind::hub,
             center, axis, 0, half_span}, 1, role};
}

void paired_links_and_loads() {
    world::State state;
    state.topology.material_links.push_back({{"ore", 2}, {"collector", 4}});
    state.topology.parts = {
        part("shaft", stationary::Role::shaft, {0, 0, 0}, mechanics::Axis::x, 4),
        part("left", stationary::Role::collector, {-4, 0, 0}, mechanics::Axis::x),
        part("right", stationary::Role::processor, {4, 0, 0}, mechanics::Axis::x),
        part("off-axis", stationary::Role::collector, {0, 0, 4}, mechanics::Axis::x),
        part("unpaired", stationary::Role::shaft, {20, 0, 0}, mechanics::Axis::x, 4),
        part("one-end", stationary::Role::collector, {24, 0, 0}, mechanics::Axis::x),
    };
    state.placed_components.emplace("weak-wood", world::PlacedComponent{
        factory::materials::Component::wooden_shaft, {0, 0, 0}, 3});
    const auto original = state;

    world::DrivePower power;
    power.mechanical.motion.emplace("shaft", mechanics::Motion{mechanics::MotionState::stalled, {3, 2}});
    power.mechanical.motion.emplace("left", mechanics::Motion{mechanics::MotionState::rotating, {-1, 2}});
    power.mechanical.motion.emplace("unloaded", mechanics::Motion{});
    power.load.emplace("shaft", world::NetworkLoad{8, 12, true, "weak-wood"});
    power.load.emplace("left", world::NetworkLoad{20, 4, false, ""});
    power.mechanical.engagements.push_back({"left", "shaft",
        mechanics::EngagementKind::coaxial_shaft, {1, 1}});

    const auto fields = drive::fields(state, power);
    check(state == original && fields.links.size() == 1 &&
          std::get<std::string>(std::get<Array>(fields.links[0].storage())[0].storage()) == "ore" &&
          std::get<std::string>(std::get<Array>(fields.links[0].storage())[1].storage()) == "collector",
          "Link readout keeps native endpoint order and does not edit the snapshot.");
    check(fields.drive_links.size() == 1 &&
          std::get<std::string>(std::get<Array>(fields.drive_links[0].storage())[0].storage()) == "left" &&
          std::get<std::string>(std::get<Array>(fields.drive_links[0].storage())[1].storage()) == "right",
          "Only the two aligned non-gear ends form the shaft's visible drive link.");
    check(fields.engagements.size() == 1 &&
          field<std::string>(std::get<Object>(fields.engagements[0].storage()), "a") == "left" &&
          field<Integer>(std::get<Object>(fields.engagements[0].storage()), "kind") ==
              static_cast<Integer>(mechanics::EngagementKind::coaxial_shaft),
          "Mechanical engagements keep the authoritative endpoint and kind.");

    const auto& stalled = field<Object>(fields.motion, "shaft");
    check(field<std::string>(stalled, "state") == "stalled" &&
          field<Integer>(stalled, "numerator") == 3 && field<Integer>(stalled, "denominator") == 2 &&
          field<double>(stalled, "capacity") == 8 && field<double>(stalled, "impact") == 12 &&
          field<bool>(stalled, "overloaded") &&
          field<std::string>(stalled, "limiting_kind") == "wooden_shaft" &&
          field<std::string>(stalled, "remedy") == "replace_with_copper_or_split_load",
          "An overloaded native shaft retains its rate, limiting material and repair guidance.");
    const auto& moving = field<Object>(fields.motion, "left");
    check(field<std::string>(moving, "state") == "rotating" &&
          field<Integer>(moving, "numerator") == -1 && !field<bool>(moving, "overloaded") &&
          !moving.contains("remedy") && !moving.contains("limiting_part"),
          "A loaded but healthy drive does not show overload repair guidance.");
    check(field<Object>(fields.motion, "unloaded").size() == 3,
          "Motion without a load record keeps the lean native wire shape.");

    power.load.at("shaft").limiting_part.clear();
    const auto no_limiter = drive::fields(state, power);
    const auto& shortfall = field<Object>(no_limiter.motion, "shaft");
    check(!shortfall.contains("limiting_kind") &&
          field<std::string>(shortfall, "remedy") == "add_power_or_reduce_load",
          "An overloaded network without a limiting part asks for power or less load.");
    power.load.at("shaft").limiting_part = "unknown-part";
    const auto unknown = drive::fields(state, power);
    check(!field<Object>(unknown.motion, "shaft").contains("limiting_kind"),
          "A missing material identity is never guessed from a load diagnostic.");
}
}  // namespace

int main() {
    try {
        paired_links_and_loads();
        std::cout << "DRIVE_PROJECTION_PASS " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Drive projection check failed: " << error.what() << '\n';
        return 1;
    }
}
