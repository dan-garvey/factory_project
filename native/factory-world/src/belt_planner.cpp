#include "belt_planner.hpp"

#include <algorithm>
#include <limits>
#include <utility>

namespace factory::world {
namespace {
using Action = belt_commands::Action;
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;
}

std::optional<BeltCommand> belt_command(const std::string& action, const Object& intent) {
    const auto selected = belt_commands::parse(action);
    if (selected == Action::none) return std::nullopt;
    const auto* target = field<std::string>(intent, "target");
    const auto* generation = field<Integer>(intent, "generation");
    if (!target || !generation) return std::nullopt;
    BeltCommand command;
    command.action = selected;
    command.target = *target;
    command.generation = *generation;
    if (selected == Action::place || selected == Action::place_selected) {
        const auto* to = field<std::string>(intent, "to");
        const auto* to_generation = field<Integer>(intent, "to_generation");
        if (!to || !to_generation) return std::nullopt;
        command.to = *to;
        command.to_generation = *to_generation;
    }
    if (selected == Action::place_selected) {
        const auto* selection = field<std::string>(intent, "selection");
        if (!selection) return std::nullopt;
        command.selection = *selection;
    }
    if (selected == Action::recover_slot || selected == Action::load_slot) {
        const auto* slot = field<Integer>(intent, "slot");
        if (!slot) return std::nullopt;
        command.slot = *slot;
    }
    if (selected == Action::recover_slot) {
        const auto* expected = field<Object>(intent, "expected");
        if (!expected) return std::nullopt;
        command.expected = *expected;
    }
    if (selected == Action::load_slot) {
        const auto* item = field<std::string>(intent, "item");
        const auto* work_id = field<Integer>(intent, "work_id");
        if (!item || !work_id) return std::nullopt;
        command.item = *item;
        command.work_id = *work_id;
    }
    return command;
}

Owner::Decision plan_belt(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const BeltCommand& command,
        const ObserveActor& observe) {
    const auto& state = snapshot.state;
    const auto& id = command.target;
    const auto generation = command.generation;
    if (command.action == Action::select) {
        const auto* selected = part(state.topology, id);
        if (!selected) return refused("unknown_target", id);
        if (selected->generation != generation) return refused("stale_generation", id);
        if (selected->role != stationary::Role::shaft) return refused("invalid_belt_geometry", id);
        auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, *cut,
            {anchor(profile, selected->geometry.center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), id, std::move(facts));
        facts.emplace("generation", Value(generation));
        return accepted(state, id, std::move(facts));
    }
    if (command.action == Action::recover_slot || command.action == Action::load_slot) {
        const auto span = std::find_if(state.topology.belt_spans.begin(), state.topology.belt_spans.end(),
            [&](const auto& item) { return item.geometry.id == id; });
        if (span == state.topology.belt_spans.end()) return refused("unknown_target", id);
        if (span->generation != generation) return refused("stale_generation", id);
        const auto first = part(state.topology, span->geometry.first_shaft);
        const auto last = part(state.topology, span->geometry.last_shaft);
        const auto lane = state.material.belt_lanes.find(id);
        if (!first || !last || lane == state.material.belt_lanes.end())
            return refused("invalid_mechanics", id);
        if (command.slot < 0 || static_cast<std::size_t>(command.slot) >= lane->second.slots.size())
            return refused("invalid_slot", id);
        const auto path = mechanics::belt_path(first->geometry, last->geometry);
        if (!path || static_cast<std::size_t>(command.slot) >= path->tiles.size())
            return refused("invalid_mechanics", id);
        if (command.action == Action::load_slot &&
            (path->kind == mechanics::BeltPathKind::vertical ||
             path->kind == mechanics::BeltPathKind::sideways))
            return refused("belt_path_cannot_carry", id);
        const auto center = path->tiles[static_cast<std::size_t>(command.slot)];
        auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, *cut, {anchor(profile, center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), id, std::move(facts));
        const auto& item = lane->second.slots.at(static_cast<std::size_t>(command.slot));
        if (command.action == Action::load_slot) {
            if (item) return refused("slot_changed", id, std::move(facts));
            const auto& kind = command.item;
            const auto work_id = command.work_id;
            if (((kind == "raw" || kind == "product") && work_id != 0) ||
                ((kind == "work" || kind == "sheet") && work_id <= 0) ||
                (kind != "raw" && kind != "product" && kind != "work" && kind != "sheet"))
                return refused("invalid_cargo", id, std::move(facts));
            auto candidate = state;
            auto& cargo = candidate.material.cargo.at(binding.actor);
            materials::Cargo moved;
            if (kind == "raw" && cargo.raw_units > 0) { --cargo.raw_units; moved.raw_units = 1; }
            else if (kind == "product" && cargo.products > 0) { --cargo.products; moved.products = 1; }
            else if (kind == "work") {
                const auto lot = std::find_if(cargo.work_lots.begin(), cargo.work_lots.end(),
                    [&](const auto& value) { return value.id == work_id; });
                if (lot == cargo.work_lots.end()) return refused("unavailable_cargo", id, std::move(facts));
                if (!materials::fits_supported_workcells(center,
                        materials::work_footprint(lot->recipe.output), 0, {center}))
                    return refused("belt_cannot_carry", id, std::move(facts));
                moved.work_lots.push_back(*lot);
                cargo.work_lots.erase(lot);
            } else if (kind == "sheet") {
                const auto sheet = std::find_if(cargo.sheets.begin(), cargo.sheets.end(),
                    [&](const auto& value) { return value.id == work_id; });
                if (sheet == cargo.sheets.end()) return refused("unavailable_cargo", id, std::move(facts));
                if (!materials::fits_supported_workcells(center,
                        materials::sheet_footprint(), sheet->rotation, {center}))
                    return refused("belt_cannot_carry", id, std::move(facts));
                return refused("invalid_mechanics", id, std::move(facts));
            } else return refused("unavailable_cargo", id, std::move(facts));
            candidate.material.belt_lanes.at(id).slots.at(static_cast<std::size_t>(command.slot)) = moved;
            facts.emplace("generation", Value(generation));
            facts.emplace("moved_raw", Value(moved.raw_units));
            facts.emplace("moved_products", Value(moved.products));
            facts.emplace("moved_work", lots_value(moved.work_lots));
            facts.emplace("slot_center", Value(Value::Array{
                Value(center[0]), Value(center[1]), Value(center[2])}));
            return accepted(std::move(candidate), id, std::move(facts));
        }
        if (!item || values::typed_difference(Value(command.expected),
                belt_cargo_value(*item, copper_profile(profile.material))))
            return refused("slot_changed", id, std::move(facts));
        auto candidate = state;
        auto& cargo = candidate.material.cargo.at(binding.actor);
        if (!add(cargo.raw_units, item->raw_units) || !add(cargo.products, item->products) ||
            cargo.work_lots.size() + item->work_lots.size() > materials::maximum_live_work_lots)
            return refused("quantity_overflow", id, std::move(facts));
        cargo.work_lots.insert(cargo.work_lots.end(), item->work_lots.begin(), item->work_lots.end());
        candidate.material.belt_lanes.at(id).slots.at(static_cast<std::size_t>(command.slot)).reset();
        facts.emplace("generation", Value(generation));
        facts.emplace("moved_raw", Value(item->raw_units));
        facts.emplace("moved_products", Value(item->products));
        facts.emplace("moved_work", lots_value(item->work_lots));
        facts.emplace("slot_center", Value(Value::Array{
            Value(center[0]), Value(center[1]), Value(center[2])}));
        return accepted(std::move(candidate), id, std::move(facts));
    }
    if (command.action == Action::place || command.action == Action::place_selected ||
        command.action == Action::remove) {
        const bool placing = command.action != Action::remove;
        const stationary::PlacedPart* first = nullptr;
        const stationary::PlacedPart* last = nullptr;
        if (placing) {
            first = part(state.topology, id);
            last = part(state.topology, command.to);
            if (!first || !last) return refused("unknown_target");
            if (first->generation != generation || last->generation != command.to_generation)
                return refused("stale_generation");
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path) return refused("invalid_belt_geometry");
            if (command.action == Action::place_selected) {
                const authority::Record* selected = nullptr;
                bool used = false;
                for (const auto& record : snapshot.history.records) {
                    const auto* actor = field<std::string>(record.intent, "actor");
                    const auto* client = field<std::string>(record.intent, "client");
                    const auto* recorded_action = field<std::string>(record.intent, "action");
                    const auto* request = field<std::string>(record.intent, "request");
                    const auto* ok = field<bool>(record.result, "accepted");
                    if (!actor || *actor != binding.actor || !client || *client != binding.client ||
                        !recorded_action || !ok || !*ok) continue;
                    if (*recorded_action == "select_belt_shaft" && request &&
                        *request == command.selection) selected = &record;
                    if (*recorded_action == "place_selected_belt_span") {
                        const auto* prior = field<std::string>(record.intent, "selection");
                        if (prior && *prior == command.selection) used = true;
                    }
                }
                const auto* selected_target = selected ? field<std::string>(selected->intent, "target") : nullptr;
                const auto* selected_generation = selected ? field<Integer>(selected->intent, "generation") : nullptr;
                const auto* selected_points = selected ? field<Value::Array>(selected->result, "targets") : nullptr;
                if (!selected_target || *selected_target != first->geometry.id || !selected_generation ||
                    *selected_generation != first->generation || !selected_points || selected_points->size() != 1 ||
                    values::typed_difference(selected_points->front(),
                        point_value(anchor(profile, first->geometry.center))) || used)
                    return refused("invalid_belt_selection");
            }
        } else {
            const auto found = std::find_if(state.topology.belt_spans.begin(), state.topology.belt_spans.end(),
                [&](const auto& span) { return span.geometry.id == id; });
            if (found == state.topology.belt_spans.end()) return refused("unknown_target", id);
            if (found->generation != generation) return refused("stale_generation", id);
            first = part(state.topology, found->geometry.first_shaft);
            last = part(state.topology, found->geometry.last_shaft);
            if (!first || !last) return refused("invalid_mechanics", id);
        }
        auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile.build_reach;
        std::optional<mechanics::Point> removal_center;
        if (command.action == Action::remove) {
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path || path->tiles.empty()) return refused("invalid_mechanics", id);
            removal_center = *std::min_element(path->tiles.begin(), path->tiles.end(),
                [&](const auto& a, const auto& b) {
                    const auto squared = [&](const auto& tile) {
                        const auto position = anchor(profile, tile);
                        double distance = 0;
                        for (std::size_t i = 0; i < position.size(); ++i)
                            distance += (position[i] - cut->position[i]) * (position[i] - cut->position[i]);
                        return distance;
                    };
                    return squared(a) < squared(b);
                });
        }
        const auto checked = authority::check_reach(binding.actor, *cut,
            removal_center ? std::vector<authority::Point>{anchor(profile, *removal_center)} :
            command.action == Action::place_selected ?
                std::vector<authority::Point>{anchor(profile, last->geometry.center)} :
                std::vector<authority::Point>{anchor(profile, first->geometry.center),
                    anchor(profile, last->geometry.center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), id, std::move(facts));
        auto candidate = state;
        auto entity = id;
        auto result_generation = generation;
        if (placing) {
            if (candidate.issued_entities.size() == maximum_issued_entities ||
                candidate.next_entity_serial == std::numeric_limits<Integer>::max())
                return refused("identity_limit");
            result_generation = candidate.next_entity_serial++;
            entity = std::string(allocated_prefix) + std::to_string(result_generation);
            if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
            const stationary::PlacedBeltSpan span{{entity, first->geometry.id, last->geometry.id},
                result_generation};
            auto proposal = stationary::prepare_belt_placement(state.topology,
                state.kits.at(binding.actor), state.material, span);
            if (const auto* error = std::get_if<stationary::PlacementRefusal>(&proposal))
                return refused(stationary::placement_error_name(error->reason), "", std::move(facts));
            auto& ready = std::get<stationary::PreparedPlacement>(proposal);
            candidate.topology = std::move(ready.candidate);
            candidate.kits.at(binding.actor) = std::move(ready.candidate_kit);
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path) return refused("invalid_belt_geometry");
            candidate.material.belt_lanes.emplace(entity, materials::BeltLane{
                std::vector<std::optional<materials::Cargo>>(path->tiles.size()), 0});
            candidate.issued_entities.emplace(entity, result_generation);
            facts.emplace("first_center", Value(Value::Array{Value(first->geometry.center[0]),
                Value(first->geometry.center[1]), Value(first->geometry.center[2])}));
            facts.emplace("last_center", Value(Value::Array{Value(last->geometry.center[0]),
                Value(last->geometry.center[1]), Value(last->geometry.center[2])}));
        } else {
            const auto removed = std::find_if(state.topology.belt_spans.begin(),
                state.topology.belt_spans.end(),
                [&](const auto& span) { return span.geometry.id == entity; });
            if (removed == state.topology.belt_spans.end()) return refused("unknown_target", entity);
            facts.emplace("removed_span", removed_span_value(*removed));
            auto proposal = stationary::prepare_belt_removal(state.topology,
                state.kits.at(binding.actor), state.material, {entity, result_generation});
            if (const auto* error = std::get_if<stationary::RemovalRefusal>(&proposal))
                return refused(stationary::removal_error_name(error->reason), entity, std::move(facts));
            auto& ready = std::get<stationary::PreparedRemoval>(proposal);
            candidate.topology = std::move(ready.candidate);
            candidate.kits.at(binding.actor) = std::move(ready.candidate_kit);
            candidate.material.belt_lanes.erase(entity);
            facts.emplace("belt_center", Value(Value::Array{Value((*removal_center)[0]),
                Value((*removal_center)[1]), Value((*removal_center)[2])}));
        }
        facts.emplace("generation", Value(result_generation));
        return accepted(std::move(candidate), entity, std::move(facts));
    }
    return refused("invalid_command");
}

} // namespace factory::world
