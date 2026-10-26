#include "fabrication_planner.hpp"
#include "factory/fabrication_command_contract.hpp"

#include <algorithm>
#include <limits>
#include <utility>

namespace factory::world {
namespace {

std::optional<FabricationHub> workshop_bench(const State& state, const std::string& id) {
    const auto placed_bench = state.placed_components.find(id);
    return state.fabrication_hub && !state.fabrication_hub->holder &&
        id == state.fabrication_hub->id ?
        std::optional<FabricationHub>(*state.fabrication_hub) :
        placed_bench != state.placed_components.end() &&
            placed_bench->second.kind == materials::Component::wooden_workbench ?
            std::optional<FabricationHub>(FabricationHub{id, placed_bench->second.center,
                placed_bench->second.generation}) : std::nullopt;
}

std::optional<std::string> mint_hand_crank(State& candidate,
        const std::string& actor, authority::Object& facts) {
    if (candidate.issued_entities.size() == maximum_issued_entities ||
        candidate.next_entity_serial == std::numeric_limits<authority::Integer>::max())
        return "identity_limit";
    const auto serial = candidate.next_entity_serial++;
    const auto crank_id = std::string(allocated_prefix) + std::to_string(serial);
    if (!candidate.issued_entities.emplace(crank_id, serial).second ||
        !candidate.crank_items.emplace(crank_id,
            HandCrank{crank_id, serial, actor}).second)
        return "identity_conflict";
    facts.emplace("crank_id", values::Value(crank_id));
    facts.emplace("crank_generation", values::Value(serial));
    return std::nullopt;
}

} // namespace

std::optional<FabricationCommand> fabrication_command(
        const std::string& action, const authority::Object& intent) {
    using Integer = authority::Integer;
    using Kind = FabricationCommand::Kind;
    using ContractAction = fabrication_commands::Action;
    const auto selected = fabrication_commands::parse(action);
    if (selected == ContractAction::field_craft) {
        const auto* component = field<std::string>(intent, "component");
        if (!component) return std::nullopt;
        return FabricationCommand{Kind::field_component, {}, 0, *component, 0};
    }
    if (selected == ContractAction::none) return std::nullopt;
    const auto* target = field<std::string>(intent, "target");
    const auto* generation = field<Integer>(intent, "generation");
    if (!target || !generation) return std::nullopt;
    if (selected == ContractAction::foundation)
        return FabricationCommand{Kind::foundation, *target, *generation, {}, 0};
    if (selected == ContractAction::component) {
        const auto* component = field<std::string>(intent, "component");
        if (!component) return std::nullopt;
        return FabricationCommand{Kind::component, *target, *generation, *component, 0};
    }
    const auto* selected_role = field<std::string>(intent, "role");
    const auto* half_span = field<Integer>(intent, "half_span");
    if (!selected_role || !half_span) return std::nullopt;
    return FabricationCommand{Kind::part, *target, *generation, *selected_role, *half_span};
}

Owner::Decision plan_fabrication(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const FabricationCommand& command,
        const ObserveActor& observe) {
    using Integer = authority::Integer;
    using Object = authority::Object;
    using Value = values::Value;
    const auto& state = snapshot.state;
    if (command.kind == FabricationCommand::Kind::field_component) {
        const auto& requested = command.recipe_name;
        const auto component = materials::component_from_name(requested);
        const auto cost = component ? materials::component_cost(*component) : std::nullopt;
        if (!cost || cost->ore != 0 || cost->timber < 1) return refused("unavailable_recipe");
        if (*component == materials::Component::hand_crank && !profile.landing_pod_center)
            return refused("unavailable_recipe");
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut, {checked_cut.position});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), {}, std::move(facts));
        auto candidate = state;
        const auto error = materials::craft_component(candidate.material, profile.material,
            material_path(candidate.topology), binding.actor, *component);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), {}, std::move(facts));
        if (*component == materials::Component::hand_crank) {
            if (const auto error = mint_hand_crank(candidate, binding.actor, facts))
                return refused(*error, {}, std::move(facts));
        }
        facts.emplace("generation", Value(Integer{0}));
        facts.emplace("component", Value(requested));
        facts.emplace("spent_timber", Value(cost->timber));
        facts.emplace("spent_raw", Value(Integer{0}));
        facts.emplace("component_count", Value(candidate.material.cargo.at(binding.actor).components.at(*component)));
        return accepted(std::move(candidate), {}, std::move(facts));
    }
    if (command.kind == FabricationCommand::Kind::foundation) {
        const auto& id = command.target;
        const auto& generation = command.generation;
        const auto bench = workshop_bench(state, id);
        if (!bench) return refused("unknown_target", id);
        if (generation != bench->generation) return refused("stale_generation", id);
        if (!profile.landing_pod_center || profile.foundation_parts == 0)
            return refused("unavailable_recipe", id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile, bench->center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), id, std::move(facts));
        auto candidate = state;
        auto& carried = candidate.material.cargo.at(binding.actor);
        if (carried.timber < foundation_timber_cost) return refused("unavailable_input", id, std::move(facts));
        Integer total = static_cast<Integer>(candidate.foundations.size());
        for (const auto& [actor, count] : candidate.foundation_kits)
            if (!add(total, count)) return refused("inventory_full", id, std::move(facts));
        if (total >= 256 || candidate.material.fabricated_timber >
                std::numeric_limits<Integer>::max() - foundation_timber_cost)
            return refused("inventory_full", id, std::move(facts));
        carried.timber -= foundation_timber_cost;
        candidate.material.fabricated_timber += foundation_timber_cost;
        const Integer count = ++candidate.foundation_kits.at(binding.actor);
        facts.emplace("generation", Value(generation));
        facts.emplace("spent_timber", Value(foundation_timber_cost));
        facts.emplace("foundation_count", Value(count));
        return accepted(std::move(candidate), id, std::move(facts));
    }
    if (command.kind == FabricationCommand::Kind::component) {
        const auto& id = command.target;
        const auto& generation = command.generation;
        const auto& requested = command.recipe_name;
        const auto bench = workshop_bench(state, id);
        if (!bench) return refused("unknown_target", id);
        if (generation != bench->generation)
            return refused("stale_generation", id);
        const auto component = materials::component_from_name(requested);
        const auto cost = component ? materials::component_cost(*component) : std::nullopt;
        if (!cost) return refused("unavailable_recipe", id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile, bench->center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), id, std::move(facts));
        auto candidate = state;
        const auto error = materials::craft_component(candidate.material, profile.material,
            material_path(candidate.topology), binding.actor, *component);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), id, std::move(facts));
        if (*component == materials::Component::hand_crank) {
            if (const auto error = mint_hand_crank(candidate, binding.actor, facts))
                return refused(*error, id, std::move(facts));
        }
        facts.emplace("generation", Value(generation));
        facts.emplace("component", Value(requested));
        facts.emplace("spent_timber", Value(cost->timber));
        facts.emplace("spent_raw", Value(cost->ore));
        facts.emplace("component_count", Value(candidate.material.cargo.at(binding.actor).components.at(*component)));
        return accepted(std::move(candidate), id, std::move(facts));
    }
    if (command.kind == FabricationCommand::Kind::part) {
        const auto& id = command.target;
        const auto& generation = command.generation;
        const auto& requested = command.recipe_name;
        const auto& half_span = command.half_span;
        const auto bench = workshop_bench(state, id);
        if (!bench) return refused("unknown_target", id);
        if (generation != bench->generation)
            return refused("stale_generation", id);
        const auto selected = role(requested);
        const auto recipe = selected ? profile.fabrication_parts.find({*selected, 0, half_span}) :
            profile.fabrication_parts.end();
        if (recipe == profile.fabrication_parts.end()) return refused("unavailable_recipe", id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile, bench->center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), id, std::move(facts));
        const auto cost = recipe->second;
        const auto& carried = state.material.cargo.at(binding.actor);
        if (carried.timber < cost.timber || carried.raw_units < cost.ore)
            return refused("unavailable_input", id, std::move(facts));
        auto candidate = state;
        auto& next_cargo = candidate.material.cargo.at(binding.actor);
        next_cargo.timber -= cost.timber;
        next_cargo.raw_units -= cost.ore;
        if (!add(candidate.material.fabricated_timber, cost.timber) ||
            !add(candidate.material.fabricated_raw, cost.ore) ||
            !add(candidate.kits.at(binding.actor)[recipe->first], 1) ||
            candidate.kits.at(binding.actor)[recipe->first] > 4096)
            return refused("quantity_overflow", id, std::move(facts));
        facts.emplace("generation", Value(generation));
        facts.emplace("role", Value(requested));
        facts.emplace("half_span", Value(half_span));
        facts.emplace("spent_timber", Value(cost.timber));
        facts.emplace("spent_raw", Value(cost.ore));
        facts.emplace("part_count", Value(candidate.kits.at(binding.actor).at(recipe->first)));
        return accepted(std::move(candidate), id, std::move(facts));
    }
    return refused("invalid_command");
}

} // namespace factory::world
