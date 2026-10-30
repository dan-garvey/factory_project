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

Owner::Decision plan_harvest(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const HarvestCommand& command,
        const ObserveActor& observe) {
    using Integer = authority::Integer;
    using Object = authority::Object;
    using Value = values::Value;
    const auto& state = snapshot.state;
    const auto pending = state.manual_cuts.find(binding.actor);
    const auto ore_region = [&](const std::string& target) {
        return ore_region_index(profile, target);
    };
    const auto is_ore = [&](const std::string& target) {
        return profile.material.manual_ore && (profile.ore_field ?
            ore_region(target).has_value() : profile.material.manual_ore->id == target);
    };
    const auto contact = [&](const std::string& target,
            const materials::DropPoint& center, const authority::Point& actor) {
        if (profile.material.manual_ore && target != profile.material.manual_ore->id)
            if (const auto region = ore_region(target))
                return ore_region_cut_target(profile, *region, actor);
        return manual_cut_target(profile, center, actor, is_ore(target));
    };
    const auto local_available = [&](const std::string& target) {
        const auto region = ore_region(target);
        return !region || (state.ore_field &&
            state.ore_field->remaining[static_cast<std::size_t>(*region)] > 0);
    };
    const auto harvest = [&](State& candidate, const std::string& target) {
        const auto region = ore_region(target);
        const auto& material_target = region ? profile.material.manual_ore->id : target;
        const auto error = materials::harvest_source(candidate.material, profile.material,
            material_path(candidate.topology), binding.actor, material_target);
        if (error == materials::Error::none && region) {
            const auto bounds = mineral_site::field_region_cells(*region);
            if (!bounds || !candidate.ore_field ||
                !mineral_site::debit_field(*candidate.ore_field, bounds->low))
                return materials::Error::invalid_state;
        }
        return error;
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
        const bool ore = is_ore(target);
        const auto tree = profile.material.timber_sites.find(target);
        if (!ore && tree == profile.material.timber_sites.end())
            return refused("unknown_target", target);
        if (!local_available(target)) return refused("unavailable_source", target);
        const auto& center = ore ? profile.material.manual_ore->center : tree->second.center;
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", target);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.manual_cut_reach > 0 ?
            profile.manual_cut_reach : profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {contact(target, center, checked_cut.position)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), target, std::move(facts));
        auto candidate = state;
        const auto error = harvest(candidate, target);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), target, std::move(facts));
        candidate.manual_cuts.erase(binding.actor);
        facts.emplace("generation", Value(Integer{1}));
        facts.emplace("moved_raw", Value(Integer{ore ? 1 : 0}));
        facts.emplace("moved_timber", Value(Integer{ore ? 0 : 1}));
        return accepted(std::move(candidate), target, std::move(facts));
    }

    const bool fast = command.kind == HarvestCommand::Kind::fast;
    if (fast && !state.developer_conveniences) return refused("developer_mode_off");
    const auto& target = command.target;
    const bool ore = is_ore(target);
    const auto tree = profile.material.timber_sites.find(target);
    if (!ore && tree == profile.material.timber_sites.end()) return refused("unknown_target", target);
    if (!local_available(target)) return refused("unavailable_source", target);
    const auto& center = ore ? profile.material.manual_ore->center : tree->second.center;
    const auto cut = observe ? observe(binding.actor) : std::nullopt;
    if (!cut) return refused("actor_unready", target);
    auto checked_cut = *cut;
    checked_cut.build_reach = profile.manual_cut_reach > 0 ?
        profile.manual_cut_reach : profile.build_reach;
    const auto checked = authority::check_reach(binding.actor, checked_cut,
        {contact(target, center, checked_cut.position)});
    auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
    if (checked.error != authority::Error::none)
        return refused(authority::error_name(checked.error), target, std::move(facts));
    if (std::any_of(state.manual_cuts.begin(), state.manual_cuts.end(),
            [&](const auto& entry) { return entry.second.target == target; }))
        return refused("source_busy", target, std::move(facts));
    auto candidate = state;
    const auto error = harvest(candidate, target);
    if (error != materials::Error::none)
        return refused(materials::error_name(error), target, std::move(facts));
    if (!fast) {
        candidate = state;
        candidate.manual_cuts.emplace(binding.actor, State::ManualCut{
            target, snapshot.revision + 1, manual_cut_ticks, 0});
    }
    facts.emplace("generation", Value(Integer{1}));
    facts.emplace("moved_raw", Value(Integer{fast && ore ? 1 : 0}));
    facts.emplace("moved_timber", Value(Integer{fast && !ore ? 1 : 0}));
    return accepted(std::move(candidate), target, std::move(facts));
}

} // namespace factory::world
