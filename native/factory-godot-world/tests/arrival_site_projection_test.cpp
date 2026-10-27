#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/arrival_site_projection.hpp"
#include "native/factory-godot-world/src/component_geometry.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <variant>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
namespace site = factory::godot_world::arrival_site_projection;
namespace geometry = factory::godot_world::component_geometry;
namespace materials = factory::materials;
namespace world = factory::world;

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

void native_arrival_readout() {
    const auto arrival = factory::godot_world::make_arrival_configuration(true, false, {"P", "Q"});
    check(arrival.has_value(), "The finite two-worker opening must be authored.");
    auto native = world::World::create("arrival-site-reader", arrival->profile, arrival->seed);
    check(native != nullptr, "World must admit the authored arrival before it is projected.");
    const auto initial = native->snapshot();
    const auto initial_fields = site::fields(arrival->profile, initial.state,
        world::drive_power(arrival->profile, initial.state));
    check(initial_fields.size() == 6 &&
          field<Object>(initial_fields, "supplied_hardware_boxes").size() == 20 &&
          field<bool>(entry(initial_fields, "landing_pod"), "hub_ready") &&
          field<bool>(entry(initial_fields, "fabrication_hub"), "installed") &&
          field<Array>(initial_fields, "fabrication_benches").empty() &&
          field<Object>(initial_fields, "crank_items").empty() &&
          field<Object>(initial_fields, "placed_components").empty(),
          "One fresh native arrival yields the issued pod and installed hub without invented buildables.");
    const auto generic = factory::godot_world::make_arrival_configuration(false, false, {"P", "Q"});
    check(generic.has_value() &&
          site::fields(generic->profile, generic->seed, {}).empty(),
          "A generic mechanics site does not acquire arrival-only fields.");

    auto state = initial.state;
    state.fabrication_hub->holder = "P";
    state.crank_items.emplace("crank-7", world::HandCrank{"crank-7", 7, "P"});
    state.placed_components.emplace("bench-1", world::PlacedComponent{
        materials::Component::wooden_workbench, {0, 4, 0}, 3});
    state.placed_components.emplace("slide-2", world::PlacedComponent{
        materials::Component::wooden_slide, {4, 4, 0}, 4});
    state.placed_components.emplace("shaft-3", world::PlacedComponent{
        materials::Component::wooden_shaft, {8, 4, 0}, 5});
    const auto original = state;
    world::DrivePower power;
    power.crank_axes.emplace("shaft-3", factory::mechanics::Axis::x);
    const auto projected = site::fields(arrival->profile, state, power);
    check(state == original && projected.size() == 6 &&
          field<Object>(projected, "supplied_hardware_boxes").size() == 10 &&
          !field<bool>(entry(projected, "landing_pod"), "hub_ready") &&
          !field<bool>(entry(projected, "fabrication_hub"), "installed") &&
          field<std::string>(entry(projected, "fabrication_hub"), "holder") == "P",
          "Carrying the issued hub changes only the readout and removes its deployed solids.");
    const auto& benches = field<Array>(projected, "fabrication_benches");
    check(benches.size() == 1 &&
          field<std::string>(std::get<Object>(benches.front().storage()), "id") == "bench-1" &&
          field<Integer>(std::get<Object>(benches.front().storage()), "generation") == 3,
          "A placed bench keeps its native identity and generation in the workshop view.");
    const auto& crank = entry(field<Object>(projected, "crank_items"), "crank-7");
    check(field<std::string>(crank, "holder") == "P" &&
          field<std::string>(crank, "attached_to").empty() &&
          field<Array>(crank, "port").empty() && field<Array>(crank, "face").empty(),
          "A carried crank remains the same native item without an invented fitting.");
    const auto& parts = field<Object>(projected, "placed_components");
    const auto& slide = entry(parts, "slide-2");
    const auto& shaft = entry(parts, "shaft-3");
    check(parts.size() == 3 && field<Array>(slide, "input_ports").size() == 2 &&
          field<Array>(shaft, "input_ports").size() == 1 &&
          field<Integer>(shaft, "crank_axis") ==
              static_cast<Integer>(factory::mechanics::Axis::x),
          "Slide and shaft ports and the driven axis follow the native component and power facts.");
    const auto actual = geometry::component_bounds(arrival->profile,
        materials::Component::wooden_slide, {4, 4, 0});
    const auto& occupied = entry(slide, "occupied");
    const Array center{Value(actual.center[0]), Value(actual.center[1]), Value(actual.center[2])};
    const Array half{Value(actual.half[0]), Value(actual.half[1]), Value(actual.half[2])};
    check(!factory::values::typed_difference(Value(center), Value(field<Array>(occupied, "center"))) &&
          !factory::values::typed_difference(Value(half), Value(field<Array>(occupied, "half"))),
          "The projected occupied volume is exactly the same geometry used for Host placement admission.");
    check(!factory::values::typed_difference(Value(projected),
              Value(site::fields(arrival->profile, state, power))) &&
          native->snapshot().state == initial.state && native->snapshot().revision == initial.revision,
          "Repeated readout cannot change the original World or maintain a second worksite state.");
}
}  // namespace

int main() {
    try {
        native_arrival_readout();
        std::cout << "ARRIVAL_SITE_PROJECTION_PASS " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Arrival site projection check failed: " << error.what() << '\n';
        return 1;
    }
}
