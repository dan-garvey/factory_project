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
    state.placed_components.emplace("loaded-slide", world::PlacedComponent{
        factory::materials::Component::slide, {0, 0, 0}, 3});
    const auto original = state;

    world::DrivePower power;
    power.mechanical.motion.emplace("shaft", mechanics::Motion{mechanics::MotionState::stalled, {3, 2}});
    power.mechanical.motion.emplace("left", mechanics::Motion{mechanics::MotionState::rotating, {-1, 2}});
    power.mechanical.motion.emplace("unloaded", mechanics::Motion{});
    power.load.emplace("shaft", world::NetworkLoad{24, 32, true, "loaded-slide"});
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
          field<double>(stalled, "capacity") == 24 && field<double>(stalled, "impact") == 32 &&
          field<bool>(stalled, "overloaded") &&
          field<std::string>(stalled, "limiting_kind") == "slide" &&
          field<std::string>(stalled, "remedy") == "split_load_or_reduce_speed",
          "An overloaded native shaft retains its rate, limiting component and repair guidance.");
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

void shared_ports_describe_connections_and_crank_limits() {
    world::State state;
    state.topology.parts = {
        {{"gearbox", mechanics::Kind::gearbox, {0, 0, 0}, mechanics::Axis::z},
            1, stationary::Role::vertical_gearbox},
        {{"vertical", mechanics::Kind::shaft, {0, 4, 0}, mechanics::Axis::y, 0, 2},
            2, stationary::Role::shaft}};
    state.issued_entities = {{"gearbox", 1}, {"vertical", 2}};
    auto power = world::drive_power(state.topology);
    const auto projected = drive::fields(state, power);
    const auto& box = field<Object>(projected.rotary_ports, "gearbox");
    check(field<Integer>(box, "generation") == 1 && field<Array>(box, "ports").size() == 4,
        "One gearbox declaration exposes four real shaft faces under its issued identity.");
    int horizontal = 0, occupied = 0;
    for (const auto& value : field<Array>(box, "ports")) {
        const auto& port = std::get<Object>(value.storage());
        horizontal += field<bool>(port, "hand_crank");
        occupied += !field<bool>(port, "open");
    }
    check(horizontal == 2 && occupied == 1,
        "Horizontal faces accept cranks, while the connected vertical shaft occupies its real face.");
    const auto& vertical = field<Object>(projected.rotary_ports, "vertical");
    for (const auto& value : field<Array>(vertical, "ports"))
        check(!field<bool>(std::get<Object>(value.storage()), "hand_crank"),
            "A vertical shaft remains connectable without offering a vertical crank.");
    state.topology.sources.push_back({"wheel", {1, 1}});
    state.topology.parts.push_back({{"wheel", mechanics::Kind::hub, {-4, 0, 0}, mechanics::Axis::x},
        1, stationary::Role::waterwheel});
    state.topology.drive_enabled = true;
    power = world::drive_power(state.topology);
    check(!field<bool>(field<Object>(drive::fields(state, power).rotary_ports,
            "gearbox"), "crank_source_available"),
        "An engaged source blocks a manual source through the shared network.");
    state.topology.drive_enabled = false;
    check(field<bool>(field<Object>(drive::fields(state, power).rotary_ports,
            "gearbox"), "crank_source_available"),
        "Disabling the source makes the same physical ports available for manual power.");
}
}  // namespace

int main() {
    try {
        paired_links_and_loads();
        shared_ports_describe_connections_and_crank_limits();
        std::cout << "DRIVE_PROJECTION_PASS " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Drive projection check failed: " << error.what() << '\n';
        return 1;
    }
}
