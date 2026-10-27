#include "factory/terrain_surface.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
namespace terrain = factory::godot_world::terrain_surface;
using Value = factory::values::Value;
using Array = Value::Array;
using Object = Value::Object;
using Integer = Value::Integer;
using Point = factory::authority::Point;

int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
void near(double actual, double expected, const char* message) {
    check(std::abs(actual - expected) < 1e-9, message);
}
Value point(double x, double y, double z) {
    return Value(Array{Value(x), Value(y), Value(z)});
}
Value box(const Point& low, const Point& high) {
    return Value(Array{point(low[0], low[1], low[2]), point(high[0], high[1], high[2])});
}
Object site() {
    // Both emitted triangles lie on y = x. The first obstacle is the trusted
    // ore hull; the second is a distinct named tree occupying the footprint.
    return {{"axis", Value(Array{Value(0.0), Value(2.0)})},
            {"heights", Value(Array{Value(0.0), Value(2.0), Value(0.0), Value(2.0)})},
            {"obstacles", Value(Array{
                box({-1.0, 0.3, -0.2}, {-0.6, 0.7, 1.2}),
                box({0.9, 0.0, 0.9}, {1.1, 1.0, 1.1})})},
            {"source_obstacle", Value(Integer{0})},
            {"tree_obstacles", Value(Object{{"tree", Value(Integer{1})}})}};
}

void samples_and_identities() {
    factory::world::Profile profile;
    profile.material.timber_sites.emplace("tree", factory::materials::TimberSite{{12, 0, 12}, 8});
    check(!terrain::Surface{}.range(1, 1), "An unbound site offers no invented ground sample.");
    const auto parsed = terrain::parse(site(), profile);
    if (!parsed.binding) throw std::runtime_error(std::string("Trusted surface refused: ") + parsed.refusal);
    check(parsed.binding.has_value() && !parsed.refusal && !parsed.binding->replace_world,
          "A valid trusted surface binds without replacing an unchanged World profile.");
    const auto& surface = parsed.binding->surface;
    check(surface.bound() && surface.source_obstacle == 0 && surface.tree_obstacles.at(1) == "tree",
          "The ore and tree obstacles retain their distinct trusted identities.");
    const auto sample = surface.range(1.0, 1.0, 0.25, 0.25);
    check(sample.has_value(), "The footprint stays inside the emitted grid.");
    near(sample->first, 0.75, "The low height follows the clipped emitted triangles.");
    near(sample->second, 1.25, "The high height follows the full footprint, not one center point.");
    check(!surface.range(0.1, 1.0, 0.25, 0.25),
          "A footprint extending beyond the emitted grid has no terrain authority.");
    check(surface.blocked({0.95, 0.2, 0.95}, {1.05, 0.8, 1.05}),
          "A placed volume overlapping a real named tree is blocked.");
    check(!surface.blocked({0.95, 0.2, 0.95}, {1.05, 0.8, 1.05}, 1),
          "Only the explicitly ignored obstacle index is omitted from a query.");
    check(surface.blocked({0.8, 0.2, 0.8}, {0.9, 0.8, 0.9}) == false,
          "Touching an obstacle face is not overlapping its solid volume.");

    auto malformed = site();
    malformed["source_obstacle"] = Value(Integer{2});
    const auto wrong_source = terrain::parse(malformed, profile);
    check(!wrong_source.binding && std::string(wrong_source.refusal) == "invalid_terrain",
          "An out-of-range ore obstacle is refused before binding anything.");
    malformed = site();
    malformed["tree_obstacles"] = Value(Object{{"unknown-tree", Value(Integer{1})}});
    const auto wrong_tree = terrain::parse(malformed, profile);
    check(!wrong_tree.binding && std::string(wrong_tree.refusal) == "invalid_terrain",
          "A tree obstacle cannot name a source absent from the trusted profile.");
    malformed = site();
    malformed["axis"] = Value(Array{Value(Integer{0}), Value(2.0)});
    const auto wrong_axis = terrain::parse(malformed, profile);
    check(!wrong_axis.binding && std::string(wrong_axis.refusal) == "invalid_terrain",
          "Trusted grid coordinates still require finite floating-point vertices.");

    malformed = site();
    malformed["water"] = Value(Array{Value(Array{Value(Integer{0})})});
    const auto wrong_water = terrain::parse(malformed, profile);
    check(!wrong_water.binding && std::string(wrong_water.refusal) == "invalid_water" && profile.water.empty(),
          "Malformed water cannot partially bind a valid ground surface or mutate the World profile.");
    malformed["water"] = Value(Array{Value(Array{Value(Integer{0}), Value(Integer{0}),
        Value(Integer{0}), Value(Integer{0}), Value(Integer{0}), Value(Integer{0})})});
    const auto with_water = terrain::parse(malformed, profile);
    check(with_water.binding && with_water.binding->replace_world &&
          with_water.binding->profile.water.size() == 1 && profile.water.empty(),
          "A valid trusted water sample requests one atomic World/profile replacement.");
}
}  // namespace

int main() {
    try {
        samples_and_identities();
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"" << error.what() << "\"}\n";
        return 1;
    }
}
