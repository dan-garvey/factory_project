#include "drive_projection.hpp"

#include <cmath>
#include <algorithm>
#include <cstddef>
#include <utility>

namespace factory::godot_world::drive_projection {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
}  // namespace

Fields fields(const world::State& state, const world::DrivePower& power) {
    Fields projected;
    for (const auto& [id, sockets] : power.rotary_ports) {
        const auto generation = state.issued_entities.find(id);
        if (generation == state.issued_entities.end()) continue;
        Array ports;
        for (const auto& socket : sockets) {
            const auto& port = socket.port;
            ports.emplace_back(Object{
                {"position", Value(Array{Value(port.position[0]), Value(port.position[1]), Value(port.position[2])})},
                {"outward", Value(Array{Value(port.outward[0]), Value(port.outward[1]), Value(port.outward[2])})},
                {"factor", Value(port.factor)},
                {"hand_crank", Value(mechanics::accepts_hand_crank(port))},
                {"open", Value(world::rotary_socket_open(state, power, id, port.position) &&
                    std::none_of(state.crank_items.begin(), state.crank_items.end(),
                        [&](const auto& entry) { return entry.second.port == port.position; }))}});
        }
        projected.rotary_ports.emplace(id, Value(Object{
            {"generation", Value(generation->second)}, {"ports", Value(std::move(ports))},
            {"crank_source_available", Value(!world::has_self_powered_source(power, state.topology, id))}}));
    }
    for (const auto& link : state.topology.material_links)
        projected.links.emplace_back(Array{Value(link.from.id), Value(link.to.id)});

    for (const auto& [id, motion] : power.mechanical.motion) {
        Object record{{"state", Value(mechanics::motion_state_name(motion.state))},
            {"numerator", Value(motion.rate.numerator)}, {"denominator", Value(motion.rate.denominator)}};
        const auto load = power.load.find(id);
        if (load != power.load.end()) {
            record.emplace("capacity", Value(load->second.capacity));
            record.emplace("impact", Value(load->second.impact));
            record.emplace("overloaded", Value(load->second.overloaded));
            if (load->second.overloaded) {
                record.emplace("limiting_part", Value(load->second.limiting_part));
                if (!load->second.limiting_part.empty()) {
                    const auto found = state.placed_components.find(load->second.limiting_part);
                    if (found != state.placed_components.end())
                        record.emplace("limiting_kind", Value(materials::component_name(found->second.kind)));
                }
                record.emplace("remedy", Value(load->second.limiting_part.empty() ?
                    "add_power_or_reduce_load" : "replace_with_copper_or_split_load"));
            }
        }
        projected.motion.emplace(id, Value(std::move(record)));
    }

    for (const auto& edge : power.mechanical.engagements)
        projected.engagements.emplace_back(Object{{"a", Value(edge.a)}, {"b", Value(edge.b)},
            {"kind", Value(static_cast<Integer>(edge.kind))}});

    for (const auto& shaft : state.topology.parts) {
        if (shaft.role != stationary::Role::shaft) continue;
        Array ends;
        const auto axis = static_cast<std::size_t>(shaft.geometry.axis);
        for (const auto& part : state.topology.parts) {
            if (part.role == stationary::Role::shaft || part.role == stationary::Role::gear ||
                part.geometry.axis != shaft.geometry.axis) continue;
            bool aligned = true;
            for (std::size_t index = 0; index < 3; ++index)
                if (index != axis && part.geometry.center[index] != shaft.geometry.center[index]) aligned = false;
            if (aligned && std::abs(part.geometry.center[axis] - shaft.geometry.center[axis]) ==
                    shaft.geometry.half_span)
                ends.emplace_back(part.geometry.id);
        }
        if (ends.size() == 2) projected.drive_links.emplace_back(std::move(ends));
    }
    return projected;
}

}  // namespace factory::godot_world::drive_projection
