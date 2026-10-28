#include "complete_projection.hpp"

#include "arrival_site_projection.hpp"
#include "assembly_projection.hpp"
#include "build_catalog_projection.hpp"
#include "drive_projection.hpp"
#include "material_projection.hpp"
#include "topology_projection.hpp"
#include "physical_geometry.hpp"
#include "factory/mineral_site.hpp"
#include "factory/physical_site.hpp"
#include "factory/projection_contract.hpp"
#include "factory/site_geometry_contract.hpp"

#include <utility>

namespace factory::godot_world::complete_projection {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
using Role = stationary::Role;
using material_projection::point_value;
using material_projection::tick_fields;
using physical_geometry::wheel_support_bounds;
using site_geometry::pitch;
using site_geometry::height_denominator;
using site_geometry::height_step;
using site_geometry::foundation_depth;
using site_geometry::anchor_height;
using site_geometry::capsule_radius;
using site_geometry::capsule_height;
constexpr Integer wheel_radius = site_geometry::wheel_radius_hundredths;
constexpr Integer wheel_axle_offset = site_geometry::wheel_axle_offset_hundredths;
}  // namespace

Object harvest_clearances(const world::Profile& profile,
        const terrain_surface::Surface& terrain, const world::State& state,
        const authority::Point& actor, bool ready) {
    Object clear;
    if (!ready) return clear;
    for (const auto& [id, path_clear] : physical_site::harvest_clearances(
            {profile, terrain}, state, actor))
        clear.emplace(id, Value(path_clear));
    return clear;
}

std::optional<Value> build(const world::Profile& profile,
        const world::Snapshot& snapshot, const terrain_surface::Surface& terrain,
        const std::map<std::string, std::size_t>& support_routes, const Actors& observed_actors) {
    const auto& state = snapshot.state;
    const physical_site::Site site{profile, terrain};
    const auto support_layout = physical_support::layout(
        physical_site::support_site(site), state, &support_routes);
    topology_projection::WheelSupports wheel_supports;
    for (const auto& part : state.topology.parts) {
        if (part.role != Role::waterwheel) continue;
        if (const auto supports = wheel_support_bounds(part.geometry.center, part.geometry.axis,
                [&terrain](double sx, double sz, double hx, double hz) {
                    return terrain.range(sx, sz, hx, hz);
                }))
            wheel_supports.emplace(part.geometry.id, *supports);
    }
    auto topology = topology_projection::fields(state, support_layout, wheel_supports);
    Object actors;
    const auto power = world::drive_power(profile, state);
    auto drive = drive_projection::fields(state, power);
    for (const auto& [actor, sample] : observed_actors) actors.emplace(actor, Value(Object{
        {"position", point_value(sample.position)}, {"capabilities", Value(Object{
            {"build_reach", Value(profile.build_reach)},
            {"harvest_reach", Value(profile.manual_cut_reach > 0 ?
                profile.manual_cut_reach : profile.build_reach)}})},
        {"ready", Value(sample.ready)}, {"native_epoch", Value(sample.epoch)},
        {"harvest_clear", Value(harvest_clearances(profile, terrain, state,
            sample.position, sample.ready))}}));
    Array mineral_cells;
    Array cell_regions;
    if (profile.ore_field) {
        for (Integer x = mineral_site::field_min.x; x <= mineral_site::field_max.x; ++x)
        for (Integer z = mineral_site::field_min.z; z <= mineral_site::field_max.z; ++z) {
            mineral_cells.emplace_back(Array{Value(x), Value(z)});
            cell_regions.emplace_back(world::ore_region_id(profile,
                *mineral_site::field_region({x, z})));
        }
    } else {
        for (const auto& cell : mineral_site::opening_cells)
            mineral_cells.emplace_back(Array{Value(cell.x), Value(cell.z)});
    }
    const auto local = world::machine_power(state.topology, power);
    Object projection{{"context", Value(snapshot.history.context)},
        {"order", Value(snapshot.history.order)}, {"initial_feed", Value(profile.initial_units)},
        {"recipe_input", Value(profile.material.input_units_per_product)}, {"entities", Value(std::move(topology.entities))},
        {"transmission_parts", Value(std::move(topology.transmission_parts))}, {"links", Value(std::move(drive.links))},
        {"drive_links", Value(std::move(drive.drive_links))}, {"engagements", Value(std::move(drive.engagements))},
        {"motion", Value(std::move(drive.motion))}, {"actors", Value(std::move(actors))},
        {"foundations", Value(std::move(topology.foundations))},
        {"source_deposit", Value(Object{{"id", Value(profile.material.manual_ore ?
            profile.material.manual_ore->id : std::string{})},
            {"cells", Value(std::move(mineral_cells))},
            {"cell_regions", Value(std::move(cell_regions))},
            {"initial_units", Value(profile.initial_units)},
            {"collector_capacity", Value(profile.material.collector_capacity)},
            {"maximum_depth", Value(mineral_site::extraction_depth_steps * height_step)}})},
        {"powered", Value(local.collector || local.belt || local.processor)},
        {"power_enabled", Value(state.topology.drive_enabled)},
        {"options", Value(Object{{"opening", Value(true)}, {"physical", Value(true)}, {"native", Value(true)},
            {"arrival", Value(profile.landing_pod_center.has_value())},
            {"copper_material", Value(material_projection::copper_forms(profile.material))},
            {"manual_sources", Value(profile.material.manual_ore.has_value())},
            {"foundations", Value(true)}, {"developer_conveniences", Value(state.developer_conveniences)}})},
        {"adapter_profile", Value(Object{{"pitch", Value(pitch)}, {"anchor_height", Value(anchor_height)},
            {"height_denominator", Value(height_denominator)}, {"height_step", Value(height_step)},
            {"foundation_depth", Value(foundation_depth)},
            {"wheel_radius", Value(wheel_radius)}, {"wheel_axle_offset", Value(wheel_axle_offset)},
            {"capsule_radius", Value(capsule_radius)}, {"capsule_height", Value(capsule_height)},
            {"collector_intake_size", Value(Array{Value(site_geometry::collector_intake_size[0]),
                Value(site_geometry::collector_intake_size[1]), Value(site_geometry::collector_intake_size[2])})},
            {"collector_intake_x", Value(site_geometry::collector_intake_x)},
            {"collector_intake_y", Value(site_geometry::collector_intake_y)},
            {"collector_second_cell_z", Value(site_geometry::collector_second_cell_z)},
            {"collector_lift", Value(Object{{"pickup_x", Value(site_geometry::collector_lift.pickup_x)},
                {"pickup_y", Value(site_geometry::collector_lift.pickup_y)},
                {"pickup_size", Value(Array{Value(site_geometry::collector_lift.pickup_size[0]),
                    Value(site_geometry::collector_lift.pickup_size[1]),
                    Value(site_geometry::collector_lift.pickup_size[2])})},
                {"carrier_x", Value(site_geometry::collector_lift.carrier_x)},
                {"carrier_bottom", Value(site_geometry::collector_lift.carrier_bottom)},
                {"carrier_top_offset", Value(site_geometry::collector_lift.carrier_top_offset)},
                {"carrier_size_xz", Value(Array{Value(site_geometry::collector_lift.carrier_size_xz[0]),
                    Value(site_geometry::collector_lift.carrier_size_xz[1])})},
                {"guide_offset", Value(Array{Value(site_geometry::collector_lift.guide_offset[0]),
                    Value(site_geometry::collector_lift.guide_offset[1])})},
                {"guide_size", Value(Array{Value(site_geometry::collector_lift.guide_size[0]),
                    Value(site_geometry::collector_lift.guide_size[1])})},
                {"flight_offset_x", Value(site_geometry::collector_lift.flight_offset_x)},
                {"flight_raise_y", Value(site_geometry::collector_lift.flight_raise_y)},
                {"flight_size", Value(Array{Value(site_geometry::collector_lift.flight_size[0]),
                    Value(site_geometry::collector_lift.flight_size[1]),
                    Value(site_geometry::collector_lift.flight_size[2])})},
                {"flight_count", Value(site_geometry::collector_lift.flight_count)},
                {"flight_span", Value(site_geometry::collector_lift.flight_span)},
                {"head_x", Value(site_geometry::collector_lift.head_x)},
                {"head_y_offset", Value(site_geometry::collector_lift.head_y_offset)},
                {"head_size_xy", Value(Array{Value(site_geometry::collector_lift.head_size_xy[0]),
                    Value(site_geometry::collector_lift.head_size_xy[1])})},
                {"head_z_size", Value(Array{Value(site_geometry::collector_lift.head_z_size[0]),
                    Value(site_geometry::collector_lift.head_z_size[1])})}})}})}};
    projection.merge(arrival_site_projection::fields(profile, state, power));
    projection.merge(assembly_projection::fields(profile, state, power));
    projection.merge(build_catalog_projection::fields(profile, snapshot));
    projection.merge(tick_fields(profile, snapshot));
    Value complete(std::move(projection));
    if (!projection_contract::complete(complete)) return std::nullopt;
    return complete;
}

}  // namespace factory::godot_world::complete_projection
