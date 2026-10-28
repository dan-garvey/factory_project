#include "physical_geometry.hpp"
#include "factory/mineral_site.hpp"
#include "factory/site_geometry_contract.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace factory::godot_world::physical_geometry {
namespace {
using Role = stationary::Role;
using Integer = mechanics::Integer;
using site_geometry::pitch;
using site_geometry::height_denominator;
using site_geometry::height_step;
using site_geometry::foundation_depth;
using site_geometry::anchor_height;
using site_geometry::capsule_radius;
using site_geometry::capsule_height;
using site_geometry::machine_width;
using site_geometry::machine_height;
using site_geometry::machine_center_height;
}  // namespace

bool capsule_intersects(const authority::Point& actor, const Bounds& box, double tolerance) {
    const auto dx = std::max(std::abs(actor[0] - box.center[0]) - box.half[0], 0.0);
    const auto dz = std::max(std::abs(actor[2] - box.center[2]) - box.half[2], 0.0);
    const auto segment_half = capsule_height / 2 - capsule_radius;
    const auto below = box.center[1] - box.half[1] - (actor[1] + segment_half);
    const auto above = actor[1] - segment_half - (box.center[1] + box.half[1]);
    const auto dy = std::max({below, above, 0.0});
    const auto radius = capsule_radius - tolerance;
    return dx * dx + dy * dy + dz * dz < radius * radius;
}

// The fixed bearings stand just outside the rotating disc. Terrain supplies
// their lower seats; neither the player wire nor saved state supplies a pose.
std::optional<std::array<Bounds, 2>> wheel_support_bounds(const mechanics::Point& center,
        mechanics::Axis axis, const TerrainRange& terrain_range) {
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

bool slide_head_fitting(std::optional<materials::Component> first,
        const mechanics::Point& first_center, materials::Component second,
        const mechanics::Point& second_center) {
    const auto slide = [](materials::Component kind) {
        return kind == materials::Component::wooden_slide ||
            kind == materials::Component::copper_slide;
    };
    if (!first) return false;
    if (*first == materials::Component::broad_flat_head &&
        second == materials::Component::broad_copper_slide)
        return second_center == mechanics::Point{first_center[0],
            first_center[1] + 3, first_center[2]};
    if (*first == materials::Component::broad_copper_slide &&
        second == materials::Component::broad_flat_head)
        return first_center == mechanics::Point{second_center[0],
            second_center[1] + 3, second_center[2]};
    if (first_center[0] != second_center[0] ||
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

bool frame_anvil_fitting(std::optional<materials::Component> first,
        const mechanics::Point& first_center, materials::Component second,
        const mechanics::Point& second_center) {
    if (!first || first_center[0] != second_center[0] ||
        first_center[2] != second_center[2]) return false;
    // The open framed press receives the anvil on its lower shelf.
    // Their conservative occupied boxes overlap, but their actual bodies do not.
    return (*first == materials::Component::anvil &&
               second == materials::Component::wooden_frame &&
               first_center[1] == second_center[1] + 1) ||
        (*first == materials::Component::wooden_frame &&
               second == materials::Component::anvil &&
               second_center[1] == first_center[1] + 1);
}

bool workbed_tray_fitting(std::optional<materials::Component> first,
        const mechanics::Point& first_center, materials::Component second,
        const mechanics::Point& second_center) {
    // A low receiver fits below the workbed's side overhang. The legs stay
    // inside the workcell; only their conservative occupied boxes overlap.
    if (!first) return false;
    const auto paired = (*first == materials::Component::anvil &&
            second == materials::Component::receiver_tray) ||
        (*first == materials::Component::receiver_tray &&
            second == materials::Component::anvil);
    return paired && first_center[0] == second_center[0] &&
        first_center[1] == second_center[1] &&
        std::abs(first_center[2] - second_center[2]) == 1;
}

bool frame_ram_fitting(std::optional<materials::Component> first,
        const mechanics::Point& first_center, materials::Component second,
        const mechanics::Point& second_center) {
    if (!first || first_center[0] != second_center[0] ||
        first_center[2] != second_center[2]) return false;
    // The frame's open upper bed surrounds the long central ram stroke.
    return (*first == materials::Component::ram_face &&
               second == materials::Component::wooden_frame &&
               first_center[1] == second_center[1] + 2) ||
        (*first == materials::Component::wooden_frame &&
               second == materials::Component::ram_face &&
               second_center[1] == first_center[1] + 2);
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

const stationary::PlacedPart* find_part(const world::State& state, const std::string& id) {
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
            half[axle] = site_geometry::belt_frame_outer_half_width;
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
        half[axle] = site_geometry::belt_frame_outer_half_width;
        result.push_back({center, half});
        return result;
    }
    const auto direction = first.axis == mechanics::Axis::x ? std::size_t{2} : std::size_t{0};
    for (const auto& point : path->tiles) {
        authority::Point half{0.3, 0.15, 0.3}; half[direction] = pitch / 2;
        half[static_cast<std::size_t>(first.axis)] = site_geometry::belt_frame_outer_half_width;
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

bool intersects_belt(const world::State& state, const Bounds& bounds,
                     const std::string* fitted_shaft) {
    const auto* fitted = fitted_shaft ? find_part(state, *fitted_shaft) : nullptr;
    for (const auto& span : state.topology.belt_spans) {
        const auto* first = find_part(state, span.geometry.first_shaft);
        const auto* last = find_part(state, span.geometry.last_shaft);
        // Endpoint and intermediate pulleys share a bearing with their own
        // stand. Other supports and placed parts collide with the full belt.
        if (fitted && fitted->role == Role::shaft && first && last &&
            fitted->geometry.axis == first->geometry.axis) {
            const auto path = mechanics::belt_path(first->geometry, last->geometry);
            if (path && std::find(path->tiles.begin(), path->tiles.end(),
                                  fitted->geometry.center) != path->tiles.end()) continue;
        }
        if (first && last && belt_intersects(first->geometry, last->geometry, bounds)) return true;
    }
    return false;
}

}  // namespace factory::godot_world::physical_geometry
