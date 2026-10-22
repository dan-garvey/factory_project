#include "factory/godot_world.hpp"
#include "factory/assembly.hpp"
#include "factory/mineral_site.hpp"
#include "factory/waterflow.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <initializer_list>
#include <limits>
#include <optional>
#include <stdexcept>
#include <tuple>
#include <utility>

namespace factory::godot_world {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
using Role = stationary::Role;

// Current opening geometry, explicitly checked by the thin scene adapter.
constexpr double pitch = 1.65;
constexpr Integer height_denominator = 4;
constexpr double height_step = pitch / height_denominator;
constexpr double foundation_depth = 2 * height_step;
constexpr double anchor_height = pitch / 2;
// Hundredths of a height step, shared with the native opening rotor.
constexpr Integer wheel_radius = 224;
constexpr Integer wheel_axle_offset = 200;
constexpr double reach = 4.0;
constexpr double capsule_radius = 0.3;
constexpr double capsule_height = 1.8;
constexpr double machine_width = 1.45;
constexpr double machine_height = 1.65;
constexpr double machine_center_height = 0.8;

const char* collector_status_name(assembly::Status status) {
    switch (status) {
        case assembly::Status::ready: return "ready";
        case assembly::Status::invalid_input: return "invalid_input";
        case assembly::Status::missing_frame: return "missing_frame";
        case assembly::Status::missing_mount: return "missing_mount";
        case assembly::Status::missing_edge: return "missing_edge";
        case assembly::Status::missing_receiver: return "missing_receiver";
        case assembly::Status::missing_shaft: return "missing_shaft";
        case assembly::Status::ambiguous: return "ambiguous";
    }
    return "invalid_input";
}

struct Bounds { authority::Point center, half; };

bool fixed_transmission(Role role) {
    return role == Role::shaft || role == Role::gear || role == Role::gearbox ||
           role == Role::vertical_gearbox || role == Role::chain_drive;
}

// The fixed bearings stand just outside the rotating disc. Terrain supplies
// their lower seats; neither the player wire nor saved state supplies a pose.
template<class TerrainRange>
std::optional<std::array<Bounds, 2>> wheel_support_bounds(const mechanics::Point& center,
        mechanics::Axis axis, TerrainRange&& terrain_range) {
    if (axis != mechanics::Axis::x && axis != mechanics::Axis::z) return std::nullopt;
    const auto x = center[0] * height_step, z = center[2] * height_step;
    const auto axle_y = center[1] * height_step + anchor_height;
    constexpr double axial_offset = 0.5, axial_half = 0.18, radial_half = 0.43;
    std::array<Bounds, 2> supports{};
    for (std::size_t index = 0; index < supports.size(); ++index) {
        const auto side = index == 0 ? -1.0 : 1.0;
        const auto foot_x = x + (axis == mechanics::Axis::x ? side * axial_offset : 0.0);
        const auto foot_z = z + (axis == mechanics::Axis::z ? side * axial_offset : 0.0);
        const auto half_x = axis == mechanics::Axis::x ? axial_half : radial_half;
        const auto half_z = axis == mechanics::Axis::z ? axial_half : radial_half;
        const auto terrain = terrain_range(foot_x, foot_z, half_x, half_z);
        if (!terrain || !std::isfinite(terrain->first) || !std::isfinite(terrain->second) ||
            terrain->second >= axle_y - 0.05) return std::nullopt;
        // Seat the pad slightly into the lowest triangle, avoiding a floating
        // corner on the emitted sloped surface.
        const auto low = terrain->first - 0.04, high = axle_y - 0.05;
        supports[index] = {{foot_x, (low + high) / 2, foot_z},
                           {half_x, (high - low) / 2, half_z}};
    }
    return supports;
}

Bounds part_bounds(const world::Profile& profile, const stationary::PlacedPart& part) {
    const auto& c = part.geometry.center;
    const auto x = c[0] * height_step, z = c[2] * height_step, floor = c[1] * height_step;
    if (part.role == Role::waterwheel) {
        const auto radius = profile.wheel_radius * part.wheel_tiles * height_step / 100.0;
        return {{x, floor + anchor_height, z},
            {part.geometry.axis == mechanics::Axis::x ? 0.3 : radius, radius,
             part.geometry.axis == mechanics::Axis::z ? 0.3 : radius}};
    }
    if (part.role == Role::gearbox || part.role == Role::vertical_gearbox ||
        part.role == Role::chain_drive)
        return {{x, floor + anchor_height, z}, {pitch / 2, pitch / 2, pitch / 2}};
    return {{x, floor + machine_center_height, z}, {machine_width / 2, machine_height / 2, machine_width / 2}};
}

// The two admitted mineral cells face one fixed west-side rock. Their pickup
// shoes occupy different strips of its real hull, independent of output turn.
std::optional<Bounds> collector_intake_bounds(const mechanics::Point& center) {
    if (center[1] < 0 || center[1] > mineral_site::extraction_depth_steps ||
        center[1] % height_denominator != 0 || center[0] != 0 ||
        (center[2] != 0 && center[2] != height_denominator))
        return std::nullopt;
    const auto cell = mineral_site::Cell{0, center[2] / height_denominator};
    const double z = center[2] * height_step + (cell.z == 0 ? 0.0 : -0.6);
    if (center[1] == 0) return Bounds{{-0.84, 0.50, z}, {0.14, 0.10, 0.12}};
    return Bounds{{-1.04, 0.55, z}, {0.17, 0.15, 0.20}};
}

std::vector<Bounds> collector_external_bounds(const mechanics::Point& center) {
    const auto pickup = collector_intake_bounds(center);
    if (!pickup) return {};
    if (center[1] == 0) return {*pickup};
    const double rise = center[1] * height_step;
    const double z = pickup->center[2];
    const double machine_z = center[2] * height_step;
    const double carrier_top = rise + 1.95;
    const double carrier_bottom = 0.67;
    const double carrier_middle = (carrier_bottom + carrier_top) / 2;
    const double carrier_height = carrier_top - carrier_bottom;
    std::vector<Bounds> parts{*pickup};
    for (const double side : {-1.0, 1.0})
        parts.push_back({{-1.05 + 0.09, carrier_middle, z + side * 0.17},
            {0.055 / 2, carrier_height / 2, 0.055 / 2}});
    for (int step = 0; step < 5; ++step)
        parts.push_back({{-1.05 - 0.025, carrier_middle + 0.05 +
                carrier_height * (static_cast<double>(step) / 4 - 0.5) * 0.88, z},
            {0.25 / 2, 0.16 / 2, 0.30 / 2}});
    parts.push_back({{-0.60, rise + 1.77, (z + machine_z) / 2},
        {0.45, 0.18, machine_z == z ? 0.20 : 0.43}});
    return parts;
}

Bounds foundation_bounds(const world::Foundation& foundation) {
    return {{foundation.center[0] * height_step, foundation.center[1] * height_step - foundation_depth / 2,
             foundation.center[2] * height_step}, {pitch / 2, foundation_depth / 2, pitch / 2}};
}

bool overlap(const Bounds& a, const Bounds& b) {
    for (std::size_t axis = 0; axis < 3; ++axis) {
        const auto distance = std::abs(a.center[axis] - b.center[axis]);
        const auto extent = a.half[axis] + b.half[axis];
        // Grid faces computed from different tile coordinates can differ by a
        // few floating-point ulps. Contact is not volume overlap.
        const auto roundoff = 8 * std::numeric_limits<double>::epsilon() *
            std::max({1.0, std::abs(a.center[axis]), std::abs(b.center[axis]), extent});
        if (distance >= extent - roundoff) return false;
    }
    return true;
}

bool overlaps_supports(const std::array<Bounds, 2>& supports, const Bounds& other) {
    return std::any_of(supports.begin(), supports.end(),
        [&](const auto& support) { return overlap(support, other); });
}

template<class T> const T* field(const Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

Value result(bool accepted, const std::string& reason) {
    return Value(Object{{"accepted", Value(accepted)}, {"reason", Value(reason)}});
}

bool keys(const Object& object, std::initializer_list<const char*> extras) {
    if (object.size() != 4 + extras.size()) return false;
    for (const auto* key : {"context", "client", "request", "action"}) if (!object.contains(key)) return false;
    for (const auto* key : extras) if (!object.contains(key)) return false;
    return true;
}

bool place_keys(const Object& object) {
    if (object.contains("rotation")) {
        auto without_rotation = object;
        without_rotation.erase("rotation");
        const auto* kind = field<std::string>(object, "kind");
        return kind && (*kind == "collector" || *kind == "processor") && place_keys(without_rotation);
    }
    if (object.contains("tiles")) {
        auto without_tiles = object;
        without_tiles.erase("tiles");
        const auto* kind = field<std::string>(object, "kind");
        return kind && *kind == "wheel" && place_keys(without_tiles);
    }
    if (object.contains("level")) return object.contains("axis") ?
        keys(object, {"kind", "cell", "axis", "level"}) : keys(object, {"kind", "cell", "level"});
    return object.contains("axis") ? keys(object, {"kind", "cell", "axis"}) : keys(object, {"kind", "cell"});
}

std::optional<mechanics::Axis> axis_value(const std::string& name) {
    if (name == "x") return mechanics::Axis::x;
    if (name == "y") return mechanics::Axis::y;
    if (name == "z") return mechanics::Axis::z;
    return std::nullopt;
}

authority::Point gear_half_extents(mechanics::Axis axis, Integer /* teeth */) {
    const auto radius = pitch / 2;
    authority::Point half{radius, radius, radius};
    half[static_cast<std::size_t>(axis)] = 0.04; // Fixture disc half-thickness, not tooth physics.
    return half;
}

authority::Point gear_axle_half_extents(mechanics::Axis axis) {
    authority::Point half{0.1, 0.1, 0.1};
    half[static_cast<std::size_t>(axis)] = pitch / 2;
    return half;
}

bool transmission_intersects(const Bounds& other, const mechanics::Point& center, mechanics::Axis axis, bool gear) {
    const authority::Point at{center[0] * height_step, anchor_height + center[1] * height_step, center[2] * height_step};
    return overlap(other, {at, gear_axle_half_extents(axis)}) ||
        (gear && overlap(other, {at, gear_half_extents(axis, 0)}));
}

bool collector_intake_intersects(const Bounds& intake, const world::Profile& profile,
        const stationary::PlacedPart& other) {
    if (other.role == Role::shaft || other.role == Role::gear)
        return transmission_intersects(intake, other.geometry.center, other.geometry.axis, other.role == Role::gear);
    return overlap(intake, part_bounds(profile, other));
}

bool transmission_intersects_foundations(const world::State& state, const mechanics::Point& center,
                                          mechanics::Axis axis, bool gear) {
    for (const auto& [id, foundation] : state.foundations) {
        (void)id;
        if (transmission_intersects(foundation_bounds(foundation), center, axis, gear)) return true;
    }
    return false;
}

std::optional<mechanics::Point> gear_center(const Array& input) {
    if (input.size() != 3) return std::nullopt;
    mechanics::Point output;
    for (std::size_t index = 0; index < 3; ++index) {
        const auto* value = std::get_if<Integer>(&input[index].storage());
        if (!value || *value < -mechanics::maximum_coordinate || *value > mechanics::maximum_coordinate) return std::nullopt;
        output[index] = *value;
    }
    return output;
}

std::optional<authority::Point> point(const Array& values) {
    if (values.size() != 3) return std::nullopt;
    authority::Point output;
    for (std::size_t index = 0; index < 3; ++index) {
        if (const auto* value = std::get_if<double>(&values[index].storage())) output[index] = *value;
        else if (const auto* value = std::get_if<Integer>(&values[index].storage())) {
            // Reject a lossy observation conversion rather than moving a body.
            constexpr Integer exact_limit = 9007199254740992;
            if (*value < -exact_limit || *value > exact_limit) return std::nullopt;
            output[index] = static_cast<double>(*value);
        } else return std::nullopt;
        if (!std::isfinite(output[index])) return std::nullopt;
    }
    return output;
}

Value point_value(const authority::Point& point) {
    return Value(Array{Value(point[0]), Value(point[1]), Value(point[2])});
}

// Check only the retained translation. Current parts, poses and generations
// cannot be used to reinterpret a historical request after removal or restore.
bool historical_wire(const authority::Record& record) {
    const auto& intent = record.intent;
    const auto* wire = field<Object>(intent, "wire");
    const auto* action = field<std::string>(intent, "action");
    const auto* accepted = field<bool>(record.result, "accepted");
    if (!wire || !action || !accepted) return false;
    if (*action == "adapter_refusal") return !*accepted;
    const auto* original_action = field<std::string>(*wire, "action");
    if (!original_action) return false;
    const auto same = [&](const char* original, const char* normalized) {
        const auto left = wire->find(original);
        const auto right = intent.find(normalized);
        return left != wire->end() && right != intent.end() &&
            !values::typed_difference(left->second, right->second);
    };
    if (*action == "pickup_material") {
        const auto* center = field<Array>(*wire, "center");
        if (*original_action != "pickup_material" || !keys(*wire, {"center", "expected"}) || !field<Object>(*wire, "expected") || !center || center->size() != 3 || !same("center", "center") || !same("expected", "expected")) return false;
        for (const auto& value : *center) {
            const auto* coordinate = std::get_if<Integer>(&value.storage());
            if (!coordinate || *coordinate < -materials::maximum_drop_coordinate || *coordinate > materials::maximum_drop_coordinate) return false;
        }
        return true;
    }
    if (*action == "harvest_source")
        return *original_action == "harvest_source" && keys(*wire, {"target"}) &&
            field<std::string>(*wire, "target") && same("target", "target");
    if (*action == "craft_component")
        return *original_action == "craft_component" && keys(*wire, {"entity", "component"}) &&
            field<std::string>(*wire, "entity") && field<std::string>(*wire, "component") &&
            same("entity", "target") && same("component", "component");
    if (*action == "take_hand_crank" || *action == "return_hand_crank")
        return *original_action == *action && keys(*wire, {"entity"}) &&
            field<std::string>(*wire, "entity") && same("entity", "target");
    if (*action == "turn_hand_crank")
        return *original_action == *action && keys(*wire, {"entity"}) &&
            field<std::string>(*wire, "entity") && same("entity", "target");
    if (*action == "place_component")
        return *original_action == "place_component" && keys(*wire, {"component", "center"}) &&
            field<std::string>(*wire, "component") && field<Array>(*wire, "center") &&
            same("component", "component") && same("center", "center");
    if (*action == "reclaim_component")
        return *original_action == "reclaim_component" && keys(*wire, {"entity"}) &&
            field<std::string>(*wire, "entity") && same("entity", "target");
    if (*action == "place_foundations") {
        const auto* cell = field<Array>(*wire, "cell");
        const auto* end = field<Array>(*wire, "end_cell");
        const auto* level = field<Integer>(*wire, "level");
        if (*original_action != "place_foundations" || !keys(*wire, {"cell", "end_cell", "level"}) ||
            !cell || !end || cell->size() != 2 || end->size() != 2 || !level ||
            *level < -1000000 || *level > 1000000) return false;
        const auto matches = [&](const Array& point, const char* name) {
            const auto* x = std::get_if<Integer>(&point[0].storage());
            const auto* z = std::get_if<Integer>(&point[1].storage());
            return x && z && *x >= -250000 && *x <= 250000 && *z >= -250000 && *z <= 250000 &&
                intent.contains(name) && !values::typed_difference(intent.at(name),
                    Value(Array{Value(4 * *x), Value(*level), Value(4 * *z)}));
        };
        return matches(*cell, "center") && matches(*end, "end");
    }
    if (*action == "place_foundation") {
        const auto* cell = field<Array>(*wire, "cell");
        const auto* level = field<Integer>(*wire, "level");
        const auto* center = field<Array>(intent, "center");
        if (*original_action != "place_foundation" || !keys(*wire, {"cell", "level"}) ||
            !cell || cell->size() != 2 || !level || !center || center->size() != 3) return false;
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        return x && z && *x >= -250000 && *x <= 250000 && *z >= -250000 && *z <= 250000 &&
            *level >= -1000000 && *level <= 1000000 &&
            !values::typed_difference(Value(*center), Value(Array{Value(4 * *x), Value(*level), Value(4 * *z)}));
    }
    if (*action == "place" || *action == "place_connected") {
        if (*original_action == "place_shaft") {
            const auto* center = field<Array>(*wire, "center");
            const auto* axis = field<std::string>(*wire, "axis");
            const auto* span = field<Integer>(*wire, "half_span");
            return *action == "place" && keys(*wire, {"center", "axis", "half_span"}) && center && gear_center(*center) &&
                axis && axis_value(*axis) && span && *span == 2 &&
                same("center", "center") && same("axis", "axis") && same("half_span", "half_span") &&
                field<std::string>(intent, "role") && *field<std::string>(intent, "role") == "shaft" &&
                field<Integer>(intent, "teeth") && *field<Integer>(intent, "teeth") == 0;
        }
        if (*original_action == "place_gear") {
            const auto* center = field<Array>(*wire, "center");
            const auto* axis = field<std::string>(*wire, "axis");
            const auto* teeth = field<Integer>(*wire, "teeth");
            return *action == "place" && keys(*wire, {"center", "axis", "teeth"}) && center && gear_center(*center) &&
                axis && axis_value(*axis) && teeth && *teeth > 0 && *teeth <= mechanics::maximum_dimension &&
                same("center", "center") && same("axis", "axis") && same("teeth", "teeth") &&
                field<std::string>(intent, "role") && *field<std::string>(intent, "role") == "gear" &&
                field<Integer>(intent, "half_span") && *field<Integer>(intent, "half_span") == 0;
        }
        if (*original_action == "place_relay") {
            const auto* center = field<Array>(*wire, "center");
            const auto* axis = field<std::string>(*wire, "axis");
            const auto* name = field<std::string>(*wire, "kind");
            const auto* relay = field<std::string>(*wire, "relay_axis");
            if (*action != "place" || !center || !gear_center(*center) || !axis || !axis_value(*axis) ||
                !name || (*name != "gearbox" && *name != "vertical_gearbox" && *name != "chain_drive") ||
                !keys(*wire, relay ? std::initializer_list<const char*>{"kind", "center", "axis", "relay_axis"} :
                    std::initializer_list<const char*>{"kind", "center", "axis"}) ||
                (relay != nullptr) != (*name == "chain_drive") ||
                (relay && (!axis_value(*relay) || axis_value(*relay) == axis_value(*axis))) ||
                (*name == "gearbox" && *axis != "y") ||
                (*name == "vertical_gearbox" && *axis == "y")) return false;
            return same("center", "center") && same("axis", "axis") &&
                field<std::string>(intent, "role") && *field<std::string>(intent, "role") == *name &&
                (!relay || same("relay_axis", "relay_axis")) &&
                field<Integer>(intent, "teeth") && *field<Integer>(intent, "teeth") == 0 &&
                field<Integer>(intent, "half_span") && *field<Integer>(intent, "half_span") == 0;
        }
        const auto* name = field<std::string>(*wire, "kind");
        const auto* cell = field<Array>(*wire, "cell");
        const auto* axis = field<std::string>(*wire, "axis");
        if (*original_action != "place" || !place_keys(*wire) ||
            (wire->contains("axis") && (!axis || !axis_value(*axis))) || !name || !cell || cell->size() != 2)
            return false;
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        const auto* level = field<Integer>(*wire, "level");
        const auto* tiles = field<Integer>(*wire, "tiles");
        const auto* rotation = field<Integer>(*wire, "rotation");
        if (wire->contains("rotation") && (!rotation || *rotation < 0 || *rotation > 3)) return false;
        if (wire->contains("rotation") != intent.contains("rotation")) return false;
        if (rotation && (!field<Integer>(intent, "rotation") || *field<Integer>(intent, "rotation") != *rotation))
            return false;
        if (!x || !z || *x < -250000 || *x > 250000 || *z < -250000 || *z > 250000 ||
            (wire->contains("level") && (!level || *level < -1000000 || *level > 1000000)) ||
            (*name != "collector" && *name != "processor" && *name != "wheel" && *name != "gear"))
            return false;
        if (wire->contains("tiles") != intent.contains("wheel_tiles")) return false;
        if (wire->contains("tiles") && (!tiles || *tiles < 3 || *tiles > mechanics::maximum_dimension ||
            !field<Integer>(intent, "wheel_tiles") || *field<Integer>(intent, "wheel_tiles") != *tiles)) return false;
        if (*action == "place_connected" && *name != "collector" && *name != "processor")
            return false;
        const Object expected{{"role", Value(*name == "wheel" ? "waterwheel" : *name)},
            {"center", Value(Array{Value(4 * *x), Value(level ? *level : Integer{0}), Value(4 * *z)})},
            {"axis", Value(axis ? *axis : "x")}, {"teeth", Value(Integer{*name == "gear" ? 2 : 0})},
            {"half_span", Value(Integer{0})}};
        for (const auto& [key, value] : expected) {
            const auto found = intent.find(key);
            if (found == intent.end() || values::typed_difference(value, found->second)) return false;
        }
        return true;
    }
    if (*action == "shaft_between" || *action == "remove_shaft_between") {
        const auto mapped = *action == "shaft_between" ? "connect_drive" : "disconnect_drive";
        return *original_action == mapped && keys(*wire, {"from", "to"}) &&
            same("from", "target") && same("to", "to");
    }
    if (*action == "place_belt_span")
        return *original_action == "place_belt_span" && keys(*wire, {"from", "to"}) &&
            same("from", "target") && same("to", "to");
    if (*action == "place_selected_belt_span")
        return *original_action == "place_selected_belt_span" && keys(*wire, {"from", "to", "selection"}) &&
            same("from", "target") && same("to", "to") && same("selection", "selection");
    if (*action == "remove_belt_span")
        return *original_action == "remove_belt_span" && keys(*wire, {"entity"}) && same("entity", "target");
    if (*action == "select_belt_shaft")
        return *original_action == "select_belt_shaft" && keys(*wire, {"entity"}) && same("entity", "target");
    if (*action == "recover_belt_slot")
        return *original_action == "recover_belt_slot" && keys(*wire, {"entity", "slot", "expected"}) &&
            same("entity", "target") && same("slot", "slot") && same("expected", "expected");
    if (*action == "load_belt_slot")
        return *original_action == "load_belt_slot" && keys(*wire, {"entity", "slot", "item", "work_id"}) &&
            same("entity", "target") && same("slot", "slot") && same("item", "item") && same("work_id", "work_id");
    if (*action == "remove" || *action == "recover")
        return *original_action == *action && keys(*wire, {"entity"}) && same("entity", "target");
    if (*action == "remove_foundation")
        return *original_action == "remove" && keys(*wire, {"entity"}) && same("entity", "target");
    if (*action == "collect" || *action == "insert_raw")
        return *original_action == (*action == "collect" ? "retrieve" : "insert_raw") &&
            keys(*wire, {"entity", "amount"}) && same("entity", "target") && same("amount", "amount");
    if (*action == "insert_work")
        return *original_action == "insert_work" && keys(*wire, {"entity", "work_id"}) &&
            same("entity", "target") && same("work_id", "work_id");
    return false;
}

const stationary::PlacedPart* find(const world::State& state, const std::string& id) {
    const auto found = std::find_if(state.topology.parts.begin(), state.topology.parts.end(),
        [&](const auto& part) { return part.geometry.id == id; });
    return found == state.topology.parts.end() ? nullptr : &*found;
}

std::vector<Bounds> belt_bounds(const mechanics::Part& first, const mechanics::Part& last) {
    std::vector<Bounds> result;
    const auto path = mechanics::belt_path(first, last);
    if (!path) return result;
    const auto at = [](const mechanics::Point& point) -> authority::Point {
        return {point[0] * height_step, anchor_height + point[1] * height_step, point[2] * height_step};
    };
    if (path->kind == mechanics::BeltPathKind::inclined) {
        const auto a = at(path->tiles.front()), b = at(path->tiles.back());
        const auto direction = first.axis == mechanics::Axis::x ? std::size_t{2} : std::size_t{0};
        const auto axle = static_cast<std::size_t>(first.axis);
        const double sx = b[direction] > a[direction] ? 1.0 : -1.0;
        const double sy = b[1] > a[1] ? 1.0 : -1.0;
        // Cover the same oriented body as site_geometry.gd, including its
        // half-tile overhang at each end. Small sections bound the 45-degree
        // rectangle without filling the empty space below the whole slope.
        const auto sections = path->tiles.size() * 8;
        const double length = path->tiles.size() * pitch;
        const double section = length / sections;
        const double normal = 0.15 / std::sqrt(2.0);
        for (std::size_t i = 0; i < sections; ++i) {
            const double along = -pitch / 2 + (i + 0.5) * section;
            auto center = a;
            center[direction] += sx * along;
            center[1] += sy * along;
            authority::Point half{};
            half[direction] = section / 2 + normal;
            half[1] = section / 2 + normal;
            half[axle] = 0.3;
            result.push_back({center, half});
        }
        return result;
    }
    if (path->kind != mechanics::BeltPathKind::horizontal) {
        const auto a = at(path->tiles.front()), b = at(path->tiles.back());
        const auto direction = a[0] != b[0] ? std::size_t{0} : (a[1] != b[1] ? std::size_t{1} : std::size_t{2});
        authority::Point center{}, half{0.3, 0.3, 0.3};
        for (std::size_t axis = 0; axis < 3; ++axis) center[axis] = (a[axis] + b[axis]) / 2;
        half[direction] = std::abs(b[direction] - a[direction]) / 2 + pitch / 2;
        const auto axle = static_cast<std::size_t>(first.axis);
        half[3 - direction - axle] = 0.15;
        result.push_back({center, half});
        return result;
    }
    const auto direction = first.axis == mechanics::Axis::x ? std::size_t{2} : std::size_t{0};
    for (const auto& point : path->tiles) {
        authority::Point half{0.3, 0.15, 0.3}; half[direction] = pitch / 2;
        result.push_back({at(point), half});
    }
    return result;
}

// Test a box against the actual rotated inclined belt after the conservative
// section broad phase. The two additional separating axes are the slope and
// its normal; this retains face contact without filling the empty corners.
bool belt_intersects(const mechanics::Part& first, const mechanics::Part& last, const Bounds& bounds) {
    const auto sections = belt_bounds(first, last);
    if (std::none_of(sections.begin(), sections.end(), [&](const auto& section) { return overlap(section, bounds); }))
        return false;
    const auto path = mechanics::belt_path(first, last);
    if (!path || path->kind != mechanics::BeltPathKind::inclined) return true;
    const auto direction = first.axis == mechanics::Axis::x ? std::size_t{2} : std::size_t{0};
    const auto& a = path->tiles.front();
    const auto& b = path->tiles.back();
    const double dx = b[direction] > a[direction] ? 1.0 : -1.0;
    const double dy = b[1] > a[1] ? 1.0 : -1.0;
    const double center_direction = (a[direction] + b[direction]) * height_step / 2;
    const double center_height = anchor_height + (a[1] + b[1]) * height_step / 2;
    const double offset_direction = bounds.center[direction] - center_direction;
    const double offset_height = bounds.center[1] - center_height;
    const double root_two = std::sqrt(2.0);
    const double box_radius = (bounds.half[direction] + bounds.half[1]) / root_two;
    const double along = std::abs(dx * offset_direction + dy * offset_height) / root_two;
    const double across = std::abs(-dy * offset_direction + dx * offset_height) / root_two;
    const double belt_half_length = path->tiles.size() * pitch / root_two;
    const auto overlaps_axis = [](double distance, double extent) {
        const auto roundoff = 8 * std::numeric_limits<double>::epsilon() * std::max({1.0, distance, extent});
        return distance < extent - roundoff;
    };
    return overlaps_axis(along, belt_half_length + box_radius) && overlaps_axis(across, 0.15 + box_radius);
}

bool intersects_belt(const world::State& state, const Bounds& bounds) {
    for (const auto& span : state.topology.belt_spans) {
        const auto* first = find(state, span.geometry.first_shaft);
        const auto* last = find(state, span.geometry.last_shaft);
        if (first && last && belt_intersects(first->geometry, last->geometry, bounds)) return true;
    }
    return false;
}

const char* kind(Role role) {
    switch (role) {
        case Role::collector: return "collector";
        case Role::belt: return "belt";
        case Role::processor: return "processor";
        case Role::waterwheel: return "wheel";
        case Role::gear: return "gear";
        case Role::shaft: return "shaft";
        case Role::gearbox: return "gearbox";
        case Role::vertical_gearbox: return "vertical_gearbox";
        case Role::chain_drive: return "chain_drive";
    }
    return "invalid";
}

Value cargo_value(const materials::Cargo& cargo, bool resources = false) {
    Array lots;
    for (const auto& lot : cargo.work_lots) lots.emplace_back(Object{
        {"id", Value(lot.id)}, {"recipe_input", Value(lot.recipe.input_units_per_product)},
        {"cycle_ticks", Value(lot.recipe.cycle_ticks)}, {"remaining", Value(lot.remaining_ticks)},
        {"completed_subticks", Value(lot.completed_subticks)}, {"work_remainder", Value(lot.work_remainder)},
        {"work_remainder_denominator", Value(lot.work_remainder_denominator)}});
    Object output{{"raw", Value(cargo.raw_units)}, {"products", Value(cargo.products)},
                  {"work_lots", Value(std::move(lots))}};
    if (resources) {
        output.emplace("timber", Value(cargo.timber));
        Object components;
        for (const auto& [kind, count] : cargo.components)
            components.emplace(materials::component_name(kind), Value(count));
        output.emplace("components", Value(std::move(components)));
    }
    return Value(std::move(output));
}

Value kit_value(const stationary::Kit& kit) {
    Object counts{{"collector", Value(Integer{0})}, {"belt", Value(Integer{0})},
        {"processor", Value(Integer{0})}, {"wheel", Value(Integer{0})},
        {"shaft", Value(Integer{0})}, {"gear", Value(Integer{0})},
        {"gearbox", Value(Integer{0})}, {"vertical_gearbox", Value(Integer{0})},
        {"chain_drive", Value(Integer{0})}};
    for (const auto& [specification, count] : kit) {
        const auto name = kind(specification.role);
        const auto previous = std::get<Integer>(counts.at(name).storage());
        if (count > std::numeric_limits<Integer>::max() - previous) throw std::overflow_error("Part projection overflow.");
        counts.at(name) = Value(previous + count);
    }
    return Value(std::move(counts));
}

Object outward(const world::Delivery& delivery, const world::Snapshot& snapshot) {
    Object output;
    if (delivery.result) output = *delivery.result;
    else output = Object{{"accepted", Value(false)},
        {"reason", Value(delivery.history_error == authority::Error::none ? "native_preparation_failed" :
                          authority::error_name(delivery.history_error))},
        {"entity", Value("")}, {"context", Value(snapshot.history.context)},
        {"revision", Value(snapshot.revision)}, {"order", Value(snapshot.history.order)}, {"duplicate", Value(false)}};
    // The current view consumes a nested receipt; the stored native result is
    // untouched. This is a detached presentation value, not another cache.
    const auto* actor = field<std::string>(output, "actor");
    const auto* position = field<Array>(output, "actor_position");
    const auto* targets = field<Array>(output, "targets");
    const auto* distances = field<Array>(output, "distances_squared");
    const auto* epoch = field<Integer>(output, "native_epoch");
    const auto* radius = field<double>(output, "build_reach");
    if (actor && position && targets && distances && epoch && radius)
        output.emplace("reach", Value(Object{{"actor", Value(*actor)}, {"position", Value(*position)},
            {"native_epoch", Value(*epoch)}, {"targets", Value(*targets)},
            {"distances_squared", Value(*distances)}, {"build_reach", Value(*radius)},
            {"reachable", Value(field<std::string>(output, "reason") && *field<std::string>(output, "reason") != "out_of_reach")}}));
    return output;
}
}  // namespace

Value Host::initialize(const std::string& context, const std::vector<std::string>& actors) {
    return initialize_site(context, actors, false);
}

Value Host::initialize_arrival(const std::string& context, const std::vector<std::string>& actors) {
    return initialize_site(context, actors, true);
}

Value Host::initialize_site(const std::string& context, const std::vector<std::string>& actors,
                            bool arrival) {
    if (owned_) return result(false, "already_initialized");
    if (actors.empty() || actors.size() > 2 || actors.front() != "P") return result(false, "invalid_roster");
    world::Profile profile;
    // Reversible opening content, with enough buffer to recover finite ore in
    // batches. All reserve and carried quantities remain in this one World.
    profile.material = {1, 32, 2};
    profile.initial_units = arrival ? 16 : mineral_site::opening_reserve;
    profile.meters_per_grid_unit = pitch / 4.0;
    profile.anchor_offset = {0, anchor_height, 0};
    profile.wheel_radius = wheel_radius;
    profile.wheel_axle_offset = wheel_axle_offset;
    profile.build_reach = reach;
    profile.foundation_parts = 24;
    // East of the river and clear of the exposed ore deposit. This is a
    // reversible authored site anchor, expressed in the one quarter-tile grid.
    if (arrival) {
        profile.landing_pod_center = mechanics::Point{4, 0, 16};
        profile.material.manual_ore = materials::OreSite{"opening-softmetal", {-3, 0, 0}};
        for (const auto& cell : mineral_site::opening_cells)
            for (Integer level = 0; level <= mineral_site::extraction_depth_steps; level += 4)
                profile.collector_faces.push_back({{4 * cell.x, level, 4 * cell.z}, {-1, 0, 0}});
        profile.material.timber_sites = {
            {"tree-east-south", {{12, 0, 12}, 8}},
            {"tree-east-north", {{12, 0, 24}, 8}},
            {"tree-north", {{0, 0, 28}, 8}}};
        profile.material.hand_carry_capacity = 24;
    }
    if (!arrival)
        profile.finite_parts = {{{Role::collector, 0, 0}, 1}, {{Role::belt, 0, 0}, 2},
            {{Role::processor, 0, 0}, 1}, {{Role::waterwheel, 0, 0}, 1}, {{Role::shaft, 0, 2}, 8},
            {{Role::gear, 2, 0}, 8}, {{Role::gear, 4, 0}, 2},
            {{Role::gearbox, 0, 0}, 2}, {{Role::vertical_gearbox, 0, 0}, 2},
            {{Role::chain_drive, 0, 0}, 8}};
    world::State seed;
    seed.topology.drive_enabled = true;
    seed.material.initial_units = profile.initial_units;
    seed.material.stock.source = profile.initial_units;
    for (const auto& [id, site] : profile.material.timber_sites)
        seed.material.timber_remaining.emplace(id, site.initial);
    if (arrival) {
        const auto& center = *profile.landing_pod_center;
        seed.landing_pod = world::LandingPod{"landing-pod", center, 1};
        seed.issued_entities.emplace("landing-pod", 1);
        seed.fabrication_hub = world::FabricationHub{"pod-fabrication-hub", world::landing_hub_center(center), 1};
        seed.issued_entities.emplace(seed.fabrication_hub->id, 1);
        seed.hand_crank = world::HandCrank{"pod-hand-crank", 1, std::nullopt};
        seed.issued_entities.emplace(seed.hand_crank->id, 1);
        const auto deck = world::landing_deck_centers(center);
        for (std::size_t index = 0; index < deck.size(); ++index) {
            const auto id = "pod-floor-" + std::to_string(index);
            seed.foundations.emplace(id, world::Foundation{deck[index], 1});
            seed.issued_entities.emplace(id, 1);
        }
    }
    auto candidate = std::make_unique<Owned>();
    for (const auto& actor : actors) {
        if ((actor != "P" && actor != "Q") || !profile.actors.insert(actor).second)
            return result(false, "invalid_roster");
        seed.material.cargo.emplace(actor, materials::Cargo{});
        seed.kits.emplace(actor, actor == "P" ? profile.finite_parts : stationary::Kit{});
        seed.foundation_kits.emplace(actor, actor == "P" ?
            profile.foundation_parts - (arrival ? world::landing_deck_parts : 0) : 0);
        candidate->actors.emplace(actor, Actor{arrival ?
            authority::Point{pitch, 1.0, (actor == "P" ? 4.0 : 5.0) * pitch} :
            authority::Point{-pitch, 1.0, (actor == "P" ? 2.0 : 3.0) * pitch}, 0, false});
    }
    candidate->world = world::World::create(context, profile, seed);
    if (!candidate->world) return result(false, "invalid_initial_world");
    profile_ = std::move(profile);
    owned_ = std::move(candidate);
    return result(true, "initialized");
}

Value Host::configure_terrain(const Object& input) {
    if (!owned_ || owned_->native_started || !terrain_axis_.empty()) return result(false, "terrain_already_bound");
    const auto* axis = field<Array>(input, "axis");
    const auto* heights = field<Array>(input, "heights");
    const auto* obstacles = field<Array>(input, "obstacles");
    const auto* source_obstacle = field<Integer>(input, "source_obstacle");
    const auto* water = field<Array>(input, "water");
    const auto* flow_cells = field<Array>(input, "flow_cells");
    if (input.size() != (water || flow_cells ? 4u : 3u) + (source_obstacle ? 1u : 0u) || (water && flow_cells) ||
        !axis || !heights || !obstacles || obstacles->size() > 1024 || axis->size() < 2 || axis->size() > 200 ||
        heights->size() != axis->size() * axis->size()) return result(false, "invalid_terrain");
    std::vector<double> coordinates, elevations;
    std::vector<std::pair<authority::Point, authority::Point>> solids;
    for (const auto& value : *axis) {
        const auto* number = std::get_if<double>(&value.storage());
        if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000 ||
            (!coordinates.empty() && coordinates.back() >= *number)) return result(false, "invalid_terrain");
        coordinates.push_back(*number);
    }
    for (const auto& value : *heights) {
        const auto* number = std::get_if<double>(&value.storage());
        if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000) return result(false, "invalid_terrain");
        elevations.push_back(*number);
    }
    for (const auto& value : *obstacles) {
        const auto* ends = std::get_if<Array>(&value.storage());
        if (!ends || ends->size() != 2) return result(false, "invalid_terrain");
        const auto* low_array = std::get_if<Array>(&ends->at(0).storage());
        const auto* high_array = std::get_if<Array>(&ends->at(1).storage());
        const auto low = low_array ? point(*low_array) : std::nullopt;
        const auto high = high_array ? point(*high_array) : std::nullopt;
        if (!low || !high) return result(false, "invalid_terrain");
        for (std::size_t axis = 0; axis < 3; ++axis)
            if ((*low)[axis] >= (*high)[axis]) return result(false, "invalid_terrain");
        solids.emplace_back(*low, *high);
    }
    if (input.contains("source_obstacle") && (!source_obstacle || *source_obstacle < 0 ||
        static_cast<std::size_t>(*source_obstacle) >= solids.size())) return result(false, "invalid_terrain");
    if (source_obstacle) {
        const auto& [low, high] = solids[static_cast<std::size_t>(*source_obstacle)];
        const Bounds source{{(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, (low[2] + high[2]) / 2},
                            {(high[0] - low[0]) / 2, (high[1] - low[1]) / 2, (high[2] - low[2]) / 2}};
        if (!overlap(source, *collector_intake_bounds({0, 0, 0})) ||
            !overlap(source, *collector_intake_bounds({0, 0, 4}))) return result(false, "invalid_terrain");
    }
    auto next_profile = profile_;
    if (flow_cells) {
        if (flow_cells->empty() || flow_cells->size() > 65536) return result(false, "invalid_water");
        std::vector<waterflow::Cell> cells;
        cells.reserve(flow_cells->size());
        for (const auto& value : *flow_cells) {
            const auto* row = std::get_if<Array>(&value.storage());
            if (!row || row->size() != 3) return result(false, "invalid_water");
            const auto* x = std::get_if<Integer>(&row->at(0).storage());
            const auto* z = std::get_if<Integer>(&row->at(1).storage());
            const auto* surface = std::get_if<Integer>(&row->at(2).storage());
            if (!x || !z || !surface) return result(false, "invalid_water");
            cells.push_back({*x, *z, *surface});
        }
        const auto derived = waterflow::derive({coordinates, elevations, height_step}, cells);
        if (!derived) return result(false, "invalid_water");
        next_profile.water = *derived;
    }
    if (water) {
        if (water->empty() || water->size() > 65536) return result(false, "invalid_water");
        for (const auto& value : *water) {
            const auto* row = std::get_if<Array>(&value.storage());
            if (!row || row->size() != 6) return result(false, "invalid_water");
            std::array<Integer, 6> fields{};
            for (std::size_t i = 0; i < fields.size(); ++i) {
                const auto* number = std::get_if<Integer>(&row->at(i).storage());
                if (!number) return result(false, "invalid_water");
                fields[i] = *number;
            }
            if (!next_profile.water.emplace(std::array<Integer, 2>{fields[0], fields[1]},
                    waterwheel::Sample{fields[2], fields[3], fields[4], fields[5]}).second)
                return result(false, "invalid_water");
        }
    }
    if (water || flow_cells) {
        const auto snapshot = owned_->world->snapshot();
        if (snapshot.revision != 0 || snapshot.history.order != 0) return result(false, "terrain_already_bound");
        auto replacement = world::World::create(snapshot.history.context, next_profile, snapshot.state);
        if (!replacement) return result(false, "invalid_water");
        owned_->world = std::move(replacement);
        profile_ = std::move(next_profile);
    }
    terrain_axis_ = std::move(coordinates);
    terrain_heights_ = std::move(elevations);
    terrain_obstacles_ = std::move(solids);
    source_obstacle_index_ = source_obstacle ? std::optional<std::size_t>{static_cast<std::size_t>(*source_obstacle)} : std::nullopt;
    return result(true, "terrain_bound");
}

bool Host::site_blocked(const authority::Point& low, const authority::Point& high,
        std::optional<std::size_t> ignored) const {
    for (std::size_t index = 0; index < terrain_obstacles_.size(); ++index) {
        if (ignored == index) continue;
        const auto& obstacle = terrain_obstacles_[index];
        bool overlaps = true;
        for (std::size_t axis = 0; axis < 3; ++axis)
            if (high[axis] <= obstacle.first[axis] || low[axis] >= obstacle.second[axis]) overlaps = false;
        if (overlaps) return true;
    }
    return false;
}

const char* Host::wheel_site_refusal(const mechanics::Point& center, mechanics::Axis axis, Integer tiles) const {
    const auto sample = profile_.water.find({center[0], center[2]});
    if (sample == profile_.water.end()) return "not_at_stream";
    const auto contact = waterwheel::immersed(center[1] * 100 + profile_.wheel_axle_offset,
                                              profile_.wheel_radius * tiles, axis, sample->second);
    if (!contact || !*contact) return "not_at_stream";
    const double x = center[0] * height_step, y = center[1] * height_step + anchor_height;
    const double z = center[2] * height_step;
    const double radius = profile_.wheel_radius * tiles * height_step / 100.0;
    const double half_x = axis == mechanics::Axis::x ? 0.3 : radius;
    const double half_z = axis == mechanics::Axis::z ? 0.3 : radius;
    if (site_blocked({x - half_x, y - radius, z - half_z}, {x + half_x, y + radius, z + half_z}))
        return "site_occupied";
    // Bound the entire rotating rim against the same emitted terrain triangles.
    // Each strip uses its highest ground and the lowest point of the arc in
    // that strip, so an unchecked peak cannot pass between point samples.
    const auto strips = static_cast<Integer>(std::ceil(2 * radius / height_step));
    for (Integer index = 0; index < strips; ++index) {
        const double a = -radius + 2 * radius * index / strips;
        const double b = -radius + 2 * radius * (index + 1) / strips;
        const double middle = (a + b) / 2, span = (b - a) / 2;
        const auto terrain = axis == mechanics::Axis::x ? terrain_range(x, z + middle, 0.3, span) :
                                                        terrain_range(x + middle, z, span, 0.3);
        if (!terrain) return "terrain_unavailable";
        const double nearest = a > 0 ? a : b < 0 ? -b : 0;
        const double low_arc = y - std::sqrt(std::max(0.0, radius * radius - nearest * nearest));
        if (terrain->second > low_arc) return "site_occupied";
    }
    const auto supports = wheel_support_bounds(center, axis,
        [this](double sx, double sz, double hx, double hz) { return terrain_range(sx, sz, hx, hz); });
    if (!supports) return "support_required";
    for (const auto& support : *supports) {
        const authority::Point low{support.center[0] - support.half[0],
            support.center[1] - support.half[1], support.center[2] - support.half[2]};
        const authority::Point high{support.center[0] + support.half[0],
            support.center[1] + support.half[1], support.center[2] + support.half[2]};
        if (site_blocked(low, high)) return "site_occupied";
    }
    return nullptr;
}

std::optional<std::pair<double, double>> Host::terrain_range(double x, double z, double half_x, double half_z) const {
    if (terrain_axis_.empty()) return std::nullopt;
    const double left = x - half_x, right = x + half_x;
    const double near = z - half_z, far = z + half_z;
    if (left < terrain_axis_.front() || right > terrain_axis_.back() ||
        near < terrain_axis_.front() || far > terrain_axis_.back()) return std::nullopt;
    const auto cell = [&](double at) {
        return std::min(terrain_axis_.size() - 2, static_cast<std::size_t>(
            std::upper_bound(terrain_axis_.begin(), terrain_axis_.end(), at) - terrain_axis_.begin() - 1));
    };
    const auto vertex = [&](std::size_t gx, std::size_t gz) {
        return authority::Point{terrain_axis_[gx], terrain_heights_[gz * terrain_axis_.size() + gx], terrain_axis_[gz]};
    };
    double low = std::numeric_limits<double>::infinity(), high = -low;
    for (auto gz = cell(near); gz <= cell(far); ++gz) for (auto gx = cell(left); gx <= cell(right); ++gx) {
        const auto a = vertex(gx, gz), b = vertex(gx + 1, gz), c = vertex(gx + 1, gz + 1), d = vertex(gx, gz + 1);
        for (auto polygon : {std::vector<authority::Point>{a, b, c}, std::vector<authority::Point>{a, c, d}}) {
            // Clip both actual emitted triangles to the complete tile footprint.
            // A linear triangle's extreme height is at a clipped polygon vertex.
            for (const auto& [axis, boundary, sign] : {std::tuple{0, left, 1.0}, {0, right, -1.0},
                    {2, near, 1.0}, {2, far, -1.0}}) {
                std::vector<authority::Point> clipped;
                for (std::size_t n = 0; n < polygon.size(); ++n) {
                    const auto& p = polygon[n];
                    const auto& q = polygon[(n + 1) % polygon.size()];
                    const bool inside = (p[axis] - boundary) * sign >= 0;
                    const bool next = (q[axis] - boundary) * sign >= 0;
                    if (inside) clipped.push_back(p);
                    if (inside != next) {
                        const auto t = (boundary - p[axis]) / (q[axis] - p[axis]);
                        clipped.push_back({p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1]), p[2] + t * (q[2] - p[2])});
                    }
                }
                polygon = std::move(clipped);
            }
            for (const auto& p : polygon) { low = std::min(low, p[1]); high = std::max(high, p[1]); }
        }
    }
    return std::pair{low, high};
}

const char* Host::machine_site_refusal(const world::State& state, const mechanics::Point& center,
        bool collector) const {
    const auto x = center[0] * height_step;
    const auto floor = center[1] * height_step;
    const auto z = center[2] * height_step;
    const bool supported = std::any_of(state.foundations.begin(), state.foundations.end(),
        [&](const auto& entry) { return entry.second.center == center; });
    const auto terrain = terrain_range(x, z);
    // A foundation supplies support, not clearance through the real ground.
    // Foundation blocks themselves may be buried; ordinary machines may not.
    if (terrain && terrain->second > floor) return "foundation_required";
    if (!supported) {
        if (!terrain) return "terrain_unavailable";
        // This is the existing seating fit, not additional character reach.
        if (terrain->first < floor - 0.04) return "foundation_required";
    }
    if (site_blocked({x - machine_width / 2, floor, z - machine_width / 2},
                     {x + machine_width / 2, floor + machine_height, z + machine_width / 2}))
        return "site_occupied";
    const auto external = collector ? collector_external_bounds(center) : std::vector<Bounds>{};
    for (std::size_t index = 0; index < external.size(); ++index) {
        const auto& at = external[index].center;
        const auto& half = external[index].half;
        const authority::Point low{at[0] - half[0], at[1] - half[1], at[2] - half[2]};
        const authority::Point high{at[0] + half[0], at[1] + half[1], at[2] + half[2]};
        const auto ground = terrain_range(at[0], at[2], half[0], half[2]);
        if (!ground) return "terrain_unavailable";
        if (ground->second > low[1] ||
            site_blocked(low, high, index == 0 ? source_obstacle_index_ : std::nullopt))
            return "site_occupied";
    }
    return nullptr;
}

std::map<std::string, Host::TransmissionSupport> Host::transmission_supports(
        const world::State& state) const {
    std::vector<const stationary::PlacedPart*> parts;
    for (const auto& part : state.topology.parts) parts.push_back(&part);
    auto jobs = parts;
    std::erase_if(jobs, [](const auto* part) { return !fixed_transmission(part->role); });
    std::sort(jobs.begin(), jobs.end(), [](const auto* a, const auto* b) {
        const auto& ac = a->geometry.center;
        const auto& bc = b->geometry.center;
        return std::tie(ac[1], ac[0], ac[2], a->geometry.axis, a->geometry.id) <
               std::tie(bc[1], bc[0], bc[2], b->geometry.axis, b->geometry.id);
    });
    std::map<std::string, TransmissionSupport> result;
    std::vector<Bounds> occupied;
    const auto beam = [](const authority::Point& a, const authority::Point& b) {
        Bounds bounds{};
        for (std::size_t dimension = 0; dimension < 3; ++dimension) {
            bounds.center[dimension] = (a[dimension] + b[dimension]) / 2;
            bounds.half[dimension] = std::abs(a[dimension] - b[dimension]) / 2 + 0.0475;
        }
        return bounds;
    };
    for (const auto* part : jobs) {
        const auto& center = part->geometry.center;
        const auto axis = part->geometry.axis;
        const authority::Point at{center[0] * height_step,
            anchor_height + center[1] * height_step, center[2] * height_step};
        // Fixed bearings stay coaxial. Move only the post, using a short arm
        // when another axle or a previously fitted stand occupies its column.
        // Try the other end of a horizontal axle if its first bearing face is
        // obstructed, for example by the collector's exterior lift.
        const std::size_t lateral = axis == mechanics::Axis::x ? 2 : 0;
        constexpr std::array offsets{0.0, 0.4, -0.4, 0.8, -0.8};
        const auto routes = offsets.size() * (axis == mechanics::Axis::y ? 1 : 2);
        for (std::size_t route = 0; route < routes; ++route) {
            const double offset = offsets[route % offsets.size()];
            const double axial = route < offsets.size() ? 0.55 : -0.55;
            auto bearing = at;
            if (axis == mechanics::Axis::x) bearing[0] += axial;
            else if (axis == mechanics::Axis::z) bearing[2] += axial;
            else bearing[1] -= 0.50;
            auto foot = bearing;
            if (axis == mechanics::Axis::y) foot[0] += 0.24;
            foot[lateral] += offset;
            const auto ground = terrain_range(foot[0], foot[2], 0.17, 0.17);
            if (!ground) continue;
            double seat = ground->second;
            for (const auto& [id, foundation] : state.foundations) {
                (void)id;
                const auto bounds = foundation_bounds(foundation);
                if (std::abs(foot[0] - bounds.center[0]) + 0.17 <= bounds.half[0] &&
                    std::abs(foot[2] - bounds.center[2]) + 0.17 <= bounds.half[2])
                    seat = std::max(seat, bounds.center[1] + bounds.half[1]);
            }
            const double base_seat = seat;
            for (const auto& obstacle : terrain_obstacles_) {
                if (obstacle.first[0] < foot[0] && obstacle.second[0] > foot[0] &&
                    obstacle.first[2] < foot[2] && obstacle.second[2] > foot[2] &&
                    obstacle.first[1] <= base_seat + 0.12)
                    seat = std::max(seat, obstacle.second[1]);
            }
            if (seat > at[1] - 0.02) continue;
            foot[1] = seat;
            const auto fitted_bearing = bearing;
            if (bearing[1] - seat > 9.0) continue;
            const double post_top = bearing[1] - 0.24;
            if (post_top <= seat) continue;
            const double column_top = std::max(post_top, seat + 0.14);
            std::vector<Bounds> boxes{{{foot[0], (seat + column_top) / 2, foot[2]},
                                      {0.17, (column_top - seat) / 2, 0.17}}};
            authority::Point half{0.185, 0.185, 0.185};
            half[static_cast<std::size_t>(axis)] = 0.1525;
            boxes.push_back({fitted_bearing, half});
            boxes.push_back({{bearing[0], bearing[1] - 0.20, bearing[2]}, {0.155, 0.04, 0.155}});
            if (foot[0] != fitted_bearing[0] || foot[2] != fitted_bearing[2]) {
                auto post_arm = foot;
                auto bearing_arm = fitted_bearing;
                post_arm[1] = bearing_arm[1] -= 0.24;
                boxes.push_back(beam(post_arm, bearing_arm));
            } else boxes.push_back({{bearing[0], post_top, bearing[2]}, {0.155, 0.0475, 0.155}});
            bool clear = true;
            for (const auto& box : boxes) {
                const auto terrain = terrain_range(box.center[0], box.center[2], box.half[0], box.half[2]);
                const authority::Point low{box.center[0] - box.half[0], box.center[1] - box.half[1], box.center[2] - box.half[2]};
                const authority::Point high{box.center[0] + box.half[0], box.center[1] + box.half[1], box.center[2] + box.half[2]};
                if (!terrain || terrain->second > low[1] + 1e-9 || site_blocked(low, high) ||
                    intersects_belt(state, box)) clear = false;
                for (const auto& [id, foundation] : state.foundations) {
                    (void)id;
                    if (overlap(box, foundation_bounds(foundation))) clear = false;
                }
                for (const auto& [id, component] : state.placed_components) {
                    (void)id;
                    if (overlap(box, {{component.center[0] * height_step,
                            component.center[1] * height_step + anchor_height,
                            component.center[2] * height_step}, {0.14, 0.14, 0.14}})) clear = false;
                }
                for (const auto* other : parts) {
                    if (other == part) continue;
                    if (collector_intake_intersects(box, profile_, *other)) clear = false;
                    if (other->role == Role::waterwheel) {
                        const auto wheel_feet = wheel_support_bounds(other->geometry.center, other->geometry.axis,
                            [this](double x, double z, double hx, double hz) { return terrain_range(x, z, hx, hz); });
                        if (!wheel_feet) clear = false;
                        else for (const auto& wheel_foot : *wheel_feet)
                            if (overlap(box, wheel_foot)) clear = false;
                    }
                    if (other->role == Role::collector)
                        for (const auto& external : collector_external_bounds(other->geometry.center))
                            if (overlap(box, external)) clear = false;
                }
                for (const auto& prior : occupied) if (overlap(box, prior)) clear = false;
                if (!clear) break;
            }
            if (!clear) continue;
            TransmissionSupport fitted{foot, fitted_bearing, {}};
            for (const auto& box : boxes) fitted.boxes.emplace_back(box.center, box.half);
            result.emplace(part->geometry.id, std::move(fitted));
            occupied.insert(occupied.end(), boxes.begin(), boxes.end());
            break;
        }
    }
    return result;
}

const char* Host::support_change_refusal(const world::State& before, const world::State& after) const {
    const auto previous = transmission_supports(before);
    const auto next = transmission_supports(after);
    for (const auto& part : after.topology.parts)
        if (fixed_transmission(part.role) && !next.contains(part.geometry.id)) return "support_required";
    for (const auto& [id, support] : next) {
        const auto old = previous.find(id);
        if (old != previous.end() && old->second.foot == support.foot &&
            old->second.bearing == support.bearing && old->second.boxes == support.boxes) continue;
        for (const auto& [center, half] : support.boxes)
            if (placement_blocked(center, half)) return "actor_occupied";
    }
    return nullptr;
}

const char* Host::transmission_site_refusal(const world::State& state, const mechanics::Point& center,
        mechanics::Axis axis, bool gear) const {
    const authority::Point at{center[0] * height_step, anchor_height + center[1] * height_step, center[2] * height_step};
    const auto axle = gear_axle_half_extents(axis);
    const auto check = [&](const authority::Point& half) -> const char* {
        const auto ground = terrain_range(at[0], at[2], half[0], half[2]);
        if (!ground) return "terrain_unavailable";
        if (ground->second > at[1] - half[1] + 1e-9) return "site_occupied";
        if (site_blocked({at[0] - half[0], at[1] - half[1], at[2] - half[2]},
                         {at[0] + half[0], at[1] + half[1], at[2] + half[2]})) return "site_occupied";
        return nullptr;
    };
    if (const auto* refusal = check(axle)) return refusal;
    if (gear) if (const auto* refusal = check(gear_half_extents(axis, 0))) return refusal;
    for (const auto& part : state.topology.parts) if (part.role == Role::waterwheel) {
        const auto supports = wheel_support_bounds(part.geometry.center, part.geometry.axis,
            [this](double sx, double sz, double hx, double hz) {
                return terrain_range(sx, sz, hx, hz);
            });
        if (!supports) return "support_required";
        for (const auto& support : *supports)
            if (transmission_intersects(support, center, axis, gear)) return "site_occupied";
    }
    return nullptr;
}

const char* Host::collector_site_refusal(const mechanics::Point& center) const {
    const mineral_site::Cell cell{center[0] / height_denominator, center[2] / height_denominator};
    if (!mineral_site::contains(cell)) return "not_at_seam";
    const auto surface = terrain_range(center[0] * height_step, center[2] * height_step);
    if (!surface) return "terrain_unavailable";
    const auto allowed = mineral_site::admit(cell, center[1] * height_step,
        {surface->first, surface->second}, mineral_site::extraction_depth_steps * height_step);
    return allowed == mineral_site::Error::none ? nullptr : mineral_site::error_name(allowed);
}

const char* Host::component_site_refusal(std::optional<materials::Component> kind,
        const mechanics::Point& center) const {
    const authority::Point at{center[0] * height_step,
        center[1] * height_step + anchor_height, center[2] * height_step};
    const Bounds volume{at, {0.14, 0.14, 0.14}};
    const auto ground = terrain_range(at[0], at[2], volume.half[0], volume.half[2]);
    if (!ground) return "terrain_unavailable";
    if (ground->second > at[1] - volume.half[1]) return "site_occupied";
    // Only the named cutting edge at one of the two trusted ore faces may
    // enter the source hull. The source obstacle is separately identified and
    // validated when terrain binds; every other obstacle still blocks it.
    bool source_contact = false;
    if (kind == materials::Component::cutting_edge)
        for (const auto& face : profile_.collector_faces)
            for (Integer height : {Integer{0}, Integer{1}})
                if (center == mechanics::Point{
                    face.machine_center[0] + 2 * face.toward_ore[0],
                    face.machine_center[1] + height,
                    face.machine_center[2] + 2 * face.toward_ore[2]}) source_contact = true;
    const auto ignored = source_contact ? source_obstacle_index_ : std::nullopt;
    if (site_blocked({at[0] - volume.half[0], at[1] - volume.half[1], at[2] - volume.half[2]},
                     {at[0] + volume.half[0], at[1] + volume.half[1], at[2] + volume.half[2]}, ignored))
        return "site_occupied";
    return nullptr;
}

world::ObserveActor Host::observe() const {
    return [this](const std::string& actor) -> std::optional<authority::ActorCut> {
        const auto found = owned_->actors.find(actor);
        if (found == owned_->actors.end()) return std::nullopt;
        return authority::ActorCut{actor, found->second.position, found->second.epoch,
                                   found->second.ready, profile_.build_reach};
    };
}

bool Host::placement_blocked(const authority::Point& target, const authority::Point& half_extents) const {
    for (const auto& [actor, state] : owned_->actors) {
        (void)actor;
        if (!state.ready) continue;
        const auto dx = std::max(std::abs(state.position[0] - target[0]) - half_extents[0], 0.0);
        const auto dz = std::max(std::abs(state.position[2] - target[2]) - half_extents[2], 0.0);
        const auto segment_half = capsule_height / 2 - capsule_radius;
        const auto below = target[1] - half_extents[1] - (state.position[1] + segment_half);
        const auto above = state.position[1] - segment_half - (target[1] + half_extents[1]);
        const auto dy = std::max({below, above, 0.0});
        if (dx * dx + dy * dy + dz * dz < capsule_radius * capsule_radius) return true;
    }
    return false;
}

Value Host::command(const std::string& bound_actor, const Object& wire) {
    if (!owned_) return result(false, "not_initialized");
    const auto* client = field<std::string>(wire, "client");
    if (!profile_.actors.contains(bound_actor) || !client || *client != bound_actor)
        return result(false, "wrong_actor");
    const auto snapshot = owned_->world->snapshot();
    const auto* request = field<std::string>(wire, "request");
    // Original wire comparison precedes generation lookup or translation. The
    // only cache is World's existing history; no adapter request map is created.
    if (request) for (const auto& record : snapshot.history.records) {
        if (field<std::string>(record.intent, "client") && *field<std::string>(record.intent, "client") == *client &&
            field<std::string>(record.intent, "request") && *field<std::string>(record.intent, "request") == *request) {
            auto replay = record.intent;
            replay.insert_or_assign("wire", Value(wire));
            return Value(outward(owned_->world->command({bound_actor, *client}, replay, observe()), snapshot));
        }
    }
    Object normalized{{"context", wire.contains("context") ? wire.at("context") : Value()},
        {"client", Value(*client)}, {"request", request ? Value(*request) : Value()},
        {"actor", Value(bound_actor)}, {"action", Value("adapter_refusal")}, {"wire", Value(wire)}};
    const auto refuse = [&](const char* reason) {
        return Value(outward(owned_->world->refuse({bound_actor, *client}, normalized, reason), owned_->world->snapshot()));
    };
    const auto* action = field<std::string>(wire, "action");
    if (!action) return refuse("invalid_action");
    const auto target = [&](const char* input, const char* output, const char* generation) {
        const auto* id = field<std::string>(wire, input);
        if (!id) return false;
        const auto* selected = find(snapshot.state, *id);
        normalized.emplace(output, Value(*id));
        const auto belt = std::find_if(snapshot.state.topology.belt_spans.begin(), snapshot.state.topology.belt_spans.end(),
            [&](const auto& span) { return span.geometry.id == *id; });
        normalized.emplace(generation, Value(selected ? selected->generation :
            belt != snapshot.state.topology.belt_spans.end() ? belt->generation : 0));
        return true;
    };
    if (*action == "harvest_source") {
        if (!keys(wire, {"target"}) || !field<std::string>(wire, "target")) return refuse("invalid_command");
        normalized.at("action") = Value("harvest_source");
        normalized.emplace("target", wire.at("target"));
    } else if (*action == "craft_component") {
        if (!keys(wire, {"entity", "component"}) || !field<std::string>(wire, "entity") ||
            !field<std::string>(wire, "component")) return refuse("invalid_command");
        normalized.at("action") = Value("craft_component");
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("generation", Value(snapshot.state.fabrication_hub &&
            snapshot.state.fabrication_hub->id == *field<std::string>(wire, "entity") ?
            snapshot.state.fabrication_hub->generation : Integer{0}));
        normalized.emplace("component", wire.at("component"));
    } else if (*action == "take_hand_crank" || *action == "return_hand_crank") {
        if (!keys(wire, {"entity"}) || !field<std::string>(wire, "entity"))
            return refuse("invalid_command");
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("generation", Value(snapshot.state.hand_crank &&
            snapshot.state.hand_crank->id == *field<std::string>(wire, "entity") ?
            snapshot.state.hand_crank->generation : Integer{0}));
    } else if (*action == "turn_hand_crank") {
        if (!keys(wire, {"entity"}) || !field<std::string>(wire, "entity"))
            return refuse("invalid_command");
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        const auto found = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        normalized.emplace("generation", Value(found == snapshot.state.placed_components.end() ?
            Integer{0} : found->second.generation));
    } else if (*action == "place_component") {
        if (!keys(wire, {"component", "center"}) || !field<std::string>(wire, "component") ||
            !field<Array>(wire, "center")) return refuse("invalid_command");
        const auto& point = *field<Array>(wire, "center");
        if (point.size() != 3) return refuse("invalid_center");
        mechanics::Point center{};
        for (std::size_t axis = 0; axis < 3; ++axis) {
            const auto* coordinate = std::get_if<Integer>(&point[axis].storage());
            if (!coordinate || *coordinate < -mechanics::maximum_coordinate ||
                *coordinate > mechanics::maximum_coordinate) return refuse("invalid_center");
            center[axis] = *coordinate;
        }
        // A small reserved volume prevents placement inside terrain, an actor,
        // a belt or an existing complete machine. Component-to-component fit
        // remains governed by World's shared quarter-grid center occupancy.
        const authority::Point at{center[0] * height_step,
            center[1] * height_step + anchor_height, center[2] * height_step};
        const Bounds volume{at, {0.14, 0.14, 0.14}};
        const auto kind = materials::component_from_name(*field<std::string>(wire, "component"));
        if (const auto* refusal = component_site_refusal(kind, center)) return refuse(refusal);
        if (placement_blocked(at, volume.half)) return refuse("actor_occupied");
        if (intersects_belt(snapshot.state, volume) ||
            std::any_of(snapshot.state.topology.parts.begin(), snapshot.state.topology.parts.end(),
                [&](const auto& item) { return overlap(volume, part_bounds(profile_, item)); }))
            return refuse("occupied");
        if (kind) {
            auto proposed = snapshot.state;
            proposed.placed_components.emplace("proposed-component", world::PlacedComponent{*kind, center, 0});
            if (const auto* refusal = support_change_refusal(snapshot.state, proposed)) return refuse(refusal);
        }
        normalized.at("action") = Value("place_component");
        normalized.emplace("component", wire.at("component"));
        normalized.emplace("center", wire.at("center"));
    } else if (*action == "reclaim_component") {
        if (!keys(wire, {"entity"}) || !field<std::string>(wire, "entity")) return refuse("invalid_command");
        normalized.at("action") = Value("reclaim_component");
        normalized.emplace("target", wire.at("entity"));
        const auto found = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        normalized.emplace("generation", Value(found == snapshot.state.placed_components.end() ?
            Integer{0} : found->second.generation));
    } else if (*action == "pickup_material") {
        if (!keys(wire, {"center", "expected"}) || !field<Object>(wire, "expected")) return refuse("invalid_command");
        const auto* center = field<Array>(wire, "center");
        if (!center || center->size() != 3) return refuse("invalid_center");
        for (const auto& value : *center) {
            const auto* coordinate = std::get_if<Integer>(&value.storage());
            if (!coordinate || *coordinate < -materials::maximum_drop_coordinate || *coordinate > materials::maximum_drop_coordinate)
                return refuse("invalid_center");
        }
        normalized.at("action") = Value("pickup_material");
        normalized.emplace("center", wire.at("center"));
        normalized.emplace("expected", wire.at("expected"));
    } else if (*action == "place_foundation" || *action == "place_foundations") {
        const bool area = *action == "place_foundations";
        if (!(area ? keys(wire, {"cell", "end_cell", "level"}) : keys(wire, {"cell", "level"})))
            return refuse("invalid_command");
        const auto* cell = field<Array>(wire, "cell");
        const auto* level = field<Integer>(wire, "level");
        if (!cell || cell->size() != 2 || !level || *level < -1000000 || *level > 1000000) return refuse("invalid_cell");
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        if (!x || !z || *x < -250000 || *x > 250000 || *z < -250000 || *z > 250000) return refuse("invalid_cell");
        const auto* end = area ? field<Array>(wire, "end_cell") : cell;
        if (!end || end->size() != 2) return refuse("invalid_cell");
        const auto* end_x = std::get_if<Integer>(&end->at(0).storage());
        const auto* end_z = std::get_if<Integer>(&end->at(1).storage());
        if (!end_x || !end_z || *end_x < -250000 || *end_x > 250000 || *end_z < -250000 || *end_z > 250000)
            return refuse("invalid_cell");
        const auto width = std::abs(*end_x - *x) + 1, depth = std::abs(*end_z - *z) + 1;
        if (width > 256 || depth > 256 || width * depth > 256) return refuse("invalid_area");
        const auto top = *level * pitch / 4;
        // Foundations intentionally intersect natural ground/scenery and need
        // no gravity support. Constructed parts and actual actors still block.
        for (auto px = std::min(*x, *end_x); px <= std::max(*x, *end_x); ++px)
            for (auto pz = std::min(*z, *end_z); pz <= std::max(*z, *end_z); ++pz) {
                if (placement_blocked({px * pitch, top - foundation_depth / 2, pz * pitch},
                    {pitch / 2, foundation_depth / 2, pitch / 2}))
                    return refuse("actor_occupied");
                if (intersects_belt(snapshot.state, {{px * pitch, top - foundation_depth / 2, pz * pitch},
                    {pitch / 2, foundation_depth / 2, pitch / 2}})) return refuse("occupied");
            }
        for (const auto& part : snapshot.state.topology.parts) {
            const auto& center = part.geometry.center;
            if (part.role == Role::shaft || part.role == Role::gear) {
                for (auto px = std::min(*x, *end_x); px <= std::max(*x, *end_x); ++px)
                    for (auto pz = std::min(*z, *end_z); pz <= std::max(*z, *end_z); ++pz)
                        if (transmission_intersects(foundation_bounds({{4 * px, *level, 4 * pz}, 1}),
                                                    center, part.geometry.axis, part.role == Role::gear))
                            return refuse("occupied");
                continue;
            }
            if (part.role == Role::waterwheel) {
                const auto supports = wheel_support_bounds(center, part.geometry.axis,
                    [this](double sx, double sz, double hx, double hz) {
                        return terrain_range(sx, sz, hx, hz);
                    });
                if (!supports) return refuse("support_required");
                for (auto px = std::min(*x, *end_x); px <= std::max(*x, *end_x); ++px)
                    for (auto pz = std::min(*z, *end_z); pz <= std::max(*z, *end_z); ++pz)
                        if (const auto proposed = foundation_bounds({{4 * px, *level, 4 * pz}, 1});
                            overlap(part_bounds(profile_, part), proposed) || overlaps_supports(*supports, proposed))
                            return refuse("occupied");
                continue;
            }
            for (const auto& external : part.role == Role::collector ?
                    collector_external_bounds(center) : std::vector<Bounds>{})
                for (auto px = std::min(*x, *end_x); px <= std::max(*x, *end_x); ++px)
                    for (auto pz = std::min(*z, *end_z); pz <= std::max(*z, *end_z); ++pz)
                        if (overlap(external, foundation_bounds({{4 * px, *level, 4 * pz}, 1})))
                            return refuse("occupied");
            if (center[0] * pitch / 4 > std::min(*x, *end_x) * pitch - pitch &&
                center[0] * pitch / 4 < std::max(*x, *end_x) * pitch + pitch &&
                center[2] * pitch / 4 > std::min(*z, *end_z) * pitch - pitch &&
                center[2] * pitch / 4 < std::max(*z, *end_z) * pitch + pitch &&
                center[1] * pitch / 4 < top && center[1] * pitch / 4 + machine_height > top - foundation_depth)
                return refuse("occupied");
        }
        for (const auto& [id, component] : snapshot.state.placed_components) {
            (void)id;
            const Bounds occupied{{component.center[0] * height_step,
                component.center[1] * height_step + anchor_height,
                component.center[2] * height_step}, {0.14, 0.14, 0.14}};
            for (auto px = std::min(*x, *end_x); px <= std::max(*x, *end_x); ++px)
                for (auto pz = std::min(*z, *end_z); pz <= std::max(*z, *end_z); ++pz)
                    if (overlap(occupied, foundation_bounds({{4 * px, *level, 4 * pz}, 1})))
                        return refuse("occupied");
        }
        normalized.at("action") = Value(*action);
        normalized.emplace("center", Value(Array{Value(4 * *x), Value(*level), Value(4 * *z)}));
        if (area) normalized.emplace("end", Value(Array{Value(4 * *end_x), Value(*level), Value(4 * *end_z)}));
    } else if (*action == "place") {
        if (!place_keys(wire))
            return refuse("invalid_command");
        const auto* axis = field<std::string>(wire, "axis");
        if (wire.contains("axis") && (!axis || !axis_value(*axis))) return refuse("invalid_axis");
        const auto* kind_name = field<std::string>(wire, "kind");
        const auto* rotation = field<Integer>(wire, "rotation");
        if (wire.contains("rotation") && (!rotation || *rotation < 0 || *rotation > 3)) return refuse("invalid_rotation");
        const auto* cell = field<Array>(wire, "cell");
        if (!kind_name || !cell || cell->size() != 2) return refuse("invalid_cell");
        const auto* x = std::get_if<Integer>(&cell->at(0).storage());
        const auto* z = std::get_if<Integer>(&cell->at(1).storage());
        const auto* level = field<Integer>(wire, "level");
        const auto* tiles = field<Integer>(wire, "tiles");
        if (!x || !z || *x < -250000 || *x > 250000 || *z < -250000 || *z > 250000 ||
            (wire.contains("level") && (!level || *level < -1000000 || *level > 1000000))) return refuse("invalid_cell");
        if (*kind_name != "collector" && *kind_name != "processor" &&
            *kind_name != "wheel" && *kind_name != "gear") return refuse("unknown_kind");
        if (*kind_name == "gear" && level && *level % 4 != 0) return refuse("invalid_cell");
        if (*kind_name != "gear" && level && *level % 4 != 0) return refuse("unaligned_elevation");
        if (wire.contains("tiles") && (!tiles || *tiles < 3 || *tiles > mechanics::maximum_dimension)) return refuse("invalid_wheel_size");
        const mechanics::Point center{4 * *x, level ? *level : 0, 4 * *z};
        if (*kind_name == "collector")
            if (const auto* refusal = collector_site_refusal(center)) return refuse(refusal);
        const auto selected_axis = axis ? *axis_value(*axis) : mechanics::Axis::x;
        const stationary::PlacedPart proposed{{"proposed", mechanics::Kind::hub, center, selected_axis, 0, 0},
            1, *kind_name == "wheel" ? Role::waterwheel : Role::collector, tiles ? *tiles : 3};
        std::optional<std::array<Bounds, 2>> proposed_supports;
        if (*kind_name == "wheel") {
            if (const auto* refusal = wheel_site_refusal(center, selected_axis, tiles ? *tiles : 3)) return refuse(refusal);
            proposed_supports = wheel_support_bounds(center, selected_axis,
                [this](double sx, double sz, double hx, double hz) {
                    return terrain_range(sx, sz, hx, hz);
                });
            if (!proposed_supports) return refuse("support_required");
        }
        for (const auto& [id, foundation] : snapshot.state.foundations) {
            (void)id;
            if (*kind_name == "wheel" &&
                (overlap(part_bounds(profile_, proposed), foundation_bounds(foundation)) ||
                 overlaps_supports(*proposed_supports, foundation_bounds(foundation)))) return refuse("occupied");
            if (foundation.center[0] == center[0] && foundation.center[2] == center[2] &&
                foundation.center[1] > center[1] && foundation.center[1] - 2 < center[1] + 4)
                return refuse("occupied");
        }
        if (*kind_name != "gear" && !(*kind_name == "wheel")) {
            if (const auto* refusal = machine_site_refusal(snapshot.state, center, *kind_name == "collector")) return refuse(refusal);
        }
        const auto proposed_external = *kind_name == "collector" ?
            collector_external_bounds(center) : std::vector<Bounds>{};
        for (const auto& external : proposed_external) {
            if (intersects_belt(snapshot.state, external)) return refuse("occupied");
            for (const auto& [id, foundation] : snapshot.state.foundations) {
                (void)id;
                if (overlap(external, foundation_bounds(foundation))) return refuse("occupied");
            }
        }
        if (*kind_name != "gear" && intersects_belt(snapshot.state, part_bounds(profile_, proposed))) return refuse("occupied");
        if (proposed_supports) for (const auto& support : *proposed_supports)
            if (intersects_belt(snapshot.state, support)) return refuse("occupied");
        for (const auto& part : snapshot.state.topology.parts) {
            if (part.geometry.center == center) return refuse("occupied");
            for (const auto& external : proposed_external)
                if (collector_intake_intersects(external, profile_, part)) return refuse("occupied");
            for (const auto& external : part.role == Role::collector ?
                    collector_external_bounds(part.geometry.center) : std::vector<Bounds>{}) {
                if (*kind_name == "gear" ? transmission_intersects(external, center, selected_axis, true) :
                    overlap(external, part_bounds(profile_, proposed))) return refuse("occupied");
                if (proposed_supports && overlaps_supports(*proposed_supports, external)) return refuse("occupied");
                for (const auto& proposed_box : proposed_external)
                    if (overlap(external, proposed_box)) return refuse("occupied");
            }
            if (*kind_name != "gear" && part.role != Role::gear && part.role != Role::shaft &&
                (*kind_name == "wheel" || part.role == Role::waterwheel) &&
                overlap(part_bounds(profile_, proposed), part_bounds(profile_, part))) return refuse("occupied");
            if (proposed_supports && part.role != Role::gear && part.role != Role::shaft &&
                overlaps_supports(*proposed_supports, part_bounds(profile_, part))) return refuse("occupied");
            if (proposed_supports && (part.role == Role::gear || part.role == Role::shaft))
                for (const auto& support : *proposed_supports)
                    if (transmission_intersects(support, part.geometry.center, part.geometry.axis,
                                                part.role == Role::gear)) return refuse("occupied");
            if (part.role == Role::waterwheel) {
                const auto existing_supports = wheel_support_bounds(part.geometry.center, part.geometry.axis,
                    [this](double sx, double sz, double hx, double hz) {
                        return terrain_range(sx, sz, hx, hz);
                    });
                if (!existing_supports) return refuse("support_required");
                if (*kind_name == "gear") {
                    for (const auto& support : *existing_supports)
                        if (transmission_intersects(support, center, selected_axis, true)) return refuse("occupied");
                } else if (overlaps_supports(*existing_supports, part_bounds(profile_, proposed)))
                    return refuse("occupied");
            }
        }
        const auto is_gear = *kind_name == "gear";
        if (is_gear) {
            if (transmission_intersects_foundations(snapshot.state, center, selected_axis, true)) return refuse("occupied");
            if (const auto* refusal = transmission_site_refusal(snapshot.state, center, selected_axis, true)) return refuse(refusal);
        }
        const bool water_wheel = *kind_name == "wheel";
        const auto radius = profile_.wheel_radius * (tiles ? *tiles : 3) * height_step / 100.0;
        const authority::Point at{*x * pitch, center[1] * pitch / 4 +
            (is_gear || water_wheel ? anchor_height : machine_center_height), *z * pitch};
        const auto half = is_gear ? gear_half_extents(selected_axis, 2) : water_wheel ?
            authority::Point{selected_axis == mechanics::Axis::x ? 0.3 : radius, radius,
                selected_axis == mechanics::Axis::z ? 0.3 : radius} :
            authority::Point{machine_width / 2, machine_height / 2, machine_width / 2};
        if (intersects_belt(snapshot.state, {at, half})) return refuse("occupied");
        if (placement_blocked(at, half)) return refuse("actor_occupied");
        for (const auto& external : proposed_external)
            if (placement_blocked(external.center, external.half)) return refuse("actor_occupied");
        if (proposed_supports) for (const auto& support : *proposed_supports)
            if (placement_blocked(support.center, support.half)) return refuse("actor_occupied");
        if (is_gear && intersects_belt(snapshot.state, {at, gear_axle_half_extents(selected_axis)})) return refuse("occupied");
        if (is_gear && placement_blocked(at, gear_axle_half_extents(selected_axis))) return refuse("actor_occupied");
        normalized.at("action") = Value(*kind_name == "collector" || *kind_name == "processor" ?
                                        "place_connected" : "place");
        normalized.emplace("role", Value(*kind_name == "wheel" ? "waterwheel" : *kind_name));
        normalized.emplace("center", Value(Array{Value(center[0]), Value(center[1]), Value(center[2])}));
        normalized.emplace("axis", Value(axis ? *axis : "x"));
        normalized.emplace("teeth", Value(Integer{*kind_name == "gear" ? 2 : 0}));
        normalized.emplace("half_span", Value(Integer{0}));
        if (rotation) normalized.emplace("rotation", Value(*rotation));
        if (tiles) normalized.emplace("wheel_tiles", Value(*tiles));
    } else if (*action == "place_shaft") {
        if (!keys(wire, {"center", "axis", "half_span"})) return refuse("invalid_command");
        const auto* input = field<Array>(wire, "center");
        const auto center = input ? gear_center(*input) : std::nullopt;
        const auto* axis = field<std::string>(wire, "axis");
        const auto selected_axis = axis ? axis_value(*axis) : std::nullopt;
        const auto* span = field<Integer>(wire, "half_span");
        if (!center) return refuse("invalid_center");
        if (!selected_axis) return refuse("invalid_axis");
        if (!span || *span != 2) return refuse("invalid_shaft");
        if (std::any_of(center->begin(), center->end(), [](Integer coordinate) { return coordinate % 4 != 0; }))
            return refuse("invalid_cell");
        const auto verified_axis = selected_axis.value_or(mechanics::Axis::x);
        if (transmission_intersects_foundations(snapshot.state, *center, verified_axis, false)) return refuse("occupied");
        if (const auto* refusal = transmission_site_refusal(snapshot.state, *center, verified_axis, false)) return refuse(refusal);
        for (const auto& part : snapshot.state.topology.parts)
            if (part.role == Role::collector)
                for (const auto& external : collector_external_bounds(part.geometry.center))
                    if (transmission_intersects(external, *center, verified_axis, false)) return refuse("occupied");
        const authority::Point at{(*center)[0] * pitch / 4, anchor_height + (*center)[1] * pitch / 4, (*center)[2] * pitch / 4};
        authority::Point half{0.1, 0.1, 0.1};
        half[static_cast<std::size_t>(verified_axis)] = *span * pitch / 4;
        if (placement_blocked(at, half)) return refuse("actor_occupied");
        normalized.at("action") = Value("place");
        normalized.emplace("role", Value("shaft"));
        normalized.emplace("center", wire.at("center"));
        normalized.emplace("axis", wire.at("axis"));
        normalized.emplace("teeth", Value(Integer{0}));
        normalized.emplace("half_span", wire.at("half_span"));
    } else if (*action == "place_gear") {
        if (!keys(wire, {"center", "axis", "teeth"})) return refuse("invalid_command");
        const auto* input = field<Array>(wire, "center");
        const auto center = input ? gear_center(*input) : std::nullopt;
        const auto* axis = field<std::string>(wire, "axis");
        const auto selected_axis = axis ? axis_value(*axis) : std::nullopt;
        const auto* teeth = field<Integer>(wire, "teeth");
        if (!center) return refuse("invalid_center");
        if (!selected_axis) return refuse("invalid_axis");
        if (!teeth || *teeth < 1 || *teeth > mechanics::maximum_dimension) return refuse("invalid_gear");
        if (std::any_of(center->begin(), center->end(), [](Integer coordinate) { return coordinate % 4 != 0; }))
            return refuse("invalid_cell");
        const auto verified_axis = selected_axis.value_or(mechanics::Axis::x);
        if (transmission_intersects_foundations(snapshot.state, *center, verified_axis, true)) return refuse("occupied");
        if (const auto* refusal = transmission_site_refusal(snapshot.state, *center, verified_axis, true)) return refuse(refusal);
        for (const auto& part : snapshot.state.topology.parts)
            if (part.role == Role::collector)
                for (const auto& external : collector_external_bounds(part.geometry.center))
                    if (transmission_intersects(external, *center, verified_axis, true)) return refuse("occupied");
        const authority::Point at{(*center)[0] * pitch / 4, anchor_height + (*center)[1] * pitch / 4, (*center)[2] * pitch / 4};
        const auto half = gear_half_extents(verified_axis, *teeth);
        if (intersects_belt(snapshot.state, {at, half})) return refuse("occupied");
        if (placement_blocked(at, half)) return refuse("actor_occupied");
        if (intersects_belt(snapshot.state, {at, gear_axle_half_extents(verified_axis)})) return refuse("occupied");
        if (placement_blocked(at, gear_axle_half_extents(verified_axis))) return refuse("actor_occupied");
        normalized.at("action") = Value("place");
        normalized.emplace("role", Value("gear"));
        normalized.emplace("center", wire.at("center"));
        normalized.emplace("axis", wire.at("axis"));
        normalized.emplace("teeth", wire.at("teeth"));
        normalized.emplace("half_span", Value(Integer{0}));
    } else if (*action == "place_relay") {
        const auto* name = field<std::string>(wire, "kind");
        const auto* input = field<Array>(wire, "center");
        const auto* axis_name = field<std::string>(wire, "axis");
        const auto* relay_name = field<std::string>(wire, "relay_axis");
        if (!name || (*name != "gearbox" && *name != "vertical_gearbox" && *name != "chain_drive") ||
            !keys(wire, relay_name ? std::initializer_list<const char*>{"kind", "center", "axis", "relay_axis"} :
                std::initializer_list<const char*>{"kind", "center", "axis"})) return refuse("invalid_command");
        const auto center = input ? gear_center(*input) : std::nullopt;
        const auto relay_axis = relay_name ? axis_value(*relay_name) : std::nullopt;
        if (!center) return refuse("invalid_center");
        if (!axis_name || !axis_value(*axis_name)) return refuse("invalid_axis");
        const auto drive_axis = axis_value(*axis_name).value_or(mechanics::Axis::x);
        if ((*name == "gearbox" && drive_axis != mechanics::Axis::y) ||
            (*name == "vertical_gearbox" && drive_axis == mechanics::Axis::y) ||
            (relay_name != nullptr) != (*name == "chain_drive") ||
            (relay_name && (!relay_axis || *relay_axis == drive_axis))) return refuse("invalid_axis");
        if (std::any_of(center->begin(), center->end(), [](Integer value) { return value % 4 != 0; }))
            return refuse("invalid_cell");
        const authority::Point at{(*center)[0] * height_step,
            anchor_height + (*center)[1] * height_step, (*center)[2] * height_step};
        const authority::Point half{pitch / 2, pitch / 2, pitch / 2};
        const Bounds shell{at, half};
        if (transmission_intersects_foundations(snapshot.state, *center, drive_axis, true)) return refuse("occupied");
        if (const auto* refusal = transmission_site_refusal(snapshot.state, *center, drive_axis, true)) return refuse(refusal);
        const auto shell_terrain = terrain_range(at[0], at[2], half[0], half[2]);
        if (!shell_terrain) return refuse("terrain_unavailable");
        if (shell_terrain->second > at[1] - half[1] + 1e-9) return refuse("site_occupied");
        if (site_blocked({at[0] - half[0], at[1] - half[1], at[2] - half[2]},
                         {at[0] + half[0], at[1] + half[1], at[2] + half[2]})) return refuse("site_occupied");
        for (const auto& [id, foundation] : snapshot.state.foundations) {
            (void)id;
            if (overlap(shell, foundation_bounds(foundation))) return refuse("occupied");
        }
        for (const auto& part : snapshot.state.topology.parts) {
            if (part.geometry.center == *center) return refuse("occupied");
            if (part.role != Role::shaft && part.role != Role::gear &&
                part.role != Role::gearbox && part.role != Role::vertical_gearbox &&
                part.role != Role::chain_drive && overlap(shell, part_bounds(profile_, part)))
                return refuse("occupied");
            if (part.role == Role::collector) if (const auto intake = collector_intake_bounds(part.geometry.center))
                if (overlap(shell, *intake)) return refuse("occupied");
        }
        if (intersects_belt(snapshot.state, shell)) return refuse("occupied");
        if (placement_blocked(at, half)) return refuse("actor_occupied");
        normalized.at("action") = Value("place");
        normalized.emplace("role", Value(*name));
        normalized.emplace("center", wire.at("center"));
        normalized.emplace("axis", wire.at("axis"));
        normalized.emplace("teeth", Value(Integer{0}));
        normalized.emplace("half_span", Value(Integer{0}));
        if (relay_name) normalized.emplace("relay_axis", wire.at("relay_axis"));
    } else if (*action == "select_belt_shaft") {
        if (!keys(wire, {"entity"}) || !target("entity", "target", "generation")) return refuse("invalid_command");
        normalized.at("action") = Value("select_belt_shaft");
    } else if (*action == "place_belt_span" || *action == "place_selected_belt_span") {
        if (!(*action == "place_belt_span" ? keys(wire, {"from", "to"}) : keys(wire, {"from", "to", "selection"})) ||
            (*action == "place_selected_belt_span" && !field<std::string>(wire, "selection")) ||
            !target("from", "target", "generation") ||
            !target("to", "to", "to_generation")) return refuse("invalid_command");
        if (*action == "place_selected_belt_span") normalized.emplace("selection", wire.at("selection"));
        const auto* first = find(snapshot.state, *field<std::string>(wire, "from"));
        const auto* last = find(snapshot.state, *field<std::string>(wire, "to"));
        if (!first || !last) return refuse("unknown_target");
        if (first->role != Role::shaft || last->role != Role::shaft) return refuse("invalid_belt_geometry");
        const auto sections = belt_bounds(first->geometry, last->geometry);
        if (sections.empty()) return refuse("invalid_belt_geometry");
        for (const auto& [foundation_id, foundation] : snapshot.state.foundations) {
            (void)foundation_id;
            if (belt_intersects(first->geometry, last->geometry, foundation_bounds(foundation))) return refuse("occupied");
        }
        for (const auto& placed : snapshot.state.topology.parts) {
            if (placed.role == Role::shaft) continue;
            if (placed.role == Role::collector)
                for (const auto& external : collector_external_bounds(placed.geometry.center))
                    if (belt_intersects(first->geometry, last->geometry, external)) return refuse("occupied");
            const auto& point = placed.geometry.center;
            const Bounds bounds = placed.role == Role::gear ? Bounds{
                {point[0] * height_step, anchor_height + point[1] * height_step, point[2] * height_step},
                gear_half_extents(placed.geometry.axis, placed.geometry.teeth)} : part_bounds(profile_, placed);
            if (belt_intersects(first->geometry, last->geometry, bounds)) return refuse("occupied");
            if (placed.role == Role::gear && belt_intersects(first->geometry, last->geometry,
                {bounds.center, gear_axle_half_extents(placed.geometry.axis)})) return refuse("occupied");
            if (placed.role == Role::waterwheel) {
                const auto supports = wheel_support_bounds(placed.geometry.center, placed.geometry.axis,
                    [this](double sx, double sz, double hx, double hz) {
                        return terrain_range(sx, sz, hx, hz);
                    });
                if (!supports) return refuse("support_required");
                for (const auto& support : *supports)
                    if (belt_intersects(first->geometry, last->geometry, support)) return refuse("occupied");
            }
        }
        for (const auto& belt_bounds : sections) {
            const auto& at = belt_bounds.center;
            const auto& half = belt_bounds.half;
            if (placement_blocked(at, half)) return refuse("actor_occupied");
            if (site_blocked({at[0] - half[0], at[1] - half[1], at[2] - half[2]},
                             {at[0] + half[0], at[1] + half[1], at[2] + half[2]})) return refuse("site_occupied");
            const auto terrain = terrain_range(at[0], at[2], half[0], half[2]);
            if (!terrain) return refuse("terrain_unavailable");
            if (terrain->second > at[1] - half[1]) return refuse("site_occupied");
        }
        normalized.at("action") = Value(*action);
    } else if (*action == "remove_belt_span") {
        if (!keys(wire, {"entity"}) || !target("entity", "target", "generation")) return refuse("invalid_command");
        normalized.at("action") = Value("remove_belt_span");
    } else if (*action == "connect_drive" || *action == "disconnect_drive") {
        if (!keys(wire, {"from", "to"}) || !target("from", "target", "generation") ||
            !target("to", "to", "to_generation")) return refuse("invalid_command");
        normalized.at("action") = Value(*action == "connect_drive" ? "shaft_between" : "remove_shaft_between");
    } else if (*action == "recover_belt_slot") {
        if (!keys(wire, {"entity", "slot", "expected"}) || !field<Integer>(wire, "slot") ||
            !field<Object>(wire, "expected") || !target("entity", "target", "generation")) return refuse("invalid_command");
        normalized.at("action") = Value("recover_belt_slot");
        normalized.emplace("slot", wire.at("slot"));
        normalized.emplace("expected", wire.at("expected"));
    } else if (*action == "load_belt_slot") {
        if (!keys(wire, {"entity", "slot", "item", "work_id"}) || !field<Integer>(wire, "slot") ||
            !field<std::string>(wire, "item") || !field<Integer>(wire, "work_id") ||
            !target("entity", "target", "generation")) return refuse("invalid_command");
        normalized.at("action") = Value("load_belt_slot");
        normalized.emplace("slot", wire.at("slot"));
        normalized.emplace("item", wire.at("item"));
        normalized.emplace("work_id", wire.at("work_id"));
    } else if (*action == "remove" || *action == "recover" || *action == "retrieve" ||
               *action == "insert_raw" || *action == "insert_work") {
        const bool amount = *action == "retrieve" || *action == "insert_raw";
        const bool work = *action == "insert_work";
        if (!(amount ? keys(wire, {"entity", "amount"}) : work ? keys(wire, {"entity", "work_id"}) : keys(wire, {"entity"})) ||
            !target("entity", "target", "generation")) return refuse("invalid_command");
        const auto* id = field<std::string>(wire, "entity");
        const auto foundation = id ? snapshot.state.foundations.find(*id) : snapshot.state.foundations.end();
        if (*action == "remove" && foundation != snapshot.state.foundations.end()) {
            normalized.at("action") = Value("remove_foundation");
            normalized.at("generation") = Value(foundation->second.generation);
        } else normalized.at("action") = Value(*action == "retrieve" ? "collect" : *action);
        if (amount) normalized.emplace("amount", wire.at("amount"));
        if (work) normalized.emplace("work_id", wire.at("work_id"));
    } else return refuse("unsupported_action");
    const auto& edit = *field<std::string>(normalized, "action");
    if (edit == "place" || edit == "place_connected" || edit == "remove" ||
        edit == "place_foundation" || edit == "place_foundations" || edit == "remove_foundation" ||
        edit == "place_belt_span" || edit == "place_selected_belt_span" || edit == "remove_belt_span") {
        // Preview only the geometry fields. World still owns the transaction,
        // inventory, material and history; no second World or clock is created.
        world::State geometry;
        geometry.topology = snapshot.state.topology;
        geometry.foundations = snapshot.state.foundations;
        std::string preview_id = "support-preview";
        while (find(geometry, preview_id) || geometry.foundations.contains(preview_id) ||
               std::any_of(geometry.topology.belt_spans.begin(), geometry.topology.belt_spans.end(),
                   [&](const auto& span) { return span.geometry.id == preview_id; })) preview_id += '-';
        if (edit == "place" || edit == "place_connected") {
            stationary::PlacedPart part{};
            const auto& name = *field<std::string>(normalized, "role");
            std::optional<Role> role;
            for (const auto value : {Role::collector, Role::belt, Role::processor, Role::waterwheel,
                                    Role::shaft, Role::gear, Role::gearbox, Role::vertical_gearbox, Role::chain_drive})
                if (name == (value == Role::waterwheel ? "waterwheel" : kind(value))) role = value;
            if (!role) return refuse("invalid_command");
            part.role = *role;
            part.geometry.id = preview_id;
            const auto& center = *field<Array>(normalized, "center");
            for (std::size_t dimension = 0; dimension < 3; ++dimension)
                part.geometry.center[dimension] = std::get<Integer>(center[dimension].storage());
            part.geometry.axis = axis_value(*field<std::string>(normalized, "axis")).value();
            if (const auto* teeth = field<Integer>(normalized, "teeth")) part.geometry.teeth = *teeth;
            if (const auto* span = field<Integer>(normalized, "half_span")) part.geometry.half_span = *span;
            part.geometry.kind = part.role == Role::shaft ? mechanics::Kind::shaft :
                part.role == Role::gear ? mechanics::Kind::gear : mechanics::Kind::hub;
            part.wheel_tiles = part.role == Role::waterwheel ? 3 : 1;
            if (const auto* tiles = field<Integer>(normalized, "wheel_tiles")) part.wheel_tiles = *tiles;
            if (std::any_of(geometry.topology.parts.begin(), geometry.topology.parts.end(),
                    [&](const auto& old) { return old.geometry.center == part.geometry.center; })) return refuse("occupied");
            geometry.topology.parts.push_back(std::move(part));
        } else if (edit == "remove") {
            const auto& target_id = *field<std::string>(normalized, "target");
            std::erase_if(geometry.topology.parts, [&](const auto& part) { return part.geometry.id == target_id; });
        } else if (edit == "place_foundation" || edit == "place_foundations") {
            const auto& start = *field<Array>(normalized, "center");
            const auto* end = field<Array>(normalized, "end");
            const auto x = std::get<Integer>(start[0].storage()), y = std::get<Integer>(start[1].storage());
            const auto z = std::get<Integer>(start[2].storage());
            const auto ex = end ? std::get<Integer>((*end)[0].storage()) : x;
            const auto ez = end ? std::get<Integer>((*end)[2].storage()) : z;
            for (auto px = std::min(x, ex); px <= std::max(x, ex); px += 4)
                for (auto pz = std::min(z, ez); pz <= std::max(z, ez); pz += 4)
                    geometry.foundations.emplace(preview_id + ':' + std::to_string(px) + ':' + std::to_string(pz),
                                                 world::Foundation{{px, y, pz}, 0});
        } else if (edit == "remove_foundation") geometry.foundations.erase(*field<std::string>(normalized, "target"));
        else if (edit == "remove_belt_span") {
            const auto& target_id = *field<std::string>(normalized, "target");
            std::erase_if(geometry.topology.belt_spans, [&](const auto& span) { return span.geometry.id == target_id; });
        } else {
            geometry.topology.belt_spans.push_back({{preview_id,
                *field<std::string>(normalized, "target"), *field<std::string>(normalized, "to")}, 0});
        }
        if (const auto* refusal = support_change_refusal(snapshot.state, geometry)) return refuse(refusal);
    }
    const auto delivered = owned_->world->command({bound_actor, *client}, normalized, observe());
    return Value(outward(delivered, owned_->world->snapshot()));
}

Value Host::publish_actor(const std::string& actor, const Array& position, Integer epoch) {
    if (!owned_ || !owned_->actors.contains(actor)) return result(false, "unknown_actor");
    auto& current = owned_->actors.at(actor);
    const auto at = point(position);
    if (!at || epoch < 1) {
        current.ready = false;
        return result(false, "invalid_actor_sample");
    }
    if (epoch <= current.epoch) return result(false, "stale_actor_sample");
    current = {*at, epoch, true};
    owned_->native_started = true;
    return result(true, "actor_published");
}

Value Host::invalidate_actor(const std::string& actor) {
    if (!owned_ || !owned_->actors.contains(actor)) return result(false, "unknown_actor");
    // Retain the last ordinal so invalidation cannot permit a stale sample.
    owned_->actors.at(actor).ready = false;
    return result(true, "actor_invalidated");
}

Value Host::advance() {
    if (!owned_) return result(false, "not_initialized");
    const auto tick = owned_->world->tick();
    if (tick.error != world::TransactionError::none) return result(false, "native_step_failed");
    return projection();
}

Value Host::projection() const {
    if (!owned_) return result(false, "not_initialized");
    const auto snapshot = owned_->world->snapshot();
    const auto& state = snapshot.state;
    const auto support_layout = transmission_supports(state);
    Object entities, transmissions, belt_spans, inventories, cargo, kits, specifications, actors, foundations;
    Array links, drive_links, engagements, dropped_material;
    for (const auto& [point, contents] : state.material.dropped_material) {
        auto drop = std::get<Object>(cargo_value(contents).storage());
        drop.emplace("center", Value(Array{Value(point[0]), Value(point[1]), Value(point[2])}));
        dropped_material.emplace_back(std::move(drop));
    }
    for (const auto& part : state.topology.parts) {
        Object projected{{"kind", Value(kind(part.role))}, {"generation", Value(part.generation)},
            {"center", Value(Array{Value(part.geometry.center[0]), Value(part.geometry.center[1]), Value(part.geometry.center[2])})},
            {"axis", Value(static_cast<Integer>(part.geometry.axis))},
            {"relay_axis", Value(static_cast<Integer>(part.geometry.relay_axis))},
            {"teeth", Value(part.geometry.teeth)}, {"half_span", Value(part.geometry.half_span)},
            {"rotation", Value(part.rotation)}};
        if (part.role == Role::waterwheel) {
            projected.emplace("tiles", Value(part.wheel_tiles));
            if (const auto supports = wheel_support_bounds(part.geometry.center, part.geometry.axis,
                    [this](double sx, double sz, double hx, double hz) {
                        return terrain_range(sx, sz, hx, hz);
                    })) {
                Array occupied;
                for (const auto& support : *supports)
                    occupied.emplace_back(Object{{"center", point_value(support.center)},
                                                 {"half", point_value(support.half)}});
                projected.emplace("supports", Value(std::move(occupied)));
            }
        }
        if (fixed_transmission(part.role)) {
            if (const auto support = support_layout.find(part.geometry.id); support != support_layout.end()) {
                Array boxes;
                for (const auto& [center, half] : support->second.boxes)
                    boxes.emplace_back(Object{{"center", point_value(center)}, {"half", point_value(half)}});
                projected.emplace("support", Value(Object{{"foot", point_value(support->second.foot)},
                    {"bearing", point_value(support->second.bearing)}, {"boxes", Value(std::move(boxes))}}));
            }
            transmissions.emplace(part.geometry.id, Value(std::move(projected)));
        }
        else {
            projected.emplace("cell", Value(Array{Value(part.geometry.center[0] / 4), Value(part.geometry.center[2] / 4)}));
            if (part.geometry.center[1] != 0) projected.emplace("level", Value(part.geometry.center[1]));
            entities.emplace(part.geometry.id, Value(std::move(projected)));
        }
    }
    Integer span_order = 0;
    // The validated ledger bounds this raw-equivalent total by initial stock.
    // Finished products are not unprocessed blanks.
    Integer belt_raw_units = 0;
    for (const auto& span : state.topology.belt_spans) {
        const auto& lane = state.material.belt_lanes.at(span.geometry.id);
        Array slots;
        for (const auto& item : lane.slots) {
            slots.push_back(item ? cargo_value(*item) : Value(nullptr));
            if (!item) continue;
            belt_raw_units += item->raw_units;
            for (const auto& lot : item->work_lots) belt_raw_units += lot.recipe.input_units_per_product;
        }
        belt_spans.emplace(span.geometry.id, Value(Object{{"generation", Value(span.generation)},
            {"order", Value(span_order++)}, {"from", Value(span.geometry.first_shaft)}, {"to", Value(span.geometry.last_shaft)},
            {"phase", Value(lane.phase)}, {"slots", Value(std::move(slots))}}));
    }
    for (const auto& link : state.topology.material_links) links.emplace_back(Array{Value(link.from.id), Value(link.to.id)});
    const auto power = world::drive_power(state.topology);
    Object motions;
    for (const auto& [id, motion] : power.mechanical.motion) {
        Object projected{{"state", Value(mechanics::motion_state_name(motion.state))},
            {"numerator", Value(motion.rate.numerator)}, {"denominator", Value(motion.rate.denominator)}};
        const auto load = power.load.find(id);
        if (load != power.load.end()) {
            projected.emplace("capacity", Value(load->second.capacity));
            projected.emplace("impact", Value(load->second.impact));
            projected.emplace("overloaded", Value(load->second.overloaded));
        }
        motions.emplace(id, Value(std::move(projected)));
    }
    for (const auto& edge : power.mechanical.engagements) engagements.emplace_back(Object{
        {"a", Value(edge.a)}, {"b", Value(edge.b)}, {"kind", Value(static_cast<Integer>(edge.kind))}});
    for (const auto& shaft : state.topology.parts) {
        if (shaft.role != Role::shaft) continue;
        Array ends;
        const auto axis = static_cast<std::size_t>(shaft.geometry.axis);
        for (const auto& part : state.topology.parts) {
            if (part.role == Role::shaft || part.role == Role::gear || part.geometry.axis != shaft.geometry.axis) continue;
            bool aligned = true;
            for (std::size_t index = 0; index < 3; ++index)
                if (index != axis && part.geometry.center[index] != shaft.geometry.center[index]) aligned = false;
            if (aligned && std::abs(part.geometry.center[axis] - shaft.geometry.center[axis]) == shaft.geometry.half_span)
                ends.emplace_back(part.geometry.id);
        }
        if (ends.size() == 2) drive_links.emplace_back(std::move(ends));
    }
    Integer player = 0;
    for (const auto& [actor, contents] : state.material.cargo) {
        inventories.emplace(actor, Value(contents.products)); player += contents.products;
        cargo.emplace(actor, cargo_value(contents,
            profile_.material.manual_ore.has_value() || !profile_.material.timber_sites.empty()));
    }
    for (const auto& [actor, kit] : state.kits) {
        auto projected_kit = std::get<Object>(kit_value(kit).storage());
        projected_kit.emplace("foundation", Value(state.foundation_kits.at(actor)));
        kits.emplace(actor, Value(std::move(projected_kit)));
        Array entries;
        for (const auto& [specification, initial] : profile_.finite_parts) {
            (void)initial;
            const auto found = kit.find(specification);
            entries.emplace_back(Object{{"kind", Value(kind(specification.role))},
                {"teeth", Value(specification.teeth)}, {"half_span", Value(specification.half_span)},
                {"count", Value(found == kit.end() ? 0 : found->second)}});
        }
        specifications.emplace(actor, Value(std::move(entries)));
    }
    for (const auto& [actor, sample] : owned_->actors) actors.emplace(actor, Value(Object{
        {"position", point_value(sample.position)}, {"capabilities", Value(Object{{"build_reach", Value(reach)}})},
        {"ready", Value(sample.ready)}, {"native_epoch", Value(sample.epoch)}}));
    const auto& stock = state.material.stock;
    Array mineral_cells;
    for (const auto& cell : mineral_site::opening_cells)
        mineral_cells.emplace_back(Array{Value(cell.x), Value(cell.z)});
    const auto local = world::machine_power(state.topology);
    for (const auto& [id, foundation] : state.foundations)
        foundations.emplace(id, Value(Object{{"cell", Value(Array{Value(foundation.center[0] / 4), Value(foundation.center[2] / 4)})},
            {"level", Value(foundation.center[1])}, {"generation", Value(foundation.generation)}}));
    auto player_parts = std::get<Object>(kit_value(state.kits.at("P")).storage());
    player_parts.emplace("foundation", Value(state.foundation_kits.at("P")));
    Object projection{{"context", Value(snapshot.history.context)}, {"revision", Value(snapshot.revision)},
        {"order", Value(snapshot.history.order)}, {"initial_feed", Value(profile_.initial_units)},
        {"recipe_input", Value(profile_.material.input_units_per_product)}, {"entities", Value(std::move(entities))},
        {"transmission_parts", Value(std::move(transmissions))}, {"links", Value(std::move(links))},
        {"belt_spans", Value(std::move(belt_spans))}, {"line_belt_raw", Value(belt_raw_units)},
        {"drive_links", Value(std::move(drive_links))}, {"engagements", Value(std::move(engagements))},
        {"motion", Value(std::move(motions))}, {"inventories", Value(std::move(inventories))},
        {"cargo", Value(std::move(cargo))}, {"part_kits", Value(std::move(kits))},
        {"dropped_material", Value(std::move(dropped_material))},
        {"part_specifications", Value(std::move(specifications))},
        {"parts", Value(std::move(player_parts))}, {"actors", Value(std::move(actors))},
        {"foundations", Value(std::move(foundations))},
        {"source_deposit", Value(Object{{"id", Value("opening-softmetal")},
            {"cells", Value(std::move(mineral_cells))}, {"initial_units", Value(profile_.initial_units)},
            {"collector_capacity", Value(profile_.material.collector_capacity)},
            {"maximum_depth", Value(mineral_site::extraction_depth_steps * height_step)}})},
        {"stock", Value(Object{{"source", Value(stock.source)}, {"collector", Value(stock.collector)},
            {"belt", Value(stock.belt)}, {"input", Value(stock.input)},
            {"held", Value(state.material.processing ? state.material.processing->recipe.input_units_per_product : 0)},
            {"output", Value(stock.output)}, {"player", Value(player)}})},
        {"remaining", Value(state.material.processing ? state.material.processing->remaining_ticks : 0)},
        {"powered", Value(local.collector || local.belt || local.processor)},
        {"power_enabled", Value(state.topology.drive_enabled)},
        {"options", Value(Object{{"opening", Value(true)}, {"physical", Value(true)}, {"native", Value(true)}, {"foundations", Value(true)}})},
        {"adapter_profile", Value(Object{{"pitch", Value(pitch)}, {"anchor_height", Value(anchor_height)},
            {"height_denominator", Value(height_denominator)}, {"height_step", Value(height_step)},
            {"foundation_depth", Value(foundation_depth)},
            {"wheel_radius", Value(wheel_radius)}, {"wheel_axle_offset", Value(wheel_axle_offset)},
            {"capsule_radius", Value(capsule_radius)}, {"capsule_height", Value(capsule_height)},
            {"collector_intake_size", Value(Array{Value(0.28), Value(0.20), Value(0.24)})},
            {"collector_intake_x", Value(-0.84)}, {"collector_intake_y", Value(0.50)},
            {"collector_second_cell_z", Value(-0.60)},
            {"collector_lift", Value(Object{{"pickup_x", Value(-1.04)},
                {"pickup_y", Value(0.55)},
                {"pickup_size", Value(Array{Value(0.34), Value(0.30), Value(0.40)})},
                {"carrier_x", Value(-1.05)}, {"carrier_bottom", Value(0.67)},
                {"carrier_top_offset", Value(1.95)},
                {"carrier_size_xz", Value(Array{Value(0.34), Value(0.42)})},
                {"guide_offset", Value(Array{Value(0.09), Value(0.17)})},
                {"guide_size", Value(Array{Value(0.055), Value(0.055)})},
                {"flight_offset_x", Value(-0.025)},
                {"flight_raise_y", Value(0.05)},
                {"flight_size", Value(Array{Value(0.25), Value(0.16), Value(0.30)})},
                {"flight_count", Value(Integer{5})}, {"flight_span", Value(0.88)},
                {"head_x", Value(-0.60)}, {"head_y_offset", Value(1.77)},
                {"head_size_xy", Value(Array{Value(0.90), Value(0.36)})},
                {"head_z_size", Value(Array{Value(0.40), Value(0.86)})}})}})}};
    if (state.landing_pod) {
        const auto& pod = *state.landing_pod;
        projection.emplace("landing_pod", Value(Object{{"id", Value(pod.id)},
            {"generation", Value(pod.generation)},
            {"center", Value(Array{Value(pod.center[0] / height_denominator),
                Value(pod.center[1]), Value(pod.center[2] / height_denominator)})},
            {"deployed", Value(true)}, {"hub_ready", Value(state.fabrication_hub.has_value())}}));
        const auto& hub = *state.fabrication_hub;
        projection.emplace("fabrication_hub", Value(Object{{"id", Value(hub.id)},
            {"generation", Value(hub.generation)},
            {"center", Value(Array{Value(hub.center[0] / height_denominator),
                Value(hub.center[1]), Value(hub.center[2] / height_denominator)})},
            {"position", Value(Array{Value(hub.center[0] * profile_.meters_per_grid_unit + profile_.anchor_offset[0]),
                Value(hub.center[1] * profile_.meters_per_grid_unit + profile_.anchor_offset[1]),
                Value(hub.center[2] * profile_.meters_per_grid_unit + profile_.anchor_offset[2])})}}));
        const auto& crank = *state.hand_crank;
        projection.emplace("hand_crank", Value(Object{{"id", Value(crank.id)},
            {"generation", Value(crank.generation)},
            {"holder", Value(crank.holder ? *crank.holder : "pod")},
            {"pod_position", Value(Array{
                Value(pod.center[0] * profile_.meters_per_grid_unit + profile_.anchor_offset[0]),
                Value(pod.center[1] * profile_.meters_per_grid_unit + profile_.anchor_offset[1]),
                Value(pod.center[2] * profile_.meters_per_grid_unit + profile_.anchor_offset[2])})}}));
        Object placed;
        for (const auto& [id, component] : state.placed_components)
            placed.emplace(id, Value(Object{{"component", Value(materials::component_name(component.kind))},
                {"generation", Value(component.generation)},
                {"center", Value(Array{Value(component.center[0]), Value(component.center[1]),
                    Value(component.center[2])})},
                {"position", Value(Array{
                    Value(component.center[0] * profile_.meters_per_grid_unit + profile_.anchor_offset[0]),
                    Value(component.center[1] * profile_.meters_per_grid_unit + profile_.anchor_offset[1]),
                    Value(component.center[2] * profile_.meters_per_grid_unit + profile_.anchor_offset[2])})}}));
        projection.emplace("placed_components", Value(std::move(placed)));
        std::vector<assembly::Part> parts;
        parts.reserve(state.placed_components.size());
        for (const auto& [id, component] : state.placed_components)
            parts.push_back({id, component.kind, component.center, component.generation});
        Array collectors;
        for (const auto& face : profile_.collector_faces) {
            const auto inspection = assembly::inspect_collector(parts, face);
            Object entry{{"center", Value(Array{Value(face.machine_center[0]),
                Value(face.machine_center[1]), Value(face.machine_center[2])})},
                {"toward_ore", Value(Array{Value(face.toward_ore[0]),
                    Value(face.toward_ore[1]), Value(face.toward_ore[2])})},
                {"status", Value(collector_status_name(inspection.status))}};
            if (inspection.collector) {
                const auto& assembled = *inspection.collector;
                entry.emplace("parts", Value(Object{{"frame", Value(assembled.frame)},
                    {"mount", Value(assembled.mount)}, {"edge", Value(assembled.edge)},
                    {"receiver", Value(assembled.receiver)}, {"shaft", Value(assembled.shaft)}}));
                entry.emplace("cutting_height", Value(assembled.cutting_height));
                entry.emplace("shaft_material", Value(materials::component_name(assembled.shaft_material)));
            }
            collectors.emplace_back(std::move(entry));
        }
        projection.emplace("collector_assemblies", Value(std::move(collectors)));
    }
    if (profile_.material.manual_ore) {
        const auto site_position = [this](const materials::DropPoint& center) {
            return Value(Array{
                Value(center[0] * profile_.meters_per_grid_unit + profile_.anchor_offset[0]),
                Value(center[1] * profile_.meters_per_grid_unit + profile_.anchor_offset[1]),
                Value(center[2] * profile_.meters_per_grid_unit + profile_.anchor_offset[2])});
        };
        Object sources;
        for (const auto& [id, site] : profile_.material.timber_sites)
            sources.emplace(id, Value(Object{{"kind", Value("tree")},
                {"position", site_position(site.center)}, {"initial", Value(site.initial)},
                {"remaining", Value(state.material.timber_remaining.at(id))}}));
        const auto& ore = *profile_.material.manual_ore;
        sources.emplace(ore.id, Value(Object{{"kind", Value("ore_deposit")},
            {"position", site_position(ore.center)}, {"initial", Value(profile_.initial_units)},
            {"remaining", Value(state.material.stock.source)}}));
        projection.emplace("hand_sources", Value(std::move(sources)));
    }
    return Value(std::move(projection));
}

Value Host::checkpoint() const {
    if (!owned_) return result(false, "not_initialized");
    const auto encoded = world::encode_checkpoint(profile_, owned_->world->snapshot());
    if (!std::holds_alternative<Value>(encoded)) return result(false, "native_checkpoint_refused");
    Object actors;
    for (const auto& [actor, sample] : owned_->actors) actors.emplace(actor, point_value(sample.position));
    return Value(Object{{"schema", Value(Integer{3})}, {"format", Value("factory-native-physical")},
        {"world", std::get<Value>(encoded)}, {"actors", Value(std::move(actors))}});
}

Host::Decoded Host::decode(const Value& input) const {
    if (!owned_) return {nullptr, "not_initialized"};
    const auto* root = std::get_if<Object>(&input.storage());
    if (!root || root->size() != 4 || !field<Integer>(*root, "schema") || *field<Integer>(*root, "schema") != 3 ||
        !field<std::string>(*root, "format") || *field<std::string>(*root, "format") != "factory-native-physical" ||
        !root->contains("world") || !field<Object>(*root, "actors")) return {nullptr, "invalid_checkpoint"};
    const auto* native = std::get_if<Object>(&root->at("world").storage());
    const auto* history = native ? field<Object>(*native, "history") : nullptr;
    const auto* context = history ? field<std::string>(*history, "context") : nullptr;
    if (!context) return {nullptr, "invalid_context"};
    auto decoded = world::decode_checkpoint(profile_, *context, root->at("world"));
    if (!std::holds_alternative<world::Snapshot>(decoded)) return {nullptr, "native_checkpoint_refused"};
    auto snapshot = std::get<world::Snapshot>(decoded);
    if (!snapshot.state.topology.drive_enabled) return {nullptr, "native_checkpoint_refused"};
    for (const auto& [id, component] : snapshot.state.placed_components) {
        (void)id;
        if (const auto* refusal = component_site_refusal(component.kind, component.center))
            return {nullptr, refusal};
    }
    const auto restored_supports = transmission_supports(snapshot.state);
    for (const auto& record : snapshot.history.records) {
        if (!field<Object>(record.intent, "wire")) return {nullptr, "missing_wire_history"};
        if (!historical_wire(record)) return {nullptr, "inconsistent_wire_history"};
        const auto* actor = field<std::string>(record.intent, "actor");
        const auto* client = field<std::string>(record.intent, "client");
        if (!actor || !client || *actor != *client) return {nullptr, "invalid_actor_binding"};
    }
    for (const auto& part : snapshot.state.topology.parts) {
        const auto& center = part.geometry.center;
        const bool relay = part.role == Role::gearbox || part.role == Role::vertical_gearbox ||
                           part.role == Role::chain_drive;
        if (std::any_of(center.begin(), center.end(), [](auto value) {
            return value < -mechanics::maximum_coordinate || value > mechanics::maximum_coordinate;
        })) return {nullptr, "incompatible_geometry"};
        if (part.role == Role::shaft) {
            if (part.geometry.half_span != 2)
                return {nullptr, "incompatible_geometry"};
        } else if (part.role == Role::gear) {
            if (part.geometry.teeth != 2 && part.geometry.teeth != 4) return {nullptr, "incompatible_geometry"};
        } else if (part.role == Role::belt || center[0] % 4 != 0 || center[2] % 4 != 0)
            return {nullptr, "incompatible_geometry"};
        if (relay && (center[1] % 4 != 0 ||
            (part.role == Role::gearbox && part.geometry.axis != mechanics::Axis::y) ||
            (part.role == Role::vertical_gearbox && part.geometry.axis == mechanics::Axis::y)))
            return {nullptr, "incompatible_geometry"};
        if (part.role == Role::collector)
            if (const auto* refusal = collector_site_refusal(center)) return {nullptr, refusal};
        for (const auto& external : part.role == Role::collector ?
                collector_external_bounds(center) : std::vector<Bounds>{}) {
            if (intersects_belt(snapshot.state, external)) return {nullptr, "occupied"};
            for (const auto& [id, foundation] : snapshot.state.foundations) {
                (void)id;
                if (overlap(external, foundation_bounds(foundation))) return {nullptr, "occupied"};
            }
            for (const auto& other : snapshot.state.topology.parts)
                if (other.geometry.id != part.geometry.id && collector_intake_intersects(external, profile_, other))
                    return {nullptr, "occupied"};
        }
        if (part.role == Role::waterwheel) {
            if (const auto* refusal = wheel_site_refusal(center, part.geometry.axis, part.wheel_tiles)) return {nullptr, refusal};
            const auto supports = wheel_support_bounds(center, part.geometry.axis,
                [this](double sx, double sz, double hx, double hz) {
                    return terrain_range(sx, sz, hx, hz);
                });
            if (!supports) return {nullptr, "support_required"};
            for (const auto& [id, foundation] : snapshot.state.foundations) {
                (void)id;
                if (overlap(part_bounds(profile_, part), foundation_bounds(foundation)) ||
                    overlaps_supports(*supports, foundation_bounds(foundation))) return {nullptr, "occupied"};
            }
            for (const auto& other : snapshot.state.topology.parts) {
                if (other.geometry.id == part.geometry.id) continue;
                if (other.role == Role::gear || other.role == Role::shaft) {
                    for (const auto& support : *supports)
                        if (transmission_intersects(support, other.geometry.center, other.geometry.axis,
                                                    other.role == Role::gear)) return {nullptr, "occupied"};
                } else if (overlap(part_bounds(profile_, part), part_bounds(profile_, other)) ||
                           overlaps_supports(*supports, part_bounds(profile_, other))) return {nullptr, "occupied"};
            }
        } else if (part.role != Role::shaft && part.role != Role::gear && !relay)
            if (const auto* refusal = machine_site_refusal(snapshot.state, center, part.role == Role::collector)) return {nullptr, refusal};
        if (part.role == Role::shaft || part.role == Role::gear || relay) {
            if (transmission_intersects_foundations(snapshot.state, center, part.geometry.axis, part.role == Role::gear))
                return {nullptr, "occupied"};
            if (const auto* refusal = transmission_site_refusal(snapshot.state, center, part.geometry.axis, part.role == Role::gear))
                return {nullptr, refusal};
            if (!restored_supports.contains(part.geometry.id)) return {nullptr, "support_required"};
            if (relay) {
                const authority::Point at{center[0] * height_step,
                    anchor_height + center[1] * height_step, center[2] * height_step};
                const authority::Point half{pitch / 2, pitch / 2, pitch / 2};
                const Bounds shell{at, half};
                const auto shell_terrain = terrain_range(at[0], at[2], half[0], half[2]);
                if (!shell_terrain) return {nullptr, "terrain_unavailable"};
                if (shell_terrain->second > at[1] - half[1] + 1e-9) return {nullptr, "site_occupied"};
                if (site_blocked({at[0] - half[0], at[1] - half[1], at[2] - half[2]},
                                 {at[0] + half[0], at[1] + half[1], at[2] + half[2]}))
                    return {nullptr, "site_occupied"};
                for (const auto& [id, foundation] : snapshot.state.foundations) {
                    (void)id;
                    if (overlap(shell, foundation_bounds(foundation))) return {nullptr, "occupied"};
                }
                for (const auto& other : snapshot.state.topology.parts) {
                    if (other.geometry.id == part.geometry.id) continue;
                    if (other.geometry.center == center) return {nullptr, "occupied"};
                    if (other.role != Role::shaft && other.role != Role::gear &&
                        other.role != Role::gearbox && other.role != Role::vertical_gearbox &&
                        other.role != Role::chain_drive && overlap(shell, part_bounds(profile_, other)))
                        return {nullptr, "occupied"};
                    if (other.role == Role::collector) if (const auto intake = collector_intake_bounds(other.geometry.center))
                        if (overlap(shell, *intake)) return {nullptr, "occupied"};
                }
                if (intersects_belt(snapshot.state, shell)) return {nullptr, "occupied"};
            }
        }
    }
    if (!snapshot.state.topology.material_links.empty()) return {nullptr, "incompatible_geometry"};
    // Validate the same path geometry used by construction and physical bodies.
    for (const auto& span : snapshot.state.topology.belt_spans) {
        const auto* first = find(snapshot.state, span.geometry.first_shaft);
        const auto* last = find(snapshot.state, span.geometry.last_shaft);
        const auto path = first && last ? mechanics::belt_path(first->geometry, last->geometry) : std::nullopt;
        if (!path) return {nullptr, "invalid_belt_geometry"};
    }
    for (const auto& span : snapshot.state.topology.belt_spans) {
        const auto* first = find(snapshot.state, span.geometry.first_shaft);
        const auto* last = find(snapshot.state, span.geometry.last_shaft);
        if (!first || !last) return {nullptr, "invalid_belt_geometry"};
        for (const auto& [id, foundation] : snapshot.state.foundations) {
            (void)id;
            if (belt_intersects(first->geometry, last->geometry, foundation_bounds(foundation))) return {nullptr, "occupied"};
        }
        for (const auto& placed : snapshot.state.topology.parts) {
            if (placed.role == Role::shaft) continue;
            const auto& point = placed.geometry.center;
            const Bounds bounds = placed.role == Role::gear ? Bounds{
                {point[0] * height_step, anchor_height + point[1] * height_step, point[2] * height_step},
                gear_half_extents(placed.geometry.axis, placed.geometry.teeth)} : part_bounds(profile_, placed);
            if (belt_intersects(first->geometry, last->geometry, bounds)) return {nullptr, "occupied"};
            if (placed.role == Role::gear && belt_intersects(first->geometry, last->geometry,
                {bounds.center, gear_axle_half_extents(placed.geometry.axis)})) return {nullptr, "occupied"};
            if (placed.role == Role::waterwheel) {
                const auto supports = wheel_support_bounds(placed.geometry.center, placed.geometry.axis,
                    [this](double sx, double sz, double hx, double hz) {
                        return terrain_range(sx, sz, hx, hz);
                    });
                if (!supports) return {nullptr, "support_required"};
                for (const auto& support : *supports)
                    if (belt_intersects(first->geometry, last->geometry, support)) return {nullptr, "occupied"};
            }
        }
        for (const auto& belt : belt_bounds(first->geometry, last->geometry)) {
            const auto& at = belt.center; const auto& half = belt.half;
            if (site_blocked({at[0] - half[0], at[1] - half[1], at[2] - half[2]},
                             {at[0] + half[0], at[1] + half[1], at[2] + half[2]})) return {nullptr, "site_occupied"};
            const auto terrain = terrain_range(at[0], at[2], half[0], half[2]);
            if (!terrain) return {nullptr, "terrain_unavailable"};
            if (terrain->second > at[1] - half[1]) return {nullptr, "site_occupied"};
        }
    }
    const auto& actors = *field<Object>(*root, "actors");
    if (actors.size() != profile_.actors.size()) return {nullptr, "actor_roster_mismatch"};
    auto candidate = std::make_unique<Owned>();
    for (const auto& actor : profile_.actors) {
        const auto found = actors.find(actor);
        const auto* position = found == actors.end() ? nullptr : std::get_if<Array>(&found->second.storage());
        const auto at = position ? point(*position) : std::nullopt;
        if (!at || !std::all_of(position->begin(), position->end(), [](const auto& coordinate) {
                return coordinate.type() == values::Type::floating;
            })) return {nullptr, "invalid_actor_seed"};
        candidate->actors.emplace(actor, Actor{*at, 0, false});
    }
    candidate->world = world::World::restore(*context, profile_, snapshot);
    if (!candidate->world) return {nullptr, "native_checkpoint_refused"};
    return {std::move(candidate), ""};
}

Value Host::validate_checkpoint(const Value& input) const {
    const auto decoded = decode(input);
    return result(decoded.candidate != nullptr, decoded.candidate ? "valid" : decoded.refusal);
}

Value Host::restore_checkpoint(const Value& input) {
    if (!owned_) return result(false, "not_initialized");
    const auto current = owned_->world->snapshot();
    if (owned_->native_started || current.history.order != 0 || current.revision != 0)
        return result(false, "restore_requires_fresh_host");
    auto decoded = decode(input);
    if (!decoded.candidate) return result(false, decoded.refusal);
    owned_.swap(decoded.candidate);
    return result(true, "restored");
}

}  // namespace factory::godot_world
