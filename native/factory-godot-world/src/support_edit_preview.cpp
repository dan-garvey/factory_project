#include "support_edit_preview.hpp"

#include "build_catalog_projection.hpp"
#include "physical_geometry.hpp"

#include <algorithm>
#include <optional>
#include <string>
#include <utility>

namespace factory::godot_world::support_edit_preview {
namespace {
using Value = values::Value;
using Object = Value::Object;
using Array = Value::Array;
using Integer = Value::Integer;
using Role = stationary::Role;
using physical_geometry::find_part;

template<class T> const T* field(const Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}
}  // namespace

bool applies(std::string_view action) {
    return action == "place" || action == "place_connected" || action == "remove" ||
        action == "place_foundation" || action == "place_foundations" ||
        action == "remove_foundation" || action == "place_belt_span" ||
        action == "place_selected_belt_span" || action == "remove_belt_span";
}

Result build(const world::State& before, const Object& normalized) {
    const auto* selected = field<std::string>(normalized, "action");
    if (!selected || !applies(*selected)) return "invalid_command";
    const auto& edit = *selected;
    world::State geometry;
    geometry.topology = before.topology;
    geometry.foundations = before.foundations;
    geometry.placed_components = before.placed_components;
    geometry.landing_pod = before.landing_pod;
    geometry.fabrication_hub = before.fabrication_hub;
    std::string preview_id = "support-preview";
    while (find_part(geometry, preview_id) || geometry.foundations.contains(preview_id) ||
           std::any_of(geometry.topology.belt_spans.begin(), geometry.topology.belt_spans.end(),
               [&](const auto& span) { return span.geometry.id == preview_id; })) preview_id += '-';
    if (edit == "place" || edit == "place_connected") {
        stationary::PlacedPart part{};
        const auto& name = *field<std::string>(normalized, "role");
        std::optional<Role> role;
        for (const auto value : {Role::collector, Role::belt, Role::processor, Role::waterwheel,
                                Role::shaft, Role::gear, Role::gearbox, Role::vertical_gearbox,
                                Role::chain_drive})
            if (name == (value == Role::waterwheel ? "waterwheel" : build_catalog_projection::kind(value)))
                role = value;
        if (!role) return "invalid_command";
        part.role = *role;
        part.geometry.id = preview_id;
        const auto& center = *field<Array>(normalized, "center");
        for (std::size_t dimension = 0; dimension < 3; ++dimension)
            part.geometry.center[dimension] = std::get<Integer>(center[dimension].storage());
        const auto& axis = *field<std::string>(normalized, "axis");
        part.geometry.axis = axis == "x" ? mechanics::Axis::x :
            axis == "y" ? mechanics::Axis::y : mechanics::Axis::z;
        if (const auto* teeth = field<Integer>(normalized, "teeth")) part.geometry.teeth = *teeth;
        if (const auto* span = field<Integer>(normalized, "half_span")) part.geometry.half_span = *span;
        part.geometry.kind = part.role == Role::shaft ? mechanics::Kind::shaft :
            part.role == Role::gear ? mechanics::Kind::gear : mechanics::Kind::hub;
        part.wheel_tiles = part.role == Role::waterwheel ? 3 : 1;
        if (const auto* tiles = field<Integer>(normalized, "wheel_tiles")) part.wheel_tiles = *tiles;
        if (std::any_of(geometry.topology.parts.begin(), geometry.topology.parts.end(),
                [&](const auto& old) { return old.geometry.center == part.geometry.center; }))
            return "occupied";
        geometry.topology.parts.push_back(std::move(part));
    } else if (edit == "remove") {
        const auto& target_id = *field<std::string>(normalized, "target");
        std::erase_if(geometry.topology.parts,
            [&](const auto& part) { return part.geometry.id == target_id; });
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
    } else if (edit == "remove_foundation") {
        geometry.foundations.erase(*field<std::string>(normalized, "target"));
    } else if (edit == "remove_belt_span") {
        const auto& target_id = *field<std::string>(normalized, "target");
        std::erase_if(geometry.topology.belt_spans,
            [&](const auto& span) { return span.geometry.id == target_id; });
    } else {
        geometry.topology.belt_spans.push_back({{preview_id,
            *field<std::string>(normalized, "target"), *field<std::string>(normalized, "to")}, 0});
    }
    return geometry;
}

}  // namespace factory::godot_world::support_edit_preview
