#include "factory/stationary.hpp"

#include <algorithm>
#include <limits>
#include <set>
#include <utility>

namespace factory::stationary {
namespace {

bool identity(const std::string& id) noexcept {
    return !id.empty() && id.size() <= 128 && id.find('\0') == std::string::npos;
}

bool valid_spec(const PartSpec& spec) noexcept {
    switch (spec.role) {
        case Role::collector:
        case Role::belt:
        case Role::processor:
        case Role::waterwheel:
            return spec.teeth == 0 && spec.half_span == 0;
        case Role::gear:
            return spec.teeth > 0 && spec.teeth <= mechanics::maximum_dimension &&
                   spec.half_span == 0;
        case Role::shaft:
            return spec.teeth == 0 && spec.half_span > 0 &&
                   spec.half_span <= mechanics::maximum_dimension;
    }
    return false;
}

PartSpec specification(const PlacedPart& part) noexcept {
    return {part.role, part.geometry.teeth, part.geometry.half_span};
}

const PlacedPart* find(const Topology& topology, const std::string& id) noexcept {
    const auto found = std::find_if(topology.parts.begin(), topology.parts.end(),
        [&](const auto& part) { return part.geometry.id == id; });
    return found == topology.parts.end() ? nullptr : &*found;
}

bool current_ref(const Topology& topology, const materials::EntityRef& ref) noexcept {
    if (!identity(ref.id) || ref.generation <= 0) return false;
    const auto* part = find(topology, ref.id);
    return part != nullptr && part->generation == ref.generation;
}

bool has_role(const Topology& topology, Role role) noexcept {
    return std::any_of(topology.parts.begin(), topology.parts.end(),
        [&](const auto& part) { return part.role == role; });
}

bool overlapping_shafts(const PlacedPart& a, const PlacedPart& b) noexcept {
    if (a.role != Role::shaft || b.role != Role::shaft || a.geometry.axis != b.geometry.axis)
        return false;
    const auto axis = static_cast<std::size_t>(a.geometry.axis);
    if (axis >= 3) return false; // The mechanics evaluator diagnoses invalid axes.
    for (std::size_t i = 0; i < 3; ++i) {
        if (a.geometry.center[i] < -mechanics::maximum_coordinate || a.geometry.center[i] > mechanics::maximum_coordinate ||
            b.geometry.center[i] < -mechanics::maximum_coordinate || b.geometry.center[i] > mechanics::maximum_coordinate)
            return false; // Avoid arithmetic on invalid coordinates.
        if (i != axis && a.geometry.center[i] != b.geometry.center[i]) return false;
    }
    return a.geometry.center[axis] - a.geometry.half_span < b.geometry.center[axis] + b.geometry.half_span &&
           b.geometry.center[axis] - b.geometry.half_span < a.geometry.center[axis] + a.geometry.half_span;
}

// Reject size/identity profiles before copying any caller-controlled string.
// Geometry dimensions/axes/coordinates are validated by the shared evaluator.
bool structure(const Topology& topology) {
    if (topology.parts.size() > mechanics::maximum_parts ||
        topology.sources.size() > topology.parts.size() ||
        topology.material_links.size() > 2 || topology.belt_spans.size() > mechanics::maximum_parts) return false;

    std::set<std::string> ids;
    std::set<Role> machines;
    for (const auto& part : topology.parts) {
        if (!identity(part.geometry.id) || part.generation <= 0 ||
            !valid_spec(specification(part))) return false;
        const auto expected = part.role == Role::gear ? mechanics::Kind::gear :
                              part.role == Role::shaft ? mechanics::Kind::shaft :
                              mechanics::Kind::hub;
        if (part.geometry.kind != expected || !ids.insert(part.geometry.id).second)
            return false;
        if ((part.role == Role::collector || part.role == Role::belt ||
             part.role == Role::processor) && !machines.insert(part.role).second)
            return false;
    }
    for (const auto& span : topology.belt_spans)
        if (!identity(span.geometry.id) || span.generation <= 0 || !ids.insert(span.geometry.id).second)
            return false;

    for (std::size_t i = 0; i < topology.parts.size(); ++i)
        for (std::size_t j = i + 1; j < topology.parts.size(); ++j)
            if (overlapping_shafts(topology.parts[i], topology.parts[j])) return false;

    std::set<std::pair<std::string, std::string>> links;
    for (const auto& link : topology.material_links) {
        if (!current_ref(topology, link.from) || !current_ref(topology, link.to))
            return false;
        const auto from = find(topology, link.from.id)->role;
        const auto to = find(topology, link.to.id)->role;
        if (!((from == Role::collector && to == Role::belt) ||
              (from == Role::belt && to == Role::processor)) ||
            !links.emplace(link.from.id, link.to.id).second) return false;
    }

    std::set<std::string> sources;
    for (const auto& source : topology.sources) {
        if (!identity(source.hub) || source.rate.denominator <= 0) return false;
        const auto* part = find(topology, source.hub);
        if (part == nullptr || part->role != Role::waterwheel ||
            !sources.insert(source.hub).second) return false;
    }
    return true;
}

bool valid_kit(const Topology& topology, const Kit& kit) {
    if (kit.size() > maximum_specifications) return false;
    std::set<PartSpec> all;
    for (const auto& [spec, count] : kit) {
        if (!valid_spec(spec) || count < 0) return false;
        all.insert(spec);
    }
    for (const auto& part : topology.parts) {
        all.insert(specification(part));
        if (all.size() > maximum_specifications) return false;
    }
    if (!topology.belt_spans.empty()) all.insert({Role::belt, 0, 0});
    if (all.size() > maximum_specifications) return false;
    return true;
}

// World already validates weighted conservation, work identity and recipe.
// Only machine membership is checked here; actor Cargo is never another slot.
bool material_membership(const Topology& topology, const materials::State& state) noexcept {
    return (has_role(topology, Role::collector) || state.stock.collector == 0) &&
           (has_role(topology, Role::belt) || state.stock.belt == 0) &&
           (has_role(topology, Role::processor) ||
               (state.stock.input == 0 && state.stock.output == 0 && !state.processing));
}

bool occupied(Role role, const materials::State& state) noexcept {
    switch (role) {
        case Role::collector: return state.stock.collector != 0;
        case Role::belt: return state.stock.belt != 0;
        case Role::processor:
            return state.stock.input != 0 || state.stock.output != 0 ||
                   state.processing.has_value();
        case Role::waterwheel:
        case Role::gear:
        case Role::shaft: return false;
    }
    return true;
}

RemovalPlan refuse(RemovalError reason,
                   materials::Error material_error = materials::Error::none,
                   mechanics::Error mechanical_error = mechanics::Error::none) {
    return RemovalRefusal{reason, material_error, mechanical_error};
}

mechanics::Result rejected_geometry() {
    mechanics::Result result;
    result.error = mechanics::Error::invalid_part;
    return result;
}

}  // namespace

const char* removal_error_name(RemovalError error) noexcept {
    switch (error) {
        case RemovalError::invalid_topology: return "invalid_topology";
        case RemovalError::invalid_kit: return "invalid_kit";
        case RemovalError::invalid_material_state: return "invalid_material_state";
        case RemovalError::unknown_target: return "unknown_target";
        case RemovalError::stale_generation: return "stale_generation";
        case RemovalError::occupied_target: return "occupied_target";
        case RemovalError::quantity_overflow: return "quantity_overflow";
        case RemovalError::invalid_mechanics: return "invalid_mechanics";
        case RemovalError::belt_attached: return "belt_attached";
    }
    return "unknown";
}

PowerView power_view(const Topology& topology) {
    if (!structure(topology)) return {topology.drive_enabled, rejected_geometry()};
    std::vector<mechanics::Part> parts;
    parts.reserve(topology.parts.size());
    for (const auto& part : topology.parts) parts.push_back(part.geometry);
    auto sources = topology.sources;
    if (!topology.drive_enabled)
        for (auto& source : sources) source.rate = {0, 1};
    std::vector<mechanics::BeltSpan> spans;
    spans.reserve(topology.belt_spans.size());
    for (const auto& span : topology.belt_spans) spans.push_back(span.geometry);
    return {topology.drive_enabled, mechanics::evaluate(parts, sources, spans)};
}

RemovalPlan prepare_removal(const Topology& topology, const Kit& kit,
                            const materials::State& state,
                            const RemovalSelection& selection) {
    if (!structure(topology)) return refuse(RemovalError::invalid_topology);
    if (!valid_kit(topology, kit)) return refuse(RemovalError::invalid_kit);
    if (!material_membership(topology, state))
        return refuse(RemovalError::invalid_material_state, materials::Error::invalid_state);

    const auto before = power_view(topology);
    if (!before.mechanical.accepted())
        return refuse(RemovalError::invalid_mechanics, materials::Error::none,
                      before.mechanical.error);

    if (!identity(selection.target.id)) return refuse(RemovalError::unknown_target);
    const auto* selected = find(topology, selection.target.id);
    if (selected == nullptr) return refuse(RemovalError::unknown_target);
    if (selection.target.generation != selected->generation)
        return refuse(RemovalError::stale_generation);
    if (occupied(selected->role, state)) return refuse(RemovalError::occupied_target);
    if (std::any_of(topology.belt_spans.begin(), topology.belt_spans.end(), [&](const auto& span) {
        return span.geometry.first_shaft == selection.target.id || span.geometry.last_shaft == selection.target.id;
    })) return refuse(RemovalError::belt_attached);

    const auto spec = specification(*selected);
    const auto carried = kit.find(spec);
    if (carried != kit.end() && carried->second == std::numeric_limits<materials::Quantity>::max())
        return refuse(RemovalError::quantity_overflow);

    PreparedRemoval plan;
    plan.candidate = topology;
    plan.candidate_kit = kit;
    ++plan.candidate_kit[spec];
    plan.facts.target = selection.target;
    plan.facts.interaction_point = selected->geometry.center;
    plan.facts.refunded_part = spec;
    for (const auto& link : topology.material_links)
        if (link.from.id == selection.target.id || link.to.id == selection.target.id)
            plan.facts.removed_material_links.push_back(link);
    plan.facts.removed_source = std::any_of(topology.sources.begin(), topology.sources.end(),
        [&](const auto& source) { return source.hub == selection.target.id; });

    std::erase_if(plan.candidate.parts,
        [&](const auto& part) { return part.geometry.id == selection.target.id; });
    std::erase_if(plan.candidate.material_links, [&](const auto& link) {
        return link.from.id == selection.target.id || link.to.id == selection.target.id;
    });
    std::erase_if(plan.candidate.sources,
        [&](const auto& source) { return source.hub == selection.target.id; });

    plan.power = power_view(plan.candidate);
    if (!plan.power.mechanical.accepted())
        return refuse(RemovalError::invalid_mechanics, materials::Error::none,
                      plan.power.mechanical.error);
    return RemovalPlan{std::move(plan)};
}


const char* placement_error_name(PlacementError error) noexcept {
    switch (error) {
        case PlacementError::invalid_topology: return "invalid_topology";
        case PlacementError::invalid_kit: return "invalid_kit";
        case PlacementError::invalid_material_state: return "invalid_material_state";
        case PlacementError::invalid_part: return "invalid_part";
        case PlacementError::identity_conflict: return "identity_conflict";
        case PlacementError::part_limit: return "part_limit";
        case PlacementError::unavailable_part: return "unavailable_part";
        case PlacementError::incompatible_source: return "incompatible_source";
        case PlacementError::overlapping_shafts: return "overlapping_shafts";
        case PlacementError::invalid_mechanics: return "invalid_mechanics";
        case PlacementError::conflicting_belt: return "conflicting_belt";
    }
    return "unknown";
}

PlacementPlan prepare_placement(const Topology& topology, const Kit& kit,
                                const materials::State& state,
                                const PlacementSelection& selection) {
    if (!structure(topology)) return PlacementRefusal{PlacementError::invalid_topology};
    if (!valid_kit(topology, kit)) return PlacementRefusal{PlacementError::invalid_kit};
    if (!material_membership(topology, state))
        return PlacementRefusal{PlacementError::invalid_material_state,
                                materials::Error::invalid_state};
    const auto before = power_view(topology);
    if (!before.mechanical.accepted())
        return PlacementRefusal{PlacementError::invalid_mechanics, materials::Error::none,
                                before.mechanical.error};

    const auto& part = selection.part;
    const auto spec = specification(part);
    if (!identity(part.geometry.id) || part.generation <= 0 || !valid_spec(spec))
        return PlacementRefusal{PlacementError::invalid_part};
    if (find(topology, part.geometry.id) != nullptr)
        return PlacementRefusal{PlacementError::identity_conflict};
    if (topology.parts.size() == mechanics::maximum_parts)
        return PlacementRefusal{PlacementError::part_limit};

    const auto expected = part.role == Role::gear ? mechanics::Kind::gear :
                          part.role == Role::shaft ? mechanics::Kind::shaft :
                          mechanics::Kind::hub;
    if (part.geometry.kind != expected)
        return PlacementRefusal{PlacementError::invalid_part};

    if (part.role == Role::waterwheel) {
        if (!selection.source || !identity(selection.source->hub) ||
            selection.source->hub != part.geometry.id ||
            selection.source->rate.denominator <= 0)
            return PlacementRefusal{PlacementError::incompatible_source};
    } else if (selection.source)
        return PlacementRefusal{PlacementError::incompatible_source};

    const auto carried = kit.find(spec);
    if (carried == kit.end() || carried->second == 0)
        return PlacementRefusal{PlacementError::unavailable_part};
    if (std::any_of(topology.parts.begin(), topology.parts.end(),
                    [&](const auto& existing) { return overlapping_shafts(existing, part); }))
        return PlacementRefusal{PlacementError::overlapping_shafts};

    PreparedPlacement plan;
    plan.candidate = topology;
    plan.candidate_kit = kit;
    --plan.candidate_kit.at(spec);
    plan.candidate.parts.push_back(part);
    if (selection.source) plan.candidate.sources.push_back(*selection.source);
    if (!structure(plan.candidate))
        return PlacementRefusal{PlacementError::invalid_part};

    plan.power = power_view(plan.candidate);
    if (!plan.power.mechanical.accepted())
        return PlacementRefusal{PlacementError::invalid_mechanics, materials::Error::none,
                                plan.power.mechanical.error};
    plan.facts.target = {part.geometry.id, part.generation};
    plan.facts.interaction_point = part.geometry.center;
    plan.facts.consumed_part = spec;
    return PlacementPlan{std::move(plan)};
}

PlacementPlan prepare_belt_placement(const Topology& topology, const Kit& kit,
                                     const materials::State& state, const PlacedBeltSpan& span) {
    if (!structure(topology)) return PlacementRefusal{PlacementError::invalid_topology};
    if (!valid_kit(topology, kit)) return PlacementRefusal{PlacementError::invalid_kit};
    if (!material_membership(topology, state)) return PlacementRefusal{PlacementError::invalid_material_state};
    if (!power_view(topology).mechanical.accepted()) return PlacementRefusal{PlacementError::invalid_mechanics};
    if (!identity(span.geometry.id) || span.generation <= 0) return PlacementRefusal{PlacementError::invalid_part};
    if (find(topology, span.geometry.id) || std::any_of(topology.belt_spans.begin(), topology.belt_spans.end(),
        [&](const auto& existing) { return existing.geometry.id == span.geometry.id; }))
        return PlacementRefusal{PlacementError::identity_conflict};
    if (topology.belt_spans.size() == mechanics::maximum_parts) return PlacementRefusal{PlacementError::part_limit};
    const PartSpec spec{Role::belt, 0, 0};
    const auto carried = kit.find(spec);
    if (carried == kit.end() || carried->second == 0) return PlacementRefusal{PlacementError::unavailable_part};
    PreparedPlacement plan;
    plan.candidate = topology;
    plan.candidate.belt_spans.push_back(span);
    plan.power = power_view(plan.candidate);
    if (!plan.power.mechanical.accepted()) return PlacementRefusal{PlacementError::invalid_mechanics,
        materials::Error::none, plan.power.mechanical.error};
    if (plan.power.mechanical.motion.at(span.geometry.first_shaft).state == mechanics::MotionState::stalled)
        return PlacementRefusal{PlacementError::conflicting_belt};
    plan.candidate_kit = kit;
    --plan.candidate_kit.at(spec);
    plan.facts = {{span.geometry.id, span.generation}, find(topology, span.geometry.first_shaft)->geometry.center, spec};
    return plan;
}

RemovalPlan prepare_belt_removal(const Topology& topology, const Kit& kit,
                                 const materials::State& state, const materials::EntityRef& target) {
    if (!structure(topology)) return refuse(RemovalError::invalid_topology);
    if (!valid_kit(topology, kit)) return refuse(RemovalError::invalid_kit);
    if (!material_membership(topology, state)) return refuse(RemovalError::invalid_material_state);
    if (!power_view(topology).mechanical.accepted()) return refuse(RemovalError::invalid_mechanics);
    const auto found = std::find_if(topology.belt_spans.begin(), topology.belt_spans.end(),
        [&](const auto& span) { return span.geometry.id == target.id; });
    if (found == topology.belt_spans.end()) return refuse(RemovalError::unknown_target);
    if (found->generation != target.generation) return refuse(RemovalError::stale_generation);
    const auto lane = state.belt_lanes.find(target.id);
    if (lane != state.belt_lanes.end() && std::any_of(lane->second.slots.begin(), lane->second.slots.end(),
            [](const auto& item) { return item.has_value(); })) return refuse(RemovalError::occupied_target);
    const PartSpec spec{Role::belt, 0, 0};
    const auto carried = kit.find(spec);
    if (carried != kit.end() && carried->second == std::numeric_limits<materials::Quantity>::max())
        return refuse(RemovalError::quantity_overflow);
    PreparedRemoval plan;
    plan.candidate = topology;
    std::erase_if(plan.candidate.belt_spans, [&](const auto& span) { return span.geometry.id == target.id; });
    plan.candidate_kit = kit;
    ++plan.candidate_kit[spec];
    plan.facts.target = target;
    plan.facts.interaction_point = find(topology, found->geometry.first_shaft)->geometry.center;
    plan.facts.refunded_part = spec;
    plan.power = power_view(plan.candidate);
    if (!plan.power.mechanical.accepted()) return refuse(RemovalError::invalid_mechanics, materials::Error::none,
                                                        plan.power.mechanical.error);
    return plan;
}

}  // namespace factory::stationary
