#include "native/factory-godot-world/src/arrival_configuration.hpp"
#include "native/factory-godot-world/src/build_catalog_projection.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {
using Value = factory::values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
namespace catalog = factory::godot_world::build_catalog_projection;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class T> const T& field(const Object& object, const char* key) {
    return std::get<T>(object.at(key).storage());
}

const Object& offered_part(const Array& entries, const std::string& name) {
    for (const auto& entry : entries) {
        const auto& candidate = std::get<Object>(entry.storage());
        if (field<std::string>(candidate, "kind") == name) return candidate;
    }
    throw std::runtime_error("Expected offered part is missing: " + name);
}

void check_profile(bool arrival, bool advanced) {
    const auto authored = factory::godot_world::make_arrival_configuration(
        arrival, advanced, {"P", "Q"});
    check(authored.has_value(), "The two-worker starting catalog must be authored.");
    auto world = factory::world::World::create("catalog-projection", authored->profile, authored->seed);
    check(world != nullptr, "The native World must admit the authored starting catalog.");

    const auto before = world->snapshot();
    const auto projected = catalog::fields(authored->profile, before);
    const auto after = world->snapshot();
    check(after.revision == before.revision &&
          after.state.material.stock.source == before.state.material.stock.source &&
          !factory::values::typed_difference(Value(projected),
              Value(catalog::fields(authored->profile, after))),
          "Reading offered parts and recipes cannot mutate the native World.");
    check(!projected.contains("cargo") && !projected.contains("manual_cuts"),
          "The build catalog does not duplicate the native tick and custody readouts.");

    const auto& inventories = field<Object>(projected, "inventories");
    const auto& kits = field<Object>(projected, "part_kits");
    const auto& specifications = field<Object>(projected, "part_specifications");
    const auto& player = field<Object>(kits, "P");
    const auto& second = field<Object>(kits, "Q");
    check(field<Integer>(inventories, "P") == 0 && field<Integer>(inventories, "Q") == 0 &&
          field<Integer>(second, "collector") == 0 && field<Integer>(second, "foundation") == 0 &&
          !factory::values::typed_difference(Value(player), Value(field<Object>(projected, "parts"))),
          "The two workers retain separate product and machine custody; the P shortcut matches P's kit.");

    if (!arrival) {
        check(field<Integer>(player, "collector") == 1 &&
              field<Integer>(player, "wheel") == 1 && field<Integer>(player, "foundation") == 24 &&
              field<Array>(specifications, "P").size() == 10 &&
              field<Integer>(offered_part(field<Array>(specifications, "P"), "collector"), "count") == 1,
              "The ordinary mechanics fixture still offers its finite machine kit.");
        check(!projected.contains("component_recipes") &&
              !projected.contains("part_recipes") &&
              !projected.contains("first_plate_unlock"),
              "Arrival-only copper recipes do not appear in the generic mechanics fixture.");
        return;
    }

    check(field<Integer>(player, "collector") == 0 &&
          field<Integer>(player, "foundation") == 15 &&
          field<Array>(specifications, "P").size() == 7 &&
          field<Integer>(offered_part(field<Array>(specifications, "P"), "wheel"), "count") == 0,
          "The Chapter 1 arrival retains its issued deck and offers no advanced machine kit.");
    const auto& recipes = field<Object>(projected, "component_recipes");
    check(recipes.size() == 20 &&
          field<Integer>(field<Object>(recipes, "copper_cog"), "copper") == 2 &&
          field<Integer>(field<Object>(recipes, "flat_head"), "copper") == 1 &&
          field<Integer>(field<Object>(recipes, "wooden_workbench"), "timber") == 4 &&
          field<Integer>(field<Object>(projected, "foundation_recipe"), "copper") == 0 &&
          field<Integer>(projected, "component_capacity") == 0,
          "The copper, workbench and foundation costs retain their exact native recipe values.");
    check(field<Array>(projected, "part_recipes").size() == 7 &&
          field<Array>(projected, "workshop_completed_actors").empty() &&
          field<bool>(projected, "first_plate_unlock") == !advanced,
          "Normal and advanced starts differ only in their authored first-plate milestone flag.");
}
}  // namespace

int main() {
    try {
        check_profile(false, false);
        check_profile(true, false);
        check_profile(true, true);
        check(std::string(catalog::kind(factory::stationary::Role::waterwheel)) == "wheel",
              "The existing waterwheel wire name remains wheel in kits and machine records.");
        std::cout << "Build catalog projection checks passed: " << checks << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Build catalog projection check failed: " << error.what() << '\n';
        return 1;
    }
}
