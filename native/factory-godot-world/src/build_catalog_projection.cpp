#include "build_catalog_projection.hpp"

#include <limits>
#include <set>
#include <stdexcept>
#include <utility>

namespace factory::godot_world::build_catalog_projection {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;

Value kit_value(const stationary::Kit& kit) {
    Object counts{{"collector", Value(Integer{0})}, {"belt", Value(Integer{0})},
        {"processor", Value(Integer{0})}, {"wheel", Value(Integer{0})},
        {"shaft", Value(Integer{0})}, {"gear", Value(Integer{0})},
        {"gearbox", Value(Integer{0})}, {"vertical_gearbox", Value(Integer{0})},
        {"chain_drive", Value(Integer{0})}};
    for (const auto& [specification, count] : kit) {
        const auto name = kind(specification.role);
        const auto previous = std::get<Integer>(counts.at(name).storage());
        if (count > std::numeric_limits<Integer>::max() - previous)
            throw std::overflow_error("Part projection overflow.");
        counts.at(name) = Value(previous + count);
    }
    return Value(std::move(counts));
}
}  // namespace

const char* kind(stationary::Role role) {
    switch (role) {
        case stationary::Role::collector: return "collector";
        case stationary::Role::belt: return "belt";
        case stationary::Role::processor: return "processor";
        case stationary::Role::waterwheel: return "wheel";
        case stationary::Role::gear: return "gear";
        case stationary::Role::shaft: return "shaft";
        case stationary::Role::gearbox: return "gearbox";
        case stationary::Role::vertical_gearbox: return "vertical_gearbox";
        case stationary::Role::chain_drive: return "chain_drive";
    }
    return "invalid";
}

Object fields(const world::Profile& profile, const world::Snapshot& snapshot) {
    const auto& state = snapshot.state;
    Object inventories, kits, specifications;
    for (const auto& [actor, contents] : state.material.cargo)
        inventories.emplace(actor, Value(contents.products));
    std::set<stationary::PartSpec> offered;
    for (const auto& [specification, initial] : profile.finite_parts) {
        (void)initial;
        offered.insert(specification);
    }
    for (const auto& [specification, cost] : profile.fabrication_parts) {
        (void)cost;
        offered.insert(specification);
    }
    for (const auto& [actor, kit] : state.kits) {
        auto projected_kit = std::get<Object>(kit_value(kit).storage());
        projected_kit.emplace("foundation", Value(state.foundation_kits.at(actor)));
        kits.emplace(actor, Value(std::move(projected_kit)));
        Array entries;
        for (const auto& specification : offered) {
            const auto found = kit.find(specification);
            entries.emplace_back(Object{{"kind", Value(kind(specification.role))},
                {"teeth", Value(specification.teeth)}, {"half_span", Value(specification.half_span)},
                {"count", Value(found == kit.end() ? 0 : found->second)}});
        }
        specifications.emplace(actor, Value(std::move(entries)));
    }
    auto player_parts = std::get<Object>(kit_value(state.kits.at("P")).storage());
    player_parts.emplace("foundation", Value(state.foundation_kits.at("P")));
    Object output{{"inventories", Value(std::move(inventories))},
        {"part_kits", Value(std::move(kits))},
        {"part_specifications", Value(std::move(specifications))},
        {"parts", Value(std::move(player_parts))}};
    if (!state.landing_pod) return output;

    Object recipes;
    for (const auto component : {materials::Component::wooden_frame, materials::Component::wooden_shaft,
            materials::Component::wooden_cog, materials::Component::receiver_tray,
            materials::Component::tool_mount, materials::Component::sliding_guide,
            materials::Component::cutting_edge, materials::Component::anvil,
            materials::Component::ram_face, materials::Component::copper_shaft,
            materials::Component::copper_cog, materials::Component::wooden_workbench,
            materials::Component::wooden_slide, materials::Component::copper_slide,
            materials::Component::flat_head, materials::Component::hand_crank,
            materials::Component::channel_narrow_x, materials::Component::channel_narrow_z,
            materials::Component::channel_broad_x, materials::Component::channel_broad_z}) {
        const auto cost = materials::component_cost(component);
        if (cost) {
            Object recipe{{"timber", Value(cost->timber)}, {"copper", Value(cost->ore)}};
            if (const auto rating = world::placed_drive_load_rating(component))
                recipe.emplace("load_rating", Value(*rating));
            recipes.emplace(materials::component_name(component), Value(std::move(recipe)));
        }
    }
    output.emplace("component_recipes", Value(std::move(recipes)));
    Array fabrication;
    for (const auto& [specification, cost] : profile.fabrication_parts)
        fabrication.emplace_back(Object{{"kind", Value(kind(specification.role))},
            {"teeth", Value(specification.teeth)}, {"half_span", Value(specification.half_span)},
            {"timber", Value(cost.timber)}, {"copper", Value(cost.ore)}});
    output.emplace("part_recipes", Value(std::move(fabrication)));
    output.emplace("foundation_recipe", Value(Object{{"timber", Value(world::foundation_timber_cost)},
        {"copper", Value(Integer{0})}}));
    output.emplace("component_capacity", Value(profile.material.component_capacity));
    Array completed;
    for (const auto& actor : state.workshop_completed_actors)
        completed.emplace_back(actor);
    output.emplace("workshop_completed_actors", Value(std::move(completed)));
    output.emplace("first_plate_unlock", Value(profile.first_plate_unlock));
    return output;
}

}  // namespace factory::godot_world::build_catalog_projection
