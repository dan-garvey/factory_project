#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/material_projection.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
namespace projection = factory::godot_world::material_projection;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const Object& object, const char* key) {
    return std::get<T>(object.at(key).storage());
}

void check_profile(bool arrival, bool advanced) {
    const auto configuration = factory::godot_world::make_arrival_configuration(
        arrival, advanced, {"P", "Q"});
    check(configuration.has_value(), "Both workers need an authored native starting state.");
    auto world = factory::world::World::create(
        "material-projection", configuration->profile, configuration->seed);
    check(world != nullptr, "The native World must admit the authored starting state.");

    const auto before = world->snapshot();
    const auto fields = projection::tick_fields(configuration->profile, before);
    const auto after = world->snapshot();
    check(field<Integer>(fields, "revision") == before.revision &&
          after.revision == before.revision &&
          after.state.material.stock.source == before.state.material.stock.source &&
          !factory::values::typed_difference(Value(fields),
              Value(projection::tick_fields(configuration->profile, after))),
          "Reading a material view is repeatable and cannot advance or consume the World.");

    const auto& stock = field<Object>(fields, "stock");
    const auto& cargo = field<Object>(fields, "cargo");
    check(field<Integer>(stock, "source") == configuration->profile.initial_units &&
          field<Integer>(stock, "player") == 0 &&
          cargo.size() == 2 && field<Integer>(field<Object>(cargo, "P"), "raw") == 0 &&
          field<Integer>(field<Object>(cargo, "Q"), "products") == 0 &&
          field<Array>(fields, "dropped_material").empty() &&
          field<Object>(fields, "belt_spans").empty(),
          "Fresh stock, each worker's custody and empty transport remain native values.");
    if (!arrival) {
        check(!fields.contains("material_mass") && !fields.contains("hand_sources") &&
              !fields.contains("slide_phases") && !stock.contains("offcuts"),
              "The generic mechanics fixture retains its established lean wire shape.");
        return;
    }

    const auto& mass = field<Object>(fields, "material_mass");
    const auto& sources = field<Object>(fields, "hand_sources");
    const auto& ore = field<Object>(sources, "opening-copper");
    check(field<Integer>(mass, "initial_mass") == 4096 * 4 &&
          field<Integer>(mass, "accounted_mass") == field<Integer>(mass, "initial_mass") &&
          field<Integer>(mass, "stock_chunks") == 4096 &&
          field<Integer>(mass, "plates") == 0 &&
          field<Integer>(stock, "offcuts") == 0,
          "The copper opening presents the conserved finite material ledger before work starts.");
    check(field<std::string>(ore, "kind") == "ore_deposit" &&
          field<Integer>(ore, "remaining") == 4096 &&
          field<Integer>(field<Object>(sources, "tree-east-south"), "remaining") == 8 &&
          field<Object>(fields, "slide_phases").empty() &&
          field<Integer>(fields, "line_belt_raw") == 0,
          "Ore, timber and unstarted transport project from the same World snapshot.");
}
}  // namespace

int main() {
    try {
        check_profile(false, false);
        check_profile(true, false);
        check_profile(true, true);
        std::cout << "Material projection checks passed: " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Material projection check failed: " << error.what() << '\n';
        return 1;
    }
}
