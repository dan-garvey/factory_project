#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/topology_projection.hpp"

#include <array>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <variant>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
namespace mechanics = factory::mechanics;
namespace stationary = factory::stationary;
namespace world = factory::world;
namespace projection = factory::godot_world::topology_projection;
namespace supports = factory::godot_world::physical_support;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const Object& object, const char* key) {
    return std::get<T>(object.at(key).storage());
}

const Object& entry(const Object& records, const char* key) {
    return std::get<Object>(records.at(key).storage());
}

stationary::PlacedPart part(const char* id, stationary::Role role,
        mechanics::Point center, mechanics::Axis axis) {
    return {{id, role == stationary::Role::shaft ? mechanics::Kind::shaft : mechanics::Kind::hub,
        center, axis, 0, role == stationary::Role::shaft ? 2 : 0}, 3, role};
}

void native_topology_readout() {
    const auto arrival = factory::godot_world::make_arrival_configuration(true, false, {"P", "Q"});
    check(arrival.has_value(), "The two-worker arrival profile must exist.");
    auto native = world::World::create("topology-reader", arrival->profile, arrival->seed);
    check(native != nullptr, "The native World must admit its authored arrival state.");
    const auto initial = native->snapshot();
    const auto plain = projection::fields(initial.state, {}, {});
    check(plain.entities.empty() && plain.transmission_parts.empty() &&
          plain.foundations.size() == initial.state.foundations.size() &&
          !plain.foundations.empty(),
          "Fresh arrival exposes its native deck but invents no placed machine or shaft.");
    const auto& [floor_id, floor] = *initial.state.foundations.begin();
    const auto& projected_floor = entry(plain.foundations, floor_id.c_str());
    check(field<Integer>(projected_floor, "generation") == floor.generation &&
          field<Integer>(projected_floor, "level") == floor.center[1] &&
          !factory::values::typed_difference(Value(field<Array>(projected_floor, "cell")),
              Value(Array{Value(floor.center[0] / 4), Value(floor.center[2] / 4)})),
          "Foundation identity, level, and cell derive from the World record.");

    auto state = initial.state;
    state.topology.parts.push_back(part("collector-3", stationary::Role::collector,
        {4, 4, 8}, mechanics::Axis::x));
    state.topology.parts.push_back(part("wheel-4", stationary::Role::waterwheel,
        {0, 0, 0}, mechanics::Axis::z));
    state.topology.parts.push_back(part("shaft-5", stationary::Role::shaft,
        {8, 4, 0}, mechanics::Axis::x));
    const auto original = state;
    supports::TransmissionSupport shaft_support{{3.2, 0.0, 0.1}, {3.3, 2.0, 0.1},
        {{{3.2, 1.0, 0.1}, {0.17, 1.0, 0.17}}}, 2};
    const std::map<std::string, supports::TransmissionSupport> stands{{"shaft-5", shaft_support}};
    projection::WheelSupports wheel_feet;
    wheel_feet.emplace("wheel-4", std::array<factory::godot_world::arrival_geometry::Bounds, 2>{
        factory::godot_world::arrival_geometry::Bounds{{-0.5, 0.5, 0.0}, {0.18, 0.5, 0.43}},
        factory::godot_world::arrival_geometry::Bounds{{0.5, 0.5, 0.0}, {0.18, 0.5, 0.43}}});
    const auto output = projection::fields(state, stands, wheel_feet);
    check(state == original && output.entities.size() == 2 &&
          output.transmission_parts.size() == 1 &&
          output.foundations.size() == plain.foundations.size(),
          "Readout classifies native machines and fixed transmission without changing World state.");
    const auto& collector = entry(output.entities, "collector-3");
    const auto& wheel = entry(output.entities, "wheel-4");
    check(field<std::string>(collector, "kind") == "collector" &&
          field<Integer>(collector, "generation") == 3 &&
          !factory::values::typed_difference(Value(field<Array>(collector, "cell")),
              Value(Array{Value(Integer{1}), Value(Integer{2})})) &&
          field<Integer>(collector, "level") == 4 &&
          field<Integer>(wheel, "tiles") == 3 && !wheel.contains("level") &&
          field<Array>(wheel, "supports").size() == 2,
          "Machine cells, elevation, wheel size and confirmed feet preserve their native facts.");
    const auto& shaft = entry(output.transmission_parts, "shaft-5");
    const auto& stand = field<Object>(shaft, "support");
    check(field<std::string>(shaft, "kind") == "shaft" &&
          field<Integer>(shaft, "half_span") == 2 &&
          field<Array>(stand, "boxes").size() == 1 &&
          !factory::values::typed_difference(Value(field<Array>(stand, "foot")),
              Value(Array{Value(3.2), Value(0.0), Value(0.1)})) &&
          !factory::values::typed_difference(Value(field<Array>(stand, "bearing")),
              Value(Array{Value(3.3), Value(2.0), Value(0.1)})),
          "The exact Host-confirmed stand remains attached to the native shaft identity.");
    const auto without_supports = projection::fields(state, {}, {});
    check(!entry(without_supports.entities, "wheel-4").contains("supports") &&
          !entry(without_supports.transmission_parts, "shaft-5").contains("support"),
          "The reader never invents a physical support when Host cannot confirm one.");
    check(!factory::values::typed_difference(Value(output.entities),
              Value(projection::fields(state, stands, wheel_feet).entities)) &&
          native->snapshot().state == initial.state && native->snapshot().revision == initial.revision,
          "Repeated projection is deterministic and leaves the owning World unchanged.");
}
}  // namespace

int main() {
    try {
        native_topology_readout();
        std::cout << "TOPOLOGY_PROJECTION_PASS " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Topology projection check failed: " << error.what() << '\n';
        return 1;
    }
}
