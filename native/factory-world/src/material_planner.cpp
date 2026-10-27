#include "material_planner.hpp"

#include <algorithm>
#include <utility>

namespace factory::world {
namespace {
using Action = material_commands::Action;
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;

std::optional<mechanics::Point> drop_point(const Object& intent, const char* name) {
    const auto* value = field<Value::Array>(intent, name);
    return value ? grid_point(Object{{"center", Value(*value)}},
        materials::maximum_drop_coordinate) : std::nullopt;
}
} // namespace

std::optional<MaterialCommand> material_command(
        const std::string& action, const Object& intent) {
    const auto selected = material_commands::parse(action);
    if (selected == Action::none) return std::nullopt;
    MaterialCommand command;
    command.action = selected;
    if (selected == Action::pickup || selected == Action::place_sheet)
        command.center = drop_point(intent, "center");
    if (selected == Action::push_sheet || selected == Action::push_small) {
        command.from = drop_point(intent, "from");
        command.to = drop_point(intent, "to");
    }
    if (selected == Action::pickup) {
        const auto* expected = field<Object>(intent, "expected");
        if (!expected) return std::nullopt;
        command.expected = *expected;
    }
    if (selected == Action::place_sheet || selected == Action::push_sheet) {
        const auto* sheet_id = field<Integer>(intent, "sheet_id");
        if (!sheet_id) return std::nullopt;
        command.sheet_id = *sheet_id;
    }
    if (selected == Action::push_small) {
        const auto* form = field<std::string>(intent, "form");
        if (!form) return std::nullopt;
        command.form = *form;
    }
    return command;
}

Owner::Decision plan_material(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const MaterialCommand& command,
        const ObserveActor& observe) {
    const auto& state = snapshot.state;
    if (command.action == Action::pickup) {
        const auto& point = command.center;
        if (!point) return refused("invalid_center");
        const auto located = state.material.dropped_material.find(*point);
        const bool broad_drop = located != state.material.dropped_material.end() &&
            broad_item(located->second);
        if (!observe) return refused("actor_unready");
        auto cut = observe(binding.actor);
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile.build_reach;
        std::vector<authority::Point> reach_targets = broad_drop ?
            broad_reach_targets(profile, *point) :
            std::vector<authority::Point>{anchor(profile, *point)};
        auto reach = authority::check_reach(binding.actor, *cut, reach_targets);
        Object facts = reach.receipt ? reach_facts(binding, *reach.receipt) : Object{};
        if (reach.error != authority::Error::none)
            return refused(authority::error_name(reach.error), "", std::move(facts));
        const auto found = located;
        if (found == state.material.dropped_material.end())
            return refused("unavailable_drop", "", std::move(facts));
        if (values::typed_difference(Value(command.expected),
                belt_cargo_value(found->second, copper_profile(profile.material))))
            return refused("drop_changed", "", std::move(facts));
        const auto contents = found->second;
        const auto press_witness = state.press_output_at_exit.find(*point);
        const auto press_work_id = press_witness == state.press_output_at_exit.end() ?
            materials::WorkId{0} : press_witness->second;
        const auto plate_receiver = state.press_output_at_receiver.find(*point);
        if (plate_receiver != state.press_output_at_receiver.end() &&
            (contents.raw_units != 0 || contents.products !=
                static_cast<Integer>(plate_receiver->second.size()) ||
             contents.offcuts != 0 || contents.timber != 0 ||
             !contents.components.empty() || !contents.work_lots.empty() ||
             !contents.sheets.empty() || press_work_id != 0))
            return refused("invalid_state", "", std::move(facts));
        State candidate = state;
        const auto error = materials::pickup_material(candidate.material, profile.material,
            material_path(candidate.topology), binding.actor, *point);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), "", std::move(facts));
        candidate.slide_press_routes.erase(*point);
        if (contents.products == 1) {
            const auto witness = candidate.press_output_at_exit.find(*point);
            if (witness != candidate.press_output_at_exit.end()) {
                const auto belt_claim = candidate.belt_press_products.find(*point);
                if (belt_claim != candidate.belt_press_products.end() &&
                    belt_claim->second.erase(witness->second) != 0 && belt_claim->second.empty())
                    candidate.belt_press_products.erase(belt_claim);
                candidate.press_output_at_exit.erase(witness);
            }
        }
        if (plate_receiver != state.press_output_at_receiver.end()) {
            Value::Array identities;
            auto belt_claim = candidate.belt_press_products.find(*point);
            for (const auto id : plate_receiver->second) {
                identities.emplace_back(id);
                if (belt_claim != candidate.belt_press_products.end()) belt_claim->second.erase(id);
            }
            if (belt_claim != candidate.belt_press_products.end() && belt_claim->second.empty())
                candidate.belt_press_products.erase(belt_claim);
            facts.emplace("press_output_work_ids", Value(std::move(identities)));
            candidate.press_output_at_receiver.erase(*point);
        }
        candidate.belt_press_work.erase(*point);
        facts.emplace("generation", Value(Integer{0}));
        facts.emplace("moved_raw", Value(contents.raw_units));
        facts.emplace("moved_products", Value(contents.products));
        if (copper_profile(profile.material)) {
            facts.emplace("moved_offcuts", Value(contents.offcuts));
            facts.emplace("moved_sheets", Value(static_cast<Integer>(contents.sheets.size())));
            if (!contents.sheets.empty()) {
                Value::Array sheet_items;
                for (const auto& sheet : contents.sheets)
                    sheet_items.emplace_back(Object{{"id", Value(sheet.id)},
                        {"rotation", Value(sheet.rotation)}});
                facts.emplace("moved_sheet_items", Value(std::move(sheet_items)));
            }
        }
        facts.emplace("moved_work", lots_value(contents.work_lots));
        facts.emplace("press_output_work_id", Value(press_work_id));
        return accepted(std::move(candidate), "", std::move(facts));
    }
    if (command.action == Action::place_sheet) {
        if (!profile.landing_pod_center || !copper_profile(profile.material) ||
            profile.material.sheet_mass == 0) return refused("unavailable_recipe");
        const auto& origin = command.center;
        const auto id = command.sheet_id;
        if (!origin || (*origin)[0] % 4 || (*origin)[2] % 4 || id <= 0 ||
            (*origin)[0] > materials::maximum_drop_coordinate - 4 ||
            (*origin)[2] > materials::maximum_drop_coordinate - 4)
            return refused("invalid_sheet_target");
        // The current sheet is square, so all four saved orientations require
        // the same supports. Check the site before disclosing carried identity.
        const auto footprint = materials::sheet_footprint();
        const auto occupied = materials::occupied_workcells(*origin, footprint, 0);
        if (!occupied) return refused("invalid_sheet_target");
        const auto& cells = *occupied;
        std::vector<materials::DropPoint> supports;
        const bool sized_bed = std::any_of(state.placed_components.begin(),
            state.placed_components.end(), [&](const auto& entry) {
                return entry.second.kind == materials::Component::broad_anvil &&
                    entry.second.center == *origin;
            });
        for (const auto& cell : cells) {
            if (sized_bed || std::any_of(state.placed_components.begin(), state.placed_components.end(),
                    [&](const auto& entry) {
                        return entry.second.kind == materials::Component::anvil &&
                            entry.second.center == cell;
                    })) supports.push_back(cell);
            if (state.material.dropped_material.contains(cell))
                return refused("occupied");
        }
        if (!materials::fits_supported_workcells(*origin, footprint, 0, supports))
            return refused("missing_support");
        for (const auto& [point, cargo] : state.material.dropped_material) {
            if (!broad_item(cargo)) continue;
            const auto other_cells = broad_cells(point);
            if (std::any_of(cells.begin(), cells.end(), [&](const auto& cell) {
                    return std::find(other_cells.begin(), other_cells.end(), cell) != other_cells.end();
                })) return refused("occupied");
        }
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            broad_reach_targets(profile, *origin));
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), "", std::move(facts));
        const auto& carried = state.material.cargo.at(binding.actor).sheets;
        const auto sheet = std::find_if(carried.begin(), carried.end(),
            [&](const auto& item) { return item.id == id; });
        if (sheet == carried.end()) return refused("unavailable_input", "", std::move(facts));
        const auto rotation = sheet->rotation;
        auto candidate = state;
        const auto error = materials::place_sheet(candidate.material, profile.material,
            material_path(candidate.topology), binding.actor, id, *origin);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), "", std::move(facts));
        facts.emplace("generation", Value(Integer{0}));
        facts.emplace("sheet_id", Value(id));
        facts.emplace("rotation", Value(rotation));
        return accepted(std::move(candidate), "", std::move(facts));
    }
    const bool sheet_move = command.action == Action::push_sheet;
    if (!profile.landing_pod_center ||
        (sheet_move && (!copper_profile(profile.material) ||
            profile.material.sheet_mass == 0)))
        return refused("unavailable_recipe");
    const auto& from = command.from;
    const auto& to = command.to;
    const auto requested_id = command.sheet_id;
    const auto& requested_form = command.form;
    if (!from || !to || (sheet_move ? requested_id <= 0 :
            (requested_form != "raw" && requested_form != "plate" &&
             requested_form != "offcut")) ||
        !channel_swept_cells(*from, *to,
            sheet_move ? materials::sheet_footprint() : materials::Footprint{1, 1},
            0, !sheet_move))
        return refused("invalid_channel_target");
    const auto source = state.material.dropped_material.find(*from);
    const auto item = source == state.material.dropped_material.end() ?
        std::nullopt : materials::single_loose_item(source->second);
    const auto form_matches = item && (sheet_move ?
        item->form == materials::LooseForm::sheet && item->id == requested_id :
        (item->form == materials::LooseForm::raw && requested_form == "raw") ||
        (item->form == materials::LooseForm::plate && requested_form == "plate") ||
        (item->form == materials::LooseForm::offcut && requested_form == "offcut"));
    if (!form_matches) return refused("unavailable_input");
    if (sheet_move && state.shear_progress.contains(requested_id))
        return refused("partial_shear");
    const auto swept = channel_swept_cells(*from, *to,
        item->footprint, item->rotation, !sheet_move);
    if (!swept) return refused("invalid_channel_target");
    if (!sheet_move && ((*from)[0] % 4 || (*from)[2] % 4) &&
        std::none_of(state.placed_components.begin(), state.placed_components.end(),
            [&](const auto& entry) {
                return entry.second.kind == materials::Component::receiver_tray &&
                    entry.second.center == *from;
            })) return refused("invalid_channel_target");
    const std::size_t travel_axis = (*from)[0] != (*to)[0] ? 0 : 2;
    std::vector<materials::DropPoint> supports;
    bool channel_seen = false;
    for (const auto& [id, placed] : state.placed_components) {
        (void)id;
        if (placed.kind == materials::Component::anvil ||
            (!sheet_move && placed.kind == materials::Component::receiver_tray)) {
            supports.push_back(placed.center);
            continue;
        }
        const auto spec = materials::channel_spec(placed.kind);
        if (!spec || spec->travel_axis != travel_axis ||
            (travel_axis == 0 ? spec->floor.z_cells < item->footprint.z_cells :
                spec->floor.x_cells < item->footprint.x_cells)) continue;
        const auto cells = materials::channel_workcells(placed.kind, placed.center);
        if (!cells) return refused("invalid_mechanics");
        for (const auto& cell : *cells) {
            supports.push_back(cell);
            if (std::find(swept->begin(), swept->end(), cell) != swept->end())
                channel_seen = true;
        }
    }
    if (!channel_seen) return refused("missing_channel");
    std::vector<materials::DropPoint> blocked;
    for (const auto& [point, cargo] : state.material.dropped_material) {
        if (point == *from) continue;
        if (broad_item(cargo)) {
            const auto cells = broad_cells(point);
            blocked.insert(blocked.end(), cells.begin(), cells.end());
        } else blocked.push_back(point);
    }
    for (const auto& [id, placed] : state.placed_components) {
        (void)id;
        if (placed.kind == materials::Component::anvil ||
            (!sheet_move && placed.kind == materials::Component::receiver_tray) ||
            materials::channel_spec(placed.kind)) continue;
        if (placed.center[1] >= (*from)[1] &&
            placed.center[1] <= (*from)[1] + 3)
            blocked.push_back(placed.center);
    }
    for (const auto& part : state.topology.parts)
        if (part.geometry.center[1] >= (*from)[1] &&
            part.geometry.center[1] <= (*from)[1] + 3)
            blocked.push_back(part.geometry.center);
    if (!channel_cells_fit(*swept, supports, blocked))
        return refused("blocked_channel");
    const auto cut = observe ? observe(binding.actor) : std::nullopt;
    if (!cut) return refused("actor_unready");
    auto checked_cut = *cut;
    checked_cut.build_reach = profile.build_reach;
    auto targets = sheet_move ? broad_reach_targets(profile, *from) :
        std::vector<authority::Point>{anchor(profile, *from)};
    if (sheet_move) {
        const auto receiver_targets = broad_reach_targets(profile, *to);
        targets.insert(targets.end(), receiver_targets.begin(), receiver_targets.end());
    } else targets.push_back(anchor(profile, *to));
    const auto checked = authority::check_reach(binding.actor, checked_cut, targets);
    auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
    if (checked.error != authority::Error::none)
        return refused(authority::error_name(checked.error), "", std::move(facts));
    auto candidate = state;
    const auto error = materials::move_loose_item(candidate.material, profile.material,
        material_path(candidate.topology), *from, *to);
    if (error != materials::Error::none)
        return refused(materials::error_name(error), "", std::move(facts));
    if (!sheet_move && item->form == materials::LooseForm::plate) {
        auto witness = candidate.press_output_at_exit.extract(*from);
        if (!witness.empty()) {
            witness.key() = *to;
            if (!candidate.press_output_at_exit.insert(std::move(witness)).inserted)
                return refused("blocked_channel", "", std::move(facts));
        } else if (const auto received = candidate.press_output_at_receiver.find(*from);
                   received != candidate.press_output_at_receiver.end()) {
            if (received->second.size() != 1 ||
                !candidate.press_output_at_exit.emplace(*to,
                    *received->second.begin()).second)
                return refused("blocked_channel", "", std::move(facts));
            candidate.press_output_at_receiver.erase(received);
        }
    }
    facts.emplace("generation", Value(Integer{0}));
    if (sheet_move) {
        facts.emplace("sheet_id", Value(requested_id));
        facts.emplace("rotation", Value(item->rotation));
    } else facts.emplace("form", Value(requested_form));
    facts.emplace("from", grid_value(*from));
    facts.emplace("to", grid_value(*to));
    return accepted(std::move(candidate), "", std::move(facts));
}

} // namespace factory::world
