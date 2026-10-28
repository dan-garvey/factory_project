#include "crank_planner.hpp"

#include <algorithm>
#include <cmath>
#include <utility>

namespace factory::world {
namespace {
using Action = crank_commands::Action;
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;
} // namespace

std::optional<CrankCommand> crank_command(
        const std::string& action, const Object& intent) {
    const auto parsed = crank_commands::parse(action);
    if (parsed == Action::none) return std::nullopt;
    CrankCommand command;
    command.action = parsed;
    if (const auto* value = field<std::string>(intent, "target")) command.target = *value;
    if (const auto* value = field<Integer>(intent, "generation")) command.generation = *value;
    if (const auto* value = field<std::string>(intent, "crank")) command.crank = *value;
    if (const auto* value = field<Integer>(intent, "crank_generation"))
        command.crank_generation = *value;
    if (const auto* value = field<Value::Array>(intent, "port")) command.port = *value;
    if (const auto* value = field<Value::Array>(intent, "face")) command.face = *value;
    return command;
}

Owner::Decision plan_crank(const Profile& profile, const Binding& binding,
        const Snapshot& snapshot, const CrankCommand& command,
        const ObserveActor& observe) {
    const auto& state = snapshot.state;
    if (command.action == Action::attach || command.action == Action::detach) {
        const bool attaching = command.action == Action::attach;
        const auto* id = (command.target ? &*command.target : nullptr);
        const auto* requested_generation = (command.generation ? &*command.generation : nullptr);
        const auto* crank_id = attaching ? (command.crank ? &*command.crank : nullptr) : id;
        const auto* crank_generation = attaching ?
            (command.crank_generation ? &*command.crank_generation : nullptr) : requested_generation;
        if (!id || !requested_generation || !crank_id || !crank_generation)
            return refused("invalid_target");
        const auto crank = state.crank_items.find(*crank_id);
        if (crank == state.crank_items.end()) return refused("unknown_crank", *crank_id);
        if (crank->second.generation != *crank_generation)
            return refused("stale_generation", *crank_id);
        const auto* port_value = attaching ? (command.port ? &*command.port : nullptr) : nullptr;
        const auto port = attaching ?
            (port_value ? grid_point(Object{{"center", Value(*port_value)}}) : std::nullopt) :
            crank->second.port;
        const auto* requested_face_value = attaching ? (command.face ? &*command.face : nullptr) : nullptr;
        const auto requested_face = requested_face_value ?
            grid_point(Object{{"center", Value(*requested_face_value)}}, 1) : std::nullopt;
        if (requested_face_value && !requested_face) return refused("invalid_crank_face", *id);
        const auto input_id = attaching ? *id : crank->second.attached_to.value_or("");
        const auto input = state.placed_components.find(input_id);
        if (!port || (attaching && (input == state.placed_components.end() ||
            !crank_input_port(input->second, *port))))
            return refused("not_rotary_input", *id);
        if (attaching && input->second.generation != *requested_generation)
            return refused("stale_generation", *id);
        if (!attaching && crank->second.holder) return refused("crank_not_attached", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile, *port)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        auto candidate = state;
        auto& item = candidate.crank_items.at(*crank_id);
        auto& cargo = candidate.material.cargo.at(binding.actor).components;
        Integer carried = 0;
        for (const auto& [kind, count] : cargo) {
            (void)kind;
            if (!add(carried, count)) return refused("inventory_full", *id, std::move(facts));
        }
        if (attaching) {
            if (item.holder != binding.actor) return refused("not_holder", *id, std::move(facts));
            if ((slide_component(input->second.kind) &&
                    !slide_input_port_clear(state, input_id, *port)) ||
                std::any_of(state.crank_items.begin(), state.crank_items.end(),
                    [&](const auto& entry) { return entry.second.port == port; }))
                return refused("input_port_occupied", *id, std::move(facts));
            const auto existing = drive_power(profile, state);
            const auto motion = existing.mechanical.motion.find(input_id);
            if (!existing.mechanical.accepted())
                return refused("input_already_driven", *id, std::move(facts));
            if (motion == existing.mechanical.motion.end())
                return refused("not_rotary_input", *id, std::move(facts));
            const auto axis = existing.crank_axes.find(input_id);
            if (axis == existing.crank_axes.end())
                return refused("not_rotary_input", *id, std::move(facts));
            if (has_self_powered_source(existing, state.topology, input_id))
                return refused("input_already_driven", *id, std::move(facts));
            if (!manual_input_available(motion->second))
                return refused("input_already_driven", *id, std::move(facts));
            mechanics::Point face = requested_face.value_or(
                crank_face_from_actor(profile, cut->position, *port, axis->second));
            if (slide_component(input->second.kind) && !requested_face) {
                face = {(*port)[0] > input->second.center[0] ? 1 : -1, 0, 0};
            }
            if (!crank_face_on_axis(face, axis->second) ||
                (slide_component(input->second.kind) &&
                    face[0] != ((*port)[0] > input->second.center[0] ? 1 : -1)))
                return refused("invalid_crank_face", *id, std::move(facts));
            const auto owned = cargo.find(materials::Component::hand_crank);
            if (owned == cargo.end() || owned->second < 1)
                return refused("no_component", *id, std::move(facts));
            if (--owned->second == 0) cargo.erase(owned);
            ++candidate.material.placed_components[materials::Component::hand_crank];
            item.holder.reset();
            item.attached_to = input_id;
            item.port = *port;
            item.face = face;
        } else {
            if (profile.material.component_capacity > 0 &&
                carried >= profile.material.component_capacity)
                return refused("inventory_full", *id, std::move(facts));
            item.holder = binding.actor;
            item.attached_to.reset();
            item.port.reset();
            item.face.reset();
            ++cargo[materials::Component::hand_crank];
            auto& placed = candidate.material.placed_components.at(materials::Component::hand_crank);
            if (--placed == 0) candidate.material.placed_components.erase(materials::Component::hand_crank);
        }
        facts.emplace("generation", Value(item.generation));
        facts.emplace("input_id", Value(input_id));
        facts.emplace("port_center", Value(Value::Array{
            Value((*port)[0]), Value((*port)[1]), Value((*port)[2])}));
        if (attaching) facts.emplace("face", Value(Value::Array{
            Value((*item.face)[0]), Value((*item.face)[1]), Value((*item.face)[2])}));
        facts.emplace("holder", Value(attaching ? "installed" : binding.actor));
        facts.emplace("component_count", Value(
            cargo.contains(materials::Component::hand_crank) ?
                cargo.at(materials::Component::hand_crank) : Integer{0}));
        return accepted(std::move(candidate), *crank_id, std::move(facts));
    }
    if (command.action == Action::operate) {
        if (!profile.landing_pod_center) return refused("crank_unavailable");
        const auto* crank_id = (command.crank ? &*command.crank : nullptr);
        const auto* crank_generation = (command.crank_generation ? &*command.crank_generation : nullptr);
        const auto* input_id = (command.target ? &*command.target : nullptr);
        const auto* input_generation = (command.generation ? &*command.generation : nullptr);
        const auto* port_value = (command.port ? &*command.port : nullptr);
        const auto port = port_value ?
            grid_point(Object{{"center", Value(*port_value)}}) : std::nullopt;
        const auto* face_value = (command.face ? &*command.face : nullptr);
        const auto face = face_value ?
            grid_point(Object{{"center", Value(*face_value)}}, 1) : std::nullopt;
        if (face_value && !face) return refused("invalid_crank_face", *crank_id);
        if (!crank_id || !crank_generation || !input_id || !input_generation || !port)
            return refused("invalid_target");
        const auto crank = state.crank_items.find(*crank_id);
        if (crank == state.crank_items.end()) return refused("unknown_crank", *crank_id);
        if (crank->second.generation != *crank_generation)
            return refused("stale_generation", *crank_id);
        if (!crank->second.attached_to)
            return refused("crank_disconnected", *crank_id);
        const auto input = state.placed_components.find(*input_id);
        if (input == state.placed_components.end()) return refused("unknown_target", *input_id);
        if (input->second.generation != *input_generation)
            return refused("stale_generation", *input_id);
        if (crank->second.attached_to != *input_id || crank->second.port != port ||
            crank->second.face != face)
            return refused("crank_not_attached", *crank_id);
        if (!crank_input_port(input->second, *port))
            return refused("not_rotary_input", *input_id);
        if (slide_component(input->second.kind) &&
            !slide_input_port_clear(state, *input_id, *port))
            return refused("input_port_occupied", *input_id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *crank_id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile, *port)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *crank_id, std::move(facts));
        const auto existing = drive_power(profile, state);
        if (!existing.mechanical.accepted())
            return refused("invalid_mechanics", *crank_id, std::move(facts));
        if (has_self_powered_source(existing, state.topology, *input_id))
            return refused("input_already_driven", *crank_id, std::move(facts));
        const auto prior_motion = existing.mechanical.motion.find(*input_id);
        if (prior_motion != existing.mechanical.motion.end() &&
            !manual_input_available(prior_motion->second))
            return refused("input_already_driven", *crank_id, std::move(facts));
        const auto powered = hand_crank_power(profile, state, *input_id, *port, face);
        if (!powered.mechanical.accepted())
            return refused("invalid_mechanics", *crank_id, std::move(facts));
        const auto motion = powered.mechanical.motion.find(*input_id);
        if (motion == powered.mechanical.motion.end() ||
            motion->second.state != mechanics::MotionState::rotating)
            return refused("insufficient_drive", *crank_id, std::move(facts));
        facts.emplace("input_id", Value(*input_id));
        facts.emplace("generation", Value(*crank_generation));
        facts.emplace("input_generation", Value(*input_generation));
        facts.emplace("crank_generation", Value(*crank_generation));
        facts.emplace("port_center", Value(Value::Array{
            Value((*port)[0]), Value((*port)[1]), Value((*port)[2])}));
        facts.emplace("rate_numerator", Value(motion->second.rate.numerator));
        facts.emplace("rate_denominator", Value(motion->second.rate.denominator));
        return accepted(state, *crank_id, std::move(facts));
    }
    if (command.action == Action::turn) {
        if (!profile.material.manual_ore || profile.collector_faces.empty())
            return refused("collector_unavailable");
        const auto* id = (command.target ? &*command.target : nullptr);
        const auto* generation = (command.generation ? &*command.generation : nullptr);
        if (!id || !generation) return refused("invalid_target");
        const auto found = state.placed_components.find(*id);
        if (found == state.placed_components.end()) return refused("unknown_target", *id);
        if (found->second.generation != *generation) return refused("stale_generation", *id);
        if (found->second.kind != materials::Component::tool_mount)
            return refused("not_collector_input", *id);
        if (!has_attached_crank(state, *id, found->second.center))
            return refused("crank_not_attached", *id);
        const auto source_power = drive_power(profile, state);
        if (has_self_powered_source(source_power, state.topology, *id))
            return refused("input_already_driven", *id);
        const auto assembly = collector_for_input(profile, assembly_parts(state), *id);
        if (assembly.ambiguous) return refused("ambiguous_assembly", *id);
        if (!assembly.collector) return refused("incomplete_assembly", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile, assembly.collector->shaft_center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        if (state.material.stock.source == 0) return refused("source_depleted", *id, std::move(facts));
        const auto receiver = assembly.collector->receiver_center;
        if (state.material.dropped_material.contains(receiver))
            return refused("receiver_full", *id, std::move(facts));
        if (state.material.dropped_material.size() >= materials::maximum_drop_points)
            return refused("output_full", *id, std::move(facts));
        auto candidate = state;
        --candidate.material.stock.source;
        candidate.material.dropped_material.emplace(receiver, materials::Cargo{1, 0, {}});
        facts.emplace("generation", Value(*generation));
        facts.emplace("shaft_center", Value(Value::Array{Value(assembly.collector->shaft_center[0]),
            Value(assembly.collector->shaft_center[1]), Value(assembly.collector->shaft_center[2])}));
        facts.emplace("receiver_center", Value(Value::Array{Value(receiver[0]),
            Value(receiver[1]), Value(receiver[2])}));
        facts.emplace("receiver_raw", Value(Integer{1}));
        facts.emplace("source_remaining", Value(candidate.material.stock.source));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (command.action == Action::turn_slide) {
        if (!profile.landing_pod_center) return refused("slide_unavailable");
        const auto* id = (command.target ? &*command.target : nullptr);
        const auto* generation = (command.generation ? &*command.generation : nullptr);
        const auto* port_value = (command.port ? &*command.port : nullptr);
        const auto port = port_value ?
            grid_point(Object{{"center", Value(*port_value)}}) : std::nullopt;
        if (!id || !generation || !port) return refused("invalid_target");
        const auto found = state.placed_components.find(*id);
        if (found == state.placed_components.end()) return refused("unknown_target", *id);
        if (found->second.generation != *generation) return refused("stale_generation", *id);
        if (!slide_component(found->second.kind)) return refused("not_slide", *id);
        if (std::none_of(state.crank_items.begin(), state.crank_items.end(),
                [&](const auto& entry) {
                    return entry.second.attached_to == *id && entry.second.port == port;
                })) return refused("crank_not_attached", *id);
        const auto& center = found->second.center;
        if (!crank_input_port(found->second, *port))
            return refused("wrong_input_port", *id);
        if (!slide_input_port_clear(state, *id, *port))
            return refused("input_port_occupied", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile, *port)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        const auto existing = drive_power(profile, state);
        if (!existing.mechanical.accepted())
            return refused("invalid_mechanics", *id, std::move(facts));
        if (has_self_powered_source(existing, state.topology, *id))
            return refused("input_already_driven", *id, std::move(facts));
        const auto prior_motion = existing.mechanical.motion.find(*id);
        if (prior_motion == existing.mechanical.motion.end() ||
            !manual_input_available(prior_motion->second))
            return refused("input_already_driven", *id, std::move(facts));
        const auto powered = hand_crank_power(profile, state, *id, *port);
        if (!powered.mechanical.accepted())
            return refused("invalid_mechanics", *id, std::move(facts));
        const auto motion = powered.mechanical.motion.find(*id);
        if (motion == powered.mechanical.motion.end() ||
            motion->second.state != mechanics::MotionState::rotating)
            return refused("insufficient_drive", *id, std::move(facts));
        auto candidate = state;
        const auto before = candidate.slide_phases.at(*id);
        if (!advance_slide_phase(candidate.slide_phases.at(*id), motion->second.rate))
            return refused("invalid_phase", *id, std::move(facts));
        const auto reaches_bottom = hand_slide_contact(before,
            candidate.slide_phases.at(*id), motion->second.rate);
        if (!reaches_bottom) return refused("invalid_crank_rate", *id, std::move(facts));
        bool formed_contact = false;
        if (*reaches_bottom) {
            const mechanics::Point work{center[0], center[1] - 2, center[2]};
            const auto route = state.slide_press_routes.find(work);
            if (route != state.slide_press_routes.end()) {
                const auto placed_for_inspection = assembly_parts(state);
                const auto inspected = assembly::Layout(placed_for_inspection).inspect_sliding_press(work);
                if (inspected.status == assembly::PressStatus::blocked_feed)
                    return refused("blocked_exit", *id, std::move(facts));
                if (inspected.press && inspected.press->slide == *id) {
                    const auto selected_exit = route->second;
                    if (std::none_of(inspected.press->open_feeds.begin(),
                            inspected.press->open_feeds.end(), [&](const assembly::PressFeed& feed) {
                                return feed.exit == selected_exit;
                            })) return refused("blocked_exit", *id, std::move(facts));
                    const auto previous = state.material.dropped_material.find(work);
                    if (previous == state.material.dropped_material.end())
                        return refused("unavailable_input", *id, std::move(facts));
                    Integer prior_auto = 0;
                    const auto completed_id = previous->second.work_lots.size() == 1 ?
                        previous->second.work_lots.front().id : materials::WorkId{0};
                    if (completed_id > 0) {
                        const auto witness = state.press_progress.find(completed_id);
                        if (witness != state.press_progress.end())
                            prior_auto = witness->second.automatic_remaining_ticks;
                    }
                    const auto error = materials::turn_press(candidate.material, profile.material,
                        material_path(candidate.topology), work, selected_exit, false,
                        materials::PressOutputLocation::supported_work);
                    if (error != materials::Error::none)
                        return refused(materials::error_name(error), *id, std::move(facts));
                    const auto current = candidate.material.dropped_material.find(work);
                    const bool finished = completed_id > 0 &&
                        current != candidate.material.dropped_material.end() &&
                        current->second.raw_units == 0 && current->second.products == 1 &&
                        current->second.work_lots.empty();
                    if (completed_id > 0)
                        candidate.press_progress[completed_id].manual_seen = true;
                    else if (current != candidate.material.dropped_material.end() &&
                             current->second.work_lots.size() == 1)
                        candidate.press_progress[current->second.work_lots.front().id].manual_seen = true;
                    if (finished) {
                        if (!candidate.press_output_on_work.emplace(work,
                                State::SupportedPressOutput{completed_id, selected_exit}).second)
                            return refused("invalid_press_output", *id, std::move(facts));
                        candidate.slide_press_routes.erase(work);
                    }
                    facts.emplace("work_center", Value(Value::Array{Value(work[0]),
                        Value(work[1]), Value(work[2])}));
                    facts.emplace("exit_center", Value(Value::Array{Value(selected_exit[0]),
                        Value(selected_exit[1]), Value(selected_exit[2])}));
                    facts.emplace("prior_work_raw", Value(previous->second.raw_units));
                    facts.emplace("prior_work_lots", lots_value(previous->second.work_lots));
                    facts.emplace("prior_auto_remaining_ticks", Value(prior_auto));
                    facts.emplace("work_raw", Value(current == candidate.material.dropped_material.end() ?
                        Integer{0} : current->second.raw_units));
                    facts.emplace("work_lots", current == candidate.material.dropped_material.end() ?
                        Value(Value::Array{}) : lots_value(current->second.work_lots));
                    facts.emplace("formed_products", Value(finished ? Integer{1} : Integer{0}));
                    facts.emplace("formed_work_id", Value(finished ? completed_id : materials::WorkId{0}));
                    formed_contact = true;
                }
            }
        }
        facts.emplace("generation", Value(*generation));
        facts.emplace("contact", Value(formed_contact));
        facts.emplace("port_center", Value(Value::Array{Value((*port)[0]),
            Value((*port)[1]), Value((*port)[2])}));
        facts.emplace("prior_phase", slide_phase_value(before));
        facts.emplace("slide_phase", slide_phase_value(candidate.slide_phases.at(*id)));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    return refused("invalid_command");
}

} // namespace factory::world
