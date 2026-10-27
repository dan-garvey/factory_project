#include "stationary_planner.hpp"

#include <algorithm>
#include <limits>
#include <utility>

namespace factory::world {
namespace {
using Action = StationaryCommand::Action;
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;
using Role = stationary::Role;

Value removed_part_value(const stationary::PlacedPart& part) {
    const auto& shape = part.geometry;
    return Value(Object{{"role", Value(Integer{static_cast<int>(part.role)})},
        {"center", Value(Value::Array{Value(shape.center[0]), Value(shape.center[1]), Value(shape.center[2])})},
        {"axis", Value(Integer{static_cast<int>(shape.axis)})},
        {"teeth", Value(shape.teeth)}, {"half_span", Value(shape.half_span)},
        {"relay_axis", Value(Integer{static_cast<int>(shape.relay_axis)})},
        {"rotation", Value(part.rotation)}, {"wheel_tiles", Value(part.wheel_tiles)}});
}

std::optional<materials::ResolvedTarget> material_target(
        const Profile& profile, const stationary::PlacedPart& selected,
        const stationary::Topology& topology) {
    materials::Holder holder;
    switch (selected.role) {
        case Role::collector: holder = materials::Holder::collector; break;
        case Role::processor: holder = materials::Holder::processor; break;
        default: return std::nullopt;
    }
    materials::ResolvedTarget target{{selected.geometry.id, selected.generation}, holder,
                                      material_path(topology), std::nullopt};
    if (selected.role == Role::processor)
        target.accepts_work = materials::RecipeSignature{
            profile.material.input_units_per_product, profile.material.cycle_ticks};
    return target;
}
} // namespace

std::optional<StationaryCommand> stationary_command(
        const std::string& action, const Object& intent) {
    StationaryCommand command;
    if (action == "place") command.action = Action::place;
    else if (action == "place_connected") command.action = Action::place_connected;
    else if (action == "remove") command.action = Action::remove;
    else if (action == "set_drive") command.action = Action::set_drive;
    else if (action == "collect") command.action = Action::collect;
    else if (action == "recover") command.action = Action::recover;
    else if (action == "insert_raw") command.action = Action::insert_raw;
    else if (action == "insert_work") command.action = Action::insert_work;
    else if (action == "shaft_between") command.action = Action::shaft_between;
    else if (action == "remove_shaft_between") command.action = Action::remove_shaft_between;
    else return std::nullopt;
    if (const auto* value = field<std::string>(intent, "target")) command.target = *value;
    if (const auto* value = field<Integer>(intent, "generation")) command.generation = *value;
    if (const auto* value = field<std::string>(intent, "to")) command.to = *value;
    if (const auto* value = field<Integer>(intent, "to_generation")) command.to_generation = *value;
    if (const auto* value = field<std::string>(intent, "role")) command.role_name = *value;
    if (const auto* value = field<std::string>(intent, "axis")) command.axis_name = *value;
    if (const auto* value = field<std::string>(intent, "relay_axis")) command.relay_axis_name = *value;
    command.center = grid_point(intent);
    if (const auto* value = field<Integer>(intent, "teeth")) command.teeth = *value;
    if (const auto* value = field<Integer>(intent, "half_span")) command.half_span = *value;
    if (const auto* value = field<Integer>(intent, "wheel_tiles")) command.wheel_tiles = *value;
    if (const auto* value = field<Integer>(intent, "rotation")) command.rotation = *value;
    if (const auto* value = field<Integer>(intent, "amount")) command.amount = *value;
    if (const auto* value = field<Integer>(intent, "work_id")) command.work_id = *value;
    if (const auto* value = field<bool>(intent, "enabled")) command.enabled = *value;
    command.has_rotation = intent.contains("rotation");
    command.has_wheel_tiles = intent.contains("wheel_tiles");
    command.has_relay_axis = intent.contains("relay_axis");
    return command;
}

Owner::Decision plan_stationary(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const StationaryCommand& command,
        const ObserveActor& observe) {
    const auto& state = snapshot.state;
    const bool placing = command.action == Action::place ||
        command.action == Action::place_connected;
    const stationary::PlacedPart* selected = nullptr;
    const stationary::PlacedPart* destination = nullptr;
    std::optional<mechanics::Point> location;
    std::optional<Role> selected_role;
    std::optional<mechanics::Axis> selected_axis;
    std::vector<authority::Point> targets;
    if (placing) {
        const auto& role_name = command.role_name;
        const auto& axis_name = command.axis_name;
        const auto& teeth = command.teeth;
        const auto& span = command.half_span;
        const auto& wheel_tiles = command.wheel_tiles;
        const auto& rotation = command.rotation;
        const auto& relay_axis_name = command.relay_axis_name;
        location = command.center;
        if (!role_name || !axis_name || !teeth || !span || !location ||
            !(selected_role = role(*role_name)) || !(selected_axis = axis(*axis_name)) ||
            !spec_valid({*selected_role, *teeth, *span}) ||
            (command.has_rotation && (!rotation || !material_machine(*selected_role) ||
                *rotation < 0 || *rotation > 3)) ||
            (command.has_wheel_tiles && (!wheel_tiles || *selected_role != Role::waterwheel ||
                *wheel_tiles < 3 || *wheel_tiles > mechanics::maximum_dimension)) ||
            (command.has_relay_axis != (*selected_role == Role::chain_drive)) ||
            (relay_axis_name && (!axis(*relay_axis_name) || axis(*relay_axis_name) == *selected_axis)) ||
            (*selected_role == Role::gearbox && *selected_axis != mechanics::Axis::y) ||
            (*selected_role == Role::vertical_gearbox && *selected_axis == mechanics::Axis::y))
            return refused("invalid_part");
        if (*selected_role == Role::belt) return refused("invalid_part");
        if (state.fabrication_hub && !state.fabrication_hub->holder && material_machine(*selected_role) &&
            *location == state.fabrication_hub->center) return refused("occupied");
        if ((material_machine(*selected_role) || *selected_role == Role::waterwheel) && (*location)[1] % 4 != 0)
            return refused("unaligned_elevation");
        if (!transmission_center(*selected_role, *location, *selected_axis, *span))
            return refused("invalid_cell");
        targets.push_back(anchor(profile, *location));
        if (profile.foundation_parts > 0 && material_machine(*selected_role) && (*location)[1] != 0) {
            const bool supported = std::any_of(state.foundations.begin(), state.foundations.end(),
                [&](const auto& entry) { return entry.second.center == *location; });
            if (!supported) return refused("foundation_required");
        }
        if (command.action == Action::place_connected && !material_machine(*selected_role))
            return refused("invalid_part");
    } else {
        const auto& id = command.target;
        const auto& generation = command.generation;
        if (!id || !generation) return refused("invalid_target");
        selected = part(state.topology, *id);
        if (!selected) return refused("unknown_target", *id);
        if (selected->generation != *generation) return refused("stale_generation", *id);
        targets.push_back(anchor(profile, selected->geometry.center));
        if (command.action == Action::shaft_between ||
            command.action == Action::remove_shaft_between) {
            const auto& to = command.to;
            const auto& to_generation = command.to_generation;
            if (!to || !to_generation) return refused("invalid_target");
            destination = part(state.topology, *to);
            if (!destination) return refused("unknown_target", *to);
            if (destination->generation != *to_generation)
                return refused("stale_generation", *to);
            targets.push_back(anchor(profile, destination->geometry.center));
        }
    }
    if (!observe) return refused("actor_unready");
    auto cut = observe(binding.actor);
    if (!cut) return refused("actor_unready");
    // Reach is profile authority, regardless of the provider's generic cut.
    cut->build_reach = profile.build_reach;
    auto reach = authority::check_reach(binding.actor, *cut, targets);
    Object facts = reach.receipt ? reach_facts(binding, *reach.receipt) : Object{};
    if (reach.error != authority::Error::none)
        return refused(authority::error_name(reach.error),
            selected ? selected->geometry.id : "", std::move(facts));

    State candidate = state;
    std::string entity;
    Integer generation{};
    if (command.action == Action::shaft_between ||
        command.action == Action::remove_shaft_between)
        return refused("individual_shaft_required", selected->geometry.id, std::move(facts));
    if (placing && std::any_of(state.topology.parts.begin(), state.topology.parts.end(), [&](const auto& existing) {
            return existing.geometry.center == *location &&
                (transmission_role(*selected_role) || transmission_role(existing.role));
        })) return refused("occupied", "", std::move(facts));
    if (placing) {
        if (candidate.issued_entities.size() == maximum_issued_entities ||
            candidate.next_entity_serial == std::numeric_limits<Integer>::max())
            return refused("identity_limit");
        generation = candidate.next_entity_serial++;
        entity = std::string(allocated_prefix) + std::to_string(generation);
        if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
        const auto kind = *selected_role == Role::gear ? mechanics::Kind::gear :
                          *selected_role == Role::shaft ? mechanics::Kind::shaft :
                          (*selected_role == Role::gearbox || *selected_role == Role::vertical_gearbox) ?
                              mechanics::Kind::gearbox :
                          *selected_role == Role::chain_drive ? mechanics::Kind::chain_drive : mechanics::Kind::hub;
        stationary::PlacedPart placed{
            {entity, kind, *location, *selected_axis, *command.teeth,
             *command.half_span, command.relay_axis_name ? *axis(*command.relay_axis_name) :
                mechanics::Axis::x},
            generation, *selected_role};
        placed.geometry.id = entity;
        placed.generation = generation;
        if (command.rotation) placed.rotation = *command.rotation;
        if (placed.role == Role::waterwheel && command.wheel_tiles)
            placed.wheel_tiles = *command.wheel_tiles;
        stationary::PlacementSelection selection{placed, std::nullopt};
        if (placed.role == Role::waterwheel) {
            const auto rate = wheel_rate(profile, placed);
            if (!rate) return refused("invalid_waterwheel");
            selection.source = mechanics::Drive{entity, *rate};
        }
        auto proposal = stationary::prepare_placement(state.topology, state.kits.at(binding.actor),
                                                     state.material, selection);
        if (const auto* error = std::get_if<stationary::PlacementRefusal>(&proposal))
            return refused(stationary::placement_error_name(error->reason));
        auto& ready = std::get<stationary::PreparedPlacement>(proposal);
        candidate.topology = std::move(ready.candidate);
        candidate.kits.at(binding.actor) = std::move(ready.candidate_kit);
        candidate.issued_entities.emplace(entity, generation);
    } else {
        entity = selected->geometry.id;
        generation = selected->generation;
        if (command.action == Action::remove) {
            facts.emplace("removed_part", removed_part_value(*selected));
            auto proposal = stationary::prepare_removal(state.topology, state.kits.at(binding.actor),
                state.material, {{entity, generation}});
            if (const auto* error = std::get_if<stationary::RemovalRefusal>(&proposal))
                return refused(stationary::removal_error_name(error->reason), entity, std::move(facts));
            auto& ready = std::get<stationary::PreparedRemoval>(proposal);
            candidate.topology = std::move(ready.candidate);
            candidate.kits.at(binding.actor) = std::move(ready.candidate_kit);
        } else if (command.action == Action::set_drive) {
            if (selected->role != Role::waterwheel) return refused("unsupported_target", entity);
            candidate.topology.drive_enabled = *command.enabled;
        } else {
            auto target = material_target(profile, *selected, state.topology);
            if (!target) return refused("unsupported_target", entity);
            if (command.action == Action::collect) {
                if (selected->role != Role::processor) return refused("unsupported_target", entity);
                const auto amount = *command.amount;
                const auto error = materials::retrieve(candidate.material, profile.material, target->path,
                                                       binding.actor, amount);
                if (error != materials::Error::none) return refused(materials::error_name(error), entity);
                facts.emplace("moved_products", Value(amount));
            } else {
                materials::TransferPlan proposal;
                if (command.action == Action::recover)
                    proposal = materials::prepare_recovery(state.material, profile.material,
                        {binding.actor, *target});
                else {
                    materials::Insertion insertion;
                    if (command.action == Action::insert_raw)
                        insertion = materials::RawInsertion{*command.amount};
                    else insertion = materials::WorkInsertion{*command.work_id};
                    proposal = materials::prepare_insertion(state.material, profile.material,
                                                            {binding.actor, *target, insertion});
                }
                if (const auto* error = std::get_if<materials::TransferRefusal>(&proposal))
                    return refused(materials::transfer_error_name(error->reason), entity, std::move(facts));
                auto& ready = std::get<materials::PreparedTransfer>(proposal);
                candidate.material = std::move(ready.candidate);
                facts.emplace("moved_raw", Value(ready.facts.moved.raw_units));
                facts.emplace("moved_products", Value(ready.facts.moved.products));
                facts.emplace("moved_work", lots_value(ready.facts.moved.work_lots));
            }
        }
    }
    facts.emplace("generation", Value(generation));
    return accepted(std::move(candidate), std::move(entity), std::move(facts));
}

} // namespace factory::world
