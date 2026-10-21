#include "factory/world.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <initializer_list>
#include <limits>
#include <set>
#include <string_view>
#include <tuple>
#include <utility>

namespace factory::world {
namespace {
using Integer = authority::Integer;
using Object = authority::Object;
using Value = values::Value;
using Role = stationary::Role;

constexpr std::size_t maximum_actors = 16;
constexpr std::size_t maximum_issued_entities = 4096;
constexpr std::size_t maximum_current_work = 256;
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
    return role == Role::collector || role == Role::belt || role == Role::processor;
}

std::optional<mechanics::Rate> wheel_rate(const Profile& profile, const stationary::PlacedPart& placed) {
    if (profile.water.empty()) return profile.waterwheel_rate;
    const auto& part = placed.geometry;
    const auto sample = profile.water.find({part.center[0], part.center[2]});
    if (sample == profile.water.end()) return mechanics::Rate{0, 1};
    return waterwheel::rate(part.center[1] * 100 + profile.wheel_axle_offset,
                            profile.wheel_radius * placed.wheel_tiles, part.axis, sample->second);
}

bool material_pair(Role from, Role to) {
    return (from == Role::collector && to == Role::belt) ||
           (from == Role::belt && to == Role::processor);
}

struct Attachment {
    const stationary::PlacedPart* neighbor;
    bool new_part_is_source;
};

std::vector<Attachment> placement_attachments(const stationary::Topology& topology,
                                             Role role, const mechanics::Point& center, mechanics::Axis axis) {
    std::vector<Attachment> result;
    const stationary::PlacedPart proposed{{"proposed", mechanics::Kind::hub, center, axis, 0, 0}, 1, role};
    for (const auto& other : topology.parts) {
        if (material_ports_adjacent(proposed, other))
            result.push_back({&other, true});
        else if (material_ports_adjacent(other, proposed))
            result.push_back({&other, false});
    }
    return result;
}

bool spec_valid(const stationary::PartSpec& spec) {
    switch (spec.role) {
        case Role::collector: case Role::belt: case Role::processor: case Role::waterwheel:
            return spec.teeth == 0 && spec.half_span == 0;
        case Role::gear:
            return spec.teeth > 0 && spec.teeth <= mechanics::maximum_dimension && spec.half_span == 0;
        case Role::shaft:
            return spec.teeth == 0 && spec.half_span == 2;
    }
    return false;
}

bool add(Integer& total, Integer count) {
    if (count < 0 || total > std::numeric_limits<Integer>::max() - count) return false;
    total += count;
    return true;
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
    if (action == "place_foundations") return keys(intent, {"center", "end"});
    if (action == "place_foundation") return keys(intent, {"center"});
    if (action == "remove_foundation") return keys(intent, {"target", "generation"});
    if (action == "recover" || action == "remove" || action == "remove_belt_span" || action == "select_belt_shaft")
        return keys(intent, {"target", "generation"});
    if (action == "recover_belt_slot") return keys(intent, {"target", "generation", "slot", "expected"}) &&
        field<Integer>(intent, "slot") && field<Object>(intent, "expected");
    if (action == "collect" || action == "insert_raw")
        return keys(intent, {"target", "generation", "amount"}) && field<Integer>(intent, "amount");
    if (action == "insert_work")
        return keys(intent, {"target", "generation", "work_id"}) && field<Integer>(intent, "work_id");
    if (action == "set_drive")
        return keys(intent, {"target", "generation", "enabled"}) && field<bool>(intent, "enabled");
    if (placement(action))
        return intent.contains("wheel_tiles") ? keys(intent, {"role", "center", "axis", "teeth", "half_span", "wheel_tiles"}) :
            keys(intent, {"role", "center", "axis", "teeth", "half_span"});
    if (action == "link" || action == "unlink" || action == "shaft_between" || action == "remove_shaft_between" || action == "place_belt_span")
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
    return action == "link" || action == "unlink" || action == "shaft_between" || action == "remove_shaft_between" ||
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
        case Role::belt: holder = materials::Holder::belt; break;
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
        {"completed_subticks", Value(lot.completed_subticks)}});
    return Value(std::move(output));
}

Value belt_cargo_value(const materials::Cargo& cargo) {
    Value::Array lots;
    for (const auto& lot : cargo.work_lots) lots.emplace_back(Object{
        {"id", Value(lot.id)}, {"recipe_input", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)}});
    return Value(Object{{"raw", Value(cargo.raw_units)}, {"products", Value(cargo.products)},
                        {"work_lots", Value(std::move(lots))}});
}

bool historical_facts(const Profile& profile, const authority::Record& record,
                      const std::string& actor, const std::string& action) {
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
        (action == "place_connected" ? points->empty() || points->size() > 3 :
         action == "remove_belt_span" ? points->size() != 1 && points->size() != 2 :
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
            if (!lot || lot->size() != 5 || !add(weighted, profile.material.input_units_per_product)) return false;
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
            if (!selected || !moved || selected->size() != 5) return false;
            for (const auto& [left, right] : {std::pair{"id", "id"}, {"recipe_input", "input_units_per_product"},
                    {"cycle_ticks", "cycle_ticks"}, {"remaining", "remaining_ticks"}, {"completed_subticks", "completed_subticks"}})
                if (!selected->contains(left) || !moved->contains(right) || values::typed_difference(selected->at(left), moved->at(right)))
                    return false;
        }
        return weighted > 0 && weighted <= profile.initial_units;
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
        const auto selected_role = role_name ? role(*role_name) : std::nullopt;
        if (!location || !selected_role || !axis_name || !axis(*axis_name) || !teeth || !span ||
            !spec_valid({*selected_role, *teeth, *span}) || targets.front() != anchor(profile, *location) ||
            (*selected_role == Role::belt && *axis_name == "y") ||
            (record.intent.contains("wheel_tiles") && (!wheel_tiles || *selected_role != Role::waterwheel ||
                *wheel_tiles < 3 || *wheel_tiles > mechanics::maximum_dimension))) return false;
        if ((*selected_role == Role::gear || *selected_role == Role::shaft) &&
            std::any_of(location->begin(), location->end(),
                        [](Integer coordinate) { return coordinate % 4 != 0; })) return false;
        if (action == "place_connected") {
            if (!material_machine(*selected_role)) return false;
            bool used_input = false;
            bool used_output = false;
            std::optional<std::size_t> direction;
            for (std::size_t index = 1; index < targets.size(); ++index) {
                bool matched = false;
                for (const std::size_t coordinate : {std::size_t{0}, std::size_t{2}}) {
                    if (direction && *direction != coordinate) continue;
                    if (*selected_role == Role::belt && coordinate != (*axis_name == "x" ? 2U : 0U)) continue;
                    auto left = *location; left[coordinate] -= 4;
                    auto right = *location; right[coordinate] += 4;
                    if (*selected_role != Role::collector && !used_input && targets[index] == anchor(profile, left))
                        used_input = matched = true;
                    else if (*selected_role != Role::processor && !used_output && targets[index] == anchor(profile, right))
                        used_output = matched = true;
                    if (matched) { direction = coordinate; break; }
                }
                if (!matched) return false;
            }
        }
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
    const bool transfer = action == "recover" || action == "recover_belt_slot" || action == "insert_raw" || action == "insert_work";
    if (result.size() != (action == "place_belt_span" || action == "place_selected_belt_span" ? 18 :
                          action == "recover_belt_slot" ? 20 : transfer ? 19 : action == "collect" ||
                          (action == "remove_belt_span" && points->size() == 1) ? 17 : 16)) return false;
    if (action == "remove_belt_span" && points->size() == 1) {
        const auto* center = field<Value::Array>(result, "belt_center");
        const auto location = center ? grid_point(Object{{"center", Value(*center)}}) : std::nullopt;
        if (!location || targets.front() != anchor(profile, *location)) return false;
    }
    if (action == "recover_belt_slot") {
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
        if (!lot || lot->size() != 5 || !add(weighted, profile.material.input_units_per_product)) return false;
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
            if (!a || !b || b->size() != 5) return false;
            for (const auto& [left, right] : {std::pair{"id", "id"}, {"input_units_per_product", "recipe_input"},
                    {"cycle_ticks", "cycle_ticks"}, {"remaining_ticks", "remaining"}, {"completed_subticks", "completed_subticks"}}) {
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
    return true;
}

bool history_domain(const Profile& profile, const Snapshot& snapshot) {
    std::set<std::pair<std::string, std::string>> used_belt_selections;
    std::map<std::pair<std::string, Integer>, mechanics::Point> placed_shafts;
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
        if (*action != "pickup_material") {
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
        if (!historical_facts(profile, record, *actor, *action)) return false;
        if (placement(*action)) {
            const auto* role_name = field<std::string>(record.intent, "role");
            const auto center = grid_point(record.intent);
            if (role_name && *role_name == "shaft" && center)
                placed_shafts.emplace(std::make_pair(*entity, *generation), *center);
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
                if (!id || *id <= 0 || *id >= snapshot.state.material.next_work_id ||
                    !weight || *weight != profile.material.input_units_per_product ||
                    !cycle || *cycle != profile.material.cycle_ticks ||
                    !remaining || *remaining < 0 || *remaining > *cycle || !completed ||
                    *completed < 0 || *completed >= materials::work_subticks_per_tick ||
                    (*remaining == 0 && *completed != 0)) return false;
            }
        }
    }
    return true;
}
}  // namespace

bool material_ports_adjacent(const stationary::PlacedPart& from, const stationary::PlacedPart& to) noexcept {
    if (!material_pair(from.role, to.role)) return false;
    const auto axis = (from.role == Role::belt ? from : to).geometry.axis;
    const auto& a = from.geometry.center;
    const auto& b = to.geometry.center;
    if (axis == mechanics::Axis::z) return b[0] == a[0] + 4 && b[1] == a[1] && b[2] == a[2];
    if (axis == mechanics::Axis::x) return b[2] == a[2] + 4 && b[1] == a[1] && b[0] == a[0];
    return false;
}

materials::Path material_path(const stationary::Topology& topology) {
    materials::Path path;
    path.powered = topology.drive_enabled;
    for (const auto& item : topology.parts) {
        path.collector_present |= item.role == Role::collector;
        path.belt_present |= item.role == Role::belt;
        path.processor_present |= item.role == Role::processor;
    }
    for (const auto& link : topology.material_links) {
        const auto* from = part(topology, link.from.id);
        const auto* to = part(topology, link.to.id);
        if (!from || !to) continue;  // Complete validation rejects stale links.
        path.collector_to_belt |= from->role == Role::collector && to->role == Role::belt;
        path.belt_to_processor |= from->role == Role::belt && to->role == Role::processor;
    }
    return path;
}

materials::MachinePower machine_power(const stationary::Topology& topology) {
    materials::MachinePower power;
    const auto view = stationary::power_view(topology);
    if (!view.mechanical.accepted()) return power;
    for (const auto& item : topology.parts) {
        const auto found = view.mechanical.motion.find(item.geometry.id);
        const bool rotating = found != view.mechanical.motion.end() &&
            found->second.state == mechanics::MotionState::rotating;
        if (item.role == Role::collector) power.collector = rotating;
        if (item.role == Role::belt) {
            power.belt = rotating;
            if (rotating) {
                // In a Y-up world, +Z rotation drives the top toward -X;
                // +X rotation drives it toward +Z.
                const bool along_z = item.geometry.axis == mechanics::Axis::x;
                power.belt_forward = along_z ? found->second.rate.numerator > 0 : found->second.rate.numerator < 0;
                power.reverse_drop = materials::DropPoint{item.geometry.center[0] - (along_z ? 0 : 2),
                    item.geometry.center[1], item.geometry.center[2] - (along_z ? 2 : 0)};
            }
        }
        if (item.role == Role::processor) {
            power.processor = rotating;
            if (rotating) {
                // Use a bounded fixed-point mapping from signed mechanical rate
                // to work. Reversal does not reverse the press cycle.
                __extension__ using Wide = __int128;
                Wide numerator = found->second.rate.numerator;
                if (numerator < 0) numerator = -numerator;
                const Wide scaled = numerator * materials::work_subticks_per_tick /
                    found->second.rate.denominator;
                power.processor_work_per_tick = static_cast<Integer>(std::clamp<Wide>(
                    scaled, 1, materials::maximum_work_subticks_per_tick));
            }
        }
    }
    return power;
}

bool validate(const Profile& profile, const Snapshot& snapshot) {
    if (profile.actors.empty() || profile.actors.size() > maximum_actors || profile.initial_units < 0 ||
        profile.finite_parts.size() > stationary::maximum_specifications ||
        profile.waterwheel_rate.numerator == 0 || profile.waterwheel_rate.denominator <= 0 ||
        !std::isfinite(profile.meters_per_grid_unit) || profile.meters_per_grid_unit <= 0 ||
        profile.meters_per_grid_unit > 1000 || !std::isfinite(profile.build_reach) ||
        profile.build_reach <= 0 || profile.build_reach > 1000000 ||
        profile.foundation_parts < 0 || profile.foundation_parts > 256) return false;
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
    for (const auto& item : state.topology.parts) {
        if (item.wheel_tiles < (item.role == Role::waterwheel ? 3 : 1) || item.wheel_tiles > mechanics::maximum_dimension ||
            (item.role != Role::waterwheel && item.wheel_tiles != 1)) return false;
        if (item.role == Role::belt && item.geometry.axis == mechanics::Axis::y) return false;
        if ((material_machine(item.role) || item.role == Role::waterwheel) && item.geometry.center[1] % 4 != 0) return false;
        if ((item.role == Role::shaft || item.role == Role::gear) &&
            std::any_of(item.geometry.center.begin(), item.geometry.center.end(),
                        [](Integer coordinate) { return coordinate % 4 != 0; })) return false;
        if ((item.role == Role::shaft || item.role == Role::gear) &&
            std::count_if(state.topology.parts.begin(), state.topology.parts.end(), [&](const auto& other) {
                return other.geometry.center == item.geometry.center;
            }) != 1) return false;
        if (profile.foundation_parts > 0 && material_machine(item.role) && item.geometry.center[1] != 0 &&
            std::none_of(state.foundations.begin(), state.foundations.end(), [&](const auto& entry) {
                return entry.second.center == item.geometry.center;
            })) return false;
        const auto issued = state.issued_entities.find(item.geometry.id);
        const auto total = totals.find({item.role, item.geometry.teeth, item.geometry.half_span});
        if (issued == state.issued_entities.end() || issued->second != item.generation ||
            total == totals.end() || !add(total->second, 1)) return false;
        const auto expected_rate = item.role == Role::waterwheel ? wheel_rate(profile, item) : std::nullopt;
        if (item.role == Role::waterwheel && (!expected_rate || std::count_if(state.topology.sources.begin(),
            state.topology.sources.end(), [&](const auto& source) {
                return source.hub == item.geometry.id && source.rate == *expected_rate;
            }) != 1)) return false;
    }
    for (const auto& span : state.topology.belt_spans) {
        const auto issued = state.issued_entities.find(span.geometry.id);
        const auto total = totals.find({Role::belt, 0, 0});
        const auto lane = state.material.belt_lanes.find(span.geometry.id);
        const auto* first = part(state.topology, span.geometry.first_shaft);
        const auto* last = part(state.topology, span.geometry.last_shaft);
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
    for (const auto& link : state.topology.material_links) {
        const auto* from = part(state.topology, link.from.id);
        const auto* to = part(state.topology, link.to.id);
        if (!from || !to || !material_ports_adjacent(*from, *to)) return false;
    }
    if (totals != profile.finite_parts || !stationary::power_view(state.topology).mechanical.accepted() ||
        materials::validate(state.material, profile.material, material_path(state.topology)) != materials::Error::none)
        return false;
    return history_domain(profile, snapshot);
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
    if (*action == "recover_belt_slot") {
        const auto* id = field<std::string>(intent, "target");
        const auto* generation = field<Integer>(intent, "generation");
        const auto* index = field<Integer>(intent, "slot");
        const auto* expected = field<Object>(intent, "expected");
        if (!id || !generation || !index || !expected) return refused("invalid_target");
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
        const auto center = path->tiles[static_cast<std::size_t>(*index)];
        auto cut = observe ? observe(binding.actor) : std::nullopt;
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile_.build_reach;
        const auto checked = authority::check_reach(binding.actor, *cut, {anchor(profile_, center)});
        auto facts = checked.receipt ? reach_facts(binding, *checked.receipt) : Object{};
        if (checked.error != authority::Error::none) return refused(authority::error_name(checked.error), *id, std::move(facts));
        const auto& item = lane->second.slots.at(static_cast<std::size_t>(*index));
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
    std::vector<Attachment> attachments;
    std::vector<authority::Point> targets;
    if (placement(*action)) {
        const auto* role_name = field<std::string>(intent, "role");
        const auto* axis_name = field<std::string>(intent, "axis");
        const auto* teeth = field<Integer>(intent, "teeth");
        const auto* span = field<Integer>(intent, "half_span");
        const auto* wheel_tiles = field<Integer>(intent, "wheel_tiles");
        location = grid_point(intent);
        if (!role_name || !axis_name || !teeth || !span || !location ||
            !(selected_role = role(*role_name)) || !(selected_axis = axis(*axis_name)) ||
            !spec_valid({*selected_role, *teeth, *span}) ||
            (intent.contains("wheel_tiles") && (!wheel_tiles || *selected_role != Role::waterwheel ||
                *wheel_tiles < 3 || *wheel_tiles > mechanics::maximum_dimension))) return refused("invalid_part");
        if (*selected_role == Role::belt && *selected_axis == mechanics::Axis::y) return refused("invalid_belt_axis");
        if ((material_machine(*selected_role) || *selected_role == Role::waterwheel) && (*location)[1] % 4 != 0)
            return refused("unaligned_elevation");
        if ((*selected_role == Role::gear || *selected_role == Role::shaft) &&
            std::any_of(location->begin(), location->end(),
                        [](Integer coordinate) { return coordinate % 4 != 0; })) return refused("invalid_cell");
        targets.push_back(anchor(profile_, *location));
        if (profile_.foundation_parts > 0 && material_machine(*selected_role) && (*location)[1] != 0) {
            const bool supported = std::any_of(state.foundations.begin(), state.foundations.end(),
                [&](const auto& entry) { return entry.second.center == *location; });
            if (!supported) return refused("foundation_required");
        }
        if (*action == "place_connected") {
            if (!material_machine(*selected_role)) return refused("invalid_part");
            attachments = placement_attachments(state.topology, *selected_role, *location, *selected_axis);
            for (const auto& attachment : attachments)
                targets.push_back(anchor(profile_, attachment.neighbor->geometry.center));
        }
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
                (*selected_role == Role::gear || *selected_role == Role::shaft ||
                 existing.role == Role::gear || existing.role == Role::shaft);
        })) return refused("occupied", "", std::move(facts));
    if (placement(*action)) {
        if (candidate.issued_entities.size() == maximum_issued_entities ||
            candidate.next_entity_serial == std::numeric_limits<Integer>::max())
            return refused("identity_limit");
        generation = candidate.next_entity_serial++;
        entity = std::string(allocated_prefix) + std::to_string(generation);
        if (candidate.issued_entities.contains(entity)) return refused("identity_conflict");
        const auto kind = *selected_role == Role::gear ? mechanics::Kind::gear :
                          *selected_role == Role::shaft ? mechanics::Kind::shaft : mechanics::Kind::hub;
        stationary::PlacedPart placed{
            {entity, kind, *location, *selected_axis, *field<Integer>(intent, "teeth"),
             *field<Integer>(intent, "half_span")}, generation, *selected_role};
        placed.geometry.id = entity;
        placed.generation = generation;
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
        for (const auto& attachment : attachments) {
            const materials::EntityRef created{entity, generation};
            const materials::EntityRef existing{attachment.neighbor->geometry.id, attachment.neighbor->generation};
            candidate.topology.material_links.push_back(attachment.new_part_is_source ?
                stationary::MaterialLink{created, existing} : stationary::MaterialLink{existing, created});
        }
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
        } else if (*action == "link" || *action == "unlink") {
            const bool compatible = (selected->role == Role::collector && destination->role == Role::belt) ||
                                    (selected->role == Role::belt && destination->role == Role::processor);
            if (!compatible) return refused("incompatible_link", entity);
            const stationary::MaterialLink link{{entity, generation},
                {destination->geometry.id, destination->generation}};
            const auto found = std::find(candidate.topology.material_links.begin(), candidate.topology.material_links.end(), link);
            if (*action == "unlink") {
                if (found == candidate.topology.material_links.end()) return refused("missing_link", entity);
                candidate.topology.material_links.erase(found);
            } else {
                if (!material_ports_adjacent(*selected, *destination))
                    return refused("ports_not_adjacent", entity, std::move(facts));
                if (found != candidate.topology.material_links.end()) return refused("existing_link", entity);
                candidate.topology.material_links.push_back(link);
            }
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
        const auto power = machine_power(candidate.topology);
        const auto error = materials::step(candidate.material, profile_.material,
            material_path(candidate.topology), power);
        if (error != materials::Error::none) throw error;
        const auto motion = stationary::power_view(candidate.topology).mechanical;
        if (!motion.accepted()) throw materials::Error::invalid_path;
        // Capture loose items before any lane moves. This gives a deterministic
        // one-tick handoff between adjacent belts regardless of span ordering.
        for (const auto& span : candidate.topology.belt_spans) {
            const auto* first = part(candidate.topology, span.geometry.first_shaft);
            const auto* last = part(candidate.topology, span.geometry.last_shaft);
            const auto rate = motion.motion.find(span.geometry.first_shaft);
            auto lane = candidate.material.belt_lanes.find(span.geometry.id);
            if (!first || !last || rate == motion.motion.end() || lane == candidate.material.belt_lanes.end())
                throw materials::Error::invalid_state;
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path || path->tiles.size() != lane->second.slots.size()) throw materials::Error::invalid_state;
            if (rate->second.state != mechanics::MotionState::rotating ||
                path->kind == mechanics::BeltPathKind::vertical || path->kind == mechanics::BeltPathKind::sideways)
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
            const auto* first = part(candidate.topology, span.geometry.first_shaft);
            const auto* last = part(candidate.topology, span.geometry.last_shaft);
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
            auto before = first->geometry.center;
            auto after = last->geometry.center;
            for (std::size_t axis = 0; axis < 3; ++axis) {
                const auto step = path->tiles[1][axis] - path->tiles[0][axis];
                before[axis] -= step;
                after[axis] += step;
            }
            const auto at = [&](Role role, const mechanics::Point& point) {
                return std::any_of(candidate.topology.parts.begin(), candidate.topology.parts.end(),
                    [&](const auto& part) { return part.role == role && part.geometry.center == point; });
            };
            if (rate->second.state == mechanics::MotionState::rotating &&
                std::any_of(lane->second.slots.begin(), lane->second.slots.end(),
                    [](const auto& item) { return item.has_value(); })) {
                __extension__ using Wide = __int128;
                Wide magnitude = rate->second.rate.numerator;
                if (magnitude < 0) magnitude = -magnitude;
                auto speed = static_cast<Integer>(std::clamp<Wide>(
                    magnitude * materials::work_subticks_per_tick / rate->second.rate.denominator,
                    1, materials::maximum_work_subticks_per_tick));
                // A diagonal tile is sqrt(2) times longer than a horizontal
                // tile. Keep surface travel per tick the same at a given
                // shaft rate; 2896/4096 approximates 1/sqrt(2).
                if (path->kind == mechanics::BeltPathKind::inclined)
                    speed = std::max<Integer>(1, speed * 2896 / materials::work_subticks_per_tick);
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
                const bool has_receiver = at(Role::processor, receiver_point);
                const bool raw = item && *item == materials::Cargo{1, 0, {}};
                const bool can_receive = raw && has_receiver &&
                    candidate.material.stock.input < profile_.material.input_units_per_product;
                const bool valid_drop_point = std::all_of(receiver_point.begin(), receiver_point.end(), [](auto coordinate) {
                    return coordinate >= -materials::maximum_drop_coordinate && coordinate <= materials::maximum_drop_coordinate;
                });
                const auto existing_drop = candidate.material.dropped_material.find(receiver_point);
                const bool drop_space = existing_drop != candidate.material.dropped_material.end() ?
                    (!item || (existing_drop->second.raw_units <= std::numeric_limits<Integer>::max() - item->raw_units &&
                               existing_drop->second.products <= std::numeric_limits<Integer>::max() - item->products)) :
                    candidate.material.dropped_material.size() < materials::maximum_drop_points;
                const bool can_drop = item && !has_receiver && valid_drop_point && drop_space;
                auto proposal = materials::advance_belt_lane(lane->second, toward_last ? speed : -speed,
                                                            can_receive || can_drop ? 1 : 0);
                if (!proposal || proposal->delivered.size() > 1) throw materials::Error::invalid_state;
                if (!proposal->delivered.empty()) {
                    const auto& delivered = proposal->delivered.front();
                    if (can_receive) {
                        if (delivered != materials::Cargo{1, 0, {}}) throw materials::Error::invalid_state;
                        ++candidate.material.stock.input;
                    } else {
                        auto& dropped = candidate.material.dropped_material[receiver_point];
                        dropped.raw_units += delivered.raw_units;
                        dropped.products += delivered.products;
                        dropped.work_lots.insert(dropped.work_lots.end(), delivered.work_lots.begin(), delivered.work_lots.end());
                    }
                }
                lane->second = std::move(proposal->candidate);
            }
            // A powered collector can fill an adjacent empty endpoint even if
            // the belt is stopped, just as it can fill a passive machine buffer.
            if (!collector_fed_span && power.collector && candidate.material.stock.collector > 0) {
                const bool feed_first = at(Role::collector, before) && !lane->second.slots.front();
                const bool feed_last = at(Role::collector, after) && !lane->second.slots.back();
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
