#include "component_geometry.hpp"

#include "factory/site_geometry_contract.hpp"

namespace factory::godot_world::component_geometry {
namespace {
using Bounds = arrival_geometry::Bounds;
using site_geometry::anchor_height;
using site_geometry::height_step;
using site_geometry::pitch;
constexpr double component_shaft_half = 0.205;
constexpr double press_work_crown_rise = 0.082;
constexpr double anvil_work_height = site_geometry::press_work_height;
}  // namespace

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
            for (authority::Integer elevation : {authority::Integer{0}, authority::Integer{1}}) {
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
            // Its feet rest on the floor. The working face spans a full belt
            // lane; the conservative body also includes its side rails.
            return {{at[0], center[1] * height_step + anvil_work_height * 0.5, at[2]},
                {0.2025, anvil_work_height * 0.5,
                 site_geometry::belt_frame_outer_half_width}};
        case materials::Component::broad_anvil: {
            const double floor = center[1] * height_step;
            return {{at[0] + pitch * 0.5, floor + anvil_work_height * 0.5,
                     at[2] + pitch * 0.5},
                    {pitch, anvil_work_height * 0.5, pitch}};
        }
        case materials::Component::ram_face:
            return vertical(center[1] * height_step - height_step + anvil_work_height,
                at[1] + height_step * 0.5);
        case materials::Component::flat_head:
            // Reserve the entire carriage-driven die sweep. The named slide
            // may occupy its coaxial upper portion as an intentional fitting.
            return vertical(center[1] * height_step - height_step + anvil_work_height,
                at[1] + 0.125);
        case materials::Component::broad_flat_head: {
            const double low = center[1] * height_step - height_step + anvil_work_height;
            const double high = at[1] + height_step * 0.5;
            return {{at[0] + pitch * 0.5, (low + high) * 0.5,
                     at[2] + pitch * 0.5},
                    {pitch, (high - low) * 0.5, pitch}};
        }
        case materials::Component::sliding_guide:
            // Its full selected rails reach the ram below, whether or not a
            // press is recognized. The admitted box includes that entire
            // span and meets the unchanged tool-mount box above.
            return vertical(at[1] - height_step * 1.5, at[1] + height_step - 0.08);
        case materials::Component::wooden_slide:
        case materials::Component::copper_slide: {
            // This selected body keeps the same dimensions alone and fitted.
            // In a press its four feet meet the workbed side rails, while the
            // integral shaft stays at the native rotary input height.
            const double low = center[1] * height_step - 2 * height_step + anvil_work_height;
            const double high = at[1] + 0.08;
            return {{at[0], (low + high) * 0.5, at[2]},
                {0.21, (high - low) * 0.5,
                 site_geometry::belt_frame_outer_half_width}};
        }
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

}  // namespace factory::godot_world::component_geometry
