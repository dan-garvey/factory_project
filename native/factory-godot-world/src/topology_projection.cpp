#include "topology_projection.hpp"

#include "build_catalog_projection.hpp"
#include "material_projection.hpp"
#include "factory/site_geometry_contract.hpp"
#include "factory/piston_assembly.hpp"

#include <utility>

namespace factory::godot_world::topology_projection {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
using build_catalog_projection::kind;
using material_projection::point_value;
}  // namespace

Fields fields(const world::State& state,
        const std::map<std::string, physical_support::TransmissionSupport>& supports,
        const WheelSupports& wheel_supports) {
    Fields output;
    for (const auto& part : state.topology.parts) {
        Object projected{{"kind", Value(kind(part.role))}, {"generation", Value(part.generation)},
            {"center", Value(Array{Value(part.geometry.center[0]), Value(part.geometry.center[1]),
                Value(part.geometry.center[2])})},
            {"axis", Value(static_cast<Integer>(part.geometry.axis))},
            {"relay_axis", Value(static_cast<Integer>(part.geometry.relay_axis))},
            {"teeth", Value(part.geometry.teeth)}, {"half_span", Value(part.geometry.half_span)},
            {"rotation", Value(part.rotation)}};
        if (!part.parent.empty()) {
            const auto offset = world::piston_assembly::displacement(state, part.parent);
            Array delta;
            for (const auto value : offset) delta.emplace_back(double(value) * site_geometry::height_step / piston::ticks_per_level);
            projected.emplace("parent", Value(part.parent));
            projected.emplace("displacement", Value(std::move(delta)));
            Array attachments;
            if (state.piston_progress.at(part.parent).position == 0)
                for (const auto& port : mechanics::rotary_ports(part.geometry)) {
                    if (port.outward[1] == 0) continue;
                    auto center = port.position;
                    center[1] += port.outward[1] * 2;
                    const world::PlacedComponent head{materials::Component::drill_head, center, 0, 0, part.parent};
                    if (world::piston_assembly::placement_refusal(state, head)) continue;
                    attachments.emplace_back(Object{{"component", Value("drill_head")},
                        {"center", Value(Array{Value(center[0]), Value(center[1]), Value(center[2])})},
                        {"orientation", Value(Integer{0})}, {"parent", Value(part.parent)}});
                }
            projected.emplace("attachments", Value(std::move(attachments)));
        }
        if (part.role == stationary::Role::waterwheel) {
            projected.emplace("tiles", Value(part.wheel_tiles));
            if (const auto found = wheel_supports.find(part.geometry.id); found != wheel_supports.end()) {
                Array occupied;
                for (const auto& support : found->second)
                    occupied.emplace_back(Object{{"center", point_value(support.center)},
                                                 {"half", point_value(support.half)}});
                projected.emplace("supports", Value(std::move(occupied)));
            }
        }
        if (physical_support::fixed_transmission(part.role)) {
            if (const auto found = supports.find(part.geometry.id); found != supports.end()) {
                Array boxes;
                for (const auto& [center, half] : found->second.boxes)
                    boxes.emplace_back(Object{{"center", point_value(center)},
                        {"half", point_value(half)}});
                projected.emplace("support", Value(Object{{"foot", point_value(found->second.foot)},
                    {"bearing", point_value(found->second.bearing)},
                    {"boxes", Value(std::move(boxes))}}));
            }
            output.transmission_parts.emplace(part.geometry.id, Value(std::move(projected)));
        } else {
            projected.emplace("cell", Value(Array{
                Value(part.geometry.center[0] / site_geometry::height_denominator),
                Value(part.geometry.center[2] / site_geometry::height_denominator)}));
            if (part.geometry.center[1] != 0)
                projected.emplace("level", Value(part.geometry.center[1]));
            output.entities.emplace(part.geometry.id, Value(std::move(projected)));
        }
    }
    for (const auto& [id, foundation] : state.foundations)
        output.foundations.emplace(id, Value(Object{{"cell", Value(Array{
            Value(foundation.center[0] / (site_geometry::height_denominator * 3)),
            Value(foundation.center[2] / (site_geometry::height_denominator * 3))})},
            {"level", Value(foundation.center[1])},
            {"generation", Value(foundation.generation)}}));
    return output;
}

}  // namespace factory::godot_world::topology_projection
