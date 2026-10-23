#include "factory/world.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <initializer_list>
#include <limits>
#include <set>
#include <string_view>
#include <tuple>
#include <unordered_map>
#include <utility>

namespace factory::world {

std::array<mechanics::Point, landing_deck_parts> landing_deck_centers(
        const mechanics::Point& center) {
    std::array<mechanics::Point, landing_deck_parts> deck{};
    std::size_t index = 0;
    for (const auto x : {-4, 0, 4})
        for (const auto z : {-4, 0, 4})
            deck[index++] = {center[0] + x, center[1], center[2] + z};
    return deck;
}

mechanics::Point landing_hub_center(const mechanics::Point& pod_center) {
    // The east deck tile is a full global tile from the hatch, not a separate
    // bench origin or a fractional placement grid.
    return {pod_center[0] + 4, pod_center[1], pod_center[2]};
}

mechanics::Point landing_freight_center(const mechanics::Point& pod_center) {
    // Five whole tiles east of the deck center, beyond its unfolding footprint.
    return {pod_center[0] + 20, pod_center[1], pod_center[2]};
}

namespace {
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;
using Role = stationary::Role;

constexpr std::size_t maximum_actors = 16;
constexpr std::size_t maximum_issued_entities = 4096;
constexpr std::size_t maximum_current_work = materials::maximum_live_work_lots;
constexpr Integer foundation_depth_levels = 2;
constexpr std::string_view allocated_prefix = "native-part-";

template<class T> const T* field(const Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

bool identity(const std::string& value) {
    return !value.empty() && value.size() <= 128 && value.find('\0') == std::string::npos;
}

bool placement(const std::string& action) {
    return action == "place" || action == "place_connected";
}

bool material_machine(Role role) {
    return role == Role::collector || role == Role::processor;
}

bool transmission_role(Role role) {
    return role == Role::gear || role == Role::shaft || role == Role::gearbox ||
           role == Role::vertical_gearbox || role == Role::chain_drive;
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

bool add(Integer& total, Integer count) {
    if (count < 0 || total > std::numeric_limits<Integer>::max() - count) return false;
    total += count;
    return true;
}

bool weighted_add(Integer& total, Integer count, Integer unit) {
    if (count < 0 || unit < 0 || (unit > 0 && count > std::numeric_limits<Integer>::max() / unit))
        return false;
    return add(total, count * unit);
}

const stationary::PlacedPart* part(const stationary::Topology& topology, const std::string& id) {
    const auto found = std::find_if(topology.parts.begin(), topology.parts.end(),
        [&](const auto& item) { return item.geometry.id == id; });
    return found == topology.parts.end() ? nullptr : &*found;
}

bool keys(const Object& object, std::initializer_list<const char*> extra) {
    constexpr const char* base[] = {"context", "client", "request", "actor", "action"};
    const auto wire = object.find("wire");
    if (wire != object.end() && !std::get_if<Object>(&wire->second.storage())) return false;
    if (object.size() != std::size(base) + extra.size() + (wire != object.end() ? 1 : 0)) return false;
    for (const auto* key : base) if (!object.contains(key)) return false;
    for (const auto* key : extra) if (!object.contains(key)) return false;
    return true;
}

bool shape(const Object& intent, const std::string& action) {
    if (action == "pickup_material") return keys(intent, {"center", "expected"}) && field<Object>(intent, "expected");
    if (action == "harvest_source") return keys(intent, {"target"}) && field<std::string>(intent, "target");
    if (action == "craft_component") return keys(intent, {"target", "generation", "component"}) &&
        field<std::string>(intent, "target") && field<Integer>(intent, "generation") &&
        field<std::string>(intent, "component");
    if (action == "field_craft") return keys(intent, {"component"}) &&
        field<std::string>(intent, "component");
    if (action == "deliver_first_plate") return keys(intent, {"target", "generation"}) &&
        field<std::string>(intent, "target") && field<Integer>(intent, "generation");
    if (action == "craft_part") return keys(intent, {"target", "generation", "role", "half_span"}) &&
        field<std::string>(intent, "target") && field<Integer>(intent, "generation") &&
        field<std::string>(intent, "role") && field<Integer>(intent, "half_span");
    if (action == "stow_fabrication_hub")
        return keys(intent, {"target", "generation"}) && field<std::string>(intent, "target") &&
            field<Integer>(intent, "generation");
    if (action == "deploy_fabrication_hub")
        return keys(intent, {"target", "generation", "center"}) &&
            field<std::string>(intent, "target") && field<Integer>(intent, "generation") &&
            field<Value::Array>(intent, "center");
    if (action == "take_hand_crank" || action == "return_hand_crank")
        return keys(intent, {"target", "generation"}) && field<std::string>(intent, "target") &&
            field<Integer>(intent, "generation");
    if (action == "turn_hand_crank")
        return keys(intent, {"target", "generation"}) && field<std::string>(intent, "target") &&
            field<Integer>(intent, "generation");
    if (action == "feed_press")
        return keys(intent, {"target", "generation", "entry"}) &&
            field<std::string>(intent, "target") && field<Integer>(intent, "generation") &&
            field<Value::Array>(intent, "entry");
    if (action == "turn_press_crank")
        return keys(intent, {"target", "generation", "drive", "exit"}) &&
            field<std::string>(intent, "target") && field<Integer>(intent, "generation") &&
            field<std::string>(intent, "drive") && field<Value::Array>(intent, "exit");
    if (action == "place_component") return keys(intent, {"component", "center"}) &&
        field<std::string>(intent, "component") && field<Value::Array>(intent, "center");
    if (action == "reclaim_component") return keys(intent, {"target", "generation"}) &&
        field<std::string>(intent, "target") && field<Integer>(intent, "generation");
    if (action == "place_foundations") return keys(intent, {"center", "end"});
    if (action == "place_foundation") return keys(intent, {"center"});
    if (action == "remove_foundation") return keys(intent, {"target", "generation"});
    if (action == "recover" || action == "remove" || action == "remove_belt_span" || action == "select_belt_shaft")
        return keys(intent, {"target", "generation"});
    if (action == "recover_belt_slot") return keys(intent, {"target", "generation", "slot", "expected"}) &&
        field<Integer>(intent, "slot") && field<Object>(intent, "expected");
    if (action == "load_belt_slot") return keys(intent, {"target", "generation", "slot", "item", "work_id"}) &&
        field<Integer>(intent, "slot") && field<std::string>(intent, "item") && field<Integer>(intent, "work_id");
    if (action == "collect" || action == "insert_raw")
        return keys(intent, {"target", "generation", "amount"}) && field<Integer>(intent, "amount");
    if (action == "insert_work")
        return keys(intent, {"target", "generation", "work_id"}) && field<Integer>(intent, "work_id");
    if (action == "set_drive")
        return keys(intent, {"target", "generation", "enabled"}) && field<bool>(intent, "enabled");
    if (placement(action) && intent.contains("rotation"))
        return keys(intent, {"role", "center", "axis", "teeth", "half_span", "rotation"});
    if (placement(action) && intent.contains("relay_axis"))
        return keys(intent, {"role", "center", "axis", "teeth", "half_span", "relay_axis"});
    if (placement(action))
        return intent.contains("wheel_tiles") ? keys(intent, {"role", "center", "axis", "teeth", "half_span", "wheel_tiles"}) :
            keys(intent, {"role", "center", "axis", "teeth", "half_span"});
    if (action == "shaft_between" || action == "remove_shaft_between" || action == "place_belt_span")
        return keys(intent, {"target", "generation", "to", "to_generation"});
    if (action == "place_selected_belt_span")
        return keys(intent, {"target", "generation", "to", "to_generation", "selection"}) && field<std::string>(intent, "selection");
    return false;
}

std::optional<Role> role(const std::string& value) {
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

std::optional<mechanics::Axis> axis(const std::string& value) {
    if (value == "x") return mechanics::Axis::x;
    if (value == "y") return mechanics::Axis::y;
    if (value == "z") return mechanics::Axis::z;
    return std::nullopt;
}

std::optional<mechanics::Point> grid_point(const Object& intent, Integer limit = mechanics::maximum_coordinate) {
    const auto* array = field<Value::Array>(intent, "center");
    if (!array || array->size() != 3) return std::nullopt;
    mechanics::Point point;
    for (std::size_t index = 0; index < point.size(); ++index) {
        const auto* value = std::get_if<Integer>(&array->at(index).storage());
        if (!value || *value < -limit || *value > limit)
            return std::nullopt;
        point[index] = *value;
    }
    return point;
}

authority::Point anchor(const Profile& profile, const mechanics::Point& point) {
    return {static_cast<double>(point[0]) * profile.meters_per_grid_unit + profile.anchor_offset[0],
            static_cast<double>(point[1]) * profile.meters_per_grid_unit + profile.anchor_offset[1],
            static_cast<double>(point[2]) * profile.meters_per_grid_unit + profile.anchor_offset[2]};
}

// A rectangle uses the same absolute quarter-pitch coordinates as every part.
// Bound the complete request before enumerating it or changing any custody.
std::vector<mechanics::Point> foundation_area(const Object& intent) {
    const auto start = grid_point(intent);
    const auto* end = field<Value::Array>(intent, "end");
    if (!start || !end) return {};
    const auto finish = grid_point(Object{{"center", Value(*end)}});
    if (!finish || (*start)[1] != (*finish)[1] || (*start)[0] % 4 || (*start)[2] % 4 ||
        (*finish)[0] % 4 || (*finish)[2] % 4) return {};
    const auto width = std::abs((*start)[0] - (*finish)[0]) / 4 + 1;
    const auto depth = std::abs((*start)[2] - (*finish)[2]) / 4 + 1;
    if (width > 256 || depth > 256 || width * depth > 256) return {};
    std::vector<mechanics::Point> points;
    for (auto x = std::min((*start)[0], (*finish)[0]); x <= std::max((*start)[0], (*finish)[0]); x += 4)
        for (auto z = std::min((*start)[2], (*finish)[2]); z <= std::max((*start)[2], (*finish)[2]); z += 4)
            points.push_back({x, (*start)[1], z});
    return points;
}

bool two_endpoints(const std::string& action) {
    return action == "shaft_between" || action == "remove_shaft_between" ||
        action == "place_belt_span" || action == "place_selected_belt_span";
}

Value point_value(const authority::Point& point) {
    return Value(Value::Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

Object reach_facts(const Binding& binding, const authority::ReachReceipt& reach) {
    Value::Array targets, distances;
    for (const auto& target : reach.targets) targets.push_back(point_value(target));
    for (const auto distance : reach.distances_squared) distances.emplace_back(distance);
    return {{"actor", Value(binding.actor)}, {"native_epoch", Value(reach.cut.native_epoch)},
        {"actor_position", point_value(reach.cut.position)}, {"targets", Value(std::move(targets))},
        {"distances_squared", Value(std::move(distances))}, {"build_reach", Value(reach.cut.build_reach)}};
}

std::vector<assembly::Part> assembly_parts(const State& state) {
    std::vector<assembly::Part> parts;
    parts.reserve(state.placed_components.size());
    for (const auto& [id, placed] : state.placed_components)
        parts.push_back({id, placed.kind, placed.center, placed.generation});
    return parts;
}

struct CollectorMatch {
    std::optional<assembly::Collector> collector;
    bool ambiguous{};
};

CollectorMatch collector_for_shaft(const Profile& profile,
        const std::vector<assembly::Part>& parts, const std::string& shaft) {
    CollectorMatch found;
    const auto selected = std::find_if(parts.begin(), parts.end(),
        [&](const auto& part) { return part.id == shaft; });
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
        if (!inspected.collector || inspected.collector->shaft != shaft) continue;
        if (found.collector) found.ambiguous = true;
        found.collector = *inspected.collector;
    }
    if (found.ambiguous) found.collector.reset();
    return found;
}

Owner::Decision refused(std::string reason, std::string entity = {}, Object facts = {}) {
    return {std::nullopt, {false, std::move(reason), std::move(entity), std::move(facts)}};
}

Owner::Decision accepted(State state, std::string entity, Object facts) {
    return {std::move(state), {true, "ok", std::move(entity), std::move(facts)}};
}

std::optional<materials::ResolvedTarget> material_target(
        const Profile& profile, const stationary::PlacedPart& selected,
        const stationary::Topology& topology) {
    materials::Holder holder;
    switch (selected.role) {
        case Role::collector: holder = materials::Holder::collector; break;
        case Role::processor: holder = materials::Holder::processor; break;
        default: return std::nullopt;
    }
    materials::ResolvedTarget target{{selected.geometry.id, selected.generation}, holder,
                                      material_path(topology), std::nullopt};
    if (selected.role == Role::processor)
        target.accepts_work = materials::RecipeSignature{
            profile.material.input_units_per_product, profile.material.cycle_ticks};
    return target;
}

Value lots_value(const std::vector<materials::WorkLot>& lots) {
    Value::Array output;
    for (const auto& lot : lots) output.emplace_back(Object{
        {"id", Value(lot.id)}, {"input_units_per_product", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining_ticks", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)}, {"work_remainder", Value(lot.work_remainder)},
        {"work_remainder_denominator", Value(lot.work_remainder_denominator)}});
    return Value(std::move(output));
}

Value belt_cargo_value(const materials::Cargo& cargo) {
    Value::Array lots;
    for (const auto& lot : cargo.work_lots) lots.emplace_back(Object{
        {"id", Value(lot.id)}, {"recipe_input", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)}, {"work_remainder", Value(lot.work_remainder)},
        {"work_remainder_denominator", Value(lot.work_remainder_denominator)}});
    return Value(Object{{"raw", Value(cargo.raw_units)}, {"products", Value(cargo.products)},
                        {"work_lots", Value(std::move(lots))}});
}

using PlacedHistory = std::map<std::string, std::pair<materials::Component, mechanics::Point>>;

std::optional<mechanics::Point> historical_bench_center(const std::optional<FabricationHub>& hub,
        const PlacedHistory& placed_components, const std::string* target) {
    if (!target) return std::nullopt;
    if (hub && !hub->holder && *target == hub->id) return hub->center;
    const auto placed = placed_components.find(*target);
    return placed != placed_components.end() &&
        placed->second.first == materials::Component::wooden_workbench ?
        std::optional<mechanics::Point>(placed->second.second) : std::nullopt;
}

bool historical_facts(const Profile& profile, const authority::Record& record,
                      const std::string& actor, const std::string& action,
                      const PlacedHistory& placed_components,
                      const std::optional<FabricationHub>& hub) {
    if (action == "shaft_between" || action == "remove_shaft_between") return false;
    const auto& result = record.result;
    const auto* reason = field<std::string>(result, "reason");
    const auto* epoch = field<Integer>(result, "native_epoch");
    const auto* reach = field<double>(result, "build_reach");
    const auto* position = field<Value::Array>(result, "actor_position");
    const auto* points = field<Value::Array>(result, "targets");
    const auto* distances = field<Value::Array>(result, "distances_squared");
    if (!reason || *reason != "ok" || !epoch || *epoch <= 0 || !reach || *reach != profile.build_reach ||
        !position || !points || !distances ||
        (action == "remove_belt_span" ? points->size() != 1 && points->size() != 2 :
         points->size() != ((two_endpoints(action) && action != "place_selected_belt_span") ? 2 : 1)) ||
        distances->size() != points->size()) return false;
    const auto point = [](const Value::Array& array) -> std::optional<authority::Point> {
        if (array.size() != 3) return std::nullopt;
        authority::Point output;
        for (std::size_t axis = 0; axis < 3; ++axis) {
            const auto* value = std::get_if<double>(&array[axis].storage());
            if (!value) return std::nullopt;
            output[axis] = *value;
        }
        return output;
    };
    const auto actor_position = point(*position);
    if (!actor_position) return false;
    std::vector<authority::Point> targets;
    for (const auto& value : *points) {
        const auto* array = std::get_if<Value::Array>(&value.storage());
        const auto target = array ? point(*array) : std::nullopt;
        if (!target) return false;
        targets.push_back(*target);
    }
    const auto checked = authority::check_reach(actor,
        {actor, *actor_position, *epoch, true, *reach}, targets);
    if (checked.error != authority::Error::none) return false;
    for (std::size_t index = 0; index < distances->size(); ++index) {
        const auto* distance = std::get_if<double>(&distances->at(index).storage());
        if (!distance || *distance != checked.receipt->distances_squared[index]) return false;
    }
    if (action == "place_foundations") {
        const auto cells = foundation_area(record.intent);
        const auto* count = field<Integer>(result, "count");
        return !cells.empty() && count && *count == static_cast<Integer>(cells.size()) &&
            targets.front() == *actor_position && result.size() == 17;
    }
    if (action == "pickup_material") {
        const auto location = grid_point(record.intent, materials::maximum_drop_coordinate);
        const auto* raw = field<Integer>(result, "moved_raw");
        const auto* products = field<Integer>(result, "moved_products");
        const auto* work = field<Value::Array>(result, "moved_work");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        if (!location || targets.front() != anchor(profile, *location) || !raw || *raw < 0 || !products || *products < 0 ||
            !work || work->size() > maximum_current_work || !entity || !entity->empty() || !generation || *generation != 0 ||
            result.size() != 19 || *products > std::numeric_limits<Integer>::max() / profile.material.input_units_per_product)
            return false;
        Integer weighted = *raw;
        if (!add(weighted, *products * profile.material.input_units_per_product)) return false;
        for (const auto& value : *work) {
            const auto* lot = std::get_if<Object>(&value.storage());
            if (!lot || lot->size() != 7 || !add(weighted, profile.material.input_units_per_product)) return false;
        }
        const auto* expected = field<Object>(record.intent, "expected");
        if (!expected || expected->size() != 3 || !field<Integer>(*expected, "raw") || !field<Integer>(*expected, "products") ||
            !field<Value::Array>(*expected, "work_lots") || *field<Integer>(*expected, "raw") != *raw ||
            *field<Integer>(*expected, "products") != *products || field<Value::Array>(*expected, "work_lots")->size() != work->size())
            return false;
        const auto& selected_work = *field<Value::Array>(*expected, "work_lots");
        for (std::size_t index = 0; index < work->size(); ++index) {
            const auto* selected = std::get_if<Object>(&selected_work[index].storage());
            const auto* moved = std::get_if<Object>(&(*work)[index].storage());
            if (!selected || !moved || selected->size() != 7) return false;
            for (const auto& [left, right] : {std::pair{"id", "id"}, {"recipe_input", "input_units_per_product"},
                    {"cycle_ticks", "cycle_ticks"}, {"remaining", "remaining_ticks"}, {"completed_subticks", "completed_subticks"},
                    {"work_remainder", "work_remainder"}, {"work_remainder_denominator", "work_remainder_denominator"}})
                if (!selected->contains(left) || !moved->contains(right) || values::typed_difference(selected->at(left), moved->at(right)))
                    return false;
        }
        return weighted > 0 && weighted <= profile.initial_units;
    }
    if (action == "harvest_source") {
        const auto* id = field<std::string>(record.intent, "target");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* raw = field<Integer>(result, "moved_raw");
        const auto* timber = field<Integer>(result, "moved_timber");
        if (!id || !entity || *entity != *id || !generation || *generation != 1 ||
            !raw || !timber || result.size() != 18) return false;
        if (profile.material.manual_ore && *id == profile.material.manual_ore->id)
            return *raw == 1 && *timber == 0 &&
                targets.front() == anchor(profile, profile.material.manual_ore->center);
        const auto found = profile.material.timber_sites.find(*id);
        return found != profile.material.timber_sites.end() && *raw == 0 && *timber == 1 &&
            targets.front() == anchor(profile, found->second.center);
    }
    if (action == "craft_component") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* requested_generation = field<Integer>(record.intent, "generation");
        const auto* requested_component = field<std::string>(record.intent, "component");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* made = field<std::string>(result, "component");
        const auto* timber = field<Integer>(result, "spent_timber");
        const auto* raw = field<Integer>(result, "spent_raw");
        const auto* count = field<Integer>(result, "component_count");
        const auto component = requested_component ? materials::component_from_name(*requested_component) : std::nullopt;
        const auto cost = component ? materials::component_cost(*component) : std::nullopt;
        const auto bench_center = historical_bench_center(hub, placed_components, target);
        return bench_center && target && requested_generation && *requested_generation > 0 &&
            entity && *entity == *target && generation && *generation == *requested_generation &&
            made && requested_component && *made == *requested_component &&
            cost && timber && *timber == cost->timber && raw && *raw == cost->ore &&
            count && *count > 0 && *count <= profile.material.component_capacity &&
            targets.front() == anchor(profile, *bench_center) && result.size() == 20;
    }
    if (action == "field_craft") {
        const auto* requested = field<std::string>(record.intent, "component");
        if (!requested) return false;
        const auto component = materials::component_from_name(*requested);
        if (!component) return false;
        const auto cost = materials::component_cost(*component);
        if (!cost) return false;
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* made = field<std::string>(result, "component");
        const auto* timber = field<Integer>(result, "spent_timber");
        const auto* raw = field<Integer>(result, "spent_raw");
        const auto* count = field<Integer>(result, "component_count");
        return cost->timber > 0 && cost->ore == 0 && entity && entity->empty() &&
            generation && *generation == 0 && made && *made == *requested &&
            timber && *timber == cost->timber && raw && *raw == 0 && count && *count > 0 &&
            *count <= profile.material.component_capacity && targets.front() == *actor_position &&
            result.size() == 20;
    }
    if (action == "deliver_first_plate") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* generation = field<Integer>(record.intent, "generation");
        const auto* entity = field<std::string>(result, "entity");
        const auto* actual_generation = field<Integer>(result, "generation");
        const auto* shipped = field<Integer>(result, "shipped_products");
        return profile.landing_pod_center && target && *target == "first-freight-beacon" &&
            generation && *generation == 1 && entity && *entity == *target &&
            actual_generation && *actual_generation == 1 && shipped && *shipped == 1 &&
            targets.front() == anchor(profile, landing_freight_center(*profile.landing_pod_center)) &&
            result.size() == 17;
    }
    if (action == "craft_part") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* requested_generation = field<Integer>(record.intent, "generation");
        const auto* requested_role = field<std::string>(record.intent, "role");
        const auto* requested_span = field<Integer>(record.intent, "half_span");
        const auto selected = requested_role ? role(*requested_role) : std::nullopt;
        const auto recipe = selected && requested_span ?
            profile.fabrication_parts.find({*selected, 0, *requested_span}) : profile.fabrication_parts.end();
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* made_role = field<std::string>(result, "role");
        const auto* made_span = field<Integer>(result, "half_span");
        const auto* timber = field<Integer>(result, "spent_timber");
        const auto* raw = field<Integer>(result, "spent_raw");
        const auto* count = field<Integer>(result, "part_count");
        const auto bench_center = historical_bench_center(hub, placed_components, target);
        return bench_center && target && requested_generation && *requested_generation > 0 &&
            entity && *entity == *target && generation && *generation == *requested_generation &&
            requested_role && made_role && *made_role == *requested_role &&
            requested_span && made_span && *made_span == *requested_span &&
            recipe != profile.fabrication_parts.end() && timber && *timber == recipe->second.timber &&
            raw && *raw == recipe->second.ore && count && *count > 0 && *count <= 4096 &&
            targets.front() == anchor(profile, *bench_center) && result.size() == 21;
    }
    if (action == "take_hand_crank" || action == "return_hand_crank") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* requested_generation = field<Integer>(record.intent, "generation");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* holder = field<std::string>(result, "holder");
        return profile.landing_pod_center && target && *target == "pod-hand-crank" &&
            requested_generation && *requested_generation == 1 &&
            entity && *entity == *target && generation && *generation == 1 &&
            holder && *holder == (action == "take_hand_crank" ? actor : "pod") &&
            targets.front() == anchor(profile, *profile.landing_pod_center) && result.size() == 17;
    }
    if (action == "stow_fabrication_hub" || action == "deploy_fabrication_hub") {
        const bool deploy = action == "deploy_fabrication_hub";
        const auto* target = field<std::string>(record.intent, "target");
        const auto* requested_generation = field<Integer>(record.intent, "generation");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* holder = field<std::string>(result, "holder");
        const auto center = deploy ? grid_point(record.intent) :
            (hub ? std::optional<mechanics::Point>(hub->center) : std::nullopt);
        return hub && target && *target == hub->id && requested_generation &&
            *requested_generation == hub->generation && entity && *entity == hub->id &&
            generation && *generation == hub->generation && holder &&
            *holder == (deploy ? "installed" : actor) &&
            (deploy ? hub->holder == actor : !hub->holder) && center &&
            targets.front() == anchor(profile, *center) && result.size() == 17;
    }
    if (action == "turn_hand_crank") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* requested_generation = field<Integer>(record.intent, "generation");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* shaft = field<Value::Array>(result, "shaft_center");
        const auto* receiver = field<Value::Array>(result, "receiver_center");
        const auto shaft_center = shaft ? grid_point(Object{{"center", Value(*shaft)}}) : std::nullopt;
        const auto receiver_center = receiver ? grid_point(Object{{"center", Value(*receiver)}}) : std::nullopt;
        const auto* raw = field<Integer>(result, "receiver_raw");
        const auto* source = field<Integer>(result, "source_remaining");
        return profile.material.manual_ore && !profile.collector_faces.empty() &&
            target && entity && *target == *entity && requested_generation && generation &&
            *requested_generation == *generation && *generation > 0 &&
            shaft_center && receiver_center && raw && *raw == 1 &&
            source && *source >= 0 && *source < profile.initial_units &&
            targets.front() == anchor(profile, *shaft_center) && result.size() == 20;
    }
    if (action == "feed_press") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* requested_generation = field<Integer>(record.intent, "generation");
        const auto* entry = field<Value::Array>(record.intent, "entry");
        const auto* work = field<Value::Array>(result, "work_center");
        const auto selected_entry = entry ? grid_point(Object{{"center", Value(*entry)}}) : std::nullopt;
        const auto selected_work = work ? grid_point(Object{{"center", Value(*work)}}) : std::nullopt;
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* moved = field<Integer>(result, "moved_raw");
        return profile.landing_pod_center && target && entity && *target == *entity &&
            requested_generation && generation && *requested_generation == *generation &&
            *generation > 0 && selected_entry && selected_work && moved && *moved == 1 &&
            targets.front() == anchor(profile, *selected_entry) && result.size() == 18;
    }
    if (action == "turn_press_crank") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* requested_generation = field<Integer>(record.intent, "generation");
        const auto* requested_exit = field<Value::Array>(record.intent, "exit");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* shaft = field<Value::Array>(result, "shaft_center");
        const auto* work = field<Value::Array>(result, "work_center");
        const auto* exit = field<Value::Array>(result, "exit_center");
        const auto* raw = field<Integer>(result, "work_raw");
        const auto* lots = field<Value::Array>(result, "work_lots");
        const auto* products = field<Integer>(result, "formed_products");
        const auto shaft_point = shaft ? grid_point(Object{{"center", Value(*shaft)}}) : std::nullopt;
        const auto work_point = work ? grid_point(Object{{"center", Value(*work)}}) : std::nullopt;
        const auto exit_point = exit ? grid_point(Object{{"center", Value(*exit)}}) : std::nullopt;
        const auto requested_point = requested_exit ?
            grid_point(Object{{"center", Value(*requested_exit)}}) : std::nullopt;
        return profile.landing_pod_center && target && entity && *target == *entity &&
            requested_generation && generation && *requested_generation == *generation &&
            *generation > 0 && shaft_point && work_point && exit_point &&
            requested_point == exit_point && raw && *raw == 0 && lots && lots->size() <= 1 &&
            products && (*products == 0 || *products == 1) &&
            targets.front() == anchor(profile, *shaft_point) && result.size() == 22;
    }
    if (action == "place_component" || action == "reclaim_component") {
        const auto* name = field<std::string>(result, "component");
        const auto* count = field<Integer>(result, "component_count");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        const auto* center = field<Value::Array>(result, "component_center");
        const auto location = center ? grid_point(Object{{"center", Value(*center)}}) : std::nullopt;
        if (!profile.landing_pod_center || !name || !materials::component_from_name(*name) ||
            !count || *count < 0 || *count > profile.material.component_capacity ||
            !entity || !generation || *generation <= 0 || !location ||
            targets.front() != anchor(profile, *location) || result.size() != 19) return false;
        if (action == "place_component") {
            const auto* requested = field<std::string>(record.intent, "component");
            return requested && *requested == *name &&
                grid_point(record.intent) == location && entity->starts_with(allocated_prefix);
        }
        const auto* target = field<std::string>(record.intent, "target");
        const auto* requested_generation = field<Integer>(record.intent, "generation");
        return target && *target == *entity && requested_generation && *requested_generation == *generation;
    }
    if (placement(action) || action == "place_foundation") {
        const auto location = grid_point(record.intent);
        if (action == "place_foundation")
            return location && (*location)[0] % 4 == 0 && (*location)[2] % 4 == 0 &&
                targets.front() == anchor(profile, *location) && result.size() == 16;
        const auto* role_name = field<std::string>(record.intent, "role");
        const auto* axis_name = field<std::string>(record.intent, "axis");
        const auto* teeth = field<Integer>(record.intent, "teeth");
        const auto* span = field<Integer>(record.intent, "half_span");
        const auto* wheel_tiles = field<Integer>(record.intent, "wheel_tiles");
        const auto* rotation = field<Integer>(record.intent, "rotation");
        const auto* relay_axis_name = field<std::string>(record.intent, "relay_axis");
        const auto selected_role = role_name ? role(*role_name) : std::nullopt;
        if (!location || !selected_role || !axis_name || !axis(*axis_name) || !teeth || !span ||
            !spec_valid({*selected_role, *teeth, *span}) || targets.front() != anchor(profile, *location) ||
            *selected_role == Role::belt ||
            (record.intent.contains("rotation") && (!rotation || !material_machine(*selected_role) ||
                *rotation < 0 || *rotation > 3)) ||
            (record.intent.contains("wheel_tiles") && (!wheel_tiles || *selected_role != Role::waterwheel ||
                *wheel_tiles < 3 || *wheel_tiles > mechanics::maximum_dimension)) ||
            (record.intent.contains("relay_axis") != (*selected_role == Role::chain_drive)) ||
            (relay_axis_name && (!axis(*relay_axis_name) || axis(*relay_axis_name) == axis(*axis_name))) ||
            (*selected_role == Role::gearbox && axis(*axis_name) != mechanics::Axis::y) ||
            (*selected_role == Role::vertical_gearbox && axis(*axis_name) == mechanics::Axis::y)) return false;
        if (transmission_role(*selected_role) &&
            std::any_of(location->begin(), location->end(),
                        [](Integer coordinate) { return coordinate % 4 != 0; })) return false;
        if (action == "place_connected" && !material_machine(*selected_role)) return false;
    } else if (action != "shaft_between" && action != "remove_shaft_between" && action != "place_belt_span" && action != "place_selected_belt_span") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* generation = field<Integer>(record.intent, "generation");
        if (!target || *target != *field<std::string>(result, "entity") ||
            !generation || *generation != *field<Integer>(result, "generation")) return false;
    }
    if (action == "place_belt_span" || action == "place_selected_belt_span") {
        const auto* first = field<Value::Array>(result, "first_center");
        const auto* last = field<Value::Array>(result, "last_center");
        const auto first_point = first ? grid_point(Object{{"center", Value(*first)}}) : std::nullopt;
        const auto last_point = last ? grid_point(Object{{"center", Value(*last)}}) : std::nullopt;
        if (!first_point || !last_point || *first_point == *last_point ||
            std::any_of(first_point->begin(), first_point->end(), [](Integer value) { return value % 4 != 0; }) ||
            std::any_of(last_point->begin(), last_point->end(), [](Integer value) { return value % 4 != 0; }) ||
            targets.back() != anchor(profile, *last_point) ||
            (action == "place_belt_span" && targets.front() != anchor(profile, *first_point))) return false;
    }
    const bool transfer = action == "recover" || action == "recover_belt_slot" || action == "load_belt_slot" || action == "insert_raw" || action == "insert_work";
    if (result.size() != (action == "place_belt_span" || action == "place_selected_belt_span" ? 18 :
                          (action == "recover_belt_slot" || action == "load_belt_slot") ? 20 : transfer ? 19 : action == "collect" ||
                          (action == "remove_belt_span" && points->size() == 1) ? 17 : 16)) return false;
    if (action == "remove_belt_span" && points->size() == 1) {
        const auto* center = field<Value::Array>(result, "belt_center");
        const auto location = center ? grid_point(Object{{"center", Value(*center)}}) : std::nullopt;
        if (!location || targets.front() != anchor(profile, *location)) return false;
    }
    if (action == "recover_belt_slot" || action == "load_belt_slot") {
        const auto* slot = field<Integer>(record.intent, "slot");
        const auto* center = field<Value::Array>(result, "slot_center");
        const auto location = center ? grid_point(Object{{"center", Value(*center)}}) : std::nullopt;
        if (!slot || *slot < 0 || *slot >= static_cast<Integer>(materials::maximum_belt_slots) || !location ||
            targets.front() != anchor(profile, *location)) return false;
    }
    if (action == "collect") {
        const auto* products = field<Integer>(result, "moved_products");
        return products && *products > 0 && *products == *field<Integer>(record.intent, "amount");
    }
    if (!transfer) return true;
    const auto* raw = field<Integer>(result, "moved_raw");
    const auto* products = field<Integer>(result, "moved_products");
    const auto* work = field<Value::Array>(result, "moved_work");
    if (!raw || !products || !work || *raw < 0 || *products < 0 || work->size() > maximum_current_work ||
        *products > std::numeric_limits<Integer>::max() / profile.material.input_units_per_product) return false;
    Integer weighted = *raw;
    if (!add(weighted, *products * profile.material.input_units_per_product)) return false;
    for (const auto& value : *work) {
        const auto* lot = std::get_if<Object>(&value.storage());
        if (!lot || lot->size() != 7 || !add(weighted, profile.material.input_units_per_product)) return false;
    }
    if (weighted == 0 || weighted > profile.initial_units) return false;
    if (action == "recover_belt_slot") {
        const auto* expected = field<Object>(record.intent, "expected");
        if (!expected || expected->size() != 3 || !field<Integer>(*expected, "raw") || !field<Integer>(*expected, "products") ||
            !field<Value::Array>(*expected, "work_lots") || *field<Integer>(*expected, "raw") != *raw ||
            *field<Integer>(*expected, "products") != *products || field<Value::Array>(*expected, "work_lots")->size() != work->size()) return false;
        for (std::size_t i = 0; i < work->size(); ++i) {
            const auto* a = std::get_if<Object>(&work->at(i).storage());
            const auto* b = std::get_if<Object>(&field<Value::Array>(*expected, "work_lots")->at(i).storage());
            if (!a || !b || b->size() != 7) return false;
            for (const auto& [left, right] : {std::pair{"id", "id"}, {"input_units_per_product", "recipe_input"},
                    {"cycle_ticks", "cycle_ticks"}, {"remaining_ticks", "remaining"}, {"completed_subticks", "completed_subticks"},
                    {"work_remainder", "work_remainder"}, {"work_remainder_denominator", "work_remainder_denominator"}}) {
                if (!a->contains(left) || !b->contains(right) || values::typed_difference(a->at(left), b->at(right))) return false;
            }
        }
    }
    if (action == "insert_raw")
        return *raw == *field<Integer>(record.intent, "amount") && *products == 0 && work->empty();
    if (action == "insert_work") {
        if (*raw != 0 || *products != 0 || work->size() != 1) return false;
        const auto* id = field<Integer>(std::get<Object>(work->front().storage()), "id");
        return id && *id == *field<Integer>(record.intent, "work_id");
    }
    if (action == "load_belt_slot") {
        const auto* kind = field<std::string>(record.intent, "item");
        const auto* id = field<Integer>(record.intent, "work_id");
        if (!kind || !id) return false;
        if (*kind == "raw") return *id == 0 && *raw == 1 && *products == 0 && work->empty();
        if (*kind == "product") return *id == 0 && *raw == 0 && *products == 1 && work->empty();
        if (*kind != "work" || *id <= 0 || *raw != 0 || *products != 0 || work->size() != 1) return false;
        const auto* lot_id = field<Integer>(std::get<Object>(work->front().storage()), "id");
        return lot_id && *lot_id == *id;
    }
    return true;
}

bool history_domain(const Profile& profile, const Snapshot& snapshot, const stationary::Kit& totals) {
    std::set<std::pair<std::string, std::string>> used_belt_selections;
    std::map<std::pair<std::string, Integer>, mechanics::Point> placed_shafts;
    auto foundation_kits = profile.starting_foundation_kits;
    std::map<std::string, Integer> harvested_timber;
    std::map<std::string, Integer> carried_timber;
    // A landing starts every actor with empty raw cargo, so its command history
    // can account for each later unit without inventing a second material State.
    std::map<std::string, Integer> carried_raw;
    Integer harvested_ore = 0;
    Integer cranked_ore = 0;
    Integer shipped_plates = 0;
    std::map<std::pair<std::string, materials::Component>, Integer> crafted_components;
    stationary::Kit fabricated_parts;
    std::map<std::string, stationary::Kit> fabricated_balances;
    std::map<std::string, stationary::PartSpec> installed_fabrication;
    PlacedHistory placed_components;
    std::optional<FabricationHub> historical_hub;
    if (profile.landing_pod_center)
        historical_hub = FabricationHub{"pod-fabrication-hub",
            landing_hub_center(*profile.landing_pod_center), 1};
    struct PressWorkRecord {
        materials::WorkId id{}; // Zero means a fed raw blank.
        Integer remaining{};
    };
    std::map<mechanics::Point, PressWorkRecord> press_work;
    std::set<mechanics::Point> press_products;
    std::set<materials::WorkId> press_work_ids;
    const auto within_component_capacity = [&](const std::string& actor) {
        Integer carried = 0;
        for (const auto& [owner_kind, count] : crafted_components)
            if (owner_kind.first == actor &&
                (count < 0 || !add(carried, count) || carried > profile.material.component_capacity)) return false;
        return true;
    };
    std::optional<std::string> crank_holder;
    for (const auto& record : snapshot.history.records) {
        const auto* actor = field<std::string>(record.intent, "actor");
        const auto* action = field<std::string>(record.intent, "action");
        const auto* accepted_value = field<bool>(record.result, "accepted");
        if (!actor || !profile.actors.contains(*actor) || !action || !accepted_value) return false;
        if (record.intent.contains("wire")) {
            const auto* wire = field<Object>(record.intent, "wire");
            if (!wire) return false;
            for (const auto* key : {"context", "client", "request"}) {
                const auto* original = field<std::string>(*wire, key);
                const auto* normalized = field<std::string>(record.intent, key);
                if (!original || !normalized || *original != *normalized) return false;
            }
        }
        // Malformed/refused commands retain their exact original intent too.
        if (!*accepted_value) continue;
        if (!shape(record.intent, *action)) return false;
        const auto* result_actor = field<std::string>(record.result, "actor");
        const auto* entity = field<std::string>(record.result, "entity");
        const auto* generation = field<Integer>(record.result, "generation");
        if (!result_actor || *result_actor != *actor || !entity || !generation) return false;
        if (*action != "pickup_material" && *action != "harvest_source" && *action != "field_craft") {
            const auto issued = snapshot.state.issued_entities.find(*entity);
            if (issued == snapshot.state.issued_entities.end() || issued->second != *generation) return false;
        }
        if (*action == "place_foundations") {
            const auto cells = foundation_area(record.intent);
            if (cells.empty() || *generation < static_cast<Integer>(cells.size())) return false;
            for (auto serial = *generation - static_cast<Integer>(cells.size()) + 1; serial <= *generation; ++serial) {
                const auto found = snapshot.state.issued_entities.find(std::string(allocated_prefix) + std::to_string(serial));
                if (found == snapshot.state.issued_entities.end() || found->second != serial) return false;
            }
        }
        if (two_endpoints(*action)) {
            const auto* from = field<std::string>(record.intent, "target");
            const auto* from_generation = field<Integer>(record.intent, "generation");
            const auto* to = field<std::string>(record.intent, "to");
            const auto* to_generation = field<Integer>(record.intent, "to_generation");
            if (!from || !from_generation || !to || !to_generation) return false;
            const auto source = snapshot.state.issued_entities.find(*from);
            const auto destination = snapshot.state.issued_entities.find(*to);
            if (source == snapshot.state.issued_entities.end() || source->second != *from_generation ||
                destination == snapshot.state.issued_entities.end() || destination->second != *to_generation) return false;
        }
        if (!historical_facts(profile, record, *actor, *action, placed_components, historical_hub))
            return false;
        if (*action == "stow_fabrication_hub") historical_hub->holder = *actor;
        if (*action == "deploy_fabrication_hub") {
            historical_hub->holder.reset();
            historical_hub->center = *grid_point(record.intent);
        }
        if (*action == "place_foundations" || *action == "place_foundation" ||
            *action == "remove_foundation") {
            const auto kit = foundation_kits.find(*actor);
            if (kit == foundation_kits.end()) return false;
            auto& carried = kit->second;
            if (*action == "remove_foundation") {
                if (!add(carried, 1) || carried > profile.foundation_parts) return false;
            } else {
                const Integer spent = *action == "place_foundations" ?
                    static_cast<Integer>(foundation_area(record.intent).size()) : 1;
                if (spent < 1 || carried < spent) return false;
                carried -= spent;
            }
        }
        if (*action == "harvest_source") {
            const auto& id = *field<std::string>(record.intent, "target");
            if (profile.material.manual_ore && id == profile.material.manual_ore->id) {
                if (!add(harvested_ore, 1) ||
                    (profile.landing_pod_center && !add(carried_raw[*actor], 1))) return false;
            } else if (!add(harvested_timber[id], 1) || !add(carried_timber[*actor], 1)) return false;
        }
        if (*action == "deliver_first_plate" && (!add(shipped_plates, 1) || shipped_plates > 1)) return false;
        if (*action == "craft_component" || *action == "field_craft") {
            const auto component = materials::component_from_name(*field<std::string>(record.intent, "component"));
            const auto cost = component ? materials::component_cost(*component) : std::nullopt;
            if (!cost || carried_timber[*actor] < cost->timber ||
                (profile.landing_pod_center && carried_raw[*actor] < cost->ore) ||
                !add(crafted_components[{*actor, *component}], 1) ||
                crafted_components[{*actor, *component}] != *field<Integer>(record.result, "component_count") ||
                !within_component_capacity(*actor))
                return false;
            carried_timber[*actor] -= cost->timber;
            if (profile.landing_pod_center) carried_raw[*actor] -= cost->ore;
        }
        if (*action == "craft_part") {
            const auto selected = role(*field<std::string>(record.intent, "role"));
            if (!selected) return false;
            const stationary::PartSpec spec{*selected, 0, *field<Integer>(record.intent, "half_span")};
            const auto recipe = profile.fabrication_parts.find(spec);
            if (recipe == profile.fabrication_parts.end() ||
                carried_timber[*actor] < recipe->second.timber ||
                carried_raw[*actor] < recipe->second.ore ||
                !add(fabricated_parts[spec], 1) || fabricated_parts[spec] > 4096 ||
                !add(fabricated_balances[*actor][spec], 1) ||
                fabricated_balances[*actor][spec] != *field<Integer>(record.result, "part_count"))
                return false;
            carried_timber[*actor] -= recipe->second.timber;
            carried_raw[*actor] -= recipe->second.ore;
        }
        if (*action == "take_hand_crank" || *action == "return_hand_crank") {
            if (!profile.landing_pod_center) return false;
            if (*action == "take_hand_crank") {
                if (crank_holder) return false;
                crank_holder = *actor;
            } else {
                if (crank_holder != *actor) return false;
                crank_holder.reset();
            }
        }
        if (*action == "turn_hand_crank") {
            if (crank_holder != *actor || !profile.material.manual_ore) return false;
            std::vector<assembly::Part> parts;
            parts.reserve(placed_components.size());
            for (const auto& [id, placed] : placed_components) {
                const auto issued = snapshot.state.issued_entities.find(id);
                if (issued == snapshot.state.issued_entities.end()) return false;
                parts.push_back({id, placed.first, placed.second, issued->second});
            }
            const auto selected = collector_for_shaft(profile, parts, *entity);
            const auto* receiver = field<Value::Array>(record.result, "receiver_center");
            const auto* shaft = field<Value::Array>(record.result, "shaft_center");
            if (!selected.collector || !receiver || !shaft ||
                grid_point(Object{{"center", Value(*receiver)}}) != selected.collector->receiver_center ||
                grid_point(Object{{"center", Value(*shaft)}}) != selected.collector->shaft_center ||
                !add(cranked_ore, 1)) return false;
        }
        if (*action == "feed_press") {
            if (carried_raw[*actor] < 1) return false;
            --carried_raw[*actor];
            const auto* entry = field<Value::Array>(record.intent, "entry");
            const auto* work = field<Value::Array>(record.result, "work_center");
            const auto selected_entry = entry ? grid_point(Object{{"center", Value(*entry)}}) : std::nullopt;
            const auto selected_work = work ? grid_point(Object{{"center", Value(*work)}}) : std::nullopt;
            const auto frame = placed_components.find(*entity);
            if (frame == placed_components.end() || frame->second.first != materials::Component::wooden_frame ||
                !selected_entry || !selected_work) return false;
            std::vector<assembly::Part> parts;
            parts.reserve(placed_components.size());
            for (const auto& [id, placed] : placed_components) {
                const auto issued = snapshot.state.issued_entities.find(id);
                if (issued == snapshot.state.issued_entities.end()) return false;
                parts.push_back({id, placed.first, placed.second, issued->second});
            }
            const auto inspected = assembly::inspect_press(parts, frame->second.second);
            if (!inspected.press || inspected.press->frame != *entity ||
                inspected.press->work_center != *selected_work ||
                std::none_of(inspected.press->open_feeds.begin(), inspected.press->open_feeds.end(),
                    [&](const assembly::PressFeed& feed) { return feed.entry == *selected_entry; }) ||
                !press_work.emplace(*selected_work, PressWorkRecord{}).second) return false;
        }
        if (*action == "turn_press_crank") {
            const auto* drive = field<std::string>(record.intent, "drive");
            const auto* exit = field<Value::Array>(record.intent, "exit");
            const auto* work = field<Value::Array>(record.result, "work_center");
            const auto* shaft = field<Value::Array>(record.result, "shaft_center");
            const auto* lots = field<Value::Array>(record.result, "work_lots");
            const auto* products = field<Integer>(record.result, "formed_products");
            const auto selected_exit = exit ? grid_point(Object{{"center", Value(*exit)}}) : std::nullopt;
            const auto selected_work = work ? grid_point(Object{{"center", Value(*work)}}) : std::nullopt;
            const auto selected_shaft = shaft ? grid_point(Object{{"center", Value(*shaft)}}) : std::nullopt;
            const auto frame = placed_components.find(*entity);
            if (crank_holder != *actor || !drive || !selected_exit || !selected_work ||
                !selected_shaft || !lots || !products || frame == placed_components.end() ||
                frame->second.first != materials::Component::wooden_frame) return false;
            std::vector<assembly::Part> parts;
            parts.reserve(placed_components.size());
            for (const auto& [id, placed] : placed_components) {
                const auto issued = snapshot.state.issued_entities.find(id);
                if (issued == snapshot.state.issued_entities.end()) return false;
                parts.push_back({id, placed.first, placed.second, issued->second});
            }
            const auto inspected = assembly::inspect_press(parts, frame->second.second);
            if (!inspected.press || inspected.press->frame != *entity ||
                inspected.press->shaft != *drive ||
                inspected.press->shaft_center != *selected_shaft ||
                inspected.press->work_center != *selected_work ||
                std::none_of(inspected.press->open_feeds.begin(), inspected.press->open_feeds.end(),
                    [&](const assembly::PressFeed& feed) { return feed.exit == *selected_exit; })) return false;
            const auto active = press_work.find(*selected_work);
            if (active == press_work.end()) return false;
            auto& entry = active->second;
            if (entry.id == 0) {
                if (lots->size() != 1) return false;
                const auto* lot = std::get_if<Object>(&lots->front().storage());
                const auto* id = lot ? field<Integer>(*lot, "id") : nullptr;
                if (!id || *id <= 0 || *id >= snapshot.state.material.next_work_id ||
                    !press_work_ids.insert(*id).second) return false;
                entry = {*id, profile.material.cycle_ticks};
            } else if (entry.remaining > 0) {
                --entry.remaining;
            }
            if (entry.id <= 0) return false;
            const materials::WorkLot expected{entry.id,
                {profile.material.input_units_per_product, profile.material.cycle_ticks}, entry.remaining};
            if (lots->size() == 1) {
                if (*products != 0 ||
                    values::typed_difference(lots_value({expected}), Value(*lots))) return false;
            } else {
                if (entry.remaining != 0 || *products != 1 ||
                    !press_products.insert(*selected_exit).second) return false;
                press_work.erase(active);
            }
        }
        if (*action == "pickup_material") {
            const auto point = grid_point(record.intent, materials::maximum_drop_coordinate);
            if (!point) return false;
            const auto active = press_work.find(*point);
            if (active != press_work.end()) {
                const auto* raw = field<Integer>(record.result, "moved_raw");
                const auto* products = field<Integer>(record.result, "moved_products");
                const auto* work = field<Value::Array>(record.result, "moved_work");
                if (!raw || !products || *products != 0 || !work) return false;
                if (active->second.id == 0) {
                    if (*raw != 1 || !work->empty()) return false;
                } else {
                    const materials::WorkLot expected{active->second.id,
                        {profile.material.input_units_per_product, profile.material.cycle_ticks},
                        active->second.remaining};
                    if (*raw != 0 || values::typed_difference(lots_value({expected}), Value(*work)))
                        return false;
                }
                press_work.erase(active);
            }
            if (press_products.erase(*point)) {
                const auto* raw = field<Integer>(record.result, "moved_raw");
                const auto* products = field<Integer>(record.result, "moved_products");
                const auto* work = field<Value::Array>(record.result, "moved_work");
                if (!raw || *raw != 0 || !products || *products != 1 || !work || !work->empty())
                    return false;
            }
        }
        if (profile.landing_pod_center &&
            (*action == "pickup_material" || *action == "recover" ||
             *action == "recover_belt_slot" || *action == "load_belt_slot" ||
             *action == "insert_raw")) {
            const auto* raw = field<Integer>(record.result, "moved_raw");
            if (!raw || *raw < 0) return false;
            auto& carried = carried_raw[*actor];
            if (*action == "pickup_material" || *action == "recover" ||
                *action == "recover_belt_slot") {
                if (!add(carried, *raw)) return false;
            } else {
                if (carried < *raw) return false;
                carried -= *raw;
            }
        }
        if (*action == "place_component" || *action == "reclaim_component") {
            const auto component = materials::component_from_name(*field<std::string>(record.result, "component"));
            const auto center = grid_point(Object{{"center", record.result.at("component_center")}});
            if (!component || !center) return false;
            auto& carried = crafted_components[{*actor, *component}];
            if (*action == "place_component") {
                if (carried < 1 || !placed_components.emplace(*entity, std::make_pair(*component, *center)).second)
                    return false;
                --carried;
            } else {
                const auto found = placed_components.find(*entity);
                if (found == placed_components.end() || found->second != std::make_pair(*component, *center) ||
                    carried >= profile.material.component_capacity) return false;
                placed_components.erase(found);
                ++carried;
            }
            if (carried != *field<Integer>(record.result, "component_count") ||
                !within_component_capacity(*actor)) return false;
        }
        if (placement(*action)) {
            const auto* role_name = field<std::string>(record.intent, "role");
            const auto center = grid_point(record.intent);
            if (role_name && *role_name == "shaft" && center)
                placed_shafts.emplace(std::make_pair(*entity, *generation), *center);
            const auto selected = role_name ? role(*role_name) : std::nullopt;
            if (selected) {
                const stationary::PartSpec spec{*selected, *field<Integer>(record.intent, "teeth"),
                    *field<Integer>(record.intent, "half_span")};
                if (profile.fabrication_parts.contains(spec) &&
                    (fabricated_balances[*actor][spec] < 1 ||
                     !installed_fabrication.emplace(*entity, spec).second)) return false;
                if (profile.fabrication_parts.contains(spec)) --fabricated_balances[*actor][spec];
            }
        }
        if (*action == "place_belt_span" || *action == "place_selected_belt_span") {
            const stationary::PartSpec spec{Role::belt, 0, 0};
            if (profile.fabrication_parts.contains(spec) &&
                (fabricated_balances[*actor][spec] < 1 ||
                 !installed_fabrication.emplace(*entity, spec).second)) return false;
            if (profile.fabrication_parts.contains(spec)) --fabricated_balances[*actor][spec];
        }
        if (*action == "remove" || *action == "remove_belt_span") {
            const auto installed = installed_fabrication.find(*entity);
            if (installed != installed_fabrication.end()) {
                if (!add(fabricated_balances[*actor][installed->second], 1)) return false;
                installed_fabrication.erase(installed);
            }
        }
        if (*action == "place_belt_span" || *action == "place_selected_belt_span") {
            for (const auto& [id_key, generation_key, center_key] : {
                    std::tuple{"target", "generation", "first_center"},
                    std::tuple{"to", "to_generation", "last_center"}}) {
                const auto* id = field<std::string>(record.intent, id_key);
                const auto* part_generation = field<Integer>(record.intent, generation_key);
                const auto* center = field<Value::Array>(record.result, center_key);
                const auto recorded = center ? grid_point(Object{{"center", Value(*center)}}) : std::nullopt;
                if (!id || !part_generation || !recorded) return false;
                const auto* live = part(snapshot.state.topology, *id);
                if (live && (live->role != Role::shaft || live->generation != *part_generation ||
                             live->geometry.center != *recorded)) return false;
                const auto prior = placed_shafts.find({*id, *part_generation});
                if (prior != placed_shafts.end() && prior->second != *recorded) return false;
            }
        }
        if (*action == "select_belt_shaft" || *action == "place_selected_belt_span") {
            const auto* id = field<std::string>(record.intent, *action == "select_belt_shaft" ? "target" : "to");
            const auto* generation = field<Integer>(record.intent, *action == "select_belt_shaft" ? "generation" : "to_generation");
            const auto* points = field<Value::Array>(record.result, "targets");
            const auto* live = id ? part(snapshot.state.topology, *id) : nullptr;
            if (!id || !generation || !points || points->size() != 1) return false;
            if (live && (live->role != Role::shaft || live->generation != *generation ||
                         values::typed_difference(points->front(), point_value(anchor(profile, live->geometry.center))))) return false;
        }
        if (*action == "place_selected_belt_span") {
            const auto* selection = field<std::string>(record.intent, "selection");
            const auto* client = field<std::string>(record.intent, "client");
            const auto* first = field<std::string>(record.intent, "target");
            const auto* generation = field<Integer>(record.intent, "generation");
            if (!selection || !client || !first || !generation ||
                !used_belt_selections.emplace(*client, *selection).second) return false;
            bool found = false;
            for (const auto& prior : snapshot.history.records) {
                if (&prior == &record) break;
                const auto* prior_actor = field<std::string>(prior.intent, "actor");
                const auto* prior_client = field<std::string>(prior.intent, "client");
                const auto* prior_action = field<std::string>(prior.intent, "action");
                const auto* request = field<std::string>(prior.intent, "request");
                const auto* target = field<std::string>(prior.intent, "target");
                const auto* target_generation = field<Integer>(prior.intent, "generation");
                const auto* ok = field<bool>(prior.result, "accepted");
                const auto* selected_points = field<Value::Array>(prior.result, "targets");
                const auto* first_center = field<Value::Array>(record.result, "first_center");
                const auto selected_center = first_center ? grid_point(Object{{"center", Value(*first_center)}}) : std::nullopt;
                if (prior_actor && *prior_actor == *actor && prior_client && *prior_client == *client &&
                    prior_action && *prior_action == "select_belt_shaft" && request && *request == *selection &&
                    target && *target == *first && target_generation && *target_generation == *generation && ok && *ok &&
                    selected_points && selected_points->size() == 1 && selected_center &&
                    !values::typed_difference(selected_points->front(), point_value(anchor(profile, *selected_center))))
                    found = true;
            }
            if (!found) return false;
        }
        if (const auto* lots = field<Value::Array>(record.result, "moved_work")) {
            for (const auto& value : *lots) {
                const auto* object = std::get_if<Object>(&value.storage());
                if (!object) return false;
                const auto* id = field<Integer>(*object, "id");
                const auto* weight = field<Integer>(*object, "input_units_per_product");
                const auto* cycle = field<Integer>(*object, "cycle_ticks");
                const auto* remaining = field<Integer>(*object, "remaining_ticks");
                const auto* completed = field<Integer>(*object, "completed_subticks");
                const auto* remainder = field<Integer>(*object, "work_remainder");
                const auto* denominator = field<Integer>(*object, "work_remainder_denominator");
                if (!id || *id <= 0 || *id >= snapshot.state.material.next_work_id ||
                    !weight || *weight != profile.material.input_units_per_product ||
                    !cycle || *cycle != profile.material.cycle_ticks ||
                    !remaining || *remaining < 0 || *remaining > *cycle || !completed ||
                    *completed < 0 || *completed >= materials::work_subticks_per_tick ||
                    !remainder || !denominator || *denominator <= 0 || *remainder < 0 || *remainder >= *denominator ||
                    (*remaining == 0 && (*completed != 0 || *remainder != 0))) return false;
            }
        }
    }
    for (const auto& [id, site] : profile.material.timber_sites) {
        const auto remaining = snapshot.state.material.timber_remaining.find(id);
        if (remaining == snapshot.state.material.timber_remaining.end() ||
            harvested_timber[id] != site.initial - remaining->second) return false;
    }
    for (const auto& [point, work] : press_work) {
        const auto item = snapshot.state.material.dropped_material.find(point);
        if (item == snapshot.state.material.dropped_material.end() || item->second.products != 0 ||
            item->second.raw_units != (work.id == 0 ? 1 : 0)) return false;
        if (work.id == 0) {
            if (!item->second.work_lots.empty()) return false;
        } else {
            const materials::WorkLot expected{work.id,
                {profile.material.input_units_per_product, profile.material.cycle_ticks}, work.remaining};
            if (item->second.work_lots != std::vector<materials::WorkLot>{expected}) return false;
        }
    }
    for (const auto& point : press_products) {
        const auto item = snapshot.state.material.dropped_material.find(point);
        if (item == snapshot.state.material.dropped_material.end() ||
            item->second.raw_units != 0 || item->second.products != 1 ||
            !item->second.work_lots.empty()) return false;
    }
    for (const auto& [actor, cargo] : snapshot.state.material.cargo)
        if (carried_timber[actor] != cargo.timber) return false;
    if (profile.landing_pod_center)
        for (const auto& [actor, cargo] : snapshot.state.material.cargo)
            if (carried_raw[actor] != cargo.raw_units) return false;
    if (foundation_kits != snapshot.state.foundation_kits) return false;
    if (harvested_ore > profile.initial_units - snapshot.state.material.stock.source ||
        cranked_ore > profile.initial_units - snapshot.state.material.stock.source - harvested_ore)
        return false;
    if (shipped_plates != snapshot.state.material.shipped_products) return false;
    if (profile.landing_pod_center && (!snapshot.state.hand_crank ||
        snapshot.state.hand_crank->holder != crank_holder)) return false;
    if (placed_components.size() != snapshot.state.placed_components.size()) return false;
    if (historical_hub != snapshot.state.fabrication_hub) return false;
    for (const auto& [id, placed] : snapshot.state.placed_components) {
        const auto found = placed_components.find(id);
        if (found == placed_components.end() || found->second != std::make_pair(placed.kind, placed.center)) return false;
    }
    for (const auto& [actor, cargo] : snapshot.state.material.cargo)
        for (const auto& [component, count] : cargo.components)
            if (crafted_components[{actor, component}] != count) return false;
    for (const auto& [actor_component, count] : crafted_components) {
        const auto actor = snapshot.state.material.cargo.find(actor_component.first);
        if (actor == snapshot.state.material.cargo.end()) return false;
        const auto found = actor->second.components.find(actor_component.second);
        if (count == 0 ? found != actor->second.components.end() :
            found == actor->second.components.end() || found->second != count) return false;
    }
    auto expected_parts = profile.finite_parts;
    for (const auto& [spec, recipe] : profile.fabrication_parts) {
        (void)recipe;
        expected_parts.try_emplace(spec, 0);
    }
    Integer embodied_timber = 0, embodied_raw = 0;
    for (const auto& [spec, count] : fabricated_parts) {
        const auto recipe = profile.fabrication_parts.find(spec);
        if (recipe == profile.fabrication_parts.end() || count < 1 ||
            !add(expected_parts[spec], count) ||
            !weighted_add(embodied_timber, count, recipe->second.timber) ||
            !weighted_add(embodied_raw, count, recipe->second.ore)) return false;
    }
    if (expected_parts != totals || embodied_timber != snapshot.state.material.fabricated_timber ||
        embodied_raw != snapshot.state.material.fabricated_raw) return false;
    for (const auto& [actor, kits] : snapshot.state.kits)
        for (const auto& [spec, recipe] : profile.fabrication_parts) {
            (void)recipe;
            const auto current = kits.find(spec);
            const auto balance = fabricated_balances[actor][spec];
            if ((current == kits.end() ? 0 : current->second) != balance) return false;
        }
    for (const auto& [id, spec] : installed_fabrication) {
        if (spec.role == Role::belt) {
            if (std::none_of(snapshot.state.topology.belt_spans.begin(), snapshot.state.topology.belt_spans.end(),
                    [&](const auto& span) { return span.geometry.id == id; })) return false;
        } else {
            const auto* live = part(snapshot.state.topology, id);
            if (!live || stationary::PartSpec{live->role, live->geometry.teeth,
                    live->geometry.half_span} != spec) return false;
        }
    }
    return true;
}
}  // namespace

materials::Path material_path(const stationary::Topology& topology) {
    materials::Path path;
    path.powered = topology.drive_enabled;
    for (const auto& item : topology.parts) {
        path.collector_present |= item.role == Role::collector;
        path.processor_present |= item.role == Role::processor;
    }
    return path;
}

namespace {

constexpr long double wooden_rating = 8;
constexpr long double softmetal_rating = 24;

long double material_rating(materials::Component kind) {
    return kind == materials::Component::wooden_shaft ||
           kind == materials::Component::wooden_cog ? wooden_rating : softmetal_rating;
}

mechanics::Axis horizontal_axis(const mechanics::Point& from, const mechanics::Point& to) {
    return from[0] != to[0] ? mechanics::Axis::x : mechanics::Axis::z;
}

DrivePower apply_load(const stationary::Topology& topology, mechanics::Result mechanical,
        const std::map<std::string, long double>& ratings,
        const std::map<std::string, long double>& assembly_impacts) {
    DrivePower power{std::move(mechanical), {}};
    if (!power.mechanical.accepted()) return power;
    // Component IDs have already been resolved by mechanics::evaluate. Index
    // the immutable topology once so disconnected machines do not rescan the
    // entire worksite for every part and water source on each native tick.
    std::unordered_map<std::string_view, const stationary::PlacedPart*> by_id;
    by_id.reserve(topology.parts.size());
    for (const auto& item : topology.parts) by_id.emplace(item.geometry.id, &item);
    std::unordered_map<std::string_view, mechanics::Rate> sources;
    sources.reserve(topology.sources.size());
    for (const auto& source : topology.sources) sources.emplace(source.hub, source.rate);
    constexpr long double wheel_capacity = 32;
    constexpr long double collector_impact = 4;
    constexpr long double processor_impact = 8;
    const auto magnitude = [](mechanics::Rate rate) {
        return std::abs(static_cast<long double>(rate.numerator)) / static_cast<long double>(rate.denominator);
    };
    for (auto& component : power.mechanical.components) {
        if (component.state != mechanics::MotionState::rotating) continue;
        long double capacity = 0, impact = 0;
        for (const auto& id : component.parts) {
            const auto found_item = by_id.find(id);
            const auto* item = found_item == by_id.end() ? nullptr : found_item->second;
            if (item && item->role == Role::waterwheel && topology.drive_enabled) {
                const auto source = sources.find(id);
                if (source != sources.end()) capacity += wheel_capacity * magnitude(source->second);
            }
            const auto speed = magnitude(power.mechanical.motion.at(id).rate);
            if (item && item->role == Role::collector) impact += collector_impact * speed;
            if (item && item->role == Role::processor) impact += processor_impact * speed;
            if (const auto found = assembly_impacts.find(id); found != assembly_impacts.end())
                impact += found->second * speed;
        }
        std::string limiting_part;
        for (const auto& id : component.parts) {
            const auto found = ratings.find(id);
            if (found != ratings.end() && found->second < capacity) {
                capacity = found->second;
                limiting_part = id;
            }
        }
        const NetworkLoad load{static_cast<double>(capacity), static_cast<double>(impact),
            impact > capacity, std::move(limiting_part)};
        for (const auto& id : component.parts) power.load.emplace(id, load);
        if (!load.overloaded) continue;
        component.state = mechanics::MotionState::stalled;
        for (const auto& id : component.parts)
            power.mechanical.motion.at(id) = {mechanics::MotionState::stalled, {0, 1}};
    }
    return power;
}

materials::MachinePower machine_power_from(const stationary::Topology& topology, const DrivePower& view) {
    materials::MachinePower power;
    if (!view.mechanical.accepted()) return power;
    for (const auto& item : topology.parts) {
        const auto found = view.mechanical.motion.find(item.geometry.id);
        const bool rotating = found != view.mechanical.motion.end() &&
            found->second.state == mechanics::MotionState::rotating;
        if (item.role == Role::collector) power.collector = rotating;
        if (item.role == Role::processor) {
            power.processor = rotating;
            if (rotating) {
                // Reversal does not reverse the press cycle. Saturate only at
                // the integer representation limit, not a gameplay speed cap.
                __extension__ using Wide = __int128;
                Wide numerator = found->second.rate.numerator;
                if (numerator < 0) numerator = -numerator;
                const Wide scaled = numerator * materials::work_subticks_per_tick;
                const auto denominator = found->second.rate.denominator;
                const Wide whole = scaled / denominator;
                power.processor_work_per_tick = static_cast<Integer>(std::min<Wide>(whole, std::numeric_limits<Integer>::max()));
                if (whole <= std::numeric_limits<Integer>::max()) {
                    power.processor_work_remainder = static_cast<Integer>(scaled % denominator);
                    if (power.processor_work_remainder != 0) power.processor_work_remainder_denominator = denominator;
                }
            }
        }
    }
    return power;
}

}  // namespace

DrivePower drive_power(const stationary::Topology& topology) {
    return apply_load(topology, stationary::power_view(topology).mechanical, {}, {});
}

static DrivePower drive_power_with_layout(const Profile& profile, const State& state,
        const std::vector<assembly::Part>& placed, const assembly::Layout& layout) {
    const auto base = stationary::power_view(state.topology);
    if (!base.mechanical.accepted()) return {base.mechanical, {}};
    std::vector<mechanics::Part> parts;
    parts.reserve(state.topology.parts.size() + state.placed_components.size());
    for (const auto& item : state.topology.parts) parts.push_back(item.geometry);
    std::map<std::string, long double> ratings, impacts;
    std::set<std::string> reserved_ids;
    for (const auto& part : state.topology.parts) reserved_ids.insert(part.geometry.id);
    for (const auto& part : placed) reserved_ids.insert(part.id);
    std::set<std::string> projected_hub_ids;
    const auto append = [&](mechanics::Part projected) {
        parts.push_back(std::move(projected));
    };
    for (const auto& face : profile.collector_faces) {
        const auto inspected = layout.inspect_collector(face);
        if (!inspected.collector) continue;
        const auto& found = *inspected.collector;
        const auto axis = horizontal_axis(found.machine_center, found.shaft_center);
        append({found.frame, mechanics::Kind::hub, found.machine_center, axis, 0, 0});
        projected_hub_ids.insert(found.frame);
        append({found.shaft, mechanics::Kind::shaft, found.shaft_center, axis, 0, 1});
        ratings.emplace(found.shaft, material_rating(found.shaft_material));
        impacts.emplace(found.frame, 4);
    }
    for (const auto& item : placed) {
        if (item.kind != materials::Component::wooden_frame) continue;
        const auto inspected = layout.inspect_press(item.center);
        if (!inspected.press) continue;
        const auto& found = *inspected.press;
        const auto axis = horizontal_axis(found.shaft_center, found.cog_center);
        const mechanics::Point hub{found.frame_center[0], found.shaft_center[1], found.frame_center[2]};
        std::string hub_id = found.frame;
        if (projected_hub_ids.contains(hub_id)) {
            // A single placed frame can carry a collector and a press at
            // different heights. Their graph hubs need distinct identities.
            std::size_t index = 0;
            do {
                hub_id = "projected-press-hub-" + std::to_string(index++);
            } while (reserved_ids.contains(hub_id));
            reserved_ids.insert(hub_id);
        }
        append({hub_id, mechanics::Kind::hub, hub, axis, 0, 0});
        projected_hub_ids.insert(hub_id);
        append({found.shaft, mechanics::Kind::shaft, found.shaft_center, axis, 0, 1});
        append({found.drive_cog, mechanics::Kind::gear, found.cog_center, axis, 2, 0});
        ratings.emplace(found.shaft, material_rating(found.shaft_material));
        ratings.emplace(found.drive_cog, material_rating(found.cog_material));
        impacts.emplace(hub_id, 8);
    }
    if (parts.size() > mechanics::maximum_parts) {
        mechanics::Result result;
        result.error = mechanics::Error::too_many_parts;
        return {std::move(result), {}};
    }
    auto sources = state.topology.sources;
    if (!state.topology.drive_enabled)
        for (auto& source : sources) source.rate = {0, 1};
    std::vector<mechanics::BeltSpan> spans;
    spans.reserve(state.topology.belt_spans.size());
    for (const auto& span : state.topology.belt_spans) spans.push_back(span.geometry);
    return apply_load(state.topology,
        mechanics::evaluate(parts, sources, spans, mechanics::SourcePolicy::overpower), ratings, impacts);
}

DrivePower drive_power(const Profile& profile, const State& state) {
    // With no placed modular components, the stationary solver already has
    // the complete graph. Reuse that result instead of deriving it twice.
    if (state.placed_components.empty()) return drive_power(state.topology);
    const auto placed = assembly_parts(state);
    const assembly::Layout layout(placed);
    return drive_power_with_layout(profile, state, placed, layout);
}

materials::MachinePower machine_power(const stationary::Topology& topology) {
    return machine_power_from(topology, drive_power(topology));
}

materials::MachinePower machine_power(const Profile& profile, const State& state) {
    return machine_power_from(state.topology, drive_power(profile, state));
}

bool validate(const Profile& profile, const Snapshot& snapshot) {
    if (profile.actors.empty() || profile.actors.size() > maximum_actors || profile.initial_units < 0 ||
        profile.finite_parts.size() + profile.fabrication_parts.size() > stationary::maximum_specifications ||
        profile.waterwheel_rate.numerator == 0 || profile.waterwheel_rate.denominator <= 0 ||
        !std::isfinite(profile.meters_per_grid_unit) || profile.meters_per_grid_unit <= 0 ||
        profile.meters_per_grid_unit > 1000 || !std::isfinite(profile.build_reach) ||
        profile.build_reach <= 0 || profile.build_reach > 1000000 ||
        profile.foundation_parts < 0 || profile.foundation_parts > 256) return false;
    if (!profile.fabrication_parts.empty() && !profile.landing_pod_center) return false;
    for (const auto& [spec, cost] : profile.fabrication_parts)
        if (!spec_valid(spec) || profile.finite_parts.contains(spec) ||
            (spec.role != Role::waterwheel && spec.role != Role::shaft && spec.role != Role::belt) ||
            cost.timber < 0 || cost.ore < 0 || (cost.timber == 0 && cost.ore == 0) ||
            cost.timber > 256 || cost.ore > profile.initial_units) return false;
    if (profile.landing_pod_center) {
        const auto& center = *profile.landing_pod_center;
        if (profile.foundation_parts < landing_deck_parts || center[0] % 4 || center[1] % 4 || center[2] % 4)
            return false;
        for (const auto coordinate : center)
            if (coordinate < -mechanics::maximum_coordinate + 4 ||
                coordinate > mechanics::maximum_coordinate - 4) return false;
    }
    if (profile.foundation_parts == 0) {
        if (!profile.starting_foundation_kits.empty()) return false;
    } else {
        if (profile.starting_foundation_kits.size() != profile.actors.size()) return false;
        Integer allocated = profile.landing_pod_center ? landing_deck_parts : 0;
        for (const auto& actor : profile.actors) {
            const auto found = profile.starting_foundation_kits.find(actor);
            if (found == profile.starting_foundation_kits.end() || !add(allocated, found->second))
                return false;
        }
        if (allocated > profile.foundation_parts) return false;
    }
    const auto valid_source = [](const std::string& id, const materials::DropPoint& center) {
        if (!identity(id) || id.starts_with(allocated_prefix) || id == "landing-pod" ||
        id == "pod-fabrication-hub" || id == "pod-hand-crank" || id == "first-freight-beacon" ||
        id.starts_with("pod-floor-")) return false;
        for (const auto coordinate : center)
            if (coordinate < -mechanics::maximum_coordinate ||
                coordinate > mechanics::maximum_coordinate) return false;
        return true;
    };
    if (profile.material.manual_ore &&
        !valid_source(profile.material.manual_ore->id, profile.material.manual_ore->center)) return false;
    if (profile.collector_faces.size() > maximum_issued_entities ||
        (!profile.landing_pod_center && !profile.collector_faces.empty()) ||
        (!profile.material.manual_ore && !profile.collector_faces.empty())) return false;
    std::set<std::pair<mechanics::Point, mechanics::Point>> unique_faces;
    for (const auto& face : profile.collector_faces)
        if (assembly::inspect_collector({}, face).status != assembly::Status::missing_frame ||
            !unique_faces.emplace(face.machine_center, face.toward_ore).second)
            return false;
    for (const auto& [id, site] : profile.material.timber_sites)
        if (!valid_source(id, site.center)) return false;
    if (profile.water.size() > 65536 || profile.wheel_radius <= 0 ||
        profile.wheel_radius > mechanics::maximum_coordinate / mechanics::maximum_dimension ||
        profile.wheel_axle_offset < -mechanics::maximum_coordinate ||
        profile.wheel_axle_offset > mechanics::maximum_coordinate) return false;
    for (const auto& [location, sample] : profile.water) {
        if (location[0] < -mechanics::maximum_coordinate || location[0] > mechanics::maximum_coordinate ||
            location[1] < -mechanics::maximum_coordinate || location[1] > mechanics::maximum_coordinate ||
            !waterwheel::rate(0, profile.wheel_radius, mechanics::Axis::x, sample)) return false;
    }
    for (const auto& actor : profile.actors) if (!identity(actor)) return false;
    for (const auto coordinate : profile.anchor_offset) if (!std::isfinite(coordinate)) return false;
    const auto& state = snapshot.state;
    if (state.landing_pod.has_value() != profile.landing_pod_center.has_value()) return false;
    if (state.fabrication_hub.has_value() != profile.landing_pod_center.has_value()) return false;
    if (state.freight_beacon.has_value() != profile.landing_pod_center.has_value()) return false;
    if (state.hand_crank.has_value() != profile.landing_pod_center.has_value()) return false;
    if (state.landing_pod) {
        const auto& pod = *state.landing_pod;
        const auto issued = state.issued_entities.find(pod.id);
        if (pod.id != "landing-pod" || pod.generation != 1 ||
            pod.center != *profile.landing_pod_center ||
            issued == state.issued_entities.end() || issued->second != pod.generation ||
            part(state.topology, pod.id) || state.foundations.contains(pod.id)) return false;
        // The trusted seed must account for the complete unfolded deck.
        // A missing tile needs a real accepted removal in this same history.
        const auto deck = landing_deck_centers(pod.center);
        for (std::size_t index = 0; index < deck.size(); ++index) {
            const auto id = "pod-floor-" + std::to_string(index);
            const auto issued_tile = state.issued_entities.find(id);
            if (issued_tile == state.issued_entities.end() || issued_tile->second != 1) return false;
            const auto tile = state.foundations.find(id);
            if (tile != state.foundations.end()) {
                if (tile->second.center != deck[index] || tile->second.generation != 1) return false;
            } else if (snapshot.revision == 0 || std::none_of(snapshot.history.records.begin(),
                    snapshot.history.records.end(), [&](const authority::Record& record) {
                        const auto* action = field<std::string>(record.intent, "action");
                        const auto* target = field<std::string>(record.intent, "target");
                        const auto* generation = field<Integer>(record.intent, "generation");
                        const auto* accepted = field<bool>(record.result, "accepted");
                        return action && *action == "remove_foundation" && target && *target == id &&
                               generation && *generation == 1 && accepted && *accepted;
                    })) return false;
        }
    }
    if (state.fabrication_hub) {
        const auto& hub = *state.fabrication_hub;
        const auto issued = state.issued_entities.find(hub.id);
        if (hub.id != "pod-fabrication-hub" || hub.generation != 1 ||
            issued == state.issued_entities.end() || issued->second != hub.generation ||
            part(state.topology, hub.id) || state.foundations.contains(hub.id) ||
            (hub.holder && !profile.actors.contains(*hub.holder)) ||
            std::any_of(hub.center.begin(), hub.center.end(),
                [](Integer coordinate) { return coordinate < -mechanics::maximum_coordinate ||
                    coordinate > mechanics::maximum_coordinate; }) ||
            std::any_of(hub.center.begin(), hub.center.end(),
                [](Integer coordinate) { return coordinate % 4 != 0; }) ||
            (!hub.holder && hub.center[1] != 0 &&
             std::none_of(state.foundations.begin(), state.foundations.end(),
                 [&](const auto& entry) { return entry.second.center == hub.center; })))
            return false;
        if (snapshot.revision == 0 &&
            (hub.holder || hub.center != landing_hub_center(*profile.landing_pod_center) ||
             !state.foundations.contains("pod-floor-7"))) return false;
        if (!hub.holder) {
            for (const auto& placed : state.topology.parts)
                if (material_machine(placed.role) && placed.geometry.center == hub.center) return false;
        }
    }
    if (state.freight_beacon) {
        const auto& beacon = *state.freight_beacon;
        const auto issued = state.issued_entities.find(beacon.id);
        if (beacon.id != "first-freight-beacon" || beacon.generation != 1 ||
            beacon.center != landing_freight_center(*profile.landing_pod_center) ||
            issued == state.issued_entities.end() || issued->second != beacon.generation ||
            part(state.topology, beacon.id) || state.foundations.contains(beacon.id) ||
            state.placed_components.contains(beacon.id)) return false;
    }
    if (state.material.shipped_products < 0 || state.material.shipped_products > 1) return false;
    if (state.hand_crank) {
        const auto& crank = *state.hand_crank;
        const auto issued = state.issued_entities.find(crank.id);
        if (crank.id != "pod-hand-crank" || crank.generation != 1 ||
            issued == state.issued_entities.end() || issued->second != 1 ||
            (crank.holder && !profile.actors.contains(*crank.holder)) ||
            part(state.topology, crank.id) || state.foundations.contains(crank.id) ||
            state.placed_components.contains(crank.id)) return false;
    }
    if (!profile.landing_pod_center && !state.placed_components.empty()) return false;
    if (state.placed_components.size() > maximum_issued_entities) return false;
    std::map<materials::Component, Integer> component_totals;
    std::set<mechanics::Point> component_centers;
    for (const auto& [id, placed] : state.placed_components) {
        const auto issued = state.issued_entities.find(id);
        if (issued == state.issued_entities.end() || issued->second != placed.generation ||
            placed.generation <= 0 || !id.starts_with(allocated_prefix) ||
            !materials::component_cost(placed.kind) ||
            !component_centers.insert(placed.center).second ||
            (state.fabrication_hub && !state.fabrication_hub->holder &&
             placed.center == state.fabrication_hub->center) ||
            !add(component_totals[placed.kind], 1)) return false;
        for (const auto coordinate : placed.center)
            if (coordinate < -mechanics::maximum_coordinate || coordinate > mechanics::maximum_coordinate) return false;
        if (placed.kind == materials::Component::wooden_workbench &&
            (std::any_of(placed.center.begin(), placed.center.end(),
                [](Integer coordinate) { return coordinate % 4 != 0; }) ||
             (placed.center[1] != 0 &&
              std::none_of(state.foundations.begin(), state.foundations.end(),
                  [&](const auto& entry) { return entry.second.center == placed.center; })))) return false;
        if (part(state.topology, id) || state.foundations.contains(id) ||
            std::any_of(state.topology.parts.begin(), state.topology.parts.end(),
                [&](const auto& item) { return item.geometry.center == placed.center; })) return false;
    }
    if (component_totals != state.material.placed_components) return false;
    if (state.material.initial_units != profile.initial_units ||
        state.material.cargo.size() != profile.actors.size() || state.kits.size() != profile.actors.size() ||
        state.issued_entities.size() > maximum_issued_entities || state.next_entity_serial < 1 ||
        authority::validate_history(snapshot.history, snapshot.revision) != authority::Error::none)
        return false;
    std::size_t current_work = state.material.processing ? 1 : 0;
    stationary::Kit totals;
    Integer foundation_total = static_cast<Integer>(state.foundations.size());
    if (profile.foundation_parts == 0) {
        if (!state.foundations.empty() || !state.foundation_kits.empty()) return false;
    } else {
        if (state.foundation_kits.size() != profile.actors.size()) return false;
        for (const auto& actor : profile.actors) {
            const auto kit = state.foundation_kits.find(actor);
            if (kit == state.foundation_kits.end() || !add(foundation_total, kit->second)) return false;
        }
        if (foundation_total != profile.foundation_parts) return false;
    }
    std::vector<mechanics::Point> foundation_centers;
    for (const auto& [id, foundation] : state.foundations) {
        const auto issued = state.issued_entities.find(id);
        if (issued == state.issued_entities.end() || issued->second != foundation.generation ||
            foundation.generation <= 0 || foundation.center[0] % 4 != 0 || foundation.center[2] % 4 != 0) return false;
        for (const auto coordinate : foundation.center)
            if (coordinate < -mechanics::maximum_coordinate || coordinate > mechanics::maximum_coordinate) return false;
        if (part(state.topology, id) || std::any_of(state.topology.belt_spans.begin(), state.topology.belt_spans.end(),
                [&](const auto& span) { return span.geometry.id == id; })) return false;
        for (const auto& center : foundation_centers)
            if (center[0] == foundation.center[0] && center[2] == foundation.center[2] &&
                std::abs(center[1] - foundation.center[1]) < foundation_depth_levels) return false;
        foundation_centers.push_back(foundation.center);
    }
    for (const auto& [spec, count] : profile.finite_parts) {
        if (!spec_valid(spec) || count <= 0) return false;
        totals.emplace(spec, 0);
    }
    for (const auto& [spec, cost] : profile.fabrication_parts) {
        (void)cost;
        totals.emplace(spec, 0);
    }
    for (const auto& actor : profile.actors) {
        const auto cargo = state.material.cargo.find(actor);
        const auto kit = state.kits.find(actor);
        if (cargo == state.material.cargo.end() || kit == state.kits.end() ||
            cargo->second.work_lots.size() > maximum_current_work - current_work ||
            kit->second.size() > stationary::maximum_specifications) return false;
        current_work += cargo->second.work_lots.size();
        for (const auto& [spec, count] : kit->second) {
            const auto total = totals.find(spec);
            if (total == totals.end() || !add(total->second, count)) return false;
        }
    }
    for (const auto& [id, generation] : state.issued_entities) {
        if (!identity(id) || generation <= 0) return false;
        if (id.starts_with(allocated_prefix)) {
            Integer serial{};
            const auto tail = std::string_view(id).substr(allocated_prefix.size());
            const auto parsed = std::from_chars(tail.data(), tail.data() + tail.size(), serial);
            if (parsed.ec != std::errc{} || parsed.ptr != tail.data() + tail.size() ||
                serial < 1 || serial >= state.next_entity_serial || generation != serial ||
                tail != std::to_string(serial)) return false;
        }
    }
    // A large site may have one trusted flow per wheel. Group source rates by
    // identity once while retaining the exact-match count used for restore.
    std::unordered_map<std::string_view, std::vector<mechanics::Rate>> source_rates;
    source_rates.reserve(state.topology.sources.size());
    for (const auto& source : state.topology.sources)
        source_rates[source.hub].push_back(source.rate);
    std::map<mechanics::Point, std::size_t> part_center_counts;
    std::unordered_map<std::string_view, const stationary::PlacedPart*> parts_by_id;
    parts_by_id.reserve(state.topology.parts.size());
    for (const auto& item : state.topology.parts) {
        ++part_center_counts[item.geometry.center];
        parts_by_id.emplace(item.geometry.id, &item);
    }
    const auto indexed_part = [&](const std::string& id) -> const stationary::PlacedPart* {
        const auto found = parts_by_id.find(id);
        return found == parts_by_id.end() ? nullptr : found->second;
    };
    for (const auto& item : state.topology.parts) {
        if (item.wheel_tiles < (item.role == Role::waterwheel ? 3 : 1) || item.wheel_tiles > mechanics::maximum_dimension ||
            (item.role != Role::waterwheel && item.wheel_tiles != 1)) return false;
        if (item.role == Role::belt) return false;
        if ((material_machine(item.role) || item.role == Role::waterwheel) && item.geometry.center[1] % 4 != 0) return false;
        if (transmission_role(item.role) &&
            std::any_of(item.geometry.center.begin(), item.geometry.center.end(),
                        [](Integer coordinate) { return coordinate % 4 != 0; })) return false;
        if (transmission_role(item.role) && part_center_counts.at(item.geometry.center) != 1) return false;
        if (profile.foundation_parts > 0 && material_machine(item.role) && item.geometry.center[1] != 0 &&
            std::none_of(state.foundations.begin(), state.foundations.end(), [&](const auto& entry) {
                return entry.second.center == item.geometry.center;
            })) return false;
        const auto issued = state.issued_entities.find(item.geometry.id);
        const auto total = totals.find({item.role, item.geometry.teeth, item.geometry.half_span});
        if (issued == state.issued_entities.end() || issued->second != item.generation ||
            total == totals.end() || !add(total->second, 1)) return false;
        const auto expected_rate = item.role == Role::waterwheel ? wheel_rate(profile, item) : std::nullopt;
        if (item.role == Role::waterwheel) {
            const auto rates = source_rates.find(item.geometry.id);
            if (!expected_rate || rates == source_rates.end() ||
                std::count(rates->second.begin(), rates->second.end(), *expected_rate) != 1) return false;
        }
    }
    for (const auto& span : state.topology.belt_spans) {
        const auto issued = state.issued_entities.find(span.geometry.id);
        const auto total = totals.find({Role::belt, 0, 0});
        const auto lane = state.material.belt_lanes.find(span.geometry.id);
        const auto* first = indexed_part(span.geometry.first_shaft);
        const auto* last = indexed_part(span.geometry.last_shaft);
        if (!first || !last || lane == state.material.belt_lanes.end() ||
            first->role != Role::shaft || last->role != Role::shaft ||
            first->geometry.axis != last->geometry.axis) return false;
        for (const auto coordinate : first->geometry.center)
            if (coordinate < -mechanics::maximum_coordinate || coordinate > mechanics::maximum_coordinate) return false;
        for (const auto coordinate : last->geometry.center)
            if (coordinate < -mechanics::maximum_coordinate || coordinate > mechanics::maximum_coordinate) return false;
        const auto path = mechanics::belt_path(first->geometry, last->geometry);
        if (!path || path->tiles.size() > materials::maximum_belt_slots ||
            lane->second.slots.size() != path->tiles.size()) return false;
        if ((path->kind == mechanics::BeltPathKind::vertical || path->kind == mechanics::BeltPathKind::sideways) &&
            (lane->second.phase != 0 || std::any_of(lane->second.slots.begin(), lane->second.slots.end(),
                [](const auto& item) { return item.has_value(); }))) return false;
        for (const auto& item : lane->second.slots) {
            if (item && item->work_lots.size() > maximum_current_work - current_work) return false;
            if (item) current_work += item->work_lots.size();
        }
        if (issued == state.issued_entities.end() || issued->second != span.generation ||
            total == totals.end() || !add(total->second, 1)) return false;
    }
    if (state.material.belt_lanes.size() != state.topology.belt_spans.size()) return false;
    if (!state.topology.material_links.empty()) return false;
    if (!drive_power(profile, state).mechanical.accepted() ||
        materials::validate(state.material, profile.material, material_path(state.topology)) != materials::Error::none)
        return false;
    return history_domain(profile, snapshot, totals);
}

std::unique_ptr<World> World::create(std::string context, Profile profile, const State& seed) {
    auto owner = Owner::create_new(std::move(context), seed,
        [profile](const Snapshot& candidate) { return validate(profile, candidate); });
    if (!owner) return nullptr;
    return std::unique_ptr<World>(new World(std::move(profile), std::move(owner)));
}

std::unique_ptr<World> World::restore(const std::string& expected_context,
                                   Profile profile, const Snapshot& saved) {
    if (saved.history.context != expected_context) return nullptr;
    auto owner = Owner::restore(saved,
        [profile](const Snapshot& candidate) { return validate(profile, candidate); });
    if (!owner) return nullptr;
    return std::unique_ptr<World>(new World(std::move(profile), std::move(owner)));
}

Delivery World::command(const Binding& binding, const Object& intent, const ObserveActor& observe) noexcept {
    const auto* actor = field<std::string>(intent, "actor");
    const auto* client = field<std::string>(intent, "client");
    if (!profile_.actors.contains(binding.actor) || !identity(binding.client) ||
        !actor || *actor != binding.actor || !client || *client != binding.client)
        return {TransactionError::history, authority::Error::wrong_actor, std::nullopt,
                owner_->current_revision()};
    return owner_->apply(intent, [&](const Snapshot& snapshot, const Object& request) {
        return plan(binding, snapshot, request, observe);
    });
}

Delivery World::refuse(const Binding& binding, const Object& intent, std::string reason) noexcept {
    const auto* actor = field<std::string>(intent, "actor");
    const auto* client = field<std::string>(intent, "client");
    if (!profile_.actors.contains(binding.actor) || !identity(binding.client) ||
        !actor || *actor != binding.actor || !client || *client != binding.client)
        return {TransactionError::history, authority::Error::wrong_actor, std::nullopt, owner_->current_revision()};
    return owner_->apply(intent, [&](const Snapshot&, const Object&) { return refused(std::move(reason)); });
}

Owner::Decision World::plan(const Binding& binding, const Snapshot& snapshot,
                            const Object& intent, const ObserveActor& observe) const {
    const auto* action = field<std::string>(intent, "action");
    if (!action || !shape(intent, *action)) return refused("invalid_command");
    const auto& state = snapshot.state;
    if (*action == "select_belt_shaft") {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        if (!id || !generation) return refused("invalid_target");
        const auto* selected = part(state.topology, *id);
        if (!selected) return refused("unknown_target", *id);
        if (selected->generation != *generation) return refused("stale_generation", *id);
        if (selected->role != Role::shaft) return refused("invalid_belt_geometry", *id);
        auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, *cut, {anchor(profile_, selected->geometry.center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        facts.emplace("generation", Value(*generation));
        return accepted(state, *id, std::move(facts));
    }
    if (*action == "pickup_material") {
        const auto point = grid_point(intent, materials::maximum_drop_coordinate);
        if (!point) return refused("invalid_center");
        if (!observe) return refused("actor_unready");
        auto cut = observe(binding.actor);
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile_.build_reach;
        auto reach = authority::check_reach(binding.actor, *cut, {anchor(profile_, *point)});
        Object facts = reach.receipt ? reach_facts(binding, *reach.receipt) : Object{};
        if (reach.error != authority::Error::none) return refused(authority::error_name(reach.error), "", std::move(facts));
        const auto found = state.material.dropped_material.find(*point);
        if (found == state.material.dropped_material.end()) return refused("unavailable_drop", "", std::move(facts));
        const auto* expected = field<Object>(intent, "expected");
        if (!expected || values::typed_difference(Value(*expected), belt_cargo_value(found->second)))
            return refused("drop_changed", "", std::move(facts));
        const auto contents = found->second;
        State candidate = state;
        const auto error = materials::pickup_material(candidate.material, profile_.material,
                                                  material_path(candidate.topology), binding.actor, *point);
        if (error != materials::Error::none) return refused(materials::error_name(error), "", std::move(facts));
        facts.emplace("generation", Value(Integer{0}));
        facts.emplace("moved_raw", Value(contents.raw_units));
        facts.emplace("moved_products", Value(contents.products));
        facts.emplace("moved_work", lots_value(contents.work_lots));
        return accepted(std::move(candidate), "", std::move(facts));
    }
    if (*action == "harvest_source") {
        const auto* id = field<std::string>(intent, "target");
        if (!id) return refused("invalid_target");
        const bool ore = profile_.material.manual_ore && profile_.material.manual_ore->id == *id;
        const auto tree = profile_.material.timber_sites.find(*id);
        if (!ore && tree == profile_.material.timber_sites.end()) return refused("unknown_target", *id);
        const auto& center = ore ? profile_.material.manual_ore->center : tree->second.center;
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut, {anchor(profile_, center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        auto candidate = state;
        const auto error = materials::harvest_source(candidate.material, profile_.material,
            material_path(candidate.topology), binding.actor, *id);
        if (error != materials::Error::none) return refused(materials::error_name(error), *id, std::move(facts));
        facts.emplace("generation", Value(Integer{1}));
        facts.emplace("moved_raw", Value(Integer{ore ? 1 : 0}));
        facts.emplace("moved_timber", Value(Integer{ore ? 0 : 1}));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "field_craft") {
        const auto* requested = field<std::string>(intent, "component");
        if (!requested) return refused("invalid_command");
        const auto component = materials::component_from_name(*requested);
        const auto cost = component ? materials::component_cost(*component) : std::nullopt;
        if (!cost || cost->ore != 0 || cost->timber < 1) return refused("unavailable_recipe");
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut, {checked_cut.position});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), {}, std::move(facts));
        auto candidate = state;
        const auto error = materials::craft_component(candidate.material, profile_.material,
            material_path(candidate.topology), binding.actor, *component);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), {}, std::move(facts));
        facts.emplace("generation", Value(Integer{0}));
        facts.emplace("component", Value(*requested));
        facts.emplace("spent_timber", Value(cost->timber));
        facts.emplace("spent_raw", Value(Integer{0}));
        facts.emplace("component_count", Value(candidate.material.cargo.at(binding.actor).components.at(*component)));
        return accepted(std::move(candidate), {}, std::move(facts));
    }
    if (*action == "craft_component") {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        const auto* requested = field<std::string>(intent, "component");
        if (!id || !generation || !requested) return refused("invalid_target");
        const auto placed_bench = state.placed_components.find(*id);
        const auto bench = state.fabrication_hub && !state.fabrication_hub->holder &&
            *id == state.fabrication_hub->id ?
            std::optional<FabricationHub>(*state.fabrication_hub) :
            placed_bench != state.placed_components.end() &&
                placed_bench->second.kind == materials::Component::wooden_workbench ?
                std::optional<FabricationHub>(FabricationHub{*id, placed_bench->second.center,
                    placed_bench->second.generation}) : std::nullopt;
        if (!bench) return refused("unknown_target", *id);
        if (*generation != bench->generation)
            return refused("stale_generation", *id);
        const auto component = materials::component_from_name(*requested);
        const auto cost = component ? materials::component_cost(*component) : std::nullopt;
        if (!cost) return refused("unavailable_recipe", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile_, bench->center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        auto candidate = state;
        const auto error = materials::craft_component(candidate.material, profile_.material,
            material_path(candidate.topology), binding.actor, *component);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), *id, std::move(facts));
        facts.emplace("generation", Value(*generation));
        facts.emplace("component", Value(*requested));
        facts.emplace("spent_timber", Value(cost->timber));
        facts.emplace("spent_raw", Value(cost->ore));
        facts.emplace("component_count", Value(candidate.material.cargo.at(binding.actor).components.at(*component)));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "deliver_first_plate") {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        if (!id || !generation) return refused("invalid_target");
        if (!state.freight_beacon || *id != state.freight_beacon->id)
            return refused("unknown_target", *id);
        if (*generation != state.freight_beacon->generation)
            return refused("stale_generation", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile_, state.freight_beacon->center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        if (state.material.shipped_products != 0) return refused("order_filled", *id, std::move(facts));
        const auto carried = state.material.cargo.find(binding.actor);
        if (carried == state.material.cargo.end() || carried->second.products < 1)
            return refused("no_plate", *id, std::move(facts));
        auto candidate = state;
        --candidate.material.cargo.at(binding.actor).products;
        candidate.material.shipped_products = 1;
        facts.emplace("generation", Value(*generation));
        facts.emplace("shipped_products", Value(Integer{1}));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "craft_part") {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        const auto* requested = field<std::string>(intent, "role");
        const auto* half_span = field<Integer>(intent, "half_span");
        if (!id || !generation || !requested || !half_span) return refused("invalid_target");
        const auto placed_bench = state.placed_components.find(*id);
        const auto bench = state.fabrication_hub && !state.fabrication_hub->holder &&
            *id == state.fabrication_hub->id ?
            std::optional<FabricationHub>(*state.fabrication_hub) :
            placed_bench != state.placed_components.end() &&
                placed_bench->second.kind == materials::Component::wooden_workbench ?
                std::optional<FabricationHub>(FabricationHub{*id, placed_bench->second.center,
                    placed_bench->second.generation}) : std::nullopt;
        if (!bench) return refused("unknown_target", *id);
        if (*generation != bench->generation)
            return refused("stale_generation", *id);
        const auto selected = role(*requested);
        const auto recipe = selected ? profile_.fabrication_parts.find({*selected, 0, *half_span}) :
            profile_.fabrication_parts.end();
        if (recipe == profile_.fabrication_parts.end()) return refused("unavailable_recipe", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile_, bench->center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        const auto cost = recipe->second;
        const auto& carried = state.material.cargo.at(binding.actor);
        if (carried.timber < cost.timber || carried.raw_units < cost.ore)
            return refused("unavailable_input", *id, std::move(facts));
        auto candidate = state;
        auto& next_cargo = candidate.material.cargo.at(binding.actor);
        next_cargo.timber -= cost.timber;
        next_cargo.raw_units -= cost.ore;
        if (!add(candidate.material.fabricated_timber, cost.timber) ||
            !add(candidate.material.fabricated_raw, cost.ore) ||
            !add(candidate.kits.at(binding.actor)[recipe->first], 1) ||
            candidate.kits.at(binding.actor)[recipe->first] > 4096)
            return refused("quantity_overflow", *id, std::move(facts));
        facts.emplace("generation", Value(*generation));
        facts.emplace("role", Value(*requested));
        facts.emplace("half_span", Value(*half_span));
        facts.emplace("spent_timber", Value(cost.timber));
        facts.emplace("spent_raw", Value(cost.ore));
        facts.emplace("part_count", Value(candidate.kits.at(binding.actor).at(recipe->first)));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "stow_fabrication_hub" || *action == "deploy_fabrication_hub") {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        if (!id || !generation) return refused("invalid_target");
        if (!state.fabrication_hub || *id != state.fabrication_hub->id)
            return refused("unknown_target", *id);
        const auto& hub = *state.fabrication_hub;
        if (*generation != hub.generation) return refused("stale_generation", *id);
        const bool deploy = *action == "deploy_fabrication_hub";
        if (deploy ? (!hub.holder || *hub.holder != binding.actor) : hub.holder.has_value())
            return refused(deploy ? "not_holder" : "already_stowed", *id);
        const auto location = deploy ? grid_point(intent) : std::optional<mechanics::Point>(hub.center);
        if (!location) return refused("invalid_cell", *id);
        const auto center = *location;
        if (deploy &&
            (std::any_of(center.begin(), center.end(),
                [](Integer coordinate) { return coordinate % 4 != 0; }) ||
             (center[1] != 0 &&
              std::none_of(state.foundations.begin(), state.foundations.end(),
                  [&](const auto& entry) { return entry.second.center == center; }))))
            return refused("unsupported_bench", *id);
        if (deploy &&
            (std::any_of(state.placed_components.begin(), state.placed_components.end(),
                [&](const auto& entry) { return entry.second.center == center; }) ||
             std::any_of(state.topology.parts.begin(), state.topology.parts.end(),
                [&](const auto& item) { return item.geometry.center == center; })))
            return refused("occupied", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut, {anchor(profile_, center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        auto candidate = state;
        candidate.fabrication_hub->center = center;
        candidate.fabrication_hub->holder = deploy ? std::nullopt : std::optional<std::string>(binding.actor);
        facts.emplace("generation", Value(*generation));
        facts.emplace("holder", Value(deploy ? "installed" : binding.actor));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "take_hand_crank" || *action == "return_hand_crank") {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        if (!id || !generation) return refused("invalid_target");
        if (!state.hand_crank || *id != state.hand_crank->id) return refused("unknown_target", *id);
        if (*generation != state.hand_crank->generation) return refused("stale_generation", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile_, state.landing_pod->center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        const bool taking = *action == "take_hand_crank";
        if (taking && state.hand_crank->holder) return refused("crank_held", *id, std::move(facts));
        if (!taking && state.hand_crank->holder != binding.actor)
            return refused("not_holder", *id, std::move(facts));
        auto candidate = state;
        candidate.hand_crank->holder = taking ? std::optional<std::string>{binding.actor} : std::nullopt;
        facts.emplace("generation", Value(*generation));
        facts.emplace("holder", Value(taking ? binding.actor : "pod"));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "turn_hand_crank") {
        if (!profile_.material.manual_ore || profile_.collector_faces.empty())
            return refused("collector_unavailable");
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        if (!id || !generation) return refused("invalid_target");
        const auto found = state.placed_components.find(*id);
        if (found == state.placed_components.end()) return refused("unknown_target", *id);
        if (found->second.generation != *generation) return refused("stale_generation", *id);
        if (found->second.kind != materials::Component::wooden_shaft &&
            found->second.kind != materials::Component::softmetal_shaft)
            return refused("not_drive_shaft", *id);
        if (!state.hand_crank || state.hand_crank->holder != binding.actor)
            return refused("not_crank_holder", *id);
        const auto assembly = collector_for_shaft(profile_, assembly_parts(state), *id);
        if (assembly.ambiguous) return refused("ambiguous_assembly", *id);
        if (!assembly.collector) return refused("incomplete_assembly", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile_, assembly.collector->shaft_center)});
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
    if (*action == "feed_press") {
        if (!profile_.landing_pod_center) return refused("press_unavailable");
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        const auto* entry = field<Value::Array>(intent, "entry");
        if (!id || !generation || !entry) return refused("invalid_target");
        const auto selected_entry = grid_point(Object{{"center", Value(*entry)}});
        if (!selected_entry) return refused("invalid_entry", *id);
        const auto frame = state.placed_components.find(*id);
        if (frame == state.placed_components.end()) return refused("unknown_target", *id);
        if (frame->second.generation != *generation) return refused("stale_generation", *id);
        if (frame->second.kind != materials::Component::wooden_frame)
            return refused("not_press_frame", *id);
        const auto inspected = assembly::inspect_press(assembly_parts(state), frame->second.center);
        if (inspected.status == assembly::PressStatus::ambiguous)
            return refused("ambiguous_assembly", *id);
        if (!inspected.press || inspected.press->frame != *id)
            return refused("incomplete_assembly", *id);
        if (std::none_of(inspected.press->open_feeds.begin(), inspected.press->open_feeds.end(),
                [&](const assembly::PressFeed& feed) { return feed.entry == *selected_entry; }))
            return refused("blocked_feed", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile_, *selected_entry)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        if (state.material.cargo.at(binding.actor).raw_units < 1)
            return refused("unavailable_input", *id, std::move(facts));
        const auto work = inspected.press->work_center;
        if (state.material.dropped_material.contains(work))
            return refused("input_full", *id, std::move(facts));
        if (state.material.dropped_material.size() >= materials::maximum_drop_points)
            return refused("output_full", *id, std::move(facts));
        auto candidate = state;
        --candidate.material.cargo.at(binding.actor).raw_units;
        candidate.material.dropped_material.emplace(work, materials::Cargo{1, 0, {}});
        facts.emplace("generation", Value(*generation));
        facts.emplace("work_center", Value(Value::Array{Value(work[0]), Value(work[1]), Value(work[2])}));
        facts.emplace("moved_raw", Value(Integer{1}));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "turn_press_crank") {
        if (!profile_.landing_pod_center) return refused("press_unavailable");
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        const auto* drive = field<std::string>(intent, "drive");
        const auto* exit = field<Value::Array>(intent, "exit");
        if (!id || !generation || !drive || !exit) return refused("invalid_target");
        const auto selected_exit = grid_point(Object{{"center", Value(*exit)}});
        if (!selected_exit) return refused("invalid_exit", *id);
        const auto frame = state.placed_components.find(*id);
        if (frame == state.placed_components.end()) return refused("unknown_target", *id);
        if (frame->second.generation != *generation) return refused("stale_generation", *id);
        if (frame->second.kind != materials::Component::wooden_frame)
            return refused("not_press_frame", *id);
        if (!state.hand_crank || state.hand_crank->holder != binding.actor)
            return refused("not_crank_holder", *id);
        const auto inspected = assembly::inspect_press(assembly_parts(state), frame->second.center);
        if (inspected.status == assembly::PressStatus::ambiguous)
            return refused("ambiguous_assembly", *id);
        if (!inspected.press || inspected.press->frame != *id)
            return refused("incomplete_assembly", *id);
        if (inspected.press->shaft != *drive) return refused("wrong_drive_shaft", *id);
        if (std::none_of(inspected.press->open_feeds.begin(), inspected.press->open_feeds.end(),
                [&](const assembly::PressFeed& feed) { return feed.exit == *selected_exit; }))
            return refused("blocked_exit", *id);
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready", *id);
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut,
            {anchor(profile_, inspected.press->shaft_center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        auto candidate = state;
        const auto error = materials::turn_press(candidate.material, profile_.material,
            material_path(candidate.topology), inspected.press->work_center, *selected_exit);
        if (error != materials::Error::none)
            return refused(materials::error_name(error), *id, std::move(facts));
        const auto work_item = candidate.material.dropped_material.find(inspected.press->work_center);
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
        facts.emplace("formed_products", Value(work_item == candidate.material.dropped_material.end() ?
            Integer{1} : Integer{0}));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "place_component" || *action == "reclaim_component") {
        if (!profile_.landing_pod_center) return refused("components_unavailable");
        const bool placing = *action == "place_component";
        const auto* requested = placing ? field<std::string>(intent, "component") : nullptr;
        const auto component = requested ? materials::component_from_name(*requested) : std::nullopt;
        const auto location = placing ? grid_point(intent) : std::nullopt;
        const auto* target = placing ? nullptr : field<std::string>(intent, "target");
        const auto* generation = placing ? nullptr : field<Integer>(intent, "generation");
        const auto found = target ? state.placed_components.find(*target) : state.placed_components.end();
        if (placing && (!component || !location)) return refused("invalid_component");
        if (!placing && (!target || !generation)) return refused("invalid_target");
        if (!placing && found == state.placed_components.end()) return refused("unknown_target", *target);
        if (!placing && found->second.generation != *generation) return refused("stale_generation", *target);
        const auto center = placing ? *location : found->second.center;
        const auto kind = placing ? *component : found->second.kind;
        if (placing && kind == materials::Component::wooden_workbench &&
            (std::any_of(center.begin(), center.end(),
                [](Integer coordinate) { return coordinate % 4 != 0; }) ||
             (center[1] != 0 &&
              std::none_of(state.foundations.begin(), state.foundations.end(),
                  [&](const auto& entry) { return entry.second.center == center; }))))
            return refused("unsupported_bench");
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut, {anchor(profile_, center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), target ? *target : "", std::move(facts));
        auto candidate = state;
        auto& cargo = candidate.material.cargo.at(binding.actor).components;
        std::string entity;
        Integer serial{};
        if (placing) {
            const auto owned = cargo.find(kind);
            if (owned == cargo.end() || owned->second < 1) return refused("no_component", "", std::move(facts));
            if (state.placed_components.size() >= maximum_issued_entities ||
                state.issued_entities.size() == maximum_issued_entities ||
                state.next_entity_serial == std::numeric_limits<Integer>::max())
                return refused("identity_limit", "", std::move(facts));
            if ((state.fabrication_hub && !state.fabrication_hub->holder &&
                 center == state.fabrication_hub->center) ||
                std::any_of(state.placed_components.begin(), state.placed_components.end(),
                    [&](const auto& entry) { return entry.second.center == center; }) ||
                std::any_of(state.topology.parts.begin(), state.topology.parts.end(),
                    [&](const auto& item) { return item.geometry.center == center; }))
                return refused("occupied", "", std::move(facts));
            if (--owned->second == 0) cargo.erase(owned);
            serial = candidate.next_entity_serial++;
            entity = std::string(allocated_prefix) + std::to_string(serial);
            if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
            candidate.issued_entities.emplace(entity, serial);
            candidate.placed_components.emplace(entity, PlacedComponent{kind, center, serial});
            ++candidate.material.placed_components[kind];
        } else {
            Integer carried = 0;
            for (const auto& [name, count] : cargo) {
                (void)name;
                if (!add(carried, count)) return refused("inventory_full", *target, std::move(facts));
            }
            if (carried >= profile_.material.component_capacity)
                return refused("inventory_full", *target, std::move(facts));
            entity = *target;
            serial = *generation;
            ++cargo[kind];
            candidate.placed_components.erase(entity);
            auto& placed = candidate.material.placed_components.at(kind);
            if (--placed == 0) candidate.material.placed_components.erase(kind);
        }
        facts.emplace("generation", Value(serial));
        facts.emplace("component", Value(materials::component_name(kind)));
        facts.emplace("component_count", Value(candidate.material.cargo.at(binding.actor).components.contains(kind) ?
            candidate.material.cargo.at(binding.actor).components.at(kind) : Integer{0}));
        facts.emplace("component_center", Value(Value::Array{Value(center[0]), Value(center[1]), Value(center[2])}));
        return accepted(std::move(candidate), entity, std::move(facts));
    }
    if (*action == "place_foundations") {
        if (profile_.foundation_parts == 0) return refused("foundations_unavailable");
        const auto cells = foundation_area(intent);
        if (cells.empty()) return refused("invalid_area");
        const auto count = static_cast<Integer>(cells.size());
        if (state.foundation_kits.at(binding.actor) < count) return refused("no_part");
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        // Area construction deliberately has no distance restriction. This cut
        // still verifies the actual bound actor and a valid native observation.
        const auto checked = authority::check_reach(binding.actor, checked_cut, {cut->position});
        Object facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none) return refused(authority::error_name(checked.error));
        auto candidate = state;
        std::string entity;
        Integer generation{};
        for (const auto& cell : cells) {
            for (const auto& placed : state.topology.parts)
                if (std::abs(placed.geometry.center[0] - cell[0]) < 4 &&
                    std::abs(placed.geometry.center[2] - cell[2]) < 4 &&
                    placed.geometry.center[1] < cell[1] && placed.geometry.center[1] + 4 > cell[1] - foundation_depth_levels)
                    return refused("occupied");
            for (const auto& [id, foundation] : state.foundations) {
                (void)id;
                if (foundation.center[0] == cell[0] && foundation.center[2] == cell[2] &&
                    std::abs(foundation.center[1] - cell[1]) < foundation_depth_levels) return refused("occupied");
            }
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
    if (*action == "place_foundation" || *action == "remove_foundation") {
        if (profile_.foundation_parts == 0) return refused("foundations_unavailable");
        auto location = grid_point(intent);
        std::string entity;
        Integer generation{};
        if (*action == "remove_foundation") {
            const auto* id = field<std::string>(intent, "target");
            const auto* expected = field<Integer>(intent, "generation");
            if (!id || !expected) return refused("invalid_target");
            const auto found = state.foundations.find(*id);
            if (found == state.foundations.end()) return refused("unknown_target", *id);
            if (found->second.generation != *expected) return refused("stale_generation", *id);
            if (state.fabrication_hub && !state.fabrication_hub->holder &&
                found->second.center == state.fabrication_hub->center)
                return refused("foundation_in_use", *id);
            if (std::any_of(state.placed_components.begin(), state.placed_components.end(),
                    [&](const auto& entry) { return entry.second.center == found->second.center; }))
                return refused("foundation_in_use", *id);
            location = found->second.center;
            entity = *id;
            generation = *expected;
        }
        if (!location || (*location)[0] % 4 != 0 || (*location)[2] % 4 != 0) return refused("invalid_cell");
        const auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        auto checked_cut = *cut;
        checked_cut.build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, checked_cut, {anchor(profile_, *location)});
        Object facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none) return refused(authority::error_name(checked.error), entity, std::move(facts));
        auto candidate = state;
        if (*action == "place_foundation") {
            for (const auto& placed : state.topology.parts)
                if (std::abs(placed.geometry.center[0] - (*location)[0]) < 4 &&
                    std::abs(placed.geometry.center[2] - (*location)[2]) < 4 &&
                    placed.geometry.center[1] < (*location)[1] && placed.geometry.center[1] + 4 > (*location)[1] - foundation_depth_levels)
                    return refused("occupied", "", std::move(facts));
            for (const auto& [id, foundation] : state.foundations) {
                (void)id;
                if (foundation.center[0] == (*location)[0] && foundation.center[2] == (*location)[2] &&
                    std::abs(foundation.center[1] - (*location)[1]) < foundation_depth_levels)
                    return refused("occupied", "", std::move(facts));
            }
            if (state.foundation_kits.at(binding.actor) == 0) return refused("no_part", "", std::move(facts));
            if (state.issued_entities.size() == maximum_issued_entities ||
                state.next_entity_serial == std::numeric_limits<Integer>::max()) return refused("identity_limit");
            generation = candidate.next_entity_serial++;
            entity = std::string(allocated_prefix) + std::to_string(generation);
            if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
            candidate.foundations.emplace(entity, Foundation{*location, generation});
            candidate.issued_entities.emplace(entity, generation);
            --candidate.foundation_kits.at(binding.actor);
        } else {
            for (const auto& placed : state.topology.parts)
                if (placed.geometry.center[0] == (*location)[0] && placed.geometry.center[2] == (*location)[2] &&
                    placed.geometry.center[1] >= (*location)[1] && placed.geometry.center[1] < (*location)[1] + foundation_depth_levels)
                    return refused("foundation_in_use", entity, std::move(facts));
            candidate.foundations.erase(entity);
            ++candidate.foundation_kits.at(binding.actor);
        }
        facts.emplace("generation", Value(generation));
        return accepted(std::move(candidate), entity, std::move(facts));
    }
    if (*action == "recover_belt_slot" || *action == "load_belt_slot") {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        const auto* index = field<Integer>(intent, "slot");
        const auto* expected = field<Object>(intent, "expected");
        if (!id || !generation || !index || (*action == "recover_belt_slot" && !expected)) return refused("invalid_target");
        const auto span = std::find_if(state.topology.belt_spans.begin(), state.topology.belt_spans.end(),
            [&](const auto& item) { return item.geometry.id == *id; });
        if (span == state.topology.belt_spans.end()) return refused("unknown_target", *id);
        if (span->generation != *generation) return refused("stale_generation", *id);
        const auto first = part(state.topology, span->geometry.first_shaft);
        const auto last = part(state.topology, span->geometry.last_shaft);
        const auto lane = state.material.belt_lanes.find(*id);
        if (!first || !last || lane == state.material.belt_lanes.end()) return refused("invalid_mechanics", *id);
        if (*index < 0 || static_cast<std::size_t>(*index) >= lane->second.slots.size()) return refused("invalid_slot", *id);
        const auto path = mechanics::belt_path(first->geometry, last->geometry);
        if (!path || static_cast<std::size_t>(*index) >= path->tiles.size()) return refused("invalid_mechanics", *id);
        if (*action == "load_belt_slot" && (path->kind == mechanics::BeltPathKind::vertical ||
            path->kind == mechanics::BeltPathKind::sideways)) return refused("belt_cannot_carry", *id);
        const auto center = path->tiles[static_cast<std::size_t>(*index)];
        auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, *cut, {anchor(profile_, center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none) return refused(authority::error_name(checked.error), *id, std::move(facts));
        const auto& item = lane->second.slots.at(static_cast<std::size_t>(*index));
        if (*action == "load_belt_slot") {
            if (item) return refused("slot_changed", *id, std::move(facts));
            const auto* kind = field<std::string>(intent, "item");
            const auto* work_id = field<Integer>(intent, "work_id");
            if (!kind || !work_id || ((*kind == "raw" || *kind == "product") && *work_id != 0) ||
                (*kind == "work" && *work_id <= 0) || (*kind != "raw" && *kind != "product" && *kind != "work"))
                return refused("invalid_cargo", *id, std::move(facts));
            auto candidate = state;
            auto& cargo = candidate.material.cargo.at(binding.actor);
            materials::Cargo moved;
            if (*kind == "raw" && cargo.raw_units > 0) { --cargo.raw_units; moved.raw_units = 1; }
            else if (*kind == "product" && cargo.products > 0) { --cargo.products; moved.products = 1; }
            else if (*kind == "work") {
                const auto lot = std::find_if(cargo.work_lots.begin(), cargo.work_lots.end(),
                    [&](const auto& value) { return value.id == *work_id; });
                if (lot == cargo.work_lots.end()) return refused("unavailable_cargo", *id, std::move(facts));
                moved.work_lots.push_back(*lot);
                cargo.work_lots.erase(lot);
            } else return refused("unavailable_cargo", *id, std::move(facts));
            candidate.material.belt_lanes.at(*id).slots.at(static_cast<std::size_t>(*index)) = moved;
            facts.emplace("generation", Value(*generation));
            facts.emplace("moved_raw", Value(moved.raw_units));
            facts.emplace("moved_products", Value(moved.products));
            facts.emplace("moved_work", lots_value(moved.work_lots));
            facts.emplace("slot_center", Value(Value::Array{Value(center[0]), Value(center[1]), Value(center[2])}));
            return accepted(std::move(candidate), *id, std::move(facts));
        }
        if (!item || values::typed_difference(Value(*expected), belt_cargo_value(*item)))
            return refused("slot_changed", *id, std::move(facts));
        auto candidate = state;
        auto& cargo = candidate.material.cargo.at(binding.actor);
        if (!add(cargo.raw_units, item->raw_units) || !add(cargo.products, item->products) ||
            cargo.work_lots.size() + item->work_lots.size() > maximum_current_work)
            return refused("quantity_overflow", *id, std::move(facts));
        cargo.work_lots.insert(cargo.work_lots.end(), item->work_lots.begin(), item->work_lots.end());
        candidate.material.belt_lanes.at(*id).slots.at(static_cast<std::size_t>(*index)).reset();
        facts.emplace("generation", Value(*generation));
        facts.emplace("moved_raw", Value(item->raw_units));
        facts.emplace("moved_products", Value(item->products));
        facts.emplace("moved_work", lots_value(item->work_lots));
        facts.emplace("slot_center", Value(Value::Array{Value(center[0]), Value(center[1]), Value(center[2])}));
        return accepted(std::move(candidate), *id, std::move(facts));
    }
    if (*action == "place_belt_span" || *action == "place_selected_belt_span" || *action == "remove_belt_span") {
        const bool placing = *action != "remove_belt_span";
        const auto* id = field<std::string>(intent, "target");
        const auto* expected = field<Integer>(intent, "generation");
        if (!id || !expected) return refused("invalid_target");
        const stationary::PlacedPart* first = nullptr;
        const stationary::PlacedPart* last = nullptr;
        if (placing) {
            first = part(state.topology, *id);
            const auto* to = field<std::string>(intent, "to");
            const auto* to_generation = field<Integer>(intent, "to_generation");
            if (!to || !to_generation) return refused("invalid_target");
            last = part(state.topology, *to);
            if (!first || !last) return refused("unknown_target");
            if (first->generation != *expected || last->generation != *to_generation)
                return refused("stale_generation");
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path)
                return refused("invalid_belt_geometry");
            if (*action == "place_selected_belt_span") {
                const auto* selection = field<std::string>(intent, "selection");
                const authority::Record* selected = nullptr;
                bool used = false;
                for (const auto& record : snapshot.history.records) {
                    const auto* actor = field<std::string>(record.intent, "actor");
                    const auto* client = field<std::string>(record.intent, "client");
                    const auto* recorded_action = field<std::string>(record.intent, "action");
                    const auto* request = field<std::string>(record.intent, "request");
                    const auto* ok = field<bool>(record.result, "accepted");
                    if (!actor || *actor != binding.actor || !client || *client != binding.client || !recorded_action || !ok || !*ok) continue;
                    if (*recorded_action == "select_belt_shaft" && request && selection && *request == *selection) selected = &record;
                    if (*recorded_action == "place_selected_belt_span") {
                        const auto* prior = field<std::string>(record.intent, "selection");
                        if (prior && selection && *prior == *selection) used = true;
                    }
                }
                const auto* selected_target = selected ? field<std::string>(selected->intent, "target") : nullptr;
                const auto* selected_generation = selected ? field<Integer>(selected->intent, "generation") : nullptr;
                const auto* selected_points = selected ? field<Value::Array>(selected->result, "targets") : nullptr;
                if (!selection || !selected_target || *selected_target != first->geometry.id || !selected_generation ||
                    *selected_generation != first->generation || !selected_points || selected_points->size() != 1 ||
                    values::typed_difference(selected_points->front(), point_value(anchor(profile_, first->geometry.center))) || used)
                    return refused("invalid_belt_selection");
            }
        } else {
            const auto found = std::find_if(state.topology.belt_spans.begin(), state.topology.belt_spans.end(),
                [&](const auto& span) { return span.geometry.id == *id; });
            if (found == state.topology.belt_spans.end()) return refused("unknown_target", *id);
            if (found->generation != *expected) return refused("stale_generation", *id);
            first = part(state.topology, found->geometry.first_shaft);
            last = part(state.topology, found->geometry.last_shaft);
            if (!first || !last) return refused("invalid_mechanics", *id);
        }
        auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile_.build_reach;
        std::optional<mechanics::Point> removal_center;
        if (*action == "remove_belt_span") {
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path || path->tiles.empty()) return refused("invalid_mechanics", *id);
            removal_center = *std::min_element(path->tiles.begin(), path->tiles.end(), [&](const auto& a, const auto& b) {
                const auto squared = [&](const auto& tile) {
                    const auto position = anchor(profile_, tile);
                    double distance = 0;
                    for (std::size_t i = 0; i < position.size(); ++i) distance += (position[i] - cut->position[i]) * (position[i] - cut->position[i]);
                    return distance;
                };
                return squared(a) < squared(b);
            });
        }
        const auto checked = authority::check_reach(binding.actor, *cut,
            removal_center ? std::vector<authority::Point>{anchor(profile_, *removal_center)} :
            *action == "place_selected_belt_span" ? std::vector<authority::Point>{anchor(profile_, last->geometry.center)} :
                std::vector<authority::Point>{anchor(profile_, first->geometry.center), anchor(profile_, last->geometry.center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none)
            return refused(authority::error_name(checked.error), *id, std::move(facts));
        auto candidate = state;
        auto entity = *id;
        auto generation = *expected;
        if (placing) {
            if (candidate.issued_entities.size() == maximum_issued_entities ||
                candidate.next_entity_serial == std::numeric_limits<Integer>::max()) return refused("identity_limit");
            generation = candidate.next_entity_serial++;
            entity = std::string(allocated_prefix) + std::to_string(generation);
            if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
            const stationary::PlacedBeltSpan span{{entity, first->geometry.id, last->geometry.id}, generation};
            auto proposal = stationary::prepare_belt_placement(state.topology, state.kits.at(binding.actor), state.material, span);
            if (const auto* error = std::get_if<stationary::PlacementRefusal>(&proposal))
                return refused(stationary::placement_error_name(error->reason), "", std::move(facts));
            auto& ready = std::get<stationary::PreparedPlacement>(proposal);
            candidate.topology = std::move(ready.candidate);
            candidate.kits.at(binding.actor) = std::move(ready.candidate_kit);
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path) return refused("invalid_belt_geometry");
            candidate.material.belt_lanes.emplace(entity, materials::BeltLane{
                std::vector<std::optional<materials::Cargo>>(path->tiles.size()), 0});
            candidate.issued_entities.emplace(entity, generation);
            facts.emplace("first_center", Value(Value::Array{Value(first->geometry.center[0]), Value(first->geometry.center[1]), Value(first->geometry.center[2])}));
            facts.emplace("last_center", Value(Value::Array{Value(last->geometry.center[0]), Value(last->geometry.center[1]), Value(last->geometry.center[2])}));
        } else {
            auto proposal = stationary::prepare_belt_removal(state.topology, state.kits.at(binding.actor), state.material,
                                                             {entity, generation});
            if (const auto* error = std::get_if<stationary::RemovalRefusal>(&proposal))
                return refused(stationary::removal_error_name(error->reason), entity, std::move(facts));
            auto& ready = std::get<stationary::PreparedRemoval>(proposal);
            candidate.topology = std::move(ready.candidate);
            candidate.kits.at(binding.actor) = std::move(ready.candidate_kit);
            candidate.material.belt_lanes.erase(entity);
            facts.emplace("belt_center", Value(Value::Array{Value((*removal_center)[0]), Value((*removal_center)[1]), Value((*removal_center)[2])}));
        }
        facts.emplace("generation", Value(generation));
        return accepted(std::move(candidate), entity, std::move(facts));
    }
    const stationary::PlacedPart* selected = nullptr;
    const stationary::PlacedPart* destination = nullptr;
    std::optional<mechanics::Point> location;
    std::optional<Role> selected_role;
    std::optional<mechanics::Axis> selected_axis;
    std::vector<authority::Point> targets;
    if (placement(*action)) {
        const auto* role_name = field<std::string>(intent, "role");
        const auto* axis_name = field<std::string>(intent, "axis");
        const auto* teeth = field<Integer>(intent, "teeth");
        const auto* span = field<Integer>(intent, "half_span");
        const auto* wheel_tiles = field<Integer>(intent, "wheel_tiles");
        const auto* rotation = field<Integer>(intent, "rotation");
        const auto* relay_axis_name = field<std::string>(intent, "relay_axis");
        location = grid_point(intent);
        if (!role_name || !axis_name || !teeth || !span || !location ||
            !(selected_role = role(*role_name)) || !(selected_axis = axis(*axis_name)) ||
            !spec_valid({*selected_role, *teeth, *span}) ||
            (intent.contains("rotation") && (!rotation || !material_machine(*selected_role) ||
                *rotation < 0 || *rotation > 3)) ||
            (intent.contains("wheel_tiles") && (!wheel_tiles || *selected_role != Role::waterwheel ||
                *wheel_tiles < 3 || *wheel_tiles > mechanics::maximum_dimension)) ||
            (intent.contains("relay_axis") != (*selected_role == Role::chain_drive)) ||
            (relay_axis_name && (!axis(*relay_axis_name) || axis(*relay_axis_name) == *selected_axis)) ||
            (*selected_role == Role::gearbox && *selected_axis != mechanics::Axis::y) ||
            (*selected_role == Role::vertical_gearbox && *selected_axis == mechanics::Axis::y)) return refused("invalid_part");
        if (*selected_role == Role::belt) return refused("invalid_part");
        if (state.fabrication_hub && !state.fabrication_hub->holder && material_machine(*selected_role) &&
            *location == state.fabrication_hub->center) return refused("occupied");
        if ((material_machine(*selected_role) || *selected_role == Role::waterwheel) && (*location)[1] % 4 != 0)
            return refused("unaligned_elevation");
        if (transmission_role(*selected_role) &&
            std::any_of(location->begin(), location->end(),
                        [](Integer coordinate) { return coordinate % 4 != 0; })) return refused("invalid_cell");
        targets.push_back(anchor(profile_, *location));
        if (profile_.foundation_parts > 0 && material_machine(*selected_role) && (*location)[1] != 0) {
            const bool supported = std::any_of(state.foundations.begin(), state.foundations.end(),
                [&](const auto& entry) { return entry.second.center == *location; });
            if (!supported) return refused("foundation_required");
        }
        if (*action == "place_connected" && !material_machine(*selected_role)) return refused("invalid_part");
    } else {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        if (!id || !generation) return refused("invalid_target");
        selected = part(state.topology, *id);
        if (!selected) return refused("unknown_target", *id);
        if (selected->generation != *generation) return refused("stale_generation", *id);
        targets.push_back(anchor(profile_, selected->geometry.center));
        if (two_endpoints(*action)) {
            const auto* to = field<std::string>(intent, "to");
            const auto* to_generation = field<Integer>(intent, "to_generation");
            if (!to || !to_generation) return refused("invalid_target");
            destination = part(state.topology, *to);
            if (!destination) return refused("unknown_target", *to);
            if (destination->generation != *to_generation) return refused("stale_generation", *to);
            targets.push_back(anchor(profile_, destination->geometry.center));
        }
    }
    if (!observe) return refused("actor_unready");
    auto cut = observe(binding.actor);
    if (!cut) return refused("actor_unready");
    // Reach is profile authority, regardless of what the provider's generic
    // ActorCut happened to contain. Clients never supply either input.
    cut->build_reach = profile_.build_reach;
    auto reach = authority::check_reach(binding.actor, *cut, targets);
    Object facts = reach.receipt ? reach_facts(binding, *reach.receipt) : Object{};
    if (reach.error != authority::Error::none)
        return refused(authority::error_name(reach.error), selected ? selected->geometry.id : "", std::move(facts));

    State candidate = state;
    std::string entity;
    Integer generation{};
    if (*action == "shaft_between" || *action == "remove_shaft_between") {
        return refused("individual_shaft_required", selected->geometry.id, std::move(facts));
    }
    if (placement(*action) && std::any_of(state.topology.parts.begin(), state.topology.parts.end(), [&](const auto& existing) {
            return existing.geometry.center == *location &&
                (transmission_role(*selected_role) || transmission_role(existing.role));
        })) return refused("occupied", "", std::move(facts));
    if (placement(*action)) {
        if (candidate.issued_entities.size() == maximum_issued_entities ||
            candidate.next_entity_serial == std::numeric_limits<Integer>::max())
            return refused("identity_limit");
        generation = candidate.next_entity_serial++;
        entity = std::string(allocated_prefix) + std::to_string(generation);
        if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
        const auto kind = *selected_role == Role::gear ? mechanics::Kind::gear :
                          *selected_role == Role::shaft ? mechanics::Kind::shaft :
                          (*selected_role == Role::gearbox || *selected_role == Role::vertical_gearbox) ? mechanics::Kind::gearbox :
                          *selected_role == Role::chain_drive ? mechanics::Kind::chain_drive : mechanics::Kind::hub;
        const auto* relay_axis_name = field<std::string>(intent, "relay_axis");
        stationary::PlacedPart placed{
            {entity, kind, *location, *selected_axis, *field<Integer>(intent, "teeth"),
             *field<Integer>(intent, "half_span"), relay_axis_name ? *axis(*relay_axis_name) : mechanics::Axis::x},
            generation, *selected_role};
        placed.geometry.id = entity;
        placed.generation = generation;
        if (const auto* rotation = field<Integer>(intent, "rotation")) placed.rotation = *rotation;
        if (placed.role == Role::waterwheel && field<Integer>(intent, "wheel_tiles"))
            placed.wheel_tiles = *field<Integer>(intent, "wheel_tiles");
        stationary::PlacementSelection selection{placed, std::nullopt};
        if (placed.role == Role::waterwheel) {
            const auto rate = wheel_rate(profile_, placed);
            if (!rate) return refused("invalid_waterwheel");
            selection.source = mechanics::Drive{entity, *rate};
        }
        auto proposal = stationary::prepare_placement(state.topology, state.kits.at(binding.actor),
                                                     state.material, selection);
        if (const auto* error = std::get_if<stationary::PlacementRefusal>(&proposal))
            return refused(stationary::placement_error_name(error->reason));
        auto& ready = std::get<stationary::PreparedPlacement>(proposal);
        candidate.topology = std::move(ready.candidate);
        candidate.kits.at(binding.actor) = std::move(ready.candidate_kit);
        candidate.issued_entities.emplace(entity, generation);
    } else {
        entity = selected->geometry.id;
        generation = selected->generation;
        if (*action == "remove") {
            auto proposal = stationary::prepare_removal(state.topology, state.kits.at(binding.actor),
                state.material, {{entity, generation}});
            if (const auto* error = std::get_if<stationary::RemovalRefusal>(&proposal))
                return refused(stationary::removal_error_name(error->reason), entity, std::move(facts));
            auto& ready = std::get<stationary::PreparedRemoval>(proposal);
            candidate.topology = std::move(ready.candidate);
            candidate.kits.at(binding.actor) = std::move(ready.candidate_kit);
        } else if (*action == "set_drive") {
            if (selected->role != Role::waterwheel) return refused("unsupported_target", entity);
            candidate.topology.drive_enabled = *field<bool>(intent, "enabled");
        } else {
            auto target = material_target(profile_, *selected, state.topology);
            if (!target) return refused("unsupported_target", entity);
            if (*action == "collect") {
                if (selected->role != Role::processor) return refused("unsupported_target", entity);
                const auto amount = *field<Integer>(intent, "amount");
                const auto error = materials::retrieve(candidate.material, profile_.material, target->path,
                                                       binding.actor, amount);
                if (error != materials::Error::none) return refused(materials::error_name(error), entity);
                facts.emplace("moved_products", Value(amount));
            } else {
                materials::TransferPlan proposal;
                if (*action == "recover")
                    proposal = materials::prepare_recovery(state.material, profile_.material, {binding.actor, *target});
                else {
                    materials::Insertion insertion;
                    if (*action == "insert_raw") insertion = materials::RawInsertion{*field<Integer>(intent, "amount")};
                    else insertion = materials::WorkInsertion{*field<Integer>(intent, "work_id")};
                    proposal = materials::prepare_insertion(state.material, profile_.material,
                                                            {binding.actor, *target, insertion});
                }
                if (const auto* error = std::get_if<materials::TransferRefusal>(&proposal))
                    return refused(materials::transfer_error_name(error->reason), entity, std::move(facts));
                auto& ready = std::get<materials::PreparedTransfer>(proposal);
                candidate.material = std::move(ready.candidate);
                facts.emplace("moved_raw", Value(ready.facts.moved.raw_units));
                facts.emplace("moved_products", Value(ready.facts.moved.products));
                facts.emplace("moved_work", lots_value(ready.facts.moved.work_lots));
            }
        }
    }
    facts.emplace("generation", Value(generation));
    return accepted(std::move(candidate), std::move(entity), std::move(facts));
}

Advance World::tick() noexcept {
    return owner_->advance([&](const Snapshot& snapshot) -> std::optional<State> {
        auto candidate = snapshot.state;
        // Material stepping changes custody, not the placed power graph. Reuse
        // one graph evaluation for machine work and signed belt movement.
        const auto placed = assembly_parts(candidate);
        const assembly::Layout layout(placed);
        const auto drive = placed.empty() ? drive_power(candidate.topology) :
            drive_power_with_layout(profile_, candidate, placed, layout);
        const auto power = machine_power_from(candidate.topology, drive);
        const auto error = materials::step(candidate.material, profile_.material,
            material_path(candidate.topology), power);
        if (error != materials::Error::none) throw error;
        const auto& motion = drive.mechanical;
        if (!motion.accepted()) throw materials::Error::invalid_path;
        // Belt routes query the same immutable placed topology several times.
        // Preserve the first matching part at a point while avoiding one full
        // scan per endpoint and material port.
        std::unordered_map<std::string_view, const stationary::PlacedPart*> belt_parts_by_id;
        std::map<std::pair<Role, mechanics::Point>, const stationary::PlacedPart*> belt_parts_by_port;
        if (!candidate.topology.belt_spans.empty()) {
            belt_parts_by_id.reserve(candidate.topology.parts.size());
            for (const auto& item : candidate.topology.parts) {
                belt_parts_by_id.emplace(item.geometry.id, &item);
                belt_parts_by_port.emplace(std::make_pair(item.role, item.geometry.center), &item);
            }
        }
        const auto belt_part = [&](const std::string& id) -> const stationary::PlacedPart* {
            const auto found = belt_parts_by_id.find(id);
            return found == belt_parts_by_id.end() ? nullptr : found->second;
        };
        const auto at = [&](Role role, const mechanics::Point& point) -> const stationary::PlacedPart* {
            const auto found = belt_parts_by_port.find(std::make_pair(role, point));
            return found == belt_parts_by_port.end() ? nullptr : found->second;
        };
        // Only an assembled tray may feed the adjacent belt mouth. A tray is
        // one quarter-grid step from its frame; the belt endpoint is the next
        // full tile on that same side. Duplicate claims are left for pickup.
        using CollectorMouth = std::pair<mechanics::Point, mechanics::Point>; // frame, tray
        std::map<mechanics::Point, std::optional<CollectorMouth>> collector_mouths;
        if (!profile_.collector_faces.empty()) {
            for (const auto& face : profile_.collector_faces) {
                const auto inspected = layout.inspect_collector(face);
                if (!inspected.collector) continue;
                const auto& collector = *inspected.collector;
                auto mouth = collector.machine_center;
                for (std::size_t axis = 0; axis < mouth.size(); ++axis)
                    mouth[axis] += 4 * (collector.receiver_center[axis] - collector.machine_center[axis]);
                const auto [entry, inserted] = collector_mouths.emplace(mouth,
                    CollectorMouth{collector.machine_center, collector.receiver_center});
                if (!inserted) entry->second.reset();
            }
        }
        // Capture loose items before any lane moves. This gives a deterministic
        // one-tick handoff between adjacent belts regardless of span ordering.
        for (const auto& span : candidate.topology.belt_spans) {
            const auto* first = belt_part(span.geometry.first_shaft);
            const auto* last = belt_part(span.geometry.last_shaft);
            const auto rate = motion.motion.find(span.geometry.first_shaft);
            auto lane = candidate.material.belt_lanes.find(span.geometry.id);
            if (!first || !last || rate == motion.motion.end() || lane == candidate.material.belt_lanes.end())
                throw materials::Error::invalid_state;
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path || path->tiles.size() != lane->second.slots.size()) throw materials::Error::invalid_state;
            // A stationary belt still supports loose cargo; rotation is needed
            // for movement, not for accepting an item onto an empty tile.
            if (path->kind == mechanics::BeltPathKind::vertical || path->kind == mechanics::BeltPathKind::sideways)
                continue;
            for (std::size_t i = 0; i < path->tiles.size(); ++i) {
                if (lane->second.slots[i]) continue;
                auto loose = candidate.material.dropped_material.find(path->tiles[i]);
                if (loose == candidate.material.dropped_material.end()) continue;
                auto& cargo = loose->second;
                materials::Cargo item;
                if (cargo.raw_units > 0) { item.raw_units = 1; --cargo.raw_units; }
                else if (cargo.products > 0) { item.products = 1; --cargo.products; }
                else if (!cargo.work_lots.empty()) {
                    item.work_lots.push_back(cargo.work_lots.front());
                    cargo.work_lots.erase(cargo.work_lots.begin());
                } else throw materials::Error::invalid_state;
                lane->second.slots[i] = std::move(item);
                if (cargo.raw_units == 0 && cargo.products == 0 && cargo.work_lots.empty())
                    candidate.material.dropped_material.erase(loose);
            }
        }
        bool collector_fed_span = false;
        for (const auto& span : candidate.topology.belt_spans) {
            const auto* first = belt_part(span.geometry.first_shaft);
            const auto* last = belt_part(span.geometry.last_shaft);
            const auto rate = motion.motion.find(span.geometry.first_shaft);
            auto lane = candidate.material.belt_lanes.find(span.geometry.id);
            if (!first || !last || rate == motion.motion.end() || lane == candidate.material.belt_lanes.end())
                throw materials::Error::invalid_state;
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path || path->tiles.size() != lane->second.slots.size()) throw materials::Error::invalid_state;
            if (path->kind == mechanics::BeltPathKind::vertical || path->kind == mechanics::BeltPathKind::sideways)
                continue;
            const auto direction = mechanics::belt_cargo_direction(first->geometry, last->geometry, rate->second.rate);
            if (!direction)
                throw materials::Error::invalid_state;
            if (rate->second.state == mechanics::MotionState::rotating && *direction != 0) {
                const bool toward_last = *direction > 0;
                const auto inlet = toward_last ? path->tiles.front() : path->tiles.back();
                const auto next = toward_last ? path->tiles[1] : path->tiles[path->tiles.size() - 2];
                const auto mouth = collector_mouths.find(inlet);
                auto& slot = toward_last ? lane->second.slots.front() : lane->second.slots.back();
                if (mouth != collector_mouths.end() && mouth->second && !slot) {
                    const auto& [frame, receiver] = *mouth->second;
                    const auto distance = [](const mechanics::Point& point, auto x, auto z) {
                        const auto dx = point[0] - x, dz = point[2] - z;
                        return dx * dx + dz * dz;
                    };
                    if (distance(next, frame[0], frame[2]) >= distance(inlet, frame[0], frame[2])) {
                        const auto loose = candidate.material.dropped_material.find(receiver);
                        if (loose != candidate.material.dropped_material.end() &&
                            loose->second == materials::Cargo{1, 0, {}}) {
                            slot = loose->second;
                            candidate.material.dropped_material.erase(loose);
                        }
                    }
                }
            }
            auto before = first->geometry.center;
            auto after = last->geometry.center;
            for (std::size_t axis = 0; axis < 3; ++axis) {
                const auto step = path->tiles[1][axis] - path->tiles[0][axis];
                before[axis] -= step;
                after[axis] += step;
            }
            const auto port_matches = [&](Role role, const mechanics::Point& point,
                                          const mechanics::Point& adjacent) {
                const auto* machine = at(role, point);
                if (!machine) return false;
                constexpr std::array<mechanics::Point, 4> forwards{{{4, 0, 0}, {0, 0, 4}, {-4, 0, 0}, {0, 0, -4}}};
                const auto& forward = forwards[static_cast<std::size_t>(machine->rotation)];
                const auto sign = role == Role::collector ? 1 : -1;
                // The path owns its incline. Facing selects the horizontal side.
                return adjacent[0] - point[0] == sign * forward[0] &&
                       adjacent[2] - point[2] == sign * forward[2];
            };
            if (rate->second.state == mechanics::MotionState::rotating &&
                std::any_of(lane->second.slots.begin(), lane->second.slots.end(),
                    [](const auto& item) { return item.has_value(); })) {
                if (*direction == 0) throw materials::Error::invalid_state;
                const bool toward_last = *direction > 0;
                const auto& receiver_point = toward_last ? after : before;
                const auto& slots = lane->second.slots;
                const auto leading = std::find_if(slots.rbegin(), slots.rend(),
                    [](const auto& item) { return item.has_value(); });
                // Reverse traversal needs a forward iterator; choose the first
                // occupied item without making an invented material type.
                const auto forward_leading = std::find_if(slots.begin(), slots.end(),
                    [](const auto& item) { return item.has_value(); });
                const auto* item = toward_last ? (leading == slots.rend() ? nullptr : &**leading) :
                    (forward_leading == slots.end() ? nullptr : &**forward_leading);
                const bool has_receiver = port_matches(Role::processor, receiver_point,
                    toward_last ? last->geometry.center : first->geometry.center);
                const bool raw = item && *item == materials::Cargo{1, 0, {}};
                const bool work = item && item->raw_units == 0 && item->products == 0 &&
                    item->work_lots.size() == 1;
                const bool can_receive = has_receiver &&
                    ((raw && candidate.material.stock.input < profile_.material.input_units_per_product) ||
                     (work && !candidate.material.processing && item->work_lots.front().recipe ==
                         materials::RecipeSignature{profile_.material.input_units_per_product, profile_.material.cycle_ticks}));
                const bool valid_drop_point = std::all_of(receiver_point.begin(), receiver_point.end(), [](auto coordinate) {
                    return coordinate >= -materials::maximum_drop_coordinate && coordinate <= materials::maximum_drop_coordinate;
                });
                const auto existing_drop = candidate.material.dropped_material.find(receiver_point);
                Integer drop_capacity = 0;
                if (!at(Role::processor, receiver_point) && !at(Role::collector, receiver_point) && valid_drop_point &&
                    (existing_drop != candidate.material.dropped_material.end() ||
                     candidate.material.dropped_material.size() < materials::maximum_drop_points)) {
                    Integer raw_total = existing_drop == candidate.material.dropped_material.end() ? 0 : existing_drop->second.raw_units;
                    Integer product_total = existing_drop == candidate.material.dropped_material.end() ? 0 : existing_drop->second.products;
                    std::size_t work_total = existing_drop == candidate.material.dropped_material.end() ? 0 : existing_drop->second.work_lots.size();
                    for (std::size_t offset = 0; offset < slots.size(); ++offset) {
                        const auto index = toward_last ? slots.size() - 1 - offset : offset;
                        if (!slots[index]) continue;
                        const auto& cargo = *slots[index];
                        if (raw_total > std::numeric_limits<Integer>::max() - cargo.raw_units ||
                            product_total > std::numeric_limits<Integer>::max() - cargo.products ||
                            work_total > materials::maximum_live_work_lots ||
                            cargo.work_lots.size() > materials::maximum_live_work_lots - work_total) break;
                        raw_total += cargo.raw_units;
                        product_total += cargo.products;
                        work_total += cargo.work_lots.size();
                        ++drop_capacity;
                    }
                }
                auto proposal = materials::advance_belt_lane_rate(lane->second, rate->second.rate.numerator,
                    rate->second.rate.denominator, toward_last ? 1 : -1,
                    path->kind == mechanics::BeltPathKind::inclined, can_receive ? 1 : drop_capacity);
                if (!proposal) throw materials::Error::invalid_state;
                if (!proposal->delivered.empty()) {
                    if (can_receive) {
                        if (proposal->delivered.size() != 1 || proposal->delivered.front() != *item)
                            throw materials::Error::invalid_state;
                        if (raw) ++candidate.material.stock.input;
                        else candidate.material.processing = proposal->delivered.front().work_lots.front();
                    } else {
                        auto& dropped = candidate.material.dropped_material[receiver_point];
                        for (const auto& delivered : proposal->delivered) {
                            dropped.raw_units += delivered.raw_units;
                            dropped.products += delivered.products;
                            dropped.work_lots.insert(dropped.work_lots.end(), delivered.work_lots.begin(), delivered.work_lots.end());
                        }
                    }
                }
                lane->second = std::move(proposal->candidate);
            }
            // A powered collector can fill an adjacent empty endpoint even if
            // the belt is stopped, just as it can fill a passive machine buffer.
            if (!collector_fed_span && power.collector && candidate.material.stock.collector > 0) {
                const bool feed_first = port_matches(Role::collector, before, first->geometry.center) && !lane->second.slots.front();
                const bool feed_last = port_matches(Role::collector, after, last->geometry.center) && !lane->second.slots.back();
                if (feed_first || feed_last) {
                    (feed_first ? lane->second.slots.front() : lane->second.slots.back()) = materials::Cargo{1, 0, {}};
                    --candidate.material.stock.collector;
                    collector_fed_span = true;
                }
            }
        }
        if (candidate.material == snapshot.state.material) return std::nullopt;
        return candidate;
    });
}

}  // namespace factory::world
