#include "factory/world.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <initializer_list>
#include <limits>
#include <string_view>
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
    if (action == "pickup_raw") return keys(intent, {"center"});
    if (action == "place_foundations") return keys(intent, {"center", "end"});
    if (action == "place_foundation") return keys(intent, {"center"});
    if (action == "remove_foundation") return keys(intent, {"target", "generation"});
    if (action == "recover" || action == "remove") return keys(intent, {"target", "generation"});
    if (action == "collect" || action == "insert_raw")
        return keys(intent, {"target", "generation", "amount"}) && field<Integer>(intent, "amount");
    if (action == "insert_work")
        return keys(intent, {"target", "generation", "work_id"}) && field<Integer>(intent, "work_id");
    if (action == "set_drive")
        return keys(intent, {"target", "generation", "enabled"}) && field<bool>(intent, "enabled");
    if (placement(action))
        return intent.contains("wheel_tiles") ? keys(intent, {"role", "center", "axis", "teeth", "half_span", "wheel_tiles"}) :
            keys(intent, {"role", "center", "axis", "teeth", "half_span"});
    if (action == "link" || action == "unlink" || action == "shaft_between" || action == "remove_shaft_between")
        return keys(intent, {"target", "generation", "to", "to_generation"});
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
    return action == "link" || action == "unlink" || action == "shaft_between" || action == "remove_shaft_between";
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
                                     points->size() != (two_endpoints(action) ? 2 : 1)) ||
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
    if (action == "pickup_raw") {
        const auto location = grid_point(record.intent, materials::maximum_drop_coordinate);
        const auto* amount = field<Integer>(result, "moved_raw");
        const auto* entity = field<std::string>(result, "entity");
        const auto* generation = field<Integer>(result, "generation");
        return location && targets.front() == anchor(profile, *location) && amount && *amount > 0 &&
            *amount <= profile.initial_units && entity && entity->empty() && generation && *generation == 0 && result.size() == 17;
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
    } else if (action != "shaft_between" && action != "remove_shaft_between") {
        const auto* target = field<std::string>(record.intent, "target");
        const auto* generation = field<Integer>(record.intent, "generation");
        if (!target || *target != *field<std::string>(result, "entity") ||
            !generation || *generation != *field<Integer>(result, "generation")) return false;
    }
    const bool transfer = action == "recover" || action == "insert_raw" || action == "insert_work";
    if (result.size() != (transfer ? 19 : action == "collect" ? 17 : 16)) return false;
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
        if (*action != "pickup_raw") {
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
        if (issued == state.issued_entities.end() || issued->second != span.generation ||
            total == totals.end() || !add(total->second, 1)) return false;
    }
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
    if (*action == "pickup_raw") {
        const auto point = grid_point(intent, materials::maximum_drop_coordinate);
        if (!point) return refused("invalid_center");
        if (!observe) return refused("actor_unready");
        auto cut = observe(binding.actor);
        if (!cut) return refused("actor_unready");
        cut->build_reach = profile_.build_reach;
        auto reach = authority::check_reach(binding.actor, *cut, {anchor(profile_, *point)});
        Object facts = reach.receipt ? reach_facts(binding, *reach.receipt) : Object{};
        if (reach.error != authority::Error::none) return refused(authority::error_name(reach.error), "", std::move(facts));
        const auto found = state.material.dropped_raw.find(*point);
        if (found == state.material.dropped_raw.end()) return refused("unavailable_drop", "", std::move(facts));
        const auto amount = found->second;
        State candidate = state;
        const auto error = materials::pickup_raw(candidate.material, profile_.material,
                                                  material_path(candidate.topology), binding.actor, *point);
        if (error != materials::Error::none) return refused(materials::error_name(error), "", std::move(facts));
        facts.emplace("generation", Value(Integer{0}));
        facts.emplace("moved_raw", Value(amount));
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
        const auto error = materials::step(candidate.material, profile_.material,
            material_path(candidate.topology), machine_power(candidate.topology));
        if (error != materials::Error::none) throw error;
        if (candidate.material == snapshot.state.material) return std::nullopt;
        return candidate;
    });
}

}  // namespace factory::world
