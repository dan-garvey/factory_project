#include "component_planner.hpp"

#include <algorithm>
#include <limits>
#include <utility>

namespace factory::world {
namespace {
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;
} // namespace

std::optional<ComponentCommand> component_command(
        const std::string& action, const Object& intent) {
    const auto parsed = component_commands::parse(action);
    if (parsed == component_commands::Action::none) return std::nullopt;
    ComponentCommand command;
    command.action = parsed;
    if (const auto* value = field<std::string>(intent, "component"))
        command.component_name = *value;
    command.center = grid_point(intent);
    if (const auto* value = field<std::string>(intent, "target"))
        command.target = *value;
    if (const auto* value = field<Integer>(intent, "generation"))
        command.generation = *value;
    return command;
}

Owner::Decision plan_component(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const ComponentCommand& command,
        const ObserveActor& observe) {
    const auto& state = snapshot.state;
    if (!profile.landing_pod_center) return refused("components_unavailable");
    const bool placing = command.action == component_commands::Action::place;
    const auto* requested = placing && command.component_name ? &*command.component_name : nullptr;
    const auto component = requested ? materials::component_from_name(*requested) : std::nullopt;
    const auto location = placing ? command.center : std::nullopt;
    const auto* target = placing || !command.target ? nullptr : &*command.target;
    const auto* generation = placing || !command.generation ? nullptr : &*command.generation;
    const auto found = target ? state.placed_components.find(*target) : state.placed_components.end();
    if (placing && (!component || !location)) return refused("invalid_component");
    if (!placing && (!target || !generation)) return refused("invalid_target");
    if (!placing && found == state.placed_components.end()) return refused("unknown_target", *target);
    if (!placing && found->second.generation != *generation) return refused("stale_generation", *target);
    const auto center = placing ? *location : found->second.center;
    const auto kind = placing ? *component : found->second.kind;
    const auto channel = materials::channel_spec(kind);
    const auto area_cells = materials::component_workcells(kind, center);
    const bool broad = kind == materials::Component::broad_anvil ||
        kind == materials::Component::broad_flat_head ||
        kind == materials::Component::broad_copper_slide;
    if (kind == materials::Component::hand_crank)
        return refused("crank_requires_port");
    if ((channel || broad) && (!area_cells || center[0] % 4 != 0 ||
                    center[2] % 4 != 0 ||
                    (kind != materials::Component::broad_flat_head &&
                     kind != materials::Component::broad_copper_slide && center[1] % 4 != 0) ||
                    (kind == materials::Component::broad_flat_head && center[1] % 4 != 1) ||
                    (kind == materials::Component::broad_copper_slide && center[1] % 4 != 0)))
        return refused("invalid_area_target");
    if (placing && kind == materials::Component::broad_copper_slide &&
        std::none_of(state.placed_components.begin(), state.placed_components.end(),
            [&](const auto& entry) {
                return entry.second.kind == materials::Component::broad_anvil &&
                    entry.second.center == mechanics::Point{center[0], center[1] - 4, center[2]};
            }))
        return refused("missing_support");
    if (!placing && kind == materials::Component::broad_anvil &&
        std::any_of(state.placed_components.begin(), state.placed_components.end(),
            [&](const auto& entry) {
                return entry.second.kind == materials::Component::broad_copper_slide &&
                    entry.second.center == mechanics::Point{center[0], center[1] + 4, center[2]};
            }))
        return refused("housing_on_workbed");
    if (area_cells) {
        for (const auto& cell : *area_cells) {
            if ((channel || kind == materials::Component::broad_anvil) && center[1] != 0 &&
                std::none_of(state.foundations.begin(), state.foundations.end(),
                    [&](const auto& entry) { return entry.second.center == cell; }))
                return refused("missing_support");
            if (std::any_of(state.material.dropped_material.begin(),
                    state.material.dropped_material.end(), [&](const auto& entry) {
                        if (!broad_item(entry.second)) return entry.first == cell;
                        const auto occupied = broad_cells(entry.first);
                        return std::find(occupied.begin(), occupied.end(), cell) != occupied.end();
                    })) return refused("occupied");
            if (placing &&
                ((state.fabrication_hub && !state.fabrication_hub->holder &&
                  state.fabrication_hub->center == cell) ||
                 std::any_of(state.placed_components.begin(), state.placed_components.end(),
                    [&](const auto& entry) {
                        const auto occupied = materials::component_workcells(
                            entry.second.kind, entry.second.center);
                        return occupied ?
                            std::find(occupied->begin(), occupied->end(), cell) != occupied->end() :
                            entry.second.center == cell;
                    }) ||
                 std::any_of(state.topology.parts.begin(), state.topology.parts.end(),
                     [&](const auto& item) { return item.geometry.center == cell; })))
                return refused("occupied");
        }
    }
    if (placing && kind == materials::Component::wooden_workbench &&
        (center[0] % 4 != 0 || center[2] % 4 != 0 ||
         (center[1] != 0 &&
          std::none_of(state.foundations.begin(), state.foundations.end(),
              [&](const auto& entry) { return entry.second.center == center; }))))
        return refused("unsupported_bench");
    const auto cut = observe ? observe(binding.actor) : std::nullopt;
    if (!cut) return refused("actor_unready");
    auto checked_cut = *cut;
    checked_cut.build_reach = profile.build_reach;
    const auto checked = authority::check_reach(binding.actor, checked_cut, {anchor(profile, center)});
    auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
    if (checked.error != authority::Error::none)
        return refused(authority::error_name(checked.error), target ? *target : "", std::move(facts));
    auto candidate = state;
    auto& cargo = candidate.material.cargo.at(binding.actor).components;
    const auto [carried_kind, part_count] = materials::placement_parts(kind);
    std::string entity;
    Integer serial{};
    if (placing) {
        const auto owned = cargo.find(carried_kind);
        if (owned == cargo.end() || owned->second < part_count)
            return refused("no_component", "", std::move(facts));
        if (state.placed_components.size() >= maximum_issued_entities ||
            state.issued_entities.size() == maximum_issued_entities ||
            state.next_entity_serial == std::numeric_limits<Integer>::max())
            return refused("identity_limit", "", std::move(facts));
        if ((state.fabrication_hub && !state.fabrication_hub->holder &&
             center == state.fabrication_hub->center) ||
            std::any_of(state.placed_components.begin(), state.placed_components.end(),
                [&](const auto& entry) {
                    const auto occupied = materials::component_workcells(
                        entry.second.kind, entry.second.center);
                    return occupied ?
                        std::find(occupied->begin(), occupied->end(), center) != occupied->end() :
                        entry.second.center == center;
                }) ||
            std::any_of(state.topology.parts.begin(), state.topology.parts.end(),
                [&](const auto& item) { return item.geometry.center == center; }))
            return refused("occupied", "", std::move(facts));
        owned->second -= part_count;
        if (owned->second == 0) cargo.erase(owned);
        serial = candidate.next_entity_serial++;
        entity = std::string(allocated_prefix) + std::to_string(serial);
        if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
        candidate.issued_entities.emplace(entity, serial);
        candidate.placed_components.emplace(entity, PlacedComponent{kind, center, serial});
        if (slide_component(kind)) candidate.slide_phases.emplace(entity, State::SlidePhase{});
        ++candidate.material.placed_components[kind];
    } else {
        Integer carried = 0;
        for (const auto& [name, count] : cargo) {
            (void)name;
            if (!add(carried, count)) return refused("inventory_full", *target, std::move(facts));
        }
        if (profile.material.component_capacity > 0 &&
            carried > profile.material.component_capacity - part_count)
            return refused("inventory_full", *target, std::move(facts));
        if ((kind == materials::Component::anvil ||
             kind == materials::Component::broad_anvil) &&
            state.slide_press_routes.contains(center))
            return refused("work_on_anvil", *target, std::move(facts));
        if ((kind == materials::Component::anvil ||
             kind == materials::Component::broad_anvil) &&
            std::any_of(state.material.dropped_material.begin(),
                state.material.dropped_material.end(), [&](const auto& entry) {
                    if (!broad_item(entry.second)) return false;
                    const auto cells = broad_cells(entry.first);
                    return std::find(cells.begin(), cells.end(), center) != cells.end();
                })) return refused("occupied", *target, std::move(facts));
        if (kind == materials::Component::receiver_tray &&
            state.press_output_at_receiver.contains(center))
            return refused("receiver_full", *target, std::move(facts));
        entity = *target;
        serial = *generation;
        cargo[carried_kind] += part_count;
        candidate.placed_components.erase(entity);
        // A crank is a separate placed source. Removing its former input
        // disconnects it; the crank keeps its position and finite identity.
        for (auto& [id, crank] : candidate.crank_items) {
            (void)id;
            if (crank.attached_to == entity) crank.attached_to.reset();
        }
        if (slide_component(kind)) candidate.slide_phases.erase(entity);
        auto& placed = candidate.material.placed_components.at(kind);
        if (--placed == 0) candidate.material.placed_components.erase(kind);
    }
    facts.emplace("generation", Value(serial));
    facts.emplace("component", Value(materials::component_name(kind)));
    facts.emplace("component_count", Value(candidate.material.cargo.at(binding.actor).components.contains(carried_kind) ?
        candidate.material.cargo.at(binding.actor).components.at(carried_kind) : Integer{0}));
    facts.emplace("component_center", Value(Value::Array{Value(center[0]), Value(center[1]), Value(center[2])}));
    return accepted(std::move(candidate), entity, std::move(facts));
}

} // namespace factory::world
