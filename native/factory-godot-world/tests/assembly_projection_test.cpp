#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/assembly_projection.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <variant>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
namespace projection = factory::godot_world::assembly_projection;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const Object& object, const char* key) {
    return std::get<T>(object.at(key).storage());
}

void arrival_and_generic_views() {
    const auto arrival = factory::godot_world::make_arrival_configuration(true, false, {"P", "Q"});
    check(arrival.has_value(), "The two-worker arrival configuration must be authored.");
    auto world = factory::world::World::create("assembly-projection", arrival->profile, arrival->seed);
    check(world != nullptr, "The native World must admit the arrival state.");
    const auto before = world->snapshot();
    const auto power = factory::world::drive_power(arrival->profile, before.state);
    const auto fields = projection::fields(arrival->profile, before.state, power);
    check(fields.size() == 6 &&
          fields.contains("collector_assemblies") && fields.contains("press_assemblies") &&
          fields.contains("guided_press_assemblies") && fields.contains("sliding_press_assemblies") &&
          fields.contains("broad_press_assemblies") && fields.contains("broad_shear_assemblies"),
          "The arrival view publishes all six collector and press readouts together.");
    const auto& collectors = field<Array>(fields, "collector_assemblies");
    check(collectors.size() == arrival->profile.collector_faces.size() && !collectors.empty() &&
          field<std::string>(std::get<Object>(collectors.front().storage()), "status") == "missing_frame" &&
          field<Array>(fields, "press_assemblies").empty() &&
          field<Array>(fields, "sliding_press_assemblies").empty() &&
          field<Array>(fields, "broad_press_assemblies").empty(),
          "A fresh finite site exposes missing collector construction without invented presses.");
    const auto repeated = projection::fields(arrival->profile, before.state, power);
    check(!factory::values::typed_difference(Value(fields), Value(repeated)) &&
          world->snapshot().state == before.state && world->snapshot().revision == before.revision,
          "Reading assemblies twice is deterministic and cannot alter native state or revision.");

    const auto generic = factory::godot_world::make_arrival_configuration(false, false, {"P", "Q"});
    check(generic.has_value(), "The generic mechanics fixture must be authored.");
    auto generic_world = factory::world::World::create("generic-assembly-projection",
        generic->profile, generic->seed);
    check(generic_world != nullptr, "The native World must admit the generic fixture.");
    const auto generic_before = generic_world->snapshot();
    check(projection::fields(generic->profile, generic_before.state,
              factory::world::drive_power(generic->profile, generic_before.state)).empty() &&
          generic_world->snapshot().state == generic_before.state,
          "The generic mechanics fixture keeps its established projection without arrival assemblies.");
}
}  // namespace

int main() {
    try {
        arrival_and_generic_views();
        std::cout << "ASSEMBLY_PROJECTION_PASS " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Assembly projection check failed: " << error.what() << '\n';
        return 1;
    }
}
