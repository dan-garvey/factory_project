#include "arrival_site_projection.hpp"

#include "component_geometry.hpp"
#include "material_projection.hpp"
#include "factory/arrival_geometry.hpp"
#include "factory/site_geometry_contract.hpp"

#include <utility>

namespace factory::godot_world::arrival_site_projection {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
using material_projection::point_value;
using site_geometry::height_denominator;
using site_geometry::height_step;
}  // namespace

Object fields(const world::Profile& profile, const world::State& state,
        const world::DrivePower& power) {
    Object projection;
    if (!state.landing_pod) return projection;
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
        {"position", Value(Array{Value(hub.center[0] * profile.meters_per_grid_unit + profile.anchor_offset[0]),
            Value(hub.center[1] * profile.meters_per_grid_unit + profile.anchor_offset[1]),
            Value(hub.center[2] * profile.meters_per_grid_unit + profile.anchor_offset[2])})}}));
    Array benches;
    for (const auto& [id, placed] : state.placed_components)
        if (placed.kind == materials::Component::wooden_workbench)
            benches.emplace_back(Object{{"id", Value(id)},
                {"generation", Value(placed.generation)},
                {"center", Value(Array{Value(placed.center[0] / height_denominator),
                    Value(placed.center[1]), Value(placed.center[2] / height_denominator)})},
                {"position", Value(Array{Value(placed.center[0] * profile.meters_per_grid_unit + profile.anchor_offset[0]),
                    Value(placed.center[1] * profile.meters_per_grid_unit + profile.anchor_offset[1]),
                    Value(placed.center[2] * profile.meters_per_grid_unit + profile.anchor_offset[2])})}});
    projection.emplace("fabrication_benches", Value(std::move(benches)));
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
        const auto occupied = component_geometry::component_bounds(profile, component.kind, component.center);
        Object part{{"component", Value(materials::component_name(component.kind))},
            {"generation", Value(component.generation)},
            {"center", Value(Array{Value(component.center[0]), Value(component.center[1]),
                Value(component.center[2])})},
            {"occupied", Value(Object{{"center", point_value(occupied.center)},
                {"half", point_value(occupied.half)}})},
            {"position", Value(Array{
                Value(component.center[0] * profile.meters_per_grid_unit + profile.anchor_offset[0]),
                Value(component.center[1] * profile.meters_per_grid_unit + profile.anchor_offset[1]),
                Value(component.center[2] * profile.meters_per_grid_unit + profile.anchor_offset[2])})}};
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
        if (part.contains("input_ports"))
            part.emplace("crank_source_available", Value(
                !world::has_self_powered_source(power, state.topology, id)));
        if (const auto axis = power.crank_axes.find(id); axis != power.crank_axes.end())
            part.emplace("crank_axis", Value(static_cast<Integer>(axis->second)));
        placed.emplace(id, Value(std::move(part)));
    }
    projection.emplace("placed_components", Value(std::move(placed)));
    return projection;
}

}  // namespace factory::godot_world::arrival_site_projection
