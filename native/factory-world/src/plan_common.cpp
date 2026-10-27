#include "plan_common.hpp"
#include "factory/foundation_command_contract.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <set>
#include <utility>

namespace factory::world {

std::optional<mechanics::Axis> axis(const std::string& value) {
    if (value == "x") return mechanics::Axis::x;
    if (value == "y") return mechanics::Axis::y;
    if (value == "z") return mechanics::Axis::z;
    return std::nullopt;
}

bool two_endpoints(const std::string& action) {
    return action == "shaft_between" || action == "remove_shaft_between" ||
        action == "place_belt_span" || action == "place_selected_belt_span";
}

using Integer = authority::Integer;
using Role = stationary::Role;
using Object = authority::Object;
using Value = values::Value;

bool placement(const std::string& action) {
    return action == "place" || action == "place_connected";
}

bool slide_component(materials::Component kind) {
    return kind == materials::Component::wooden_slide ||
           kind == materials::Component::copper_slide;
}

bool crank_input_port(const PlacedComponent& component, const mechanics::Point& port) {
    const auto& center = component.center;
    if (slide_component(component.kind))
        return port[1] == center[1] && port[2] == center[2] &&
            std::abs(port[0] - center[0]) == 1;
    // Collector mounts and routed shafts expose their embodied spindle at
    // their own grid anchor. The crank is visually cantilevered from it.
    return (component.kind == materials::Component::tool_mount ||
        component.kind == materials::Component::wooden_shaft ||
        component.kind == materials::Component::copper_shaft) && port == center;
}

bool crank_face_on_axis(const mechanics::Point& face, mechanics::Axis axis) {
    const auto index = static_cast<std::size_t>(axis);
    if (std::abs(face[index]) != 1) return false;
    for (std::size_t other = 0; other < face.size(); ++other)
        if (other != index && face[other] != 0) return false;
    return true;
}

mechanics::Point crank_face_from_actor(const Profile& profile,
        const authority::Point& actor, const mechanics::Point& port,
        mechanics::Axis axis) {
    mechanics::Point face{};
    const auto index = static_cast<std::size_t>(axis);
    face[index] = actor[index] < anchor(profile, port)[index] ? -1 : 1;
    return face;
}

bool manual_input_available(const mechanics::Motion& motion) {
    return motion.state == mechanics::MotionState::unpowered ||
        (motion.state == mechanics::MotionState::stopped && motion.rate.numerator == 0);
}

bool slide_input_port_clear(const State& state, const std::string& slide,
        const mechanics::Point& port) {
    for (const auto& [id, crank] : state.crank_items) {
        (void)id;
        if (crank.port == port && crank.attached_to != slide) return false;
    }
    for (const auto& [id, component] : state.placed_components)
        if (id != slide && component.center == port) return false;
    for (const auto& part : state.topology.parts) {
        const auto& geometry = part.geometry;
        if (geometry.center[1] == port[1] && geometry.center[2] == port[2] &&
            (geometry.center == port ||
             (geometry.kind == mechanics::Kind::shaft &&
              geometry.axis == mechanics::Axis::x &&
              std::abs(geometry.center[0] - port[0]) <= geometry.half_span)))
            return false;
    }
    return true;
}

std::optional<bool> hand_slide_contact(const State::SlidePhase& before,
        const State::SlidePhase& after, mechanics::Rate rate) {
    // The issued crank supplies one shaft turn. The die touches its work only
    // when the native carriage crosses the bottom of its reciprocal stroke.
    // A different graph ratio cannot be inferred from these two endpoints.
    if (rate.denominator <= 0 ||
        (rate.numerator != rate.denominator && rate.numerator != -rate.denominator))
        return std::nullopt;
    constexpr Integer bottom = slide_cycle_subticks / 2;
    if (rate.numerator > 0)
        return before.subticks < bottom && after.subticks >= bottom;
    return (before.subticks > bottom ||
            (before.subticks == bottom && before.remainder > 0)) &&
        (after.subticks < bottom ||
            (after.subticks == bottom && after.remainder == 0));
}

CollectorMatch collector_for_input(const Profile& profile,
        const std::vector<assembly::Part>& parts, const std::string& input) {
    CollectorMatch found;
    const auto selected = std::find_if(parts.begin(), parts.end(),
        [&](const auto& part) { return part.id == input; });
    if (selected == parts.end()) return found;
    const assembly::Layout layout(parts);
    for (const auto& face : profile.collector_faces) {
        const auto inspected = layout.inspect_collector(face);
        const auto& center = face.machine_center;
        const auto& at = selected->center;
        const auto adjacent = std::abs(at[0] - center[0]) + std::abs(at[1] - center[1]) +
            std::abs(at[2] - center[2]) == 1;
        if (inspected.status == assembly::Status::ambiguous && adjacent)
            found.ambiguous = true;
        if (!inspected.collector || inspected.collector->mount != input) continue;
        if (found.collector) found.ambiguous = true;
        found.collector = *inspected.collector;
    }
    if (found.ambiguous) found.collector.reset();
    return found;
}

Value slide_phase_value(const State::SlidePhase& phase) {
    return Value(Object{{"subticks", Value(phase.subticks)},
        {"remainder", Value(phase.remainder)},
        {"denominator", Value(phase.denominator)}});
}

bool has_attached_crank(const State& state, const std::string& input,
        const mechanics::Point& port) {
    return std::any_of(state.crank_items.begin(), state.crank_items.end(),
        [&](const auto& entry) {
            return entry.second.attached_to == input && entry.second.port == port;
        });
}

std::vector<assembly::Part> assembly_parts(const State& state) {
    std::vector<assembly::Part> parts;
    parts.reserve(state.placed_components.size());
    for (const auto& [id, placed] : state.placed_components)
        parts.push_back({id, placed.kind, placed.center, placed.generation});
    return parts;
}

WorkingPressInspection inspect_working_press(const assembly::Layout& layout,
        materials::Component anchor_kind, const mechanics::Point& center) {
    if (anchor_kind == materials::Component::anvil) {
        const auto sliding = layout.inspect_sliding_press(center);
        if (sliding.press) {
            const auto& press = *sliding.press;
            return {sliding.status, WorkingPress{press.anvil, center, press.work_center,
                press.slide_center, press.slide, press.open_feeds, std::nullopt,
                std::nullopt, true}};
        }
        if (sliding.status == assembly::PressStatus::blocked_feed)
            return {sliding.status, std::nullopt};
        const auto inspected = layout.inspect_guided_press(center);
        if (!inspected.press) return {inspected.status, std::nullopt};
        const auto& press = *inspected.press;
        return {inspected.status, WorkingPress{press.anvil, center, press.work_center,
            press.shaft_center, press.shaft, press.open_feeds, press.offcut_receiver,
            press.plate_receiver}};
    }
    if (anchor_kind == materials::Component::wooden_frame) {
        const auto inspected = layout.inspect_press(center);
        if (!inspected.press) return {inspected.status, std::nullopt};
        const auto& press = *inspected.press;
        return {inspected.status, WorkingPress{press.frame, center, press.work_center,
            press.shaft_center, press.shaft, press.open_feeds, std::nullopt, std::nullopt}};
    }
    return {};
}

bool material_machine(Role role) {
    return role == Role::collector || role == Role::processor;
}

bool transmission_role(Role role) {
    return role == Role::gear || role == Role::shaft || role == Role::gearbox ||
           role == Role::vertical_gearbox || role == Role::chain_drive;
}

bool transmission_center(Role role, const mechanics::Point& center,
        mechanics::Axis axis, Integer half_span) {
    if (!transmission_role(role)) return true;
    const std::size_t along = axis == mechanics::Axis::x ? 0 :
        axis == mechanics::Axis::y ? 1 : 2;
    for (std::size_t index = 0; index < center.size(); ++index) {
        const auto remainder = center[index] % 4;
        if (remainder == 0) continue;
        // A two-half-span shaft bridges adjacent full-grid ports from their
        // common half-tile center. It still uses the same quarter-grid origin.
        if (role != Role::shaft || half_span != 2 || index != along ||
            std::abs(remainder) != 2) return false;
    }
    return true;
}

std::optional<mechanics::Rate> wheel_rate(const Profile& profile, const stationary::PlacedPart& placed) {
    if (profile.water.empty()) return profile.waterwheel_rate;
    const auto& part = placed.geometry;
    const auto sample = profile.water.find({part.center[0], part.center[2]});
    if (sample == profile.water.end()) return mechanics::Rate{0, 1};
    return waterwheel::rate(part.center[1] * 100 + profile.wheel_axle_offset,
                            profile.wheel_radius * placed.wheel_tiles, part.axis, sample->second);
}

bool spec_valid(const stationary::PartSpec& spec) {
    switch (spec.role) {
        case Role::collector: case Role::belt: case Role::processor: case Role::waterwheel:
            return spec.teeth == 0 && spec.half_span == 0;
        case Role::gear:
            return spec.teeth > 0 && spec.teeth <= mechanics::maximum_dimension && spec.half_span == 0;
        case Role::shaft:
            return spec.teeth == 0 && spec.half_span == 2;
        case Role::gearbox: case Role::vertical_gearbox: case Role::chain_drive:
            return spec.teeth == 0 && spec.half_span == 0;
    }
    return false;
}

values::Value grid_value(const mechanics::Point& point) {
    using Value = values::Value;
    return Value(Value::Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

std::array<mechanics::Point, 4> broad_cells(const mechanics::Point& origin) {
    return {origin, mechanics::Point{origin[0] + 4, origin[1], origin[2]},
        mechanics::Point{origin[0], origin[1], origin[2] + 4},
        mechanics::Point{origin[0] + 4, origin[1], origin[2] + 4}};
}

bool broad_item(const materials::Cargo& cargo) {
    return !cargo.sheets.empty() || std::any_of(cargo.work_lots.begin(),
        cargo.work_lots.end(), [](const auto& lot) {
            return lot.recipe.output == materials::WorkOutput::sheet;
        });
}

std::vector<authority::Point> broad_reach_targets(const Profile& profile,
                                                   const mechanics::Point& origin) {
    std::vector<authority::Point> targets;
    targets.reserve(4);
    for (const auto& cell : broad_cells(origin)) targets.push_back(anchor(profile, cell));
    return targets;
}

std::optional<std::vector<materials::DropPoint>> channel_swept_cells(
        const mechanics::Point& from, const mechanics::Point& to,
        materials::Footprint footprint, authority::Integer rotation, bool small_move) {
    if (from[1] != to[1]) return std::nullopt;
    const auto distance = std::abs(to[0] - from[0]) +
        std::abs(to[2] - from[2]);
    if (distance == 4) {
        if (auto cells = materials::swept_workcells(from, to, footprint, rotation))
            return cells;
    }
    if (!small_move || footprint.x_cells != 1 || footprint.z_cells != 1 ||
        rotation != 0 || to[0] % 4 || to[2] % 4)
        return std::nullopt;
    const bool offset_x = from[0] % 4 != 0;
    const bool offset_z = from[2] % 4 != 0;
    if (offset_x == offset_z) return std::nullopt;
    const auto axis = offset_x ? 0U : 2U;
    const auto other = offset_x ? 2U : 0U;
    if (std::abs(from[axis] % 4) % 2 != 1 || from[other] != to[other] ||
        std::abs(to[axis] - from[axis]) < 1 ||
        std::abs(to[axis] - from[axis]) > 3) return std::nullopt;
    return std::vector<materials::DropPoint>{from, to};
}

bool channel_cells_fit(const std::vector<materials::DropPoint>& cells,
        const std::vector<materials::DropPoint>& supports,
        const std::vector<materials::DropPoint>& blocked) {
    const std::set<materials::DropPoint> supported(supports.begin(), supports.end());
    const std::set<materials::DropPoint> obstructed(blocked.begin(), blocked.end());
    return std::all_of(cells.begin(), cells.end(), [&](const auto& cell) {
        return supported.contains(cell) && !obstructed.contains(cell);
    });
}

std::optional<mechanics::Point> grid_point(const authority::Object& intent,
        authority::Integer limit) {
    const auto* array = field<values::Value::Array>(intent, "center");
    if (!array || array->size() != 3) return std::nullopt;
    mechanics::Point point;
    for (std::size_t index = 0; index < point.size(); ++index) {
        const auto* value = std::get_if<authority::Integer>(&array->at(index).storage());
        if (!value || *value < -limit || *value > limit)
            return std::nullopt;
        point[index] = *value;
    }
    return point;
}

// A rectangle uses the same absolute quarter-pitch coordinates as every part.
// Bound the complete request before enumerating it or changing any custody.
std::vector<mechanics::Point> foundation_area(const authority::Object& intent) {
    const auto start = grid_point(intent);
    const auto* end = field<values::Value::Array>(intent, "end");
    if (!start || !end) return {};
    const auto finish = grid_point(authority::Object{{"center", values::Value(*end)}});
    if (!finish || (*start)[1] != (*finish)[1] || (*start)[0] % 4 || (*start)[2] % 4 ||
        (*finish)[0] % 4 || (*finish)[2] % 4) return {};
    const auto width = std::abs((*start)[0] - (*finish)[0]) / 4 + 1;
    const auto depth = std::abs((*start)[2] - (*finish)[2]) / 4 + 1;
    if (width > foundation_commands::maximum_area_side ||
        depth > foundation_commands::maximum_area_side ||
        width * depth > foundation_commands::maximum_area_side) return {};
    std::vector<mechanics::Point> points;
    for (auto x = std::min((*start)[0], (*finish)[0]); x <= std::max((*start)[0], (*finish)[0]); x += 4)
        for (auto z = std::min((*start)[2], (*finish)[2]); z <= std::max((*start)[2], (*finish)[2]); z += 4)
            points.push_back({x, (*start)[1], z});
    return points;
}

bool add(authority::Integer& total, authority::Integer count) {
    if (count < 0 || total > std::numeric_limits<authority::Integer>::max() - count)
        return false;
    total += count;
    return true;
}

std::optional<stationary::Role> role(const std::string& value) {
    using Role = stationary::Role;
    if (value == "collector") return Role::collector;
    if (value == "belt") return Role::belt;
    if (value == "processor") return Role::processor;
    if (value == "waterwheel") return Role::waterwheel;
    if (value == "gear") return Role::gear;
    if (value == "shaft") return Role::shaft;
    if (value == "gearbox") return Role::gearbox;
    if (value == "vertical_gearbox") return Role::vertical_gearbox;
    if (value == "chain_drive") return Role::chain_drive;
    return std::nullopt;
}

const stationary::PlacedPart* part(const stationary::Topology& topology, const std::string& id) {
    const auto found = std::find_if(topology.parts.begin(), topology.parts.end(),
        [&](const auto& item) { return item.geometry.id == id; });
    return found == topology.parts.end() ? nullptr : &*found;
}

values::Value removed_span_value(const stationary::PlacedBeltSpan& span) {
    using Value = values::Value;
    using Object = authority::Object;
    return Value(Object{{"first_shaft", Value(span.geometry.first_shaft)},
        {"last_shaft", Value(span.geometry.last_shaft)}});
}

values::Value lots_value(const std::vector<materials::WorkLot>& lots) {
    using Value = values::Value;
    using Object = authority::Object;
    Value::Array output;
    for (const auto& lot : lots) {
        Object item{
        {"id", Value(lot.id)}, {"input_units_per_product", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining_ticks", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)}, {"work_remainder", Value(lot.work_remainder)},
        {"work_remainder_denominator", Value(lot.work_remainder_denominator)}};
        if (lot.recipe.output == materials::WorkOutput::sheet)
            item.emplace("output_form", Value("sheet"));
        output.emplace_back(std::move(item));
    }
    return Value(std::move(output));
}

bool copper_profile(const materials::Config& config) {
    return config.raw_mass != 1 || config.plate_mass != 0 || config.sheet_mass != 0;
}

values::Value belt_cargo_value(const materials::Cargo& cargo, bool copper) {
    using Value = values::Value;
    using Object = authority::Object;
    using Integer = authority::Integer;
    Value::Array lots;
    for (const auto& lot : cargo.work_lots) {
        Object item{
        {"id", Value(lot.id)}, {"recipe_input", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)}, {"work_remainder", Value(lot.work_remainder)},
        {"work_remainder_denominator", Value(lot.work_remainder_denominator)}};
        if (lot.recipe.output == materials::WorkOutput::sheet)
            item.emplace("output_form", Value("sheet"));
        lots.emplace_back(std::move(item));
    }
    Object output{{"raw", Value(cargo.raw_units)}, {"products", Value(cargo.products)},
                  {"work_lots", Value(std::move(lots))}};
    if (copper) {
        output.emplace("offcuts", Value(cargo.offcuts));
        output.emplace("sheets", Value(static_cast<Integer>(cargo.sheets.size())));
        if (!cargo.sheets.empty()) {
            Value::Array sheet_items;
            for (const auto& sheet : cargo.sheets)
                sheet_items.emplace_back(Object{{"id", Value(sheet.id)},
                    {"rotation", Value(sheet.rotation)}});
            output.emplace("sheet_items", Value(std::move(sheet_items)));
        }
    }
    return Value(std::move(output));
}

authority::Point anchor(const Profile& profile, const mechanics::Point& point) {
    return {static_cast<double>(point[0]) * profile.meters_per_grid_unit + profile.anchor_offset[0],
            static_cast<double>(point[1]) * profile.meters_per_grid_unit + profile.anchor_offset[1],
            static_cast<double>(point[2]) * profile.meters_per_grid_unit + profile.anchor_offset[2]};
}

values::Value point_value(const authority::Point& point) {
    using Value = values::Value;
    return Value(Value::Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

authority::Object reach_facts(const Binding& binding, const authority::ReachReceipt& reach) {
    using Value = values::Value;
    Value::Array targets, distances;
    for (const auto& target : reach.targets) targets.push_back(point_value(target));
    for (const auto distance : reach.distances_squared) distances.emplace_back(distance);
    return {{"actor", Value(binding.actor)}, {"native_epoch", Value(reach.cut.native_epoch)},
        {"actor_position", point_value(reach.cut.position)}, {"targets", Value(std::move(targets))},
        {"distances_squared", Value(std::move(distances))}, {"build_reach", Value(reach.cut.build_reach)}};
}

Owner::Decision refused(std::string reason, std::string entity, authority::Object facts) {
    return {std::nullopt, {false, std::move(reason), std::move(entity), std::move(facts)}};
}

Owner::Decision accepted(State state, std::string entity, authority::Object facts) {
    return {std::move(state), {true, "ok", std::move(entity), std::move(facts)}};
}

} // namespace factory::world
