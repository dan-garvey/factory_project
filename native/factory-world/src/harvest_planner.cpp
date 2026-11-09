#include "harvest_planner.hpp"
#include "factory/worksite_command_contract.hpp"

#include <algorithm>
#include <utility>

namespace factory::world {

std::optional<HarvestCommand> harvest_command(
        const std::string& action, const authority::Object& intent) {
    const auto selected = worksite_commands::parse_intent(action);
    if (selected == worksite_commands::Action::finish_harvest)
        return HarvestCommand{HarvestCommand::Kind::finish, {}};
    if (selected == worksite_commands::Action::cancel_harvest)
        return HarvestCommand{HarvestCommand::Kind::cancel, {}};
    if (selected != worksite_commands::Action::harvest &&
        selected != worksite_commands::Action::fast_harvest) return std::nullopt;
    const auto* target = field<std::string>(intent, "target");
    if (!target) return std::nullopt;
    return HarvestCommand{selected == worksite_commands::Action::harvest ? HarvestCommand::Kind::start :
        HarvestCommand::Kind::fast, *target};
}

HarvestTargetResult resolve_harvest_target(const Profile& profile,const State& state,
        const std::string& target,const authority::Point& actor) {
    const auto tree=profile.material.timber_sites.find(target);
    if(tree!=profile.material.timber_sites.end()) {
        const auto stock=state.material.timber_remaining.find(target);
        if(stock==state.material.timber_remaining.end()) return {"invalid_state",{}};
        if(stock->second<=0) return {"unavailable_source",{}};
        return {"none",HarvestTarget{false,manual_cut_target(profile,tree->second.center,actor,false),{}}};
    }
    if(profile.excavation) {
        if(!state.excavation) return {"invalid_ore_columns",{}};
        const auto selected=ore_columns::resolve_target(*profile.excavation,*state.excavation,
            state.material,target,actor);
        if(!selected.target) return {ore_columns::target_error_name(selected.error),{}};
        return {"none",HarvestTarget{true,selected.target->reach_point,selected.target}};
    }
    const auto region=ore_region_index(profile,target);
    const bool ore=profile.material.manual_ore && (profile.ore_field?
        region.has_value():profile.material.manual_ore->id==target);
    if(!ore) return {"unknown_target",{}};
    if(state.material.stock.source<=0 || (region && (!state.ore_field ||
            state.ore_field->remaining[static_cast<std::size_t>(*region)]<=0)))
        return {"unavailable_source",{}};
    const auto point=region && target!=profile.material.manual_ore->id?
        ore_region_cut_target(profile,*region,actor):
        manual_cut_target(profile,profile.material.manual_ore->center,actor,true);
    return {"none",HarvestTarget{true,point,{}}};
}

Owner::Decision plan_harvest(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const HarvestCommand& command,
        const ObserveActor& observe) {
    using Integer = authority::Integer;
    using Object = authority::Object;
    using Value = values::Value;
    const auto& state = snapshot.state;
    const auto pending = state.manual_cuts.find(binding.actor);
    const auto harvest = [&](State& candidate, const std::string& target,
                             const HarvestTarget& selected) -> const char* {
        if(selected.column) {
            if(!profile.excavation||!candidate.excavation) return "invalid_ore_columns";
            const auto result=ore_columns::cut_to_actor(*profile.excavation,*candidate.excavation,
                candidate.material,profile.material,material_path(candidate.topology),
                selected.column->cutting,profile.excavation->grid.work_per_unit,binding.actor);
            if(result.error==ore_columns::Error::invalid_material)
                return materials::error_name(result.material_error);
            if(result.error!=ore_columns::Error::none) return ore_columns::error_name(result.error);
            if(result.cutting==excavation::Status::receiver_full) return "inventory_full";
            return result.produced_units==1?nullptr:excavation::status_name(result.cutting);
        }
        const auto region = selected.ore?ore_region_index(profile,target):std::nullopt;
        const auto& material_target = region ? profile.material.manual_ore->id : target;
        const auto error = materials::harvest_source(candidate.material, profile.material,
            material_path(candidate.topology), binding.actor, material_target);
        if (error == materials::Error::none && region) {
            const auto bounds = mineral_site::field_region_cells(*region);
            if (!bounds || !candidate.ore_field ||
                !mineral_site::debit_field(*candidate.ore_field, bounds->low))
                return "invalid_state";
        }
        return error==materials::Error::none?nullptr:materials::error_name(error);
    };
    const auto append_column_facts=[](Object& facts,const HarvestTarget& selected) {
        if(!selected.column) return;
        auto columns=ore_columns::contact_facts(*selected.column);
        facts.merge(columns);
    };
    if (command.kind == HarvestCommand::Kind::cancel) {
        if (pending == state.manual_cuts.end()) return refused("no_active_cut");
        auto candidate = state;
        const auto target = pending->second.target;
        candidate.manual_cuts.erase(binding.actor);
        return accepted(std::move(candidate), target,
            {{"actor", Value(binding.actor)}, {"generation", Value(Integer{0})}});
    }
    if (command.kind == HarvestCommand::Kind::finish) {
        if (pending == state.manual_cuts.end()) return refused("no_active_cut");
        const auto target = pending->second.target;
        if (pending->second.interrupted_revision != 0)
            return refused("cut_interrupted", target);
        if (pending->second.remaining_ticks != 0)
            return refused("cut_in_progress", target);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", target);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.manual_cut_reach > 0 ?
            profile.manual_cut_reach : profile.build_reach;
        const auto selected=resolve_harvest_target(profile,state,target,checked_cut.position);
        if(!selected.target) return refused(selected.reason,target);
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {selected.target->reach_point});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), target, std::move(facts));
        auto candidate = state;
        const auto error = harvest(candidate, target,*selected.target);
        if (error) return refused(error,target,std::move(facts));
        candidate.manual_cuts.erase(binding.actor);
        append_column_facts(facts,*selected.target);
        facts.emplace("generation", Value(Integer{1}));
        facts.emplace("moved_raw", Value(Integer{selected.target->ore ? 1 : 0}));
        facts.emplace("moved_timber", Value(Integer{selected.target->ore ? 0 : 1}));
        return accepted(std::move(candidate), target, std::move(facts));
    }

    const bool fast = command.kind == HarvestCommand::Kind::fast;
    if (fast && !state.developer_conveniences) return refused("developer_mode_off");
    const auto& target = command.target;
    const auto cut = observe ? observe(binding.actor) : std::nullopt;
    if (!cut) return refused("actor_unready", target);
    auto checked_cut = *cut;
    checked_cut.build_reach = profile.manual_cut_reach > 0 ?
        profile.manual_cut_reach : profile.build_reach;
    const auto selected=resolve_harvest_target(profile,state,target,checked_cut.position);
    if(!selected.target) return refused(selected.reason,target);
    const auto checked = authority::check_reach(binding.actor, checked_cut,
        {selected.target->reach_point});
    auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
    if (checked.error != authority::Error::none)
        return refused(authority::error_name(checked.error), target, std::move(facts));
    if (std::any_of(state.manual_cuts.begin(), state.manual_cuts.end(),
            [&](const auto& entry) { return entry.second.target == target; }))
        return refused("source_busy", target, std::move(facts));
    auto candidate = state;
    const auto error = harvest(candidate,target,*selected.target);
    if (error) return refused(error,target,std::move(facts));
    if (!fast) {
        candidate = state;
        candidate.manual_cuts.emplace(binding.actor, State::ManualCut{
            target, snapshot.revision + 1, manual_cut_ticks, 0});
    }
    append_column_facts(facts,*selected.target);
    facts.emplace("generation", Value(Integer{1}));
    facts.emplace("moved_raw", Value(Integer{fast && selected.target->ore ? 1 : 0}));
    facts.emplace("moved_timber", Value(Integer{fast && !selected.target->ore ? 1 : 0}));
    return accepted(std::move(candidate), target, std::move(facts));
}

} // namespace factory::world
