#include "foundation_planner.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace factory::world {
namespace {
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;

bool foundation_occupied(const State& state, const mechanics::Point& cell) {
    for (const auto& placed : state.topology.parts)
        if (std::abs(placed.geometry.center[0] - cell[0]) < 4 &&
            std::abs(placed.geometry.center[2] - cell[2]) < 4 &&
            placed.geometry.center[1] < cell[1] &&
            placed.geometry.center[1] + 4 > cell[1] - foundation_depth_levels)
            return true;
    for (const auto& [id, foundation] : state.foundations) {
        (void)id;
        if (foundation.center[0] == cell[0] && foundation.center[2] == cell[2] &&
            std::abs(foundation.center[1] - cell[1]) < foundation_depth_levels)
            return true;
    }
    return false;
}
} // namespace

std::optional<FoundationCommand> foundation_command(
        const std::string& action, const Object& intent) {
    FoundationCommand command;
    if (action == "place_foundations") {
        command.kind = FoundationCommand::Kind::place_area;
        command.cells = foundation_area(intent);
    } else if (action == "place_foundation") {
        command.kind = FoundationCommand::Kind::place_one;
        command.center = grid_point(intent);
    } else if (action == "remove_foundation") {
        command.kind = FoundationCommand::Kind::remove_one;
        if (const auto* target = field<std::string>(intent, "target")) command.target = *target;
        if (const auto* generation = field<Integer>(intent, "generation"))
            command.generation = *generation;
    } else return std::nullopt;
    return command;
}

Owner::Decision plan_foundation(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const FoundationCommand& command,
        const ObserveActor& observe) {
    const auto& state = snapshot.state;
    if (profile.foundation_parts == 0) return refused("foundations_unavailable");
    if (command.kind == FoundationCommand::Kind::place_area) {
        const auto& cells = command.cells;
        if (cells.empty()) return refused("invalid_area");
        const auto count = static_cast<Integer>(cells.size());
        if (state.foundation_kits.at(binding.actor) < count) return refused("no_part");
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        // Area construction deliberately has no distance restriction. This cut
        // still verifies the actual bound actor and a valid native observation.
        const auto checked = authority::check_reach(binding.actor, checked_cut, {cut->position});
        Object facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none) return refused(authority::error_name(checked.error));
        auto candidate = state;
        std::string entity;
        Integer generation{};
        for (const auto& cell : cells) {
            if (foundation_occupied(state, cell)) return refused("occupied");
            if (candidate.issued_entities.size() == maximum_issued_entities ||
                candidate.next_entity_serial == std::numeric_limits<Integer>::max()) return refused("identity_limit");
            generation = candidate.next_entity_serial++;
            entity = std::string(allocated_prefix) + std::to_string(generation);
            if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
            candidate.foundations.emplace(entity, Foundation{cell, generation});
            candidate.issued_entities.emplace(entity, generation);
            --candidate.foundation_kits.at(binding.actor);
        }
        facts.emplace("generation", Value(generation));
        facts.emplace("count", Value(count));
        return accepted(std::move(candidate), entity, std::move(facts));
    }

    auto location = command.center;
    std::string entity;
    Integer generation{};
    if (command.kind == FoundationCommand::Kind::remove_one) {
        if (!command.target || !command.generation) return refused("invalid_target");
        const auto& id = *command.target;
        const auto found = state.foundations.find(id);
        if (found == state.foundations.end()) return refused("unknown_target", id);
        if (found->second.generation != *command.generation)
            return refused("stale_generation", id);
        if (state.fabrication_hub && !state.fabrication_hub->holder &&
            found->second.center == state.fabrication_hub->center)
            return refused("foundation_in_use", id);
        if (std::any_of(state.placed_components.begin(), state.placed_components.end(),
                [&](const auto& entry) {
                    const auto occupied = materials::component_workcells(
                        entry.second.kind, entry.second.center);
                    return occupied ? std::find(occupied->begin(), occupied->end(),
                        found->second.center) != occupied->end() :
                        entry.second.center == found->second.center;
                }))
            return refused("foundation_in_use", id);
        location = found->second.center;
        entity = id;
        generation = *command.generation;
    }
    if (!location || (*location)[0] % 4 != 0 || (*location)[2] % 4 != 0)
        return refused("invalid_cell");
    const auto cut = observe ? observe(binding.actor) : std::nullopt;
    if (!cut) return refused("actor_unready");
    auto checked_cut = *cut;
    checked_cut.build_reach = profile.build_reach;
    const auto checked = authority::check_reach(binding.actor, checked_cut,
        {anchor(profile, *location)});
    Object facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
    if (checked.error != authority::Error::none)
        return refused(authority::error_name(checked.error), entity, std::move(facts));
    auto candidate = state;
    if (command.kind == FoundationCommand::Kind::place_one) {
        if (foundation_occupied(state, *location))
            return refused("occupied", "", std::move(facts));
        if (state.foundation_kits.at(binding.actor) == 0)
            return refused("no_part", "", std::move(facts));
        if (state.issued_entities.size() == maximum_issued_entities ||
            state.next_entity_serial == std::numeric_limits<Integer>::max())
            return refused("identity_limit");
        generation = candidate.next_entity_serial++;
        entity = std::string(allocated_prefix) + std::to_string(generation);
        if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
        candidate.foundations.emplace(entity, Foundation{*location, generation});
        candidate.issued_entities.emplace(entity, generation);
        --candidate.foundation_kits.at(binding.actor);
    } else {
        for (const auto& placed : state.topology.parts)
            if (placed.geometry.center[0] == (*location)[0] &&
                placed.geometry.center[2] == (*location)[2] &&
                placed.geometry.center[1] >= (*location)[1] &&
                placed.geometry.center[1] < (*location)[1] + foundation_depth_levels)
                return refused("foundation_in_use", entity, std::move(facts));
        candidate.foundations.erase(entity);
        ++candidate.foundation_kits.at(binding.actor);
    }
    facts.emplace("generation", Value(generation));
    return accepted(std::move(candidate), entity, std::move(facts));
}

} // namespace factory::world
