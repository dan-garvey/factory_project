#include "press_planner.hpp"

#include <algorithm>
#include <utility>

namespace factory::world {
namespace {
using Action = press_commands::Action;
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;
} // namespace

std::optional<PressCommand> press_command(
        const std::string& action, const Object& intent) {
    const auto parsed = press_commands::parse(action);
    if (parsed == Action::none) return std::nullopt;
    PressCommand command;
    command.action = parsed;
    if (const auto* value = field<std::string>(intent, "target")) command.target = *value;
    if (const auto* value = field<Integer>(intent, "generation")) command.generation = *value;
    if (const auto* value = field<Integer>(intent, "sheet_id")) command.sheet_id = *value;
    if (const auto* value = field<Integer>(intent, "work_id")) command.work_id = *value;
    if (const auto* value = field<std::string>(intent, "drive")) command.drive = *value;
    if (const auto* value = field<Value::Array>(intent, "entry")) command.entry = *value;
    if (const auto* value = field<Value::Array>(intent, "exit")) command.exit = *value;
    return command;
}

Owner::Decision plan_press(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const PressCommand& command,
        const ObserveActor& observe) {
    const auto& state = snapshot.state;
    if (command.action == Action::stroke_shear) {
        if (!profile.landing_pod_center || !copper_profile(profile.material) ||
            profile.material.plate_mass <= 0 || profile.material.sheet_mass <= 0 ||
            profile.material.sheet_mass % 4 != 0 ||
            profile.material.sheet_mass / 4 != profile.material.plate_mass)
            return refused("unavailable_recipe");
        const auto* id = (command.target ? &*command.target : nullptr);
        const auto* generation = (command.generation ? &*command.generation : nullptr);
        const auto* sheet_id = (command.sheet_id ? &*command.sheet_id : nullptr);
        if (!id || !generation || !sheet_id || *sheet_id <= 0)
            return refused("invalid_target");
        const auto found = state.placed_components.find(*id);
        if (found == state.placed_components.end()) return refused("unknown_target", *id);
        if (found->second.generation != *generation)
            return refused("stale_generation", *id);
        if (found->second.kind != materials::Component::anvil)
            return refused("not_shear_anvil", *id);
        const auto parts = assembly_parts(state);
        const auto geometry = assembly::Layout(parts).inspect_broad_shear(found->second.center);
        if (!geometry.shear || geometry.shear->anvils.front() != *id)
            return refused("incomplete_shear", *id);
        const auto& shear = *geometry.shear;
        const auto staged = state.material.dropped_material.find(shear.origin);
        if (staged == state.material.dropped_material.end() ||
            staged->second.raw_units != 0 || staged->second.products != 0 ||
            staged->second.offcuts != 0 || staged->second.timber != 0 ||
            !staged->second.components.empty() || !staged->second.work_lots.empty() ||
            staged->second.sheets.size() != 1 ||
            staged->second.sheets.front().id != *sheet_id)
            return refused("unavailable_input", *id);
        const auto previous = state.shear_progress.find(*sheet_id);
        if (previous != state.shear_progress.end() &&
            (previous->second.origin != shear.origin || previous->second.strokes >= 4))
            return refused("incompatible_sheet", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            broad_reach_targets(profile, shear.origin));
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        const auto driven = BroadPressDriveIndex(drive_power(profile, state)).inspect(shear);
        if (driven.status != BroadPressDriveStatus::ready || !driven.stroke_rate ||
            driven.stroke_rate->numerator <= 0)
            return refused("shear_unpowered", *id, std::move(facts));
        if (std::any_of(shear.work_centers.begin() + 1, shear.work_centers.end(),
                [&](const auto& cell) {
                    return state.material.dropped_material.contains(cell);
                })) return refused("output_full", *id, std::move(facts));
        auto candidate = state;
        auto& progress = candidate.shear_progress[*sheet_id];
        progress.origin = shear.origin;
        ++progress.strokes;
        if (progress.strokes == 4) {
            const auto error = materials::shear_sheet(candidate.material, profile.material,
                material_path(candidate.topology), *sheet_id, shear.origin);
            if (error != materials::Error::none)
                return refused(materials::error_name(error), *id, std::move(facts));
        }
        facts.emplace("generation", Value(*generation));
        facts.emplace("sheet_id", Value(*sheet_id));
        facts.emplace("work_center", Value(Value::Array{Value(shear.origin[0]),
            Value(shear.origin[1]), Value(shear.origin[2])}));
        facts.emplace("shear_strokes", Value(progress.strokes));
        facts.emplace("formed_products", Value(progress.strokes == 4 ? Integer{4} : Integer{0}));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (command.action == Action::feed_broad || command.action == Action::refeed_broad) {
        if (!profile.landing_pod_center || !copper_profile(profile.material) ||
            profile.material.sheet_mass != 3 * profile.material.raw_mass)
            return refused("unavailable_recipe");
        const auto* id = (command.target ? &*command.target : nullptr);
        const auto* generation = (command.generation ? &*command.generation : nullptr);
        const bool refeed = command.action == Action::refeed_broad;
        const auto* work_id = refeed ? (command.work_id ? &*command.work_id : nullptr) : nullptr;
        if (!id || !generation || (refeed && (!work_id || *work_id <= 0)))
            return refused("invalid_target");
        const auto found = state.placed_components.find(*id);
        if (found == state.placed_components.end()) return refused("unknown_target", *id);
        if (found->second.generation != *generation) return refused("stale_generation", *id);
        if (found->second.kind != materials::Component::anvil &&
            found->second.kind != materials::Component::broad_anvil)
            return refused("not_press_anvil", *id);
        const auto parts = assembly_parts(state);
        const assembly::Layout layout(parts);
        const auto geometry = layout.inspect_broad_press(found->second.center);
        const auto sized = layout.inspect_broad_sliding_press(found->second.center);
        if ((!geometry.press || geometry.press->anvils.front() != *id) &&
            (!sized.press || sized.press->anvil != *id))
            return refused("incomplete_assembly", *id);
        const auto& origin = found->second.center;
        const auto& work_centers = sized.press ? sized.press->work_centers :
            geometry.press->work_centers;
        for (const auto& center : work_centers)
            if (state.material.dropped_material.contains(center))
                return refused("input_full", *id);
        for (const auto& [point, cargo] : state.material.dropped_material) {
            if (!broad_item(cargo)) continue;
            const auto occupied = broad_cells(point);
            if (std::any_of(work_centers.begin(), work_centers.end(),
                    [&](const auto& cell) {
                        return std::find(occupied.begin(), occupied.end(), cell) != occupied.end();
                    })) return refused("input_full", *id);
        }
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            broad_reach_targets(profile, origin));
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        const auto& cargo = state.material.cargo.at(binding.actor);
        const auto lot = refeed ? std::find_if(cargo.work_lots.begin(), cargo.work_lots.end(),
            [&](const materials::WorkLot& item) { return item.id == *work_id; }) : cargo.work_lots.end();
        if (refeed && (lot == cargo.work_lots.end() ||
            lot->recipe != materials::RecipeSignature{3, profile.material.cycle_ticks,
                materials::WorkOutput::sheet}))
            return refused("incompatible_work", *id, std::move(facts));
        auto candidate = state;
        const auto error = materials::feed_broad_press(candidate.material, profile.material,
            material_path(candidate.topology), binding.actor, origin,
            refeed ? std::optional<materials::WorkId>(*work_id) : std::nullopt);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), *id, std::move(facts));
        if (!refeed) candidate.press_progress.try_emplace(
            candidate.material.dropped_material.at(origin).work_lots.front().id);
        else candidate.press_progress.at(*work_id).refeed_seen = true;
        facts.emplace("generation", Value(*generation));
        facts.emplace("work_center", Value(Value::Array{Value(origin[0]),
            Value(origin[1]), Value(origin[2])}));
        if (refeed) facts.emplace("moved_work", lots_value({*lot}));
        else {
            facts.emplace("moved_raw", Value(Integer{3}));
            facts.emplace("formed_work_id", Value(candidate.material.dropped_material.at(
                origin).work_lots.front().id));
        }
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (command.action == Action::feed || command.action == Action::refeed ||
        command.action == Action::compact) {
        const bool refeed_work = command.action == Action::refeed;
        const bool compacting = command.action == Action::compact;
        if (!profile.landing_pod_center) return refused("press_unavailable");
        const auto* id = (command.target ? &*command.target : nullptr);
        const auto* generation = (command.generation ? &*command.generation : nullptr);
        const auto* entry = (command.entry ? &*command.entry : nullptr);
        const auto* drive = compacting ? (command.drive ? &*command.drive : nullptr) : nullptr;
        const auto* work_id = refeed_work ? (command.work_id ? &*command.work_id : nullptr) : nullptr;
        if (!id || !generation || !entry || (compacting && !drive))
            return refused("invalid_target");
        if (refeed_work && (!work_id || *work_id <= 0)) return refused("invalid_work_id", *id);
        const auto selected_entry = grid_point(Object{{"center", Value(*entry)}});
        if (!selected_entry) return refused("invalid_entry", *id);
        const auto frame = state.placed_components.find(*id);
        if (frame == state.placed_components.end()) return refused("unknown_target", *id);
        if (frame->second.generation != *generation) return refused("stale_generation", *id);
        if (frame->second.kind != materials::Component::wooden_frame &&
            frame->second.kind != materials::Component::anvil)
            return refused("not_press_frame", *id);
        const auto parts = assembly_parts(state);
        const auto inspected = inspect_working_press(assembly::Layout(parts),
            frame->second.kind, frame->second.center);
        if (inspected.status == assembly::PressStatus::ambiguous)
            return refused("ambiguous_assembly", *id);
        if (inspected.status == assembly::PressStatus::blocked_feed)
            return refused("blocked_feed", *id);
        if (!inspected.press || inspected.press->anchor != *id)
            return refused("incomplete_assembly", *id);
        if (compacting && inspected.press->sliding)
            return refused("slide_requires_contact_stroke", *id);
        if (compacting && (!copper_profile(profile.material) ||
            profile.material.input_units_per_product != 1))
            return refused("unavailable_recipe", *id);
        if (compacting && inspected.press->shaft != *drive)
            return refused("wrong_drive_shaft", *id);
        if (compacting && !has_attached_crank(state, *drive, inspected.press->shaft_center))
            return refused("crank_not_attached", *id);
        const auto selected_feed = std::find_if(inspected.press->open_feeds.begin(),
            inspected.press->open_feeds.end(), [&](const assembly::PressFeed& feed) {
                return feed.entry == *selected_entry;
            });
        if (selected_feed == inspected.press->open_feeds.end())
            return refused("blocked_feed", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        std::vector<authority::Point> reach_targets{anchor(profile, *selected_entry)};
        if (compacting) reach_targets.push_back(anchor(profile, inspected.press->shaft_center));
        const auto checked = authority::check_reach(binding.actor, checked_cut, reach_targets);
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        const auto& carried = state.material.cargo.at(binding.actor);
        const auto selected_work = refeed_work ? std::find_if(carried.work_lots.begin(),
            carried.work_lots.end(), [&](const materials::WorkLot& lot) { return lot.id == *work_id; }) :
            carried.work_lots.end();
        if (refeed_work) {
            if (selected_work == carried.work_lots.end())
                return refused("unavailable_work", *id, std::move(facts));
            if (selected_work->recipe != materials::RecipeSignature{
                    profile.material.input_units_per_product, profile.material.cycle_ticks} ||
                !state.press_progress.contains(*work_id))
                return refused("incompatible_work", *id, std::move(facts));
        } else if (compacting && carried.offcuts < profile.material.raw_mass) {
            return refused("unavailable_input", *id, std::move(facts));
        } else if (!compacting && carried.raw_units < 1) {
            return refused("unavailable_input", *id, std::move(facts));
        }
        const auto work = inspected.press->work_center;
        for (const auto& [point, item] : state.material.dropped_material) {
            if (!broad_item(item)) continue;
            const auto cells = broad_cells(point);
            if (std::find(cells.begin(), cells.end(), work) != cells.end())
                return refused("broad_work_occupied", *id, std::move(facts));
        }
        if (state.material.dropped_material.contains(work))
            return refused("input_full", *id, std::move(facts));
        if (state.material.dropped_material.size() >= materials::maximum_drop_points)
            return refused("output_full", *id, std::move(facts));
        auto candidate = state;
        if (inspected.press->sliding &&
            !candidate.slide_press_routes.emplace(work, selected_feed->exit).second)
            return refused("input_full", *id, std::move(facts));
        if (refeed_work) {
            const auto lot = *selected_work;
            auto& next_lots = candidate.material.cargo.at(binding.actor).work_lots;
            next_lots.erase(std::find_if(next_lots.begin(), next_lots.end(),
                [&](const materials::WorkLot& item) { return item.id == *work_id; }));
            candidate.material.dropped_material.emplace(work,
                materials::Cargo{0, 0, std::vector<materials::WorkLot>{lot}});
            candidate.press_progress.at(*work_id).refeed_seen = true;
            facts.emplace("moved_work", lots_value(std::vector<materials::WorkLot>{lot}));
        } else if (compacting) {
            const auto error = materials::compact_offcuts(candidate.material, profile.material,
                material_path(candidate.topology), binding.actor, work);
            if (error != materials::Error::none)
                return refused(materials::error_name(error), *id, std::move(facts));
            facts.emplace("moved_offcuts", Value(profile.material.raw_mass));
            facts.emplace("formed_raw", Value(Integer{1}));
            facts.emplace("shaft_center", Value(Value::Array{
                Value(inspected.press->shaft_center[0]), Value(inspected.press->shaft_center[1]),
                Value(inspected.press->shaft_center[2])}));
        } else {
            --candidate.material.cargo.at(binding.actor).raw_units;
            candidate.material.dropped_material.emplace(work, materials::Cargo{1, 0, {}});
            facts.emplace("moved_raw", Value(Integer{1}));
        }
        facts.emplace("generation", Value(*generation));
        facts.emplace("work_center", Value(Value::Array{Value(work[0]), Value(work[1]), Value(work[2])}));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (command.action == Action::turn) {
        if (!profile.landing_pod_center) return refused("press_unavailable");
        const auto* id = (command.target ? &*command.target : nullptr);
        const auto* generation = (command.generation ? &*command.generation : nullptr);
        const auto* drive = (command.drive ? &*command.drive : nullptr);
        const auto* exit = (command.exit ? &*command.exit : nullptr);
        if (!id || !generation || !drive || !exit) return refused("invalid_target");
        const auto selected_exit = grid_point(Object{{"center", Value(*exit)}});
        if (!selected_exit) return refused("invalid_exit", *id);
        const auto frame = state.placed_components.find(*id);
        if (frame == state.placed_components.end()) return refused("unknown_target", *id);
        if (frame->second.generation != *generation) return refused("stale_generation", *id);
        if (frame->second.kind != materials::Component::wooden_frame &&
            frame->second.kind != materials::Component::anvil)
            return refused("not_press_frame", *id);
        const auto parts = assembly_parts(state);
        const auto inspected = inspect_working_press(assembly::Layout(parts),
            frame->second.kind, frame->second.center);
        if (inspected.status == assembly::PressStatus::ambiguous)
            return refused("ambiguous_assembly", *id);
        if (!inspected.press || inspected.press->anchor != *id)
            return refused("incomplete_assembly", *id);
        if (inspected.press->sliding)
            return refused("slide_requires_contact_stroke", *id);
        if (inspected.press->shaft != *drive) return refused("wrong_drive_shaft", *id);
        if (!has_attached_crank(state, *drive, inspected.press->shaft_center))
            return refused("crank_not_attached", *id);
        if (std::none_of(inspected.press->open_feeds.begin(), inspected.press->open_feeds.end(),
                [&](const assembly::PressFeed& feed) { return feed.exit == *selected_exit; }))
            return refused("blocked_exit", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile, inspected.press->shaft_center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        auto candidate = state;
        const auto previous_work = state.material.dropped_material.find(inspected.press->work_center);
        Integer prior_auto_remaining_ticks = 0;
        if (previous_work != state.material.dropped_material.end()) {
            facts.emplace("prior_work_raw", Value(previous_work->second.raw_units));
            facts.emplace("prior_work_lots", lots_value(previous_work->second.work_lots));
            if (previous_work->second.work_lots.size() == 1) {
                const auto witness = state.press_progress.find(previous_work->second.work_lots.front().id);
                if (witness != state.press_progress.end())
                    prior_auto_remaining_ticks = witness->second.automatic_remaining_ticks;
            }
        }
        facts.emplace("prior_auto_remaining_ticks", Value(prior_auto_remaining_ticks));
        const auto completed_id = previous_work != state.material.dropped_material.end() &&
            previous_work->second.work_lots.size() == 1 ?
            previous_work->second.work_lots.front().id : materials::WorkId{0};
        const auto error = materials::turn_press(candidate.material, profile.material,
            material_path(candidate.topology), inspected.press->work_center, *selected_exit,
            inspected.press->plate_receiver == selected_exit);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), *id, std::move(facts));
        const auto work_item = candidate.material.dropped_material.find(inspected.press->work_center);
        const bool finished = completed_id > 0 &&
            (work_item == candidate.material.dropped_material.end() ||
             (work_item->second.offcuts == profile.material.raw_mass - profile.material.plate_mass &&
              work_item->second.raw_units == 0 && work_item->second.products == 0 &&
              work_item->second.sheets.empty() && work_item->second.work_lots.empty()));
        if (completed_id > 0) {
            candidate.press_progress[completed_id].manual_seen = true;
        } else if (work_item != candidate.material.dropped_material.end() &&
                   work_item->second.work_lots.size() == 1) {
            candidate.press_progress[work_item->second.work_lots.front().id].manual_seen = true;
        }
        const auto belt_work = candidate.belt_press_work.find(inspected.press->work_center);
        if (belt_work != candidate.belt_press_work.end()) {
            if (finished) {
                if (completed_id <= 0 ||
                    !candidate.belt_press_products[*selected_exit].insert(completed_id).second)
                    return refused("invalid_press_output", *id, std::move(facts));
                candidate.belt_press_work.erase(belt_work);
            } else if (work_item->second.work_lots.size() == 1) {
                belt_work->second = work_item->second.work_lots.front().id;
                candidate.belt_press_work_ids.insert(belt_work->second);
            }
        }
        if (finished) {
            if (completed_id <= 0) return refused("invalid_press_output", *id, std::move(facts));
            if (inspected.press->plate_receiver == selected_exit) {
                if (!candidate.press_output_at_receiver[*selected_exit].insert(completed_id).second)
                    return refused("invalid_press_output", *id, std::move(facts));
            } else if (!candidate.press_output_at_exit.emplace(*selected_exit, completed_id).second)
                return refused("invalid_press_output", *id, std::move(facts));
        }
        facts.emplace("generation", Value(*generation));
        facts.emplace("shaft_center", Value(Value::Array{Value(inspected.press->shaft_center[0]),
            Value(inspected.press->shaft_center[1]), Value(inspected.press->shaft_center[2])}));
        facts.emplace("work_center", Value(Value::Array{Value(inspected.press->work_center[0]),
            Value(inspected.press->work_center[1]), Value(inspected.press->work_center[2])}));
        facts.emplace("exit_center", Value(Value::Array{Value((*selected_exit)[0]),
            Value((*selected_exit)[1]), Value((*selected_exit)[2])}));
        facts.emplace("work_raw", Value(work_item == candidate.material.dropped_material.end() ?
            Integer{0} : work_item->second.raw_units));
        facts.emplace("work_lots", work_item == candidate.material.dropped_material.end() ?
            Value(Value::Array{}) : lots_value(work_item->second.work_lots));
        facts.emplace("formed_products", Value(finished ?
            Integer{1} : Integer{0}));
        facts.emplace("formed_work_id", Value(finished ?
            completed_id : materials::WorkId{0}));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    return refused("invalid_command");
}

} // namespace factory::world
