#include "factory/godot_world.hpp"
#include "factory/arrival_geometry.hpp"
#include "factory/assembly.hpp"
#include "factory/mineral_site.hpp"
#include "factory/waterflow.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <initializer_list>
#include <limits>
#include <optional>
#include <set>
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
constexpr double component_shaft_half = 0.205;
// Hundredths of a height step, shared with the native opening rotor.
constexpr Integer wheel_radius = 224;
constexpr Integer wheel_axle_offset = 200;
constexpr double reach = 4.0;
constexpr double capsule_radius = 0.3;
constexpr double capsule_height = 1.8;
constexpr double machine_width = 1.45;
constexpr double machine_height = 1.65;
constexpr double machine_center_height = 0.8;
constexpr double press_work_crown_rise = 0.082;

Integer crafting_bench_generation(const world::State& state, const std::string& id) {
    if (state.fabrication_hub && !state.fabrication_hub->holder && state.fabrication_hub->id == id)
        return state.fabrication_hub->generation;
    const auto placed = state.placed_components.find(id);
    return placed != state.placed_components.end() &&
        placed->second.kind == materials::Component::wooden_workbench ?
        placed->second.generation : Integer{0};
}

const char* collector_status_name(assembly::Status status) {
    switch (status) {
        case assembly::Status::ready: return "ready";
        case assembly::Status::invalid_input: return "invalid_input";
        case assembly::Status::missing_frame: return "missing_frame";
        case assembly::Status::missing_mount: return "missing_mount";
        case assembly::Status::missing_edge: return "missing_edge";
        case assembly::Status::missing_receiver: return "missing_receiver";
        case assembly::Status::ambiguous: return "ambiguous";
    }
    return "invalid_input";
}

const char* press_status_name(assembly::PressStatus status) {
    switch (status) {
        case assembly::PressStatus::ready: return "ready";
        case assembly::PressStatus::invalid_input: return "invalid_input";
        case assembly::PressStatus::missing_frame: return "missing_frame";
        case assembly::PressStatus::missing_anvil: return "missing_anvil";
        case assembly::PressStatus::missing_ram: return "missing_ram";
        case assembly::PressStatus::missing_flat_head: return "missing_flat_head";
        case assembly::PressStatus::missing_slide: return "missing_slide";
        case assembly::PressStatus::missing_guide: return "missing_guide";
        case assembly::PressStatus::missing_mount: return "missing_mount";
        case assembly::PressStatus::missing_shaft: return "missing_shaft";
        case assembly::PressStatus::missing_cog: return "missing_cog";
        case assembly::PressStatus::blocked_stroke: return "blocked_stroke";
        case assembly::PressStatus::blocked_feed: return "blocked_feed";
        case assembly::PressStatus::ambiguous: return "ambiguous";
    }
    return "invalid_input";
}

const char* broad_geometry_status_name(assembly::BroadPressStatus status) {
    switch (status) {
        case assembly::BroadPressStatus::ready: return "ready";
        case assembly::BroadPressStatus::invalid_input: return "invalid_input";
        case assembly::BroadPressStatus::missing_anvil: return "missing_anvil";
        case assembly::BroadPressStatus::missing_ram: return "missing_ram";
        case assembly::BroadPressStatus::missing_guide: return "missing_guide";
        case assembly::BroadPressStatus::blocked_stroke: return "blocked_stroke";
        case assembly::BroadPressStatus::missing_shaft: return "missing_shaft";
        case assembly::BroadPressStatus::missing_cog: return "missing_cog";
        case assembly::BroadPressStatus::ambiguous: return "ambiguous";
    }
    return "invalid_input";
}

const char* broad_shear_status_name(assembly::BroadShearStatus status) {
    switch (status) {
        case assembly::BroadShearStatus::ready: return "ready";
        case assembly::BroadShearStatus::invalid_input: return "invalid_input";
        case assembly::BroadShearStatus::missing_anvil: return "missing_anvil";
        case assembly::BroadShearStatus::missing_blade: return "missing_blade";
        case assembly::BroadShearStatus::missing_guide: return "missing_guide";
        case assembly::BroadShearStatus::blocked_stroke: return "blocked_stroke";
        case assembly::BroadShearStatus::missing_shaft: return "missing_shaft";
        case assembly::BroadShearStatus::missing_cog: return "missing_cog";
        case assembly::BroadShearStatus::ambiguous: return "ambiguous";
    }
    return "invalid_input";
}

const char* broad_drive_status_name(world::BroadPressDriveStatus status) {
    switch (status) {
        case world::BroadPressDriveStatus::ready: return "ready";
        case world::BroadPressDriveStatus::invalid_power: return "invalid_power";
        case world::BroadPressDriveStatus::invalid_geometry: return "invalid_geometry";
        case world::BroadPressDriveStatus::unpowered: return "unpowered";
        case world::BroadPressDriveStatus::stopped: return "stopped";
        case world::BroadPressDriveStatus::stalled: return "stalled";
        case world::BroadPressDriveStatus::incompatible_axis: return "incompatible_axis";
        case world::BroadPressDriveStatus::mismatched_rate: return "mismatched_rate";
        case world::BroadPressDriveStatus::disconnected: return "disconnected";
    }
    return "invalid_power";
}

using Bounds = arrival_geometry::Bounds;

bool capsule_intersects(const authority::Point& actor, const Bounds& box, double tolerance = 0) {
    const auto dx = std::max(std::abs(actor[0] - box.center[0]) - box.half[0], 0.0);
    const auto dz = std::max(std::abs(actor[2] - box.center[2]) - box.half[2], 0.0);
    const auto segment_half = capsule_height / 2 - capsule_radius;
    const auto below = box.center[1] - box.half[1] - (actor[1] + segment_half);
    const auto above = actor[1] - segment_half - (box.center[1] + box.half[1]);
    const auto dy = std::max({below, above, 0.0});
    const auto radius = capsule_radius - tolerance;
    return dx * dx + dy * dy + dz * dz < radius * radius;
}

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

Bounds component_bounds(const world::Profile& profile,
        std::optional<materials::Component> kind, const mechanics::Point& center) {
    const authority::Point at{center[0] * height_step,
        center[1] * height_step + anchor_height, center[2] * height_step};
    const auto vertical = [&](double low, double high) -> Bounds {
        return {{at[0], (low + high) / 2, at[2]}, {0.14, (high - low) / 2, 0.14}};
    };
    if (!kind) return {at, {0.14, 0.14, 0.14}};
    if (const auto channel = materials::channel_spec(*kind)) {
        const double low = center[1] * height_step;
        const double high = at[1] + press_work_crown_rise + 0.12;
        const double width_x = pitch * channel->floor.x_cells;
        const double width_z = pitch * channel->floor.z_cells;
        return {{at[0] + (width_x - pitch) / 2, (low + high) / 2,
                 at[2] + (width_z - pitch) / 2},
                {width_x / 2, (high - low) / 2, width_z / 2}};
    }
    if (*kind == materials::Component::tool_mount ||
        *kind == materials::Component::cutting_edge) {
        const auto step = *kind == materials::Component::tool_mount ? 1 : 2;
        for (const auto& face : profile.collector_faces)
            for (Integer elevation : {Integer{0}, Integer{1}}) {
                const mechanics::Point tool_cell{
                    face.machine_center[0] + step * face.toward_ore[0],
                    face.machine_center[1] + elevation,
                    face.machine_center[2] + step * face.toward_ore[2]};
                if (center != tool_cell) continue;
                // These independently placed parts own their supports down to
                // the frame's floor. A press mount or part away from a trusted
                // ore face retains its shorter original box.
                const double floor = face.machine_center[1] * height_step;
                const double top = at[1] + (*kind == materials::Component::tool_mount ?
                    0.28 : 0.105);
                const bool along_x = face.toward_ore[0] != 0;
                const double face_half = *kind == materials::Component::tool_mount ?
                    0.21 : 0.2025;
                const double cross_x = *kind == materials::Component::tool_mount ?
                    0.20 : 0.21;
                const double cross_z = *kind == materials::Component::tool_mount ?
                    0.19 : 0.18;
                return {{at[0], (floor + top) / 2, at[2]},
                    {along_x ? face_half : cross_x, (top - floor) / 2,
                     along_x ? cross_z : face_half}};
            }
    }
    switch (*kind) {
        case materials::Component::wooden_frame:
            // The frame's four load-bearing feet meet the level's floor.
            return {{at[0], center[1] * height_step + 0.45, at[2]}, {0.2025, 0.45, 0.2025}};
        case materials::Component::wooden_workbench:
            // A floor-seated table is usable on ground or an ordinary joined deck.
            return {{at[0], center[1] * height_step + 0.45, at[2]}, {0.34, 0.45, 0.30}};
        case materials::Component::tool_mount:
            return {{at[0], at[1] + 0.10, at[2]},
                    {height_step - component_shaft_half, 0.18,
                     height_step - component_shaft_half}};
        case materials::Component::anvil:
            // The cast pedestal meets the frame's 0.9 m top. Its upper
            // clearance reaches the retained copper crown at the work point.
            // The ram's swept die begins at this same face.
            return vertical(at[1] - height_step + (0.9 - anchor_height),
                at[1] + press_work_crown_rise);
        case materials::Component::ram_face:
            return vertical(at[1] - height_step + press_work_crown_rise,
                at[1] + height_step * 0.5);
        case materials::Component::flat_head:
            // Reserve the entire carriage-driven die sweep. The named slide
            // may occupy its coaxial upper portion as an intentional fitting.
            return vertical(at[1] - height_step * 0.75,
                at[1] + height_step * 0.5);
        case materials::Component::sliding_guide:
            // Its full selected rails reach the ram below, whether or not a
            // press is recognized. The admitted box includes that entire
            // span and meets the unchanged tool-mount box above.
            return vertical(at[1] - height_step * 1.5, at[1] + height_step - 0.08);
        case materials::Component::wooden_slide:
        case materials::Component::copper_slide:
            // Its fixed rails and moving carriage live inside this volume.
            // The lower face is the admitted stroke limit even when unloaded.
            return {{at[0], at[1] - height_step * 0.5, at[2]},
                {0.21, height_step, 0.21}};
        case materials::Component::cutting_edge:
            return {{at[0], at[1] - 0.015, at[2]}, {0.21, 0.12, 0.18}};
        case materials::Component::receiver_tray:
            return {{at[0], at[1] - 0.0825, at[2]}, {0.18, 0.15, 0.205}};
        case materials::Component::wooden_shaft:
        case materials::Component::copper_shaft:
            return {at, {component_shaft_half, 0.12, component_shaft_half}};
        case materials::Component::wooden_cog:
        case materials::Component::copper_cog:
            // Either horizontal press layout seats this hub against the
            // neighboring shaft without moving either common-grid center.
            return {at, {height_step - component_shaft_half, 0.14,
                         height_step - component_shaft_half}};
        default:
            return {at, {0.14, 0.14, 0.14}};
    }
}

bool slide_head_fitting(std::optional<materials::Component> first,
        const mechanics::Point& first_center, materials::Component second,
        const mechanics::Point& second_center) {
    const auto slide = [](materials::Component kind) {
        return kind == materials::Component::wooden_slide ||
            kind == materials::Component::copper_slide;
    };
    if (!first || first_center[0] != second_center[0] ||
        first_center[2] != second_center[2]) return false;
    return (*first == materials::Component::flat_head && slide(second) &&
               second_center[1] == first_center[1] + 1) ||
        (slide(*first) && second == materials::Component::flat_head &&
               first_center[1] == second_center[1] + 1);
}

bool guide_ram_fitting(std::optional<materials::Component> first,
        const mechanics::Point& first_center, materials::Component second,
        const mechanics::Point& second_center) {
    if (!first || first_center[0] != second_center[0] ||
        first_center[2] != second_center[2]) return false;
    // The guide's narrow fixed side rails wrap the centered ram. Their
    // conservative occupied boxes overlap in this one fitted stack.
    return (*first == materials::Component::sliding_guide &&
               second == materials::Component::ram_face &&
               first_center[1] == second_center[1] + 1) ||
        (*first == materials::Component::ram_face &&
               second == materials::Component::sliding_guide &&
               second_center[1] == first_center[1] + 1);
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

bool shaft_meets_component_cog(std::optional<materials::Component> kind,
        const mechanics::Point& component, const mechanics::Point& shaft, mechanics::Axis axis) {
    if (kind != materials::Component::wooden_cog &&
        kind != materials::Component::copper_cog) return false;
    if (axis != mechanics::Axis::x && axis != mechanics::Axis::z) return false;
    const auto along = static_cast<std::size_t>(axis);
    for (std::size_t dimension = 0; dimension < 3; ++dimension)
        if (dimension != along && component[dimension] != shaft[dimension]) return false;
    // A one-tile shaft ends at the hub center two height steps away. Its
    // placement box and the cog's occupied box overlap at this intended joint.
    return std::abs(component[along] - shaft[along]) == 2;
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
    if (*action == "place_sheet")
        return *original_action == "place_sheet" &&
            keys(*wire, {"center", "sheet_id"}) &&
            field<Array>(*wire, "center") && field<Integer>(*wire, "sheet_id") &&
            same("center", "center") && same("sheet_id", "sheet_id");
    if (*action == "push_channel_sheet")
        return *original_action == "push_channel_sheet" &&
            keys(*wire, {"from", "to", "sheet_id"}) &&
            field<Array>(*wire, "from") && field<Array>(*wire, "to") &&
            field<Integer>(*wire, "sheet_id") &&
            same("from", "from") && same("to", "to") &&
            same("sheet_id", "sheet_id");
    if (*action == "push_channel_small")
        return *original_action == "push_channel_small" &&
            keys(*wire, {"from", "to", "form"}) &&
            field<Array>(*wire, "from") && field<Array>(*wire, "to") &&
            field<std::string>(*wire, "form") &&
            same("from", "from") && same("to", "to") &&
            same("form", "form");
    if (*action == "stroke_broad_shear")
        return *original_action == "stroke_broad_shear" &&
            keys(*wire, {"entity", "sheet_id"}) &&
            field<std::string>(*wire, "entity") &&
            field<Integer>(*wire, "sheet_id") &&
            same("entity", "target") && same("sheet_id", "sheet_id");
    if (*action == "harvest_source")
        return *original_action == "harvest_source" && keys(*wire, {"target"}) &&
            field<std::string>(*wire, "target") && same("target", "target");
    if (*action == "fast_harvest_source")
        return *original_action == "harvest_source" && keys(*wire, {"target"}) &&
            field<std::string>(*wire, "target") && same("target", "target");
    if (*action == "set_developer_conveniences")
        return *original_action == *action && keys(*wire, {"enabled"}) &&
            field<bool>(*wire, "enabled") && same("enabled", "enabled");
    if (*action == "finish_harvest" || *action == "cancel_harvest")
        return *original_action == *action && keys(*wire, {});
    if (*action == "craft_component")
        return *original_action == "craft_component" && keys(*wire, {"entity", "component"}) &&
            field<std::string>(*wire, "entity") && field<std::string>(*wire, "component") &&
            same("entity", "target") && same("component", "component");
    if (*action == "craft_foundation")
        return *original_action == "craft_foundation" && keys(*wire, {"entity"}) &&
            field<std::string>(*wire, "entity") && same("entity", "target");
    if (*action == "field_craft")
        return *original_action == "field_craft" && keys(*wire, {"component"}) &&
            field<std::string>(*wire, "component") && same("component", "component");
    if (*action == "stow_fabrication_hub")
        return *original_action == "stow_fabrication_hub" && keys(*wire, {"entity"}) &&
            field<std::string>(*wire, "entity") && same("entity", "target");
    if (*action == "deploy_fabrication_hub")
        return *original_action == "deploy_fabrication_hub" && keys(*wire, {"entity", "center"}) &&
            field<std::string>(*wire, "entity") && field<Array>(*wire, "center") &&
            same("entity", "target") && same("center", "center");
    if (*action == "craft_part")
        return *original_action == "craft_part" && keys(*wire, {"entity", "role", "half_span"}) &&
            field<std::string>(*wire, "entity") && field<std::string>(*wire, "role") &&
            field<Integer>(*wire, "half_span") && same("entity", "target") &&
            same("role", "role") && same("half_span", "half_span");
    if (*action == "attach_hand_crank")
        return *original_action == *action &&
            (keys(*wire, {"entity", "crank", "port"}) ||
             keys(*wire, {"entity", "crank", "port", "face"})) &&
            field<std::string>(*wire, "entity") && field<std::string>(*wire, "crank") &&
            field<Array>(*wire, "port") && same("entity", "target") &&
            same("crank", "crank") && same("port", "port") &&
            (wire->contains("face") ? same("face", "face") : !intent.contains("face"));
    if (*action == "detach_hand_crank")
        return *original_action == *action && keys(*wire, {"entity"}) &&
            field<std::string>(*wire, "entity") && same("entity", "target");
    if (*action == "operate_hand_crank")
        return *original_action == *action && keys(*wire, {"entity"}) &&
            field<std::string>(*wire, "entity") && same("entity", "crank");
    if (*action == "turn_hand_crank")
        return *original_action == *action && keys(*wire, {"entity"}) &&
            field<std::string>(*wire, "entity") && same("entity", "target");
    if (*action == "turn_slide_crank")
        return *original_action == *action && keys(*wire, {"entity", "port"}) &&
            field<std::string>(*wire, "entity") && field<Array>(*wire, "port") &&
            same("entity", "target") && same("port", "port");
    if (*action == "feed_press")
        return *original_action == *action && keys(*wire, {"entity", "entry"}) &&
            field<std::string>(*wire, "entity") && field<Array>(*wire, "entry") &&
            same("entity", "target") && same("entry", "entry");
    if (*action == "feed_broad_press" || *action == "refeed_broad_press_work")
        return *original_action == *action &&
            keys(*wire, *action == "feed_broad_press" ?
                std::initializer_list<const char*>{"entity"} :
                std::initializer_list<const char*>{"entity", "work_id"}) &&
            field<std::string>(*wire, "entity") && same("entity", "target") &&
            (*action == "feed_broad_press" ||
                (field<Integer>(*wire, "work_id") && same("work_id", "work_id")));
    if (*action == "compact_offcuts")
        return *original_action == *action && keys(*wire, {"entity", "entry", "drive"}) &&
            field<std::string>(*wire, "entity") && field<Array>(*wire, "entry") &&
            field<std::string>(*wire, "drive") && same("entity", "target") &&
            same("entry", "entry") && same("drive", "drive");
    if (*action == "refeed_press_work")
        return *original_action == *action && keys(*wire, {"entity", "entry", "work_id"}) &&
            field<std::string>(*wire, "entity") && field<Array>(*wire, "entry") &&
            field<Integer>(*wire, "work_id") && same("entity", "target") &&
            same("entry", "entry") && same("work_id", "work_id");
    if (*action == "turn_press_crank")
        return *original_action == *action && keys(*wire, {"entity", "drive", "exit"}) &&
            field<std::string>(*wire, "entity") && field<std::string>(*wire, "drive") &&
            field<Array>(*wire, "exit") && same("entity", "target") &&
            same("drive", "drive") && same("exit", "exit");
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

Value cargo_value(const materials::Cargo& cargo, bool resources = false, bool copper = false) {
    Array lots;
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
    if (resources) {
        output.emplace("timber", Value(cargo.timber));
        Object components;
        for (const auto& [kind, count] : cargo.components)
            components.emplace(materials::component_name(kind), Value(count));
        output.emplace("components", Value(std::move(components)));
    }
    if (copper) {
        output.emplace("offcuts", Value(cargo.offcuts));
        output.emplace("sheets", Value(static_cast<Integer>(cargo.sheets.size())));
        if (!cargo.sheets.empty()) {
            Array sheet_items;
            for (const auto& sheet : cargo.sheets)
                sheet_items.emplace_back(Object{{"id", Value(sheet.id)},
                    {"rotation", Value(sheet.rotation)}});
            output.emplace("sheet_items", Value(std::move(sheet_items)));
        }
    }
    return Value(std::move(output));
}

bool copper_forms(const materials::Config& config) {
    return config.raw_mass != 1 || config.plate_mass != 0 || config.sheet_mass != 0;
}

Value material_mass_value(const materials::State& state, const materials::Config& config) {
    Integer stock_chunks = state.stock.source + state.stock.collector +
        state.stock.belt + state.stock.input;
    Integer work_chunks = state.processing ? state.processing->recipe.input_units_per_product : 0;
    Integer plates = state.stock.output;
    Integer offcuts = state.stock.offcuts;
    Integer sheets = 0;
    Integer embodied_chunks = state.fabricated_raw;
    const auto count_cargo = [&](const materials::Cargo& cargo) {
        stock_chunks += cargo.raw_units;
        plates += cargo.products;
        offcuts += cargo.offcuts;
        sheets += static_cast<Integer>(cargo.sheets.size());
        for (const auto& lot : cargo.work_lots)
            work_chunks += lot.recipe.input_units_per_product;
        for (const auto& [kind, count] : cargo.components)
            embodied_chunks += materials::component_cost(kind)->ore * count;
    };
    for (const auto& [actor, cargo] : state.cargo) { (void)actor; count_cargo(cargo); }
    for (const auto& [point, cargo] : state.dropped_material) { (void)point; count_cargo(cargo); }
    for (const auto& [id, lane] : state.belt_lanes) {
        (void)id;
        for (const auto& slot : lane.slots) if (slot) count_cargo(*slot);
    }
    for (const auto& [kind, count] : state.placed_components)
        embodied_chunks += materials::component_cost(kind)->ore * count;
    const Integer plate_mass = config.plate_mass == 0 ?
        config.input_units_per_product * config.raw_mass : config.plate_mass;
    const Integer accounted = (stock_chunks + work_chunks + embodied_chunks) * config.raw_mass +
        plates * plate_mass + offcuts + sheets * config.sheet_mass;
    return Value(Object{{"stock_chunks", Value(stock_chunks)},
        {"work_chunks", Value(work_chunks)}, {"plates", Value(plates)},
        {"offcut_units", Value(offcuts)}, {"sheets", Value(sheets)},
        {"embodied_chunks", Value(embodied_chunks)},
        {"accounted_mass", Value(accounted)},
        {"initial_mass", Value(state.initial_units * config.raw_mass)}});
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

Object slide_phase_projection(const world::State& state) {
    Object phases;
    for (const auto& [id, phase] : state.slide_phases)
        phases.emplace(id, Value(Object{{"subticks", Value(phase.subticks)},
            {"remainder", Value(phase.remainder)},
            {"denominator", Value(phase.denominator)},
            {"cycle_subticks", Value(world::slide_cycle_subticks)}}));
    return phases;
}
}  // namespace

Value Host::initialize(const std::string& context, const std::vector<std::string>& actors) {
    return initialize_site(context, actors, false);
}

Value Host::initialize_arrival(const std::string& context, const std::vector<std::string>& actors) {
    return initialize_site(context, actors, true);
}

Value Host::initialize_arrival_advanced_fixture(const std::string& context,
        const std::vector<std::string>& actors) {
    return initialize_site(context, actors, true, true);
}

Value Host::initialize_site(const std::string& context, const std::vector<std::string>& actors,
                            bool arrival, bool advanced_fixture) {
    if (owned_) return result(false, "already_initialized");
    if (actors.empty() || actors.size() > 2 || actors.front() != "P") return result(false, "invalid_roster");
    world::Profile profile;
    // Reversible opening content, with enough buffer to recover finite ore in
    // batches. All reserve and carried quantities remain in this one World.
    profile.material = {1, 32, 2};
    profile.initial_units = mineral_site::opening_reserve;
    profile.meters_per_grid_unit = pitch / 4.0;
    profile.anchor_offset = {0, anchor_height, 0};
    profile.wheel_radius = wheel_radius;
    profile.wheel_axle_offset = wheel_axle_offset;
    profile.build_reach = reach;
    if (arrival) profile.manual_cut_reach = 2.55;
    profile.foundation_parts = 24;
    // East of the river and clear of the exposed ore deposit. This is a
    // reversible authored site anchor, expressed in the one quarter-tile grid.
    if (arrival) {
        profile.landing_pod_center = mechanics::Point{4, 0, 16};
        profile.first_plate_unlock = !advanced_fixture;
        profile.material.manual_ore = materials::OreSite{"opening-copper", {-3, 0, 0}};
        profile.material.raw_mass = 4;
        profile.material.plate_mass = 3;
        profile.material.sheet_mass = 12;
        for (const auto& cell : mineral_site::opening_cells)
            for (Integer level = 0; level <= mineral_site::extraction_depth_steps; level += 4)
                profile.collector_faces.push_back({{4 * cell.x, level, 4 * cell.z}, {-1, 0, 0}});
        profile.material.timber_sites = {
            {"tree-east-south", {{16, 0, 8}, 8}},
            {"tree-east-north", {{16, 0, 28}, 8}},
            {"tree-north", {{0, 0, 28}, 8}},
            {"tree-east-upstream", {{16, 0, -4}, 8}},
            // Mature bank trees have stable native identities. The scene
            // matches each prepared mesh root to these quarter-tile centers.
            {"fir_00", {{-28, 0, -44}, 8}},
            {"fir_01", {{-31, 0, -11}, 8}},
            {"fir_02", {{-51, 0, 37}, 8}},
            {"fir_03", {{29, 0, -24}, 8}},
            {"fir_04", {{32, 0, -2}, 8}},
            {"fir_05", {{44, 0, 15}, 8}},
            {"broadleaf_00", {{15, 1, -46}, 8}},
            {"broadleaf_01", {{-46, 0, -34}, 8}}};
        // Zero means no carried-count limit. Finite sources and native custody
        // still bound the material that can exist in the opening.
        profile.material.hand_carry_capacity = 0;
        profile.material.component_capacity = 0;
        // Reversible cold-workshop costs for a real powered receiver route.
        // Every kit remains in the one World inventory and history ledger.
        profile.fabrication_parts = {{{Role::shaft, 0, 2}, {1, 0}},
            {{Role::belt, 0, 0}, {2, 1}}, {{Role::waterwheel, 0, 0}, {2, 1}},
            {{Role::gearbox, 0, 0}, {1, 1}},
            {{Role::vertical_gearbox, 0, 0}, {1, 1}}};
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
        profile.starting_foundation_kits.emplace(actor, seed.foundation_kits.at(actor));
        // Start on the unfolded front deck, clear of the rear pressure shell,
        // side doors and threshold. Both capsules remain near the local bench.
        candidate->actors.emplace(actor, Actor{arrival ?
            authority::Point{(actor == "P" ? 1.0 : 0.5) * pitch, 1.0, 4.8} :
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
    const auto* tree_obstacles = field<Object>(input, "tree_obstacles");
    const auto* water = field<Array>(input, "water");
    const auto* flow_cells = field<Array>(input, "flow_cells");
    if (input.size() != (water || flow_cells ? 4u : 3u) + (source_obstacle ? 1u : 0u) +
        (tree_obstacles ? 1u : 0u) || (water && flow_cells) ||
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
    std::map<std::size_t, std::string> named_trees;
    if (tree_obstacles) for (const auto& [id, value] : *tree_obstacles) {
        const auto* index = std::get_if<Integer>(&value.storage());
        if (!index || *index < 0 || static_cast<std::size_t>(*index) >= solids.size() ||
            (source_obstacle && *index == *source_obstacle) ||
            !profile_.material.timber_sites.contains(id) ||
            named_trees.contains(static_cast<std::size_t>(*index)))
            return result(false, "invalid_terrain");
        named_trees.emplace(static_cast<std::size_t>(*index), id);
    }
    auto next_profile = profile_;
    if (source_obstacle && next_profile.material.manual_ore)
        next_profile.manual_ore_contact_bounds = solids[static_cast<std::size_t>(*source_obstacle)];
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
    if (water || flow_cells || (source_obstacle && next_profile.material.manual_ore)) {
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
    tree_obstacle_sources_ = std::move(named_trees);
    return result(true, "terrain_bound");
}

bool Host::clear_harvest_path(const world::State& state, const std::string& source,
        const authority::Point& actor, const authority::Point& contact) const {
    // The held tool just above the actor center is the origin; the selected source's own obstacle
    // is the destination, not a wall between the two. Other trusted solids
    // and the emitted ground can still stop a cut despite valid radial reach.
    auto start = actor;
    start[1] += 0.20;
    const authority::Point delta{contact[0] - start[0], contact[1] - start[1], contact[2] - start[2]};
    const auto intersects = [&](const authority::Point& low, const authority::Point& high) {
        double entry = 0.0, exit = 1.0;
        for (std::size_t axis = 0; axis < 3; ++axis) {
            if (std::abs(delta[axis]) < 1e-9) {
                if (start[axis] < low[axis] || start[axis] > high[axis]) return false;
                continue;
            }
            const double a = (low[axis] - start[axis]) / delta[axis];
            const double b = (high[axis] - start[axis]) / delta[axis];
            entry = std::max(entry, std::min(a, b));
            exit = std::min(exit, std::max(a, b));
        }
        return entry <= exit && entry < 1.0 - 1e-6 && exit > 1e-6;
    };
    for (std::size_t index = 0; index < terrain_obstacles_.size(); ++index) {
        if (source_obstacle_index_ == index && profile_.material.manual_ore &&
            profile_.material.manual_ore->id == source) continue;
        if (const auto tree = tree_obstacle_sources_.find(index);
            tree != tree_obstacle_sources_.end() &&
            (tree->second == source || state.material.timber_remaining.at(tree->second) == 0)) continue;
        const auto& [low, high] = terrain_obstacles_[index];
        if (intersects(low, high)) return false;
    }
    const auto blocked_volume = [&](const Bounds& bounds) {
        authority::Point low{}, high{};
        for (std::size_t axis = 0; axis < 3; ++axis) {
            low[axis] = bounds.center[axis] - bounds.half[axis];
            high[axis] = bounds.center[axis] + bounds.half[axis];
        }
        return intersects(low, high);
    };
    for (const auto& [id, part] : state.placed_components) {
        (void)id;
        if (blocked_volume(component_bounds(profile_, part.kind, part.center))) return false;
    }
    for (const auto& part : state.topology.parts)
        if (blocked_volume(part_bounds(profile_, part))) return false;
    const double span = std::hypot(delta[0], delta[2]);
    const int steps = std::max(1, static_cast<int>(std::ceil(span / 0.15)));
    for (int step = 1; step < steps; ++step) {
        const double t = static_cast<double>(step) / steps;
        const auto ground = terrain_range(start[0] + delta[0] * t,
            start[2] + delta[2] * t, 0, 0);
        if (!ground || ground->second > start[1] + delta[1] * t - 0.02) return false;
    }
    return true;
}

Object Host::harvest_clearances(const world::State& state, const Actor& actor) const {
    Object clear;
    if (!actor.ready) return clear;
    const auto examine = [&](const std::string& id, const materials::DropPoint& center, bool ore) {
        const auto contact = world::manual_cut_target(profile_, center, actor.position, ore);
        clear.emplace(id, Value(clear_harvest_path(state, id, actor.position, contact)));
    };
    if (profile_.material.manual_ore)
        examine(profile_.material.manual_ore->id, profile_.material.manual_ore->center, true);
    for (const auto& [id, site] : profile_.material.timber_sites)
        examine(id, site.center, false);
    return clear;
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
        // Stacked cases need posts outside lower shells. A diagonal fallback
        // can stand beside the river shaft and ore outcrop while its complete
        // post and arm still pass the same terrain and occupancy checks.
        constexpr std::array offsets{0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.6, -1.6};
        constexpr std::array diagonals{
            std::array{-1.6, -1.6}, std::array{-1.6, 1.6},
            std::array{1.6, -1.6}, std::array{1.6, 1.6}};
        const auto routes = offsets.size() * (axis == mechanics::Axis::y ? 1 : 2) +
            (axis == mechanics::Axis::y ? diagonals.size() : 0);
        for (std::size_t route = 0; route < routes; ++route) {
            const bool diagonal = axis == mechanics::Axis::y && route >= offsets.size();
            const double offset = diagonal ? diagonals[route - offsets.size()][0] : offsets[route % offsets.size()];
            const double axial = route < offsets.size() ? 0.55 : -0.55;
            auto bearing = at;
            if (axis == mechanics::Axis::x) bearing[0] += axial;
            else if (axis == mechanics::Axis::z) bearing[2] += axial;
            else bearing[1] -= 0.50;
            auto foot = bearing;
            if (axis == mechanics::Axis::y) foot[0] += 0.24;
            foot[lateral] += offset;
            if (diagonal) foot[2] += diagonals[route - offsets.size()][1];
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
                    if (overlap(box, component_bounds(profile_, component.kind, component.center))) clear = false;
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

const char* Host::component_site_refusal(const world::State& state,
        std::optional<materials::Component> kind, const mechanics::Point& center) const {
    const auto volume = component_bounds(profile_, kind, center);
    const auto& at = volume.center;
    const auto ground = terrain_range(at[0], at[2], volume.half[0], volume.half[2]);
    if (!ground) return "terrain_unavailable";
    if (ground->second > at[1] - volume.half[1]) return "site_occupied";
    if (kind && materials::channel_spec(*kind) && center[1] == 0 &&
        ground->first < at[1] - volume.half[1] - 0.04)
        return "support_required";
    if (kind == materials::Component::wooden_workbench) {
        const bool supported = std::any_of(state.foundations.begin(), state.foundations.end(),
            [&](const auto& entry) { return entry.second.center == center; });
        if (!supported && ground->first < at[1] - volume.half[1] - 0.04)
            return "support_required";
    }
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

const char* Host::component_space_refusal(const world::State& state,
        std::optional<materials::Component> kind, const mechanics::Point& center,
        const std::string* current_id) const {
    const auto volume = component_bounds(profile_, kind, center);
    for (const auto& [id, foundation] : state.foundations) {
        (void)id;
        if (overlap(volume, foundation_bounds(foundation))) return "occupied";
    }
    for (const auto& [id, other] : state.placed_components)
        if ((!current_id || id != *current_id) &&
            !slide_head_fitting(kind, center, other.kind, other.center) &&
            !guide_ram_fitting(kind, center, other.kind, other.center) &&
            overlap(volume, component_bounds(profile_, other.kind, other.center))) return "occupied";
    if (intersects_belt(state, volume)) return "occupied";
    for (const auto& part : state.topology.parts) {
        if (part.role == Role::gear || part.role == Role::shaft) {
            if (transmission_intersects(volume, part.geometry.center, part.geometry.axis,
                                        part.role == Role::gear) &&
                !(part.role == Role::shaft && shaft_meets_component_cog(
                    kind, center, part.geometry.center, part.geometry.axis))) return "occupied";
        } else if (overlap(volume, part_bounds(profile_, part))) return "occupied";
        if (part.role == Role::collector)
            for (const auto& external : collector_external_bounds(part.geometry.center))
                if (overlap(volume, external)) return "occupied";
        if (part.role == Role::waterwheel) {
            const auto supports = wheel_support_bounds(part.geometry.center, part.geometry.axis,
                [this](double x, double z, double hx, double hz) {
                    return terrain_range(x, z, hx, hz);
                });
            if (!supports) return "support_required";
            if (overlaps_supports(*supports, volume)) return "occupied";
        }
    }
    return nullptr;
}

const char* Host::supplied_space_refusal(const world::State& state) const {
    const auto solids = arrival_geometry::supplied(state, height_step);
    if (solids.empty()) return nullptr;
    const auto supports = transmission_supports(state);
    for (const auto& [id, solid] : solids) {
        const auto& box = solid.bounds;
        for (const auto& [other_id, other] : solids)
            if (id < other_id && solid.entity != other.entity && overlap(box, other.bounds))
                return "occupied";
        for (const auto& [unused, floor] : state.foundations) {
            (void)unused;
            if (overlap(box, foundation_bounds(floor))) return "occupied";
        }
        for (const auto& [unused, component] : state.placed_components) {
            (void)unused;
            if (overlap(box, component_bounds(profile_, component.kind, component.center))) return "occupied";
        }
        if (intersects_belt(state, box)) return "occupied";
        for (const auto& part : state.topology.parts) {
            if (part.role == Role::shaft || part.role == Role::gear) {
                if (transmission_intersects(box, part.geometry.center, part.geometry.axis,
                        part.role == Role::gear)) return "occupied";
            } else if (overlap(box, part_bounds(profile_, part))) return "occupied";
            if (part.role == Role::collector)
                for (const auto& external : collector_external_bounds(part.geometry.center))
                    if (overlap(box, external)) return "occupied";
            if (part.role == Role::waterwheel) {
                const auto feet = wheel_support_bounds(part.geometry.center, part.geometry.axis,
                    [this](double x, double z, double hx, double hz) { return terrain_range(x, z, hx, hz); });
                if (!feet) return "support_required";
                if (overlaps_supports(*feet, box)) return "occupied";
            }
        }
        for (const auto& [unused, support] : supports) {
            (void)unused;
            for (const auto& [center, half] : support.boxes)
                if (overlap(box, {center, half})) return "occupied";
        }
    }
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
        if (capsule_intersects(state.position, {target, half_extents})) return true;
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
    const auto complete_crank_pulse = [&](world::Delivery delivered) -> Value {
        if (delivered.completed() && field<bool>(*delivered.result, "accepted") &&
            *field<bool>(*delivered.result, "accepted")) {
            const auto* revision = field<Integer>(*delivered.result, "revision");
            const auto current = owned_->world->snapshot();
            const auto& records = current.history.records;
            const auto* last_action = records.empty() ? nullptr :
                field<std::string>(records.back().intent, "action");
            const auto* last_request = records.empty() ? nullptr :
                field<std::string>(records.back().intent, "request");
            const auto* last_client = records.empty() ? nullptr :
                field<std::string>(records.back().intent, "client");
            const auto* last_accepted = records.empty() ? nullptr :
                field<bool>(records.back().result, "accepted");
            if (revision && current.revision == *revision && last_action &&
                *last_action == "operate_hand_crank" && request && last_request &&
                *last_request == *request && last_client && *last_client == *client &&
                last_accepted && *last_accepted) {
                const auto tick = owned_->world->tick(observe());
                if (tick.error != world::TransactionError::none || !tick.changed ||
                    !settle_manual_cuts()) return result(false, "native_step_failed");
            }
        }
        return Value(outward(delivered, owned_->world->snapshot()));
    };
    // Server-owned completion IDs cannot be occupied by a client request.
    if (request && request->starts_with("native-cut-"))
        return result(false, "reserved_request");
    // Original wire comparison precedes generation lookup or translation. The
    // only cache is World's existing history; no adapter request map is created.
    if (request) for (const auto& record : snapshot.history.records) {
        if (field<std::string>(record.intent, "client") && *field<std::string>(record.intent, "client") == *client &&
            field<std::string>(record.intent, "request") && *field<std::string>(record.intent, "request") == *request) {
            auto replay = record.intent;
            replay.insert_or_assign("wire", Value(wire));
            auto delivered = owned_->world->command({bound_actor, *client}, replay, observe());
            if (field<std::string>(record.intent, "action") &&
                *field<std::string>(record.intent, "action") == "operate_hand_crank")
                return complete_crank_pulse(std::move(delivered));
            return Value(outward(delivered, snapshot));
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
    const auto occupied_by_component = [&](const Bounds& volume) {
        return std::any_of(snapshot.state.placed_components.begin(), snapshot.state.placed_components.end(),
            [&](const auto& entry) {
                return overlap(volume, component_bounds(profile_, entry.second.kind, entry.second.center));
            });
    };
    if (*action == "set_developer_conveniences") {
        if (!keys(wire, {"enabled"}) || !field<bool>(wire, "enabled")) return refuse("invalid_command");
        normalized.at("action") = Value(*action);
        normalized.emplace("enabled", wire.at("enabled"));
    } else if (*action == "harvest_source") {
        if (!keys(wire, {"target"}) || !field<std::string>(wire, "target")) return refuse("invalid_command");
        const auto& id = *field<std::string>(wire, "target");
        const bool ore = profile_.material.manual_ore && profile_.material.manual_ore->id == id;
        const auto tree = profile_.material.timber_sites.find(id);
        if (ore || tree != profile_.material.timber_sites.end()) {
            const auto observed = observe()(bound_actor);
            if (observed && observed->ready) {
                const auto& center = ore ? profile_.material.manual_ore->center : tree->second.center;
                if (!clear_harvest_path(snapshot.state, id, observed->position,
                    world::manual_cut_target(profile_, center, observed->position, ore)))
                    return refuse("source_occluded");
            }
        }
        normalized.at("action") = Value(snapshot.state.developer_conveniences ?
            "fast_harvest_source" : "harvest_source");
        normalized.emplace("target", wire.at("target"));
    } else if (*action == "finish_harvest" || *action == "cancel_harvest") {
        if (!keys(wire, {})) return refuse("invalid_command");
        normalized.at("action") = Value(*action);
    } else if (*action == "craft_foundation") {
        if (!keys(wire, {"entity"}) || !field<std::string>(wire, "entity"))
            return refuse("invalid_command");
        normalized.at("action") = Value("craft_foundation");
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("generation", Value(crafting_bench_generation(snapshot.state,
            *field<std::string>(wire, "entity"))));
    } else if (*action == "craft_component") {
        if (!keys(wire, {"entity", "component"}) || !field<std::string>(wire, "entity") ||
            !field<std::string>(wire, "component")) return refuse("invalid_command");
        normalized.at("action") = Value("craft_component");
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("generation", Value(crafting_bench_generation(snapshot.state,
            *field<std::string>(wire, "entity"))));
        normalized.emplace("component", wire.at("component"));
    } else if (*action == "field_craft") {
        if (!keys(wire, {"component"}) || !field<std::string>(wire, "component"))
            return refuse("invalid_command");
        normalized.at("action") = Value("field_craft");
        normalized.emplace("component", wire.at("component"));
    } else if (*action == "stow_fabrication_hub" || *action == "deploy_fabrication_hub") {
        const bool deploy = *action == "deploy_fabrication_hub";
        if (!keys(wire, deploy ? std::initializer_list<const char*>{"entity", "center"} :
                std::initializer_list<const char*>{"entity"}) ||
            !field<std::string>(wire, "entity")) return refuse("invalid_command");
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("generation", Value(snapshot.state.fabrication_hub &&
            snapshot.state.fabrication_hub->id == *field<std::string>(wire, "entity") ?
            snapshot.state.fabrication_hub->generation : Integer{0}));
        if (deploy) {
            const auto* point = field<Array>(wire, "center");
            if (!point || point->size() != 3) return refuse("invalid_center");
            mechanics::Point center{};
            for (std::size_t axis = 0; axis < 3; ++axis) {
                const auto* coordinate = std::get_if<Integer>(&point->at(axis).storage());
                if (!coordinate || *coordinate < -mechanics::maximum_coordinate ||
                    *coordinate > mechanics::maximum_coordinate) return refuse("invalid_center");
                center[axis] = *coordinate;
            }
            const auto volume = component_bounds(profile_, materials::Component::wooden_workbench, center);
            if (const auto* refusal = component_site_refusal(snapshot.state,
                    materials::Component::wooden_workbench, center))
                return refuse(refusal);
            if (placement_blocked(volume.center, volume.half)) return refuse("actor_occupied");
            auto proposed = snapshot.state;
            if (proposed.fabrication_hub) {
                proposed.fabrication_hub->center = center;
                proposed.fabrication_hub->holder.reset();
                const bool supported = std::any_of(proposed.foundations.begin(), proposed.foundations.end(),
                    [&](const auto& floor) { return floor.second.center == center; });
                for (const auto& [unused, solid] : arrival_geometry::supplied(proposed, height_step)) {
                    (void)unused;
                    if (solid.entity != proposed.fabrication_hub->id) continue;
                    const auto& box = solid.bounds;
                    if (placement_blocked(box.center, box.half)) return refuse("actor_occupied");
                    const auto ground = terrain_range(box.center[0], box.center[2], box.half[0], box.half[2]);
                    if (!ground) return refuse("terrain_unavailable");
                    const authority::Point low{box.center[0] - box.half[0], box.center[1] - box.half[1], box.center[2] - box.half[2]};
                    const authority::Point high{box.center[0] + box.half[0], box.center[1] + box.half[1], box.center[2] + box.half[2]};
                    if (ground->second > low[1] + 1e-9 || site_blocked(low, high)) return refuse("site_occupied");
                    if (!supported && std::abs(low[1] - center[1] * height_step) < 1e-9 && ground->first < low[1] - 0.04)
                        return refuse("support_required");
                }
                if (const auto* refusal = supplied_space_refusal(proposed)) return refuse(refusal);
            }
            if (const auto* refusal = component_space_refusal(snapshot.state,
                    materials::Component::wooden_workbench, center)) return refuse(refusal);
            normalized.emplace("center", wire.at("center"));
        }
    } else if (*action == "craft_part") {
        if (!keys(wire, {"entity", "role", "half_span"}) ||
            !field<std::string>(wire, "entity") || !field<std::string>(wire, "role") ||
            !field<Integer>(wire, "half_span")) return refuse("invalid_command");
        normalized.at("action") = Value("craft_part");
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("generation", Value(crafting_bench_generation(snapshot.state,
            *field<std::string>(wire, "entity"))));
        normalized.emplace("role", wire.at("role"));
        normalized.emplace("half_span", wire.at("half_span"));
    } else if (*action == "attach_hand_crank") {
        if (!(keys(wire, {"entity", "crank", "port"}) ||
                keys(wire, {"entity", "crank", "port", "face"})) ||
            !field<std::string>(wire, "entity") || !field<std::string>(wire, "crank") ||
            !field<Array>(wire, "port") || !gear_center(*field<Array>(wire, "port")) ||
            (wire.contains("face") &&
                (!field<Array>(wire, "face") || !gear_center(*field<Array>(wire, "face")))))
            return refuse("invalid_command");
        const auto slide = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        const auto crank = snapshot.state.crank_items.find(*field<std::string>(wire, "crank"));
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("generation", Value(slide == snapshot.state.placed_components.end() ?
            Integer{0} : slide->second.generation));
        normalized.emplace("crank", wire.at("crank"));
        normalized.emplace("crank_generation", Value(crank == snapshot.state.crank_items.end() ?
            Integer{0} : crank->second.generation));
        normalized.emplace("port", wire.at("port"));
        if (wire.contains("face")) normalized.emplace("face", wire.at("face"));
    } else if (*action == "detach_hand_crank") {
        if (!keys(wire, {"entity"}) || !field<std::string>(wire, "entity"))
            return refuse("invalid_command");
        const auto crank = snapshot.state.crank_items.find(*field<std::string>(wire, "entity"));
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("generation", Value(crank == snapshot.state.crank_items.end() ?
            Integer{0} : crank->second.generation));
    } else if (*action == "operate_hand_crank") {
        if (!keys(wire, {"entity"}) || !field<std::string>(wire, "entity"))
            return refuse("invalid_command");
        const auto crank_id = *field<std::string>(wire, "entity");
        const auto crank = snapshot.state.crank_items.find(crank_id);
        const auto input_id = crank == snapshot.state.crank_items.end() ?
            std::string{} : crank->second.attached_to.value_or("");
        const auto input = snapshot.state.placed_components.find(input_id);
        Array port;
        if (crank != snapshot.state.crank_items.end() && crank->second.port) {
            const auto& point = *crank->second.port;
            port = {Value(point[0]), Value(point[1]), Value(point[2])};
        }
        normalized.at("action") = Value(*action);
        normalized.emplace("target", Value(input_id));
        normalized.emplace("generation", Value(input == snapshot.state.placed_components.end() ?
            Integer{0} : input->second.generation));
        normalized.emplace("crank", wire.at("entity"));
        normalized.emplace("crank_generation", Value(crank == snapshot.state.crank_items.end() ?
            Integer{0} : crank->second.generation));
        normalized.emplace("port", Value(port));
        if (crank != snapshot.state.crank_items.end() && crank->second.face) {
            const auto& face = *crank->second.face;
            normalized.emplace("face", Value(Array{
                Value(face[0]), Value(face[1]), Value(face[2])}));
        }
    } else if (*action == "turn_hand_crank") {
        if (!keys(wire, {"entity"}) || !field<std::string>(wire, "entity"))
            return refuse("invalid_command");
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        const auto found = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        normalized.emplace("generation", Value(found == snapshot.state.placed_components.end() ?
            Integer{0} : found->second.generation));
    } else if (*action == "turn_slide_crank") {
        if (!keys(wire, {"entity", "port"}) || !field<std::string>(wire, "entity") ||
            !field<Array>(wire, "port")) return refuse("invalid_command");
        const auto port = gear_center(*field<Array>(wire, "port"));
        if (!port) return refuse("invalid_command");
        if (const auto* refusal = component_site_refusal(snapshot.state, std::nullopt, *port))
            return refuse(refusal);
        if (const auto* refusal = component_space_refusal(snapshot.state, std::nullopt, *port))
            return refuse(refusal);
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        const auto found = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        normalized.emplace("generation", Value(found == snapshot.state.placed_components.end() ?
            Integer{0} : found->second.generation));
        normalized.emplace("port", wire.at("port"));
    } else if (*action == "feed_broad_press" || *action == "refeed_broad_press_work") {
        const bool refeed = *action == "refeed_broad_press_work";
        if (!keys(wire, refeed ? std::initializer_list<const char*>{"entity", "work_id"} :
                std::initializer_list<const char*>{"entity"}) ||
            !field<std::string>(wire, "entity") ||
            (refeed && !field<Integer>(wire, "work_id"))) return refuse("invalid_command");
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        const auto found = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        normalized.emplace("generation", Value(found == snapshot.state.placed_components.end() ?
            Integer{0} : found->second.generation));
        if (refeed) normalized.emplace("work_id", wire.at("work_id"));
    } else if (*action == "feed_press" || *action == "refeed_press_work" ||
               *action == "compact_offcuts") {
        const bool refeed_work = *action == "refeed_press_work";
        const bool compacting = *action == "compact_offcuts";
        if (!keys(wire, refeed_work ? std::initializer_list<const char*>{"entity", "entry", "work_id"} :
                compacting ? std::initializer_list<const char*>{"entity", "entry", "drive"} :
                std::initializer_list<const char*>{"entity", "entry"}) ||
            !field<std::string>(wire, "entity") || !field<Array>(wire, "entry") ||
            (refeed_work && !field<Integer>(wire, "work_id")) ||
            (compacting && !field<std::string>(wire, "drive"))) return refuse("invalid_command");
        const auto& entry = *field<Array>(wire, "entry");
        if (entry.size() == 3) {
            mechanics::Point center{};
            bool valid = true;
            for (std::size_t axis = 0; axis < 3; ++axis) {
                const auto* coordinate = std::get_if<Integer>(&entry[axis].storage());
                if (!coordinate || *coordinate < -mechanics::maximum_coordinate ||
                    *coordinate > mechanics::maximum_coordinate) valid = false;
                else center[axis] = *coordinate;
            }
            if (valid) if (const auto* refusal = component_site_refusal(snapshot.state, std::nullopt, center))
                return refuse(refusal);
        }
        normalized.at("action") = Value(*action);
        normalized.emplace("target", wire.at("entity"));
        const auto found = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        normalized.emplace("generation", Value(found == snapshot.state.placed_components.end() ?
            Integer{0} : found->second.generation));
        normalized.emplace("entry", wire.at("entry"));
        if (refeed_work) normalized.emplace("work_id", wire.at("work_id"));
        if (compacting) normalized.emplace("drive", wire.at("drive"));
    } else if (*action == "turn_press_crank") {
        if (!keys(wire, {"entity", "drive", "exit"}) ||
            !field<std::string>(wire, "entity") || !field<std::string>(wire, "drive") ||
            !field<Array>(wire, "exit")) return refuse("invalid_command");
        const auto& exit = *field<Array>(wire, "exit");
        if (exit.size() == 3) {
            mechanics::Point center{};
            bool valid = true;
            for (std::size_t axis = 0; axis < 3; ++axis) {
                const auto* coordinate = std::get_if<Integer>(&exit[axis].storage());
                if (!coordinate || *coordinate < -mechanics::maximum_coordinate ||
                    *coordinate > mechanics::maximum_coordinate) valid = false;
                else center[axis] = *coordinate;
            }
            if (valid) if (const auto* refusal = component_site_refusal(snapshot.state, std::nullopt, center))
                return refuse(refusal);
        }
        normalized.at("action") = Value("turn_press_crank");
        normalized.emplace("target", wire.at("entity"));
        const auto found = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        normalized.emplace("generation", Value(found == snapshot.state.placed_components.end() ?
            Integer{0} : found->second.generation));
        normalized.emplace("drive", wire.at("drive"));
        normalized.emplace("exit", wire.at("exit"));
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
        // The confirmed component shape, rather than only its grid anchor,
        // reserves actor, terrain and neighboring construction clearance.
        const auto kind = materials::component_from_name(*field<std::string>(wire, "component"));
        const auto volume = component_bounds(profile_, kind, center);
        if (const auto* refusal = component_site_refusal(snapshot.state, kind, center)) return refuse(refusal);
        if (placement_blocked(volume.center, volume.half)) return refuse("actor_occupied");
        if (const auto* refusal = component_space_refusal(snapshot.state, kind, center)) return refuse(refusal);
        if (kind) {
            auto proposed = snapshot.state;
            proposed.placed_components.emplace("proposed-component", world::PlacedComponent{*kind, center, 0});
            if (const auto* refusal = supplied_space_refusal(proposed)) return refuse(refusal);
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
    } else if (*action == "place_sheet") {
        if (!keys(wire, {"center", "sheet_id"}) ||
            !field<Integer>(wire, "sheet_id")) return refuse("invalid_command");
        const auto* center = field<Array>(wire, "center");
        if (!center || center->size() != 3) return refuse("invalid_center");
        for (const auto& value : *center) {
            const auto* coordinate = std::get_if<Integer>(&value.storage());
            if (!coordinate || *coordinate < -materials::maximum_drop_coordinate ||
                *coordinate > materials::maximum_drop_coordinate)
                return refuse("invalid_center");
        }
        normalized.at("action") = Value("place_sheet");
        normalized.emplace("center", wire.at("center"));
        normalized.emplace("sheet_id", wire.at("sheet_id"));
    } else if (*action == "push_channel_sheet" || *action == "push_channel_small") {
        const bool sheet_move = *action == "push_channel_sheet";
        if (!(sheet_move ? keys(wire, {"from", "to", "sheet_id"}) &&
                    field<Integer>(wire, "sheet_id") :
                keys(wire, {"from", "to", "form"}) &&
                    field<std::string>(wire, "form"))) return refuse("invalid_command");
        for (const auto* name : {"from", "to"}) {
            const auto* point = field<Array>(wire, name);
            if (!point || point->size() != 3) return refuse("invalid_center");
            for (const auto& value : *point) {
                const auto* coordinate = std::get_if<Integer>(&value.storage());
                if (!coordinate || *coordinate < -materials::maximum_drop_coordinate ||
                    *coordinate > materials::maximum_drop_coordinate)
                    return refuse("invalid_center");
            }
        }
        normalized.at("action") = Value(*action);
        normalized.emplace("from", wire.at("from"));
        normalized.emplace("to", wire.at("to"));
        if (sheet_move) normalized.emplace("sheet_id", wire.at("sheet_id"));
        else normalized.emplace("form", wire.at("form"));
    } else if (*action == "stroke_broad_shear") {
        if (!keys(wire, {"entity", "sheet_id"}) ||
            !field<std::string>(wire, "entity") || !field<Integer>(wire, "sheet_id"))
            return refuse("invalid_command");
        normalized.at("action") = Value("stroke_broad_shear");
        normalized.emplace("target", wire.at("entity"));
        normalized.emplace("sheet_id", wire.at("sheet_id"));
        const auto found = snapshot.state.placed_components.find(*field<std::string>(wire, "entity"));
        normalized.emplace("generation", Value(found == snapshot.state.placed_components.end() ?
            Integer{0} : found->second.generation));
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
            const auto occupied = component_bounds(profile_, component.kind, component.center);
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
        if (occupied_by_component({at, half})) return refuse("occupied");
        for (const auto& external : proposed_external)
            if (occupied_by_component(external)) return refuse("occupied");
        if (proposed_supports) for (const auto& support : *proposed_supports)
            if (occupied_by_component(support)) return refuse("occupied");
        if (intersects_belt(snapshot.state, {at, half})) return refuse("occupied");
        if (placement_blocked(at, half)) return refuse("actor_occupied");
        for (const auto& external : proposed_external)
            if (placement_blocked(external.center, external.half)) return refuse("actor_occupied");
        if (proposed_supports) for (const auto& support : *proposed_supports)
            if (placement_blocked(support.center, support.half)) return refuse("actor_occupied");
        if (is_gear && intersects_belt(snapshot.state, {at, gear_axle_half_extents(selected_axis)})) return refuse("occupied");
        if (is_gear && placement_blocked(at, gear_axle_half_extents(selected_axis))) return refuse("actor_occupied");
        if (is_gear && occupied_by_component({at, gear_axle_half_extents(selected_axis)})) return refuse("occupied");
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
        const auto verified_axis = selected_axis.value_or(mechanics::Axis::x);
        for (std::size_t index = 0; index < center->size(); ++index) {
            const auto remainder = (*center)[index] % 4;
            if (remainder != 0 &&
                (index != static_cast<std::size_t>(verified_axis) ||
                 (remainder != 2 && remainder != -2))) return refuse("invalid_cell");
        }
        if (transmission_intersects_foundations(snapshot.state, *center, verified_axis, false)) return refuse("occupied");
        if (const auto* refusal = transmission_site_refusal(snapshot.state, *center, verified_axis, false)) return refuse(refusal);
        for (const auto& part : snapshot.state.topology.parts)
            if (part.role == Role::collector)
                for (const auto& external : collector_external_bounds(part.geometry.center))
                    if (transmission_intersects(external, *center, verified_axis, false)) return refuse("occupied");
        const authority::Point at{(*center)[0] * pitch / 4, anchor_height + (*center)[1] * pitch / 4, (*center)[2] * pitch / 4};
        authority::Point half{0.1, 0.1, 0.1};
        half[static_cast<std::size_t>(verified_axis)] = *span * pitch / 4;
        for (const auto& [id, component] : snapshot.state.placed_components) {
            (void)id;
            if (transmission_intersects(component_bounds(profile_, component.kind, component.center),
                    *center, verified_axis, false) &&
                !shaft_meets_component_cog(component.kind, component.center, *center,
                    verified_axis)) return refuse("occupied");
        }
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
        for (const auto& [id, component] : snapshot.state.placed_components) {
            (void)id;
            if (transmission_intersects(component_bounds(profile_, component.kind, component.center),
                    *center, verified_axis, true)) return refuse("occupied");
        }
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
        if (occupied_by_component(shell)) return refuse("occupied");
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
        for (const auto& section : sections)
            if (occupied_by_component(section)) return refuse("occupied");
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
        geometry.placed_components = snapshot.state.placed_components;
        geometry.landing_pod = snapshot.state.landing_pod;
        geometry.fabrication_hub = snapshot.state.fabrication_hub;
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
        if (const auto* refusal = supplied_space_refusal(geometry)) return refuse(refusal);
        if (const auto* refusal = support_change_refusal(snapshot.state, geometry)) return refuse(refusal);
    }
    auto delivered = owned_->world->command({bound_actor, *client}, normalized, observe());
    if (edit == "operate_hand_crank") return complete_crank_pulse(std::move(delivered));
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
    if (!settle_manual_cuts(actor)) return result(false, "native_step_failed");
    return result(true, "actor_published");
}

Value Host::actor_projection(const std::string& actor) const {
    if (!owned_) return result(false, "not_initialized");
    const auto found = owned_->actors.find(actor);
    if (found == owned_->actors.end()) return result(false, "unknown_actor");
    const auto& current = found->second;
    return Value(Object{{"accepted", Value(true)}, {"ready", Value(current.ready)},
        {"position", point_value(current.position)}, {"native_epoch", Value(current.epoch)},
        {"harvest_clear", Value(harvest_clearances(owned_->world->snapshot().state, current))}});
}

Value Host::invalidate_actor(const std::string& actor) {
    if (!owned_ || !owned_->actors.contains(actor)) return result(false, "unknown_actor");
    // Retain the last ordinal so invalidation cannot permit a stale sample.
    owned_->actors.at(actor).ready = false;
    if (!settle_manual_cuts(actor)) return result(false, "native_step_failed");
    return result(true, "actor_invalidated");
}

Value Host::advance() {
    if (!owned_) return result(false, "not_initialized");
    const auto tick = owned_->world->tick(observe());
    if (tick.error != world::TransactionError::none) return result(false, "native_step_failed");
    if (!settle_manual_cuts()) return result(false, "native_step_failed");
    return projection();
}

Value Host::advance_tick_fields() {
    if (!owned_) return result(false, "not_initialized");
    const auto tick = owned_->world->tick(observe());
    if (tick.error != world::TransactionError::none) return result(false, "native_step_failed");
    if (!settle_manual_cuts()) return result(false, "native_step_failed");
    return Value(tick_fields(owned_->world->snapshot()));
}

bool Host::settle_manual_cuts(const std::optional<std::string>& observed_actor) {
    if (!owned_->world->has_manual_cuts()) return true;
    const auto snapshot = owned_->world->snapshot();
    for (const auto& [actor, cut] : snapshot.state.manual_cuts) {
        if (observed_actor && actor != *observed_actor) continue;
        const bool ore = profile_.material.manual_ore &&
            profile_.material.manual_ore->id == cut.target;
        const auto tree = profile_.material.timber_sites.find(cut.target);
        if (!ore && tree == profile_.material.timber_sites.end()) return false;
        const auto& center = ore ? profile_.material.manual_ore->center : tree->second.center;
        const auto sampled = observe()(actor);
        auto actor_cut = sampled.value_or(authority::ActorCut{});
        actor_cut.build_reach = profile_.manual_cut_reach > 0 ?
            profile_.manual_cut_reach : profile_.build_reach;
        const auto target = world::manual_cut_target(profile_, center, actor_cut.position, ore);
        const bool lost_reach = !sampled || authority::check_reach(actor, actor_cut,
            {target}).error != authority::Error::none ||
            !clear_harvest_path(snapshot.state, cut.target, actor_cut.position, target);
        const bool interrupted = cut.interrupted_revision != 0 || lost_reach;
        if (!interrupted && cut.remaining_ticks != 0) continue;
        const Object wire{{"context", Value(snapshot.history.context)},
            {"client", Value(actor)},
            {"request", Value(std::string("native-cut-") +
                (interrupted ? "cancel-" : "finish-") + actor +
                "-" + std::to_string(cut.start_revision))},
            {"action", Value(interrupted ? "cancel_harvest" : "finish_harvest")}};
        Object normalized = wire;
        normalized.emplace("actor", Value(actor));
        normalized.emplace("wire", Value(wire));
        const auto delivered = owned_->world->command({actor, actor}, normalized, observe());
        if (!delivered.completed()) return false;
        if (!interrupted && !*field<bool>(*delivered.result, "accepted")) {
            // A changed custody or reach condition can refuse contact after
            // its final tick. Release the source instead of retrying a ready
            // cut forever under the same request identity.
            Object cancel_wire{{"context", Value(snapshot.history.context)},
                {"client", Value(actor)},
                {"request", Value("native-cut-cancel-" + actor + "-" +
                    std::to_string(cut.start_revision))},
                {"action", Value("cancel_harvest")}};
            Object cancel = cancel_wire;
            cancel.emplace("actor", Value(actor));
            cancel.emplace("wire", Value(cancel_wire));
            const auto canceled = owned_->world->command({actor, actor}, cancel, observe());
            if (!canceled.completed() || !*field<bool>(*canceled.result, "accepted")) return false;
        }
    }
    return true;
}

Object Host::tick_fields(const world::Snapshot& snapshot) const {
    const auto& state = snapshot.state;
    const bool copper = copper_forms(profile_.material);
    Object manual_cuts, cargo;
    for (const auto& [actor, cut] : state.manual_cuts)
        manual_cuts.emplace(actor, Value(Object{{"target", Value(cut.target)},
            {"remaining_ticks", Value(cut.remaining_ticks)},
            {"duration_ticks", Value(world::manual_cut_ticks)},
            {"interrupted", Value(cut.interrupted_revision != 0)}}));
    for (const auto& [actor, contents] : state.material.cargo)
        cargo.emplace(actor, cargo_value(contents,
            profile_.material.manual_ore.has_value() || !profile_.material.timber_sites.empty(), copper));
    Array dropped_material;
    for (const auto& [point, contents] : state.material.dropped_material) {
        auto drop = std::get<Object>(cargo_value(contents, false, copper).storage());
        drop.emplace("center", Value(Array{Value(point[0]), Value(point[1]), Value(point[2])}));
        dropped_material.emplace_back(std::move(drop));
    }
    Object belt_spans;
    Integer span_order = 0;
    // The validated ledger bounds this raw-equivalent total by initial stock.
    // Finished products are not unprocessed blanks.
    Integer belt_raw_units = 0;
    for (const auto& span : state.topology.belt_spans) {
        const auto& lane = state.material.belt_lanes.at(span.geometry.id);
        Array slots;
        for (const auto& item : lane.slots) {
            slots.push_back(item ? cargo_value(*item, false, copper) : Value(nullptr));
            if (!item) continue;
            belt_raw_units += item->raw_units;
            for (const auto& lot : item->work_lots) belt_raw_units += lot.recipe.input_units_per_product;
        }
        belt_spans.emplace(span.geometry.id, Value(Object{{"generation", Value(span.generation)},
            {"order", Value(span_order++)}, {"from", Value(span.geometry.first_shaft)}, {"to", Value(span.geometry.last_shaft)},
            {"phase", Value(lane.phase)}, {"slots", Value(std::move(slots))}}));
    }
    Integer player = 0;
    for (const auto& [actor, contents] : state.material.cargo) {
        (void)actor;
        player += contents.products;
    }
    const auto& stock = state.material.stock;
    Object stock_fields{{"source", Value(stock.source)}, {"collector", Value(stock.collector)},
        {"belt", Value(stock.belt)}, {"input", Value(stock.input)},
        {"held", Value(state.material.processing ? state.material.processing->recipe.input_units_per_product : 0)},
        {"output", Value(stock.output)}, {"player", Value(player)}};
    if (copper) stock_fields.emplace("offcuts", Value(stock.offcuts));
    Object fields{{"revision", Value(snapshot.revision)},
        {"order", Value(snapshot.history.order)},
        {"manual_cuts", Value(std::move(manual_cuts))},
        {"cargo", Value(std::move(cargo))},
        {"belt_spans", Value(std::move(belt_spans))}, {"line_belt_raw", Value(belt_raw_units)},
        {"dropped_material", Value(std::move(dropped_material))},
        {"stock", Value(std::move(stock_fields))},
        {"remaining", Value(state.material.processing ? state.material.processing->remaining_ticks : 0)}};
    if (state.landing_pod) fields.emplace("slide_phases", Value(slide_phase_projection(state)));
    if (copper) fields.emplace("material_mass", material_mass_value(state.material, profile_.material));
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
        Object projected_ore{{"kind", Value("ore_deposit")},
            {"position", site_position(ore.center)}, {"initial", Value(profile_.initial_units)},
            {"remaining", Value(state.material.stock.source)}};
        if (profile_.manual_ore_contact_bounds) {
            const auto& [low, high] = *profile_.manual_ore_contact_bounds;
            projected_ore.emplace("contact_bounds", Value(Array{point_value(low), point_value(high)}));
        }
        sources.emplace(ore.id, Value(std::move(projected_ore)));
        fields.emplace("hand_sources", Value(std::move(sources)));
    }
    return fields;
}

Value Host::projection() const {
    if (!owned_) return result(false, "not_initialized");
    const auto snapshot = owned_->world->snapshot();
    const auto& state = snapshot.state;
    const auto support_layout = transmission_supports(state);
    Object entities, transmissions, inventories, cargo, kits, specifications, actors, foundations, manual_cuts;
    Array links, drive_links, engagements;
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
    for (const auto& link : state.topology.material_links) links.emplace_back(Array{Value(link.from.id), Value(link.to.id)});
    const auto power = world::drive_power(profile_, state);
    Object motions;
    for (const auto& [id, motion] : power.mechanical.motion) {
        Object projected{{"state", Value(mechanics::motion_state_name(motion.state))},
            {"numerator", Value(motion.rate.numerator)}, {"denominator", Value(motion.rate.denominator)}};
        const auto load = power.load.find(id);
        if (load != power.load.end()) {
            projected.emplace("capacity", Value(load->second.capacity));
            projected.emplace("impact", Value(load->second.impact));
            projected.emplace("overloaded", Value(load->second.overloaded));
            if (load->second.overloaded) {
                projected.emplace("limiting_part", Value(load->second.limiting_part));
                if (!load->second.limiting_part.empty()) {
                    const auto found = state.placed_components.find(load->second.limiting_part);
                    if (found != state.placed_components.end())
                        projected.emplace("limiting_kind", Value(materials::component_name(found->second.kind)));
                }
                projected.emplace("remedy", Value(load->second.limiting_part.empty() ?
                    "add_power_or_reduce_load" : "replace_with_copper_or_split_load"));
            }
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
    for (const auto& [actor, contents] : state.material.cargo) {
        inventories.emplace(actor, Value(contents.products));
        cargo.emplace(actor, cargo_value(contents,
            profile_.material.manual_ore.has_value() || !profile_.material.timber_sites.empty(),
            copper_forms(profile_.material)));
    }
    for (const auto& [actor, kit] : state.kits) {
        auto projected_kit = std::get<Object>(kit_value(kit).storage());
        projected_kit.emplace("foundation", Value(state.foundation_kits.at(actor)));
        kits.emplace(actor, Value(std::move(projected_kit)));
        Array entries;
        std::set<stationary::PartSpec> offered;
        for (const auto& [specification, initial] : profile_.finite_parts) {
            (void)initial;
            offered.insert(specification);
        }
        for (const auto& [specification, cost] : profile_.fabrication_parts) {
            (void)cost;
            offered.insert(specification);
        }
        for (const auto& specification : offered) {
            const auto found = kit.find(specification);
            entries.emplace_back(Object{{"kind", Value(kind(specification.role))},
                {"teeth", Value(specification.teeth)}, {"half_span", Value(specification.half_span)},
                {"count", Value(found == kit.end() ? 0 : found->second)}});
        }
        specifications.emplace(actor, Value(std::move(entries)));
    }
    for (const auto& [actor, sample] : owned_->actors) actors.emplace(actor, Value(Object{
        {"position", point_value(sample.position)}, {"capabilities", Value(Object{
            {"build_reach", Value(profile_.build_reach)},
            {"harvest_reach", Value(profile_.manual_cut_reach > 0 ?
                profile_.manual_cut_reach : profile_.build_reach)}})},
        {"ready", Value(sample.ready)}, {"native_epoch", Value(sample.epoch)},
        {"harvest_clear", Value(harvest_clearances(state, sample))}}));
    for (const auto& [actor, cut] : state.manual_cuts)
        manual_cuts.emplace(actor, Value(Object{{"target", Value(cut.target)},
            {"remaining_ticks", Value(cut.remaining_ticks)},
            {"duration_ticks", Value(world::manual_cut_ticks)},
            {"interrupted", Value(cut.interrupted_revision != 0)}}));
    Array mineral_cells;
    for (const auto& cell : mineral_site::opening_cells)
        mineral_cells.emplace_back(Array{Value(cell.x), Value(cell.z)});
    const auto local = world::machine_power(state.topology, power);
    for (const auto& [id, foundation] : state.foundations)
        foundations.emplace(id, Value(Object{{"cell", Value(Array{Value(foundation.center[0] / 4), Value(foundation.center[2] / 4)})},
            {"level", Value(foundation.center[1])}, {"generation", Value(foundation.generation)}}));
    auto player_parts = std::get<Object>(kit_value(state.kits.at("P")).storage());
    player_parts.emplace("foundation", Value(state.foundation_kits.at("P")));
    Object projection{{"context", Value(snapshot.history.context)},
        {"order", Value(snapshot.history.order)}, {"initial_feed", Value(profile_.initial_units)},
        {"recipe_input", Value(profile_.material.input_units_per_product)}, {"entities", Value(std::move(entities))},
        {"transmission_parts", Value(std::move(transmissions))}, {"links", Value(std::move(links))},
        {"drive_links", Value(std::move(drive_links))}, {"engagements", Value(std::move(engagements))},
        {"motion", Value(std::move(motions))}, {"inventories", Value(std::move(inventories))},
        {"cargo", Value(std::move(cargo))}, {"part_kits", Value(std::move(kits))},
        {"part_specifications", Value(std::move(specifications))},
        {"parts", Value(std::move(player_parts))}, {"actors", Value(std::move(actors))},
        {"manual_cuts", Value(std::move(manual_cuts))},
        {"foundations", Value(std::move(foundations))},
        {"source_deposit", Value(Object{{"id", Value(profile_.material.manual_ore ?
            profile_.material.manual_ore->id : std::string{})},
            {"cells", Value(std::move(mineral_cells))}, {"initial_units", Value(profile_.initial_units)},
            {"collector_capacity", Value(profile_.material.collector_capacity)},
            {"maximum_depth", Value(mineral_site::extraction_depth_steps * height_step)}})},
        {"powered", Value(local.collector || local.belt || local.processor)},
        {"power_enabled", Value(state.topology.drive_enabled)},
        {"options", Value(Object{{"opening", Value(true)}, {"physical", Value(true)}, {"native", Value(true)},
            {"foundations", Value(true)}, {"developer_conveniences", Value(state.developer_conveniences)}})},
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
        Object supplied;
        for (const auto& [id, solid] : arrival_geometry::supplied(state, height_step))
            supplied.emplace(id, Value(Object{{"entity", Value(solid.entity)},
                {"generation", Value(solid.generation)}, {"center", point_value(solid.bounds.center)},
                {"half", point_value(solid.bounds.half)}}));
        projection.emplace("supplied_hardware_boxes", Value(std::move(supplied)));
        projection.emplace("landing_pod", Value(Object{{"id", Value(pod.id)},
            {"generation", Value(pod.generation)},
            {"center", Value(Array{Value(pod.center[0] / height_denominator),
                Value(pod.center[1]), Value(pod.center[2] / height_denominator)})},
            {"deployed", Value(true)}, {"hub_ready", Value(state.fabrication_hub &&
                !state.fabrication_hub->holder)}}));
        const auto& hub = *state.fabrication_hub;
        projection.emplace("fabrication_hub", Value(Object{{"id", Value(hub.id)},
            {"generation", Value(hub.generation)},
            {"installed", Value(!hub.holder)},
            {"holder", hub.holder ? Value(*hub.holder) : Value(nullptr)},
            {"center", Value(Array{Value(hub.center[0] / height_denominator),
                Value(hub.center[1]), Value(hub.center[2] / height_denominator)})},
            {"position", Value(Array{Value(hub.center[0] * profile_.meters_per_grid_unit + profile_.anchor_offset[0]),
                Value(hub.center[1] * profile_.meters_per_grid_unit + profile_.anchor_offset[1]),
                Value(hub.center[2] * profile_.meters_per_grid_unit + profile_.anchor_offset[2])})}}));
        Array benches;
        for (const auto& [id, placed] : state.placed_components)
            if (placed.kind == materials::Component::wooden_workbench)
                benches.emplace_back(Object{{"id", Value(id)},
                    {"generation", Value(placed.generation)},
                    {"center", Value(Array{Value(placed.center[0] / height_denominator),
                        Value(placed.center[1]), Value(placed.center[2] / height_denominator)})},
                    {"position", Value(Array{Value(placed.center[0] * profile_.meters_per_grid_unit + profile_.anchor_offset[0]),
                        Value(placed.center[1] * profile_.meters_per_grid_unit + profile_.anchor_offset[1]),
                        Value(placed.center[2] * profile_.meters_per_grid_unit + profile_.anchor_offset[2])})}});
        projection.emplace("fabrication_benches", Value(std::move(benches)));
        Object recipes;
        for (const auto kind : {materials::Component::wooden_frame, materials::Component::wooden_shaft,
                materials::Component::wooden_cog, materials::Component::receiver_tray,
                materials::Component::tool_mount, materials::Component::sliding_guide,
                materials::Component::cutting_edge, materials::Component::anvil,
                materials::Component::ram_face, materials::Component::copper_shaft,
                materials::Component::copper_cog, materials::Component::wooden_workbench,
                materials::Component::wooden_slide, materials::Component::copper_slide,
                materials::Component::flat_head, materials::Component::hand_crank,
                materials::Component::channel_narrow_x, materials::Component::channel_narrow_z,
                materials::Component::channel_broad_x, materials::Component::channel_broad_z}) {
            const auto cost = materials::component_cost(kind);
            if (cost) {
                Object recipe{{"timber", Value(cost->timber)}, {"copper", Value(cost->ore)}};
                if (const auto rating = world::placed_drive_load_rating(kind))
                    recipe.emplace("load_rating", Value(*rating));
                recipes.emplace(materials::component_name(kind), Value(std::move(recipe)));
            }
        }
        projection.emplace("component_recipes", Value(std::move(recipes)));
        Array fabrication;
        for (const auto& [spec, cost] : profile_.fabrication_parts)
            fabrication.emplace_back(Object{{"kind", Value(kind(spec.role))},
                {"teeth", Value(spec.teeth)}, {"half_span", Value(spec.half_span)},
                {"timber", Value(cost.timber)}, {"copper", Value(cost.ore)}});
        projection.emplace("part_recipes", Value(std::move(fabrication)));
        projection.emplace("foundation_recipe", Value(Object{{"timber", Value(world::foundation_timber_cost)},
            {"copper", Value(Integer{0})}}));
        projection.emplace("component_capacity", Value(profile_.material.component_capacity));
        Array completed;
        for (const auto& actor : state.workshop_completed_actors)
            completed.emplace_back(actor);
        projection.emplace("workshop_completed_actors", Value(std::move(completed)));
        projection.emplace("first_plate_unlock", Value(profile_.first_plate_unlock));
        Object crank_items;
        for (const auto& [id, item] : state.crank_items)
            crank_items.emplace(id, Value(Object{{"id", Value(item.id)},
                {"generation", Value(item.generation)},
                {"holder", Value(item.holder.value_or(""))},
                {"attached_to", Value(item.attached_to.value_or(""))},
                {"port", Value(item.port ? Array{Value((*item.port)[0]),
                    Value((*item.port)[1]), Value((*item.port)[2])} : Array{})},
                {"face", Value(item.face ? Array{Value((*item.face)[0]),
                    Value((*item.face)[1]), Value((*item.face)[2])} : Array{})}}));
        projection.emplace("crank_items", Value(std::move(crank_items)));
        Object placed;
        for (const auto& [id, component] : state.placed_components) {
            const auto occupied = component_bounds(profile_, component.kind, component.center);
            Object part{{"component", Value(materials::component_name(component.kind))},
                {"generation", Value(component.generation)},
                {"center", Value(Array{Value(component.center[0]), Value(component.center[1]),
                    Value(component.center[2])})},
                {"occupied", Value(Object{{"center", point_value(occupied.center)},
                    {"half", point_value(occupied.half)}})},
                {"position", Value(Array{
                    Value(component.center[0] * profile_.meters_per_grid_unit + profile_.anchor_offset[0]),
                    Value(component.center[1] * profile_.meters_per_grid_unit + profile_.anchor_offset[1]),
                    Value(component.center[2] * profile_.meters_per_grid_unit + profile_.anchor_offset[2])})}};
            if (component.kind == materials::Component::wooden_slide ||
                component.kind == materials::Component::copper_slide) {
                Array ports;
                for (const Integer direction : {-1, 1})
                    ports.emplace_back(Array{Value(component.center[0] + direction),
                        Value(component.center[1]), Value(component.center[2])});
                part.emplace("input_ports", Value(std::move(ports)));
            } else if (component.kind == materials::Component::tool_mount ||
                component.kind == materials::Component::wooden_shaft ||
                component.kind == materials::Component::copper_shaft) {
                part.emplace("input_ports", Value(Array{Value(Array{
                    Value(component.center[0]), Value(component.center[1]),
                    Value(component.center[2])})}));
            }
            if (const auto axis = power.crank_axes.find(id); axis != power.crank_axes.end())
                part.emplace("crank_axis", Value(static_cast<Integer>(axis->second)));
            placed.emplace(id, Value(std::move(part)));
        }
        projection.emplace("placed_components", Value(std::move(placed)));
        projection.emplace("slide_phases", Value(slide_phase_projection(state)));
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
        Array presses;
        for (const auto& frame : parts) {
            if (frame.kind != materials::Component::wooden_frame) continue;
            const auto inspection = assembly::inspect_press(parts, frame.center);
            Object entry{{"frame", Value(frame.id)},
                {"center", Value(Array{Value(frame.center[0]), Value(frame.center[1]),
                    Value(frame.center[2])})},
                {"status", Value(press_status_name(inspection.status))}};
            if (inspection.press) {
                const auto& press = *inspection.press;
                entry.emplace("parts", Value(Object{{"frame", Value(press.frame)},
                    {"anvil", Value(press.anvil)}, {"ram", Value(press.ram)},
                    {"guide", Value(press.guide)}, {"mount", Value(press.mount)},
                    {"shaft", Value(press.shaft)}, {"drive_cog", Value(press.drive_cog)}}));
                entry.emplace("work_center", Value(Array{Value(press.work_center[0]),
                    Value(press.work_center[1]), Value(press.work_center[2])}));
                entry.emplace("shaft_center", Value(Array{Value(press.shaft_center[0]),
                    Value(press.shaft_center[1]), Value(press.shaft_center[2])}));
                entry.emplace("cog_center", Value(Array{Value(press.cog_center[0]),
                    Value(press.cog_center[1]), Value(press.cog_center[2])}));
                entry.emplace("shaft_material", Value(materials::component_name(press.shaft_material)));
                entry.emplace("cog_material", Value(materials::component_name(press.cog_material)));
                Array feeds;
                for (const auto& feed : press.open_feeds)
                    feeds.emplace_back(Object{{"entry", Value(Array{Value(feed.entry[0]),
                        Value(feed.entry[1]), Value(feed.entry[2])})},
                        {"exit", Value(Array{Value(feed.exit[0]), Value(feed.exit[1]),
                            Value(feed.exit[2])})}});
                entry.emplace("open_feeds", Value(std::move(feeds)));
            }
            presses.emplace_back(std::move(entry));
        }
        projection.emplace("press_assemblies", Value(std::move(presses)));
        Array guided_presses;
        for (const auto& anvil : parts) {
            if (anvil.kind != materials::Component::anvil) continue;
            const auto inspection = assembly::inspect_guided_press(parts, anvil.center);
            Object entry{{"anvil", Value(anvil.id)},
                {"center", Value(Array{Value(anvil.center[0]), Value(anvil.center[1]),
                    Value(anvil.center[2])})},
                {"status", Value(press_status_name(inspection.status))}};
            if (inspection.press) {
                const auto& press = *inspection.press;
                entry.emplace("parts", Value(Object{{"anvil", Value(press.anvil)},
                    {"ram", Value(press.ram)}, {"guide", Value(press.guide)},
                    {"shaft", Value(press.shaft)}, {"drive_cog", Value(press.drive_cog)}}));
                entry.emplace("work_center", Value(Array{Value(press.work_center[0]),
                    Value(press.work_center[1]), Value(press.work_center[2])}));
                entry.emplace("shaft_center", Value(Array{Value(press.shaft_center[0]),
                    Value(press.shaft_center[1]), Value(press.shaft_center[2])}));
                entry.emplace("cog_center", Value(Array{Value(press.cog_center[0]),
                    Value(press.cog_center[1]), Value(press.cog_center[2])}));
                entry.emplace("shaft_material", Value(materials::component_name(press.shaft_material)));
                entry.emplace("cog_material", Value(materials::component_name(press.cog_material)));
                if (press.plate_receiver) {
                    const auto& receiver = *press.plate_receiver;
                    entry.emplace("plate_receiver", Value(Array{Value(receiver[0]),
                        Value(receiver[1]), Value(receiver[2])}));
                    const auto dropped = state.material.dropped_material.find(receiver);
                    entry.emplace("plate_count", Value(dropped == state.material.dropped_material.end() ?
                        Integer{0} : dropped->second.products));
                    entry.emplace("plate_capacity", Value(materials::press_plate_receiver_capacity));
                }
                if (press.offcut_receiver) {
                    const auto& receiver = *press.offcut_receiver;
                    entry.emplace("offcut_receiver", Value(Array{Value(receiver[0]),
                        Value(receiver[1]), Value(receiver[2])}));
                    const auto dropped = state.material.dropped_material.find(receiver);
                    entry.emplace("offcut_count", Value(dropped == state.material.dropped_material.end() ?
                        Integer{0} : dropped->second.offcuts));
                    entry.emplace("offcut_capacity", Value(materials::press_offcut_receiver_capacity));
                }
                Array feeds;
                for (const auto& feed : press.open_feeds)
                    feeds.emplace_back(Object{{"entry", Value(Array{Value(feed.entry[0]),
                        Value(feed.entry[1]), Value(feed.entry[2])})},
                        {"exit", Value(Array{Value(feed.exit[0]), Value(feed.exit[1]),
                            Value(feed.exit[2])})}});
                entry.emplace("open_feeds", Value(std::move(feeds)));
            }
            guided_presses.emplace_back(std::move(entry));
        }
        projection.emplace("guided_press_assemblies", Value(std::move(guided_presses)));
        Array sliding_presses;
        std::set<mechanics::Point> belt_tiles;
        std::map<mechanics::Point, std::pair<int, int>> mouth_roles;
        // World accepts press handoff only at a full-tile belt endpoint.
        // Index all lanes once so each workbed reads only its two X mouths.
        for (const auto& span : state.topology.belt_spans) {
            const auto* first = find(state, span.geometry.first_shaft);
            const auto* last = find(state, span.geometry.last_shaft);
            if (!first || !last) continue;
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (!path) continue;
            belt_tiles.insert(path->tiles.begin(), path->tiles.end());
            const auto motion = power.mechanical.motion.find(span.geometry.first_shaft);
            if (motion == power.mechanical.motion.end() ||
                motion->second.state != mechanics::MotionState::rotating) continue;
            const auto direction = mechanics::belt_cargo_direction(first->geometry,
                last->geometry, motion->second.rate);
            if (!direction || *direction == 0) continue;
            for (const bool at_last : {false, true}) {
                const auto& mouth = at_last ? path->tiles.back() : path->tiles.front();
                auto& [inbound, outbound] = mouth_roles[mouth];
                if (at_last == (*direction > 0)) ++inbound;
                else ++outbound;
            }
        }
        for (const auto& anvil : parts) {
            if (anvil.kind != materials::Component::anvil) continue;
            const auto inspection = assembly::inspect_sliding_press(parts, anvil.center);
            const mechanics::Point west_mouth{anvil.center[0] - 4, anvil.center[1], anvil.center[2]};
            const mechanics::Point east_mouth{anvil.center[0] + 4, anvil.center[1], anvil.center[2]};
            const bool mouth_has_belt = belt_tiles.contains(west_mouth) || belt_tiles.contains(east_mouth);
            const bool manual_auto_route = profile_.landing_pod_center.has_value();
            Object entry{{"anvil", Value(anvil.id)},
                {"center", Value(Array{Value(anvil.center[0]), Value(anvil.center[1]),
                    Value(anvil.center[2])})},
                {"status", Value(press_status_name(inspection.status))}};
            if (manual_auto_route && (inspection.status == assembly::PressStatus::ready ||
                    inspection.status == assembly::PressStatus::blocked_feed))
                entry.emplace("auto_route", Value(true));
            if (inspection.press) {
                const auto& press = *inspection.press;
                entry.emplace("parts", Value(Object{{"anvil", Value(press.anvil)},
                    {"head", Value(press.head)}, {"slide", Value(press.slide)}}));
                entry.emplace("work_center", Value(Array{Value(press.work_center[0]),
                    Value(press.work_center[1]), Value(press.work_center[2])}));
                entry.emplace("slide_center", Value(Array{Value(press.slide_center[0]),
                    Value(press.slide_center[1]), Value(press.slide_center[2])}));
                entry.emplace("slide_material", Value(materials::component_name(press.slide_material)));
                if (const auto selected = snapshot.state.slide_press_routes.find(press.work_center);
                    selected != snapshot.state.slide_press_routes.end())
                    entry.emplace("selected_exit", Value(Array{Value(selected->second[0]),
                        Value(selected->second[1]), Value(selected->second[2])}));
                Array feeds;
                const auto selected = state.slide_press_routes.find(press.work_center);
                const auto route_score = [&](const assembly::PressFeed& feed) {
                    const auto entry_mouth = feed.entry[0] < press.work_center[0] ? west_mouth : east_mouth;
                    const auto exit_mouth = feed.exit[0] < press.work_center[0] ? west_mouth : east_mouth;
                    const auto [input_in, input_out] = mouth_roles[entry_mouth];
                    const auto [output_in, output_out] = mouth_roles[exit_mouth];
                    return input_out || output_in ? 0 : input_in + output_out;
                };
                int candidate_count = 0;
                mechanics::Point inferred_exit{};
                if (manual_auto_route && mouth_has_belt && selected == state.slide_press_routes.end())
                    for (const auto& feed : press.open_feeds)
                        if (route_score(feed) > 0) { ++candidate_count; inferred_exit = feed.exit; }
                for (const auto& feed : press.open_feeds) {
                    Object route{{"entry", Value(Array{Value(feed.entry[0]),
                        Value(feed.entry[1]), Value(feed.entry[2])})},
                        {"exit", Value(Array{Value(feed.exit[0]), Value(feed.exit[1]),
                            Value(feed.exit[2])})}};
                    // Retained work keeps its native outlet. A tray on one
                    // side leaves a single physically open through-feed;
                    // only two open manual routes need the east default.
                    // A connected lane supplies a role only when exactly one
                    // route agrees with its actual cargo motion.
                    if (manual_auto_route && (selected != state.slide_press_routes.end() ?
                            feed.exit == selected->second :
                            mouth_has_belt ? candidate_count == 1 && feed.exit == inferred_exit :
                            (press.open_feeds.size() == 1 ||
                                feed.exit == mechanics::Point{press.work_center[0] + 1,
                                    press.work_center[1], press.work_center[2]})))
                        entry.emplace("auto_feed", Value(route));
                    feeds.emplace_back(std::move(route));
                }
                entry.emplace("open_feeds", Value(std::move(feeds)));
            }
            sliding_presses.emplace_back(std::move(entry));
        }
        projection.emplace("sliding_press_assemblies", Value(std::move(sliding_presses)));
        Array broad_presses, broad_shears;
        std::set<mechanics::Point> anvil_centers;
        for (const auto& part : parts)
            if (part.kind == materials::Component::anvil) anvil_centers.insert(part.center);
        std::vector<mechanics::Point> broad_origins;
        for (const auto& origin : anvil_centers)
            if (anvil_centers.contains({origin[0] + 4, origin[1], origin[2]}) &&
                anvil_centers.contains({origin[0], origin[1], origin[2] + 4}) &&
                anvil_centers.contains({origin[0] + 4, origin[1], origin[2] + 4}))
                broad_origins.push_back(origin);
        const auto ids_value = [](const std::array<std::string, 4>& ids) {
            Array values;
            for (const auto& id : ids) values.emplace_back(id);
            return Value(std::move(values));
        };
        const auto grid_value = [](const mechanics::Point& center) {
            return Value(Array{Value(center[0]), Value(center[1]), Value(center[2])});
        };
        if (!broad_origins.empty()) {
            const assembly::Layout broad_layout(parts);
            const world::BroadPressDriveIndex broad_drives(power);
            for (const auto& origin : broad_origins) {
                const auto geometry = broad_layout.inspect_broad_press(origin);
                Object entry{{"origin", grid_value(origin)},
                    {"geometry_status", Value(broad_geometry_status_name(geometry.status))},
                    {"status", Value(broad_geometry_status_name(geometry.status))}};
                if (geometry.press) {
                    const auto& press = *geometry.press;
                    const auto drive = broad_drives.inspect(press);
                    entry["status"] = Value(broad_drive_status_name(drive.status));
                    Array work_centers;
                    for (const auto& center : press.work_centers)
                        work_centers.emplace_back(grid_value(center));
                    entry.emplace("work_centers", Value(std::move(work_centers)));
                    entry.emplace("parts", Value(Object{{"anvils", ids_value(press.anvils)},
                        {"rams", ids_value(press.rams)}, {"guides", ids_value(press.guides)},
                        {"shafts", ids_value(press.shafts)},
                        {"drive_cogs", ids_value(press.drive_cogs)}}));
                    Array windings;
                    for (const auto winding : drive.pad_winding)
                        windings.emplace_back(static_cast<Integer>(winding));
                    entry.emplace("pad_winding", Value(std::move(windings)));
                    if (drive.stroke_rate)
                        entry.emplace("stroke_rate", Value(Array{Value(drive.stroke_rate->numerator),
                            Value(drive.stroke_rate->denominator)}));
                }
                broad_presses.emplace_back(std::move(entry));
                const auto cutting = broad_layout.inspect_broad_shear(origin);
                Object shear_entry{{"origin", grid_value(origin)},
                    {"geometry_status", Value(broad_shear_status_name(cutting.status))},
                    {"status", Value(broad_shear_status_name(cutting.status))}};
                if (cutting.shear) {
                    const auto& shear = *cutting.shear;
                    const auto drive = broad_drives.inspect(shear);
                    shear_entry["status"] = Value(broad_drive_status_name(drive.status));
                    shear_entry.emplace("parts", Value(Object{
                        {"anvils", ids_value(shear.anvils)},
                        {"blades", ids_value(shear.blades)},
                        {"guides", ids_value(shear.guides)},
                        {"shafts", ids_value(shear.shafts)},
                        {"drive_cogs", ids_value(shear.drive_cogs)}}));
                    const auto staged = state.material.dropped_material.find(origin);
                    if (staged != state.material.dropped_material.end() &&
                        staged->second.sheets.size() == 1) {
                        const auto sheet_id = staged->second.sheets.front().id;
                        shear_entry.emplace("sheet_id", Value(sheet_id));
                        const auto progress = state.shear_progress.find(sheet_id);
                        shear_entry.emplace("strokes", Value(progress == state.shear_progress.end() ?
                            Integer{0} : progress->second.strokes));
                    }
                }
                broad_shears.emplace_back(std::move(shear_entry));
            }
        }
        projection.emplace("broad_press_assemblies", Value(std::move(broad_presses)));
        projection.emplace("broad_shear_assemblies", Value(std::move(broad_shears)));
    }
    projection.merge(tick_fields(snapshot));
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
    if (const auto* refusal = supplied_space_refusal(snapshot.state)) return {nullptr, refusal};
    if (snapshot.state.fabrication_hub && !snapshot.state.fabrication_hub->holder &&
        profile_.landing_pod_center && snapshot.state.fabrication_hub->center !=
            world::landing_hub_center(*profile_.landing_pod_center)) {
        const auto center = snapshot.state.fabrication_hub->center;
        if (const auto* refusal = component_site_refusal(snapshot.state,
                materials::Component::wooden_workbench, center))
            return {nullptr, refusal};
        if (const auto* refusal = component_space_refusal(snapshot.state,
                materials::Component::wooden_workbench, center)) return {nullptr, refusal};
    }
    for (const auto& [id, component] : snapshot.state.placed_components) {
        if (const auto* refusal = component_site_refusal(snapshot.state, component.kind, component.center))
            return {nullptr, refusal};
        if (const auto* refusal = component_space_refusal(snapshot.state, component.kind,
                component.center, &id)) return {nullptr, refusal};
    }
    const auto restored_supports = transmission_supports(snapshot.state);
    for (const auto& record : snapshot.history.records) {
        if (!field<Object>(record.intent, "wire")) return {nullptr, "missing_wire_history"};
        if (!historical_wire(record)) return {nullptr, "inconsistent_wire_history"};
        if (const auto* action = field<std::string>(record.intent, "action");
            action && *action == "turn_slide_crank" &&
            field<bool>(record.result, "accepted") &&
            *field<bool>(record.result, "accepted")) {
            const auto* value = field<Array>(record.intent, "port");
            const auto port = value ? gear_center(*value) : std::nullopt;
            if (!port || component_site_refusal(snapshot.state, std::nullopt, *port))
                return {nullptr, "inconsistent_wire_history"};
        }
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
        // Match ActorWorld's existing 1 mm contact margin. Saved positions
        // inside supplied solid hardware are invalid, rather than migrated.
        for (const auto& [unused, solid] : arrival_geometry::supplied(snapshot.state, height_step)) {
            (void)unused;
            if (capsule_intersects(*at, solid.bounds, 0.001)) return {nullptr, "actor_inside_supplied_hardware"};
        }
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
