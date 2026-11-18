#include "arrival_site_projection.hpp"

#include "component_geometry.hpp"
#include "material_projection.hpp"
#include "factory/arrival_geometry.hpp"
#include "factory/site_geometry_contract.hpp"
#include "factory/piston_assembly.hpp"

#include <utility>
#include <algorithm>

namespace factory::godot_world::arrival_site_projection {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
using material_projection::point_value;
using site_geometry::height_denominator;
using site_geometry::height_step;
Value grid_point(mechanics::Point p) { return Value(Array{Value(p[0]),Value(p[1]),Value(p[2])}); }
Value axes_value(const piston::Basis& axes) { return Value(Array{grid_point(axes[0]),grid_point(axes[1]),grid_point(axes[2])}); }
}  // namespace

Object fields(const world::Profile& profile, const world::State& state) {
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
    const auto power=world::drive_power(profile,state);
    Object crank_items;
    for (const auto& [id, item] : state.crank_items) {
        const auto socket=item.attached_to && item.port ? world::rotary_socket(power,*item.attached_to,*item.port) : std::nullopt;
        crank_items.emplace(id, Value(Object{{"id", Value(item.id)},
            {"generation", Value(item.generation)},
            {"position",socket ? point_value(world::rotary_position(profile,*socket)) : Value(Array{})},
            {"holder", Value(item.holder.value_or(""))},
            {"attached_to", Value(item.attached_to.value_or(""))},
            {"port", Value(item.port ? Array{Value((*item.port)[0]),
                Value((*item.port)[1]), Value((*item.port)[2])} : Array{})},
            {"face", Value(item.face ? Array{Value((*item.face)[0]),
                Value((*item.face)[1]), Value((*item.face)[2])} : Array{})}}));
    }
    projection.emplace("crank_items", Value(std::move(crank_items)));
    Array rotations;
    for (Integer orientation=0;orientation<24;++orientation) rotations.push_back(axes_value(*piston::basis(orientation)));
    projection.emplace("component_orientations",Value(std::move(rotations)));
    Object placed;
    for (const auto& [id, component] : state.placed_components) {
        const auto occupied = component_geometry::placed_bounds(profile, state, id, component);
        Array collision;
        for (const auto& solid : component_geometry::placed_solids(profile, state, id, component))
            collision.emplace_back(Object{{"center", point_value(solid.center)},
                {"half", point_value(solid.half)}});
        Object part{{"component", Value(materials::component_name(component.kind))},
            {"basis",axes_value(*piston::basis(component.orientation))},
            {"orientation",Value(component.orientation)}, {"parent",Value(component.parent)},
            {"collision", Value(std::move(collision))},
            {"generation", Value(component.generation)},
            {"center", Value(Array{Value(component.center[0]), Value(component.center[1]),
                Value(component.center[2])})},
            {"occupied", Value(Object{{"center", point_value(occupied.center)},
                {"half", point_value(occupied.half)}})},
            {"position", point_value(world::piston_assembly::position(profile,state,component))}};
        if (component.kind==materials::Component::segmented_piston) {
            const auto config=world::piston_assembly::configuration(state,id);
            const auto& progress=state.piston_progress.at(id);
            part.emplace("piston",Value(Object{{"segments",Value(config->segments)},
                {"position_ticks",Value(progress.position)}, {"stroke_ticks",Value(config->segments*piston::segment_ticks)},
                {"blocked",Value(progress.blocked)}}));
        }
        Array attachments;
        const auto offer=[&](materials::Component kind,mechanics::Point center,Integer orientation,const std::string& parent) {
            if (world::piston_assembly::placement_refusal(state,{kind,center,0,orientation,parent})) return;
            if (std::any_of(state.placed_components.begin(),state.placed_components.end(),
                [&](const auto& entry) { return entry.second.center==center && entry.second.parent==parent; })) return;
            attachments.emplace_back(Object{{"component",Value(materials::component_name(kind))},
                {"center",grid_point(center)}, {"orientation",Value(orientation)}, {"parent",Value(parent)}});
        };
        if (component.kind==materials::Component::stationary_mount)
            offer(materials::Component::segmented_piston,{component.center[0],component.center[1]+5,component.center[2]},0,"");
        const auto parent=component.kind==materials::Component::segmented_piston ? id : component.parent;
        const auto config=world::piston_assembly::configuration(state,parent);
        if (config && state.piston_progress.at(parent).position==0) {
            offer(materials::Component::piston_segment,piston::segment_center(*config,config->segments),config->orientation,parent);
            std::vector<mechanics::RotaryPort> ports;
            if (component.kind==materials::Component::segmented_piston) {
                for (const auto& port:piston::ports(*config,{}))
                    if (port.moving) ports.push_back(port.reference);
            } else if (const auto rotor=world::piston_assembly::spindle(id,component)) { const auto endpoints=mechanics::rotary_ports(*rotor); ports.assign(endpoints.begin(),endpoints.end()); }
            for (const auto& port:ports) {
                mechanics::Point center=port.position;
                for (unsigned n=0;n<3;++n) center[n]+=port.outward[n]*2;
                for (const auto kind:{materials::Component::drill_head}) {
                    for (Integer orientation=0;orientation<24;++orientation) {
                        const auto axis=(*piston::basis(orientation))[1];
                        if (axis!=port.outward && axis!=mechanics::Point{-port.outward[0],-port.outward[1],-port.outward[2]}) continue;
                        if (kind==materials::Component::drill_head && axis!=mechanics::Point{0,1,0}) continue;
                        offer(kind,center,orientation,parent); break;
                    }
                }
            }
        }
        part.emplace("attachments",Value(std::move(attachments)));
        placed.emplace(id, Value(std::move(part)));
    }
    projection.emplace("placed_components", Value(std::move(placed)));
    return projection;
}

}  // namespace factory::godot_world::arrival_site_projection
