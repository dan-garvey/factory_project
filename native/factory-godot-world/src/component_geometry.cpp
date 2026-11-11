#include "component_geometry.hpp"

#include "factory/site_geometry_contract.hpp"
#include <cmath>

namespace factory::godot_world::component_geometry {
namespace {
using Bounds = arrival_geometry::Bounds;
using site_geometry::anchor_height;
using site_geometry::height_step;
using site_geometry::pitch;
constexpr double press_scale = pitch / 1.65;
constexpr double reference_component_shaft_half = 0.205;
constexpr double press_shaft_half = reference_component_shaft_half * press_scale;
constexpr double press_work_crown_rise = height_step / 5;
constexpr double anvil_work_height = site_geometry::press_work_height;

}  // namespace

Bounds component_bounds(const world::Profile& profile,
        std::optional<materials::Component> kind, const mechanics::Point& center) {
    const authority::Point at{center[0] * height_step,
        center[1] * height_step + anchor_height, center[2] * height_step};
    if (!kind) return {at, {0.14, 0.14, 0.14}};
    if (const auto channel = materials::channel_spec(*kind)) {
        const double low = center[1] * height_step;
        const double high = at[1] + press_work_crown_rise + height_step * 0.30;
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
                // The deferred collector keeps its original physical cutter height.
                const double top = center[1] * height_step + 0.825 + (*kind == materials::Component::tool_mount ?
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
        case materials::Component::stationary_mount:
            return {{at[0], center[1] * height_step + pitch * 0.5, at[2]},
                {pitch * 1.5, pitch * 0.5, pitch * 1.5}};
        case materials::Component::drill_head:
            return {{at[0], at[1] - height_step, at[2]},
                {pitch * 0.5, pitch * 0.5, pitch * 0.5}};
        case materials::Component::wooden_frame:
            // Every issued frame keeps the same half-U body at any cell.
            return {{at[0], center[1] * height_step + 0.45 * press_scale, at[2]},
                {0.2025 * press_scale, 0.45 * press_scale, 0.2025 * press_scale}};
        case materials::Component::wooden_workbench:
            // A floor-seated table is usable on ground or an ordinary joined deck.
            // Its physical size remains useful beside the smaller machinery.
            return {{at[0], center[1] * height_step + 0.45, at[2]},
                {0.34, 0.45, 0.30}};
        case materials::Component::tool_mount:
            return {{at[0], at[1] + 0.10 * press_scale, at[2]},
                    {height_step - press_shaft_half,
                     0.18 * press_scale,
                     height_step - press_shaft_half}};
        case materials::Component::anvil:
            // The independent workbed owns one full foundation cell. Its
            // inset face and open underframe do not release that cell.
            return {{at[0], center[1] * height_step + anvil_work_height * 0.5, at[2]},
                {pitch * 0.5, anvil_work_height * 0.5, pitch * 0.5}};
        case materials::Component::broad_anvil: {
            const double floor = center[1] * height_step;
            return {{at[0] + pitch * 0.5, floor + anvil_work_height * 0.5,
                     at[2] + pitch * 0.5},
                    {pitch, anvil_work_height * 0.5, pitch}};
        }
        case materials::Component::flat_head: {
            // Reserve the entire carriage-driven die sweep. The named slide
            // may occupy its coaxial upper portion as an intentional fitting.
            const double low = center[1] * height_step - height_step + anvil_work_height;
            const double high = at[1] + height_step * 0.30;
            return {{at[0], (low + high) * 0.5, at[2]},
                {pitch * 0.5, (high - low) * 0.5, pitch * 0.5}};
        }
        case materials::Component::broad_flat_head: {
            const double low = center[1] * height_step - height_step + anvil_work_height;
            const double high = at[1] + height_step * 0.5;
            return {{at[0] + pitch * 0.5, (low + high) * 0.5,
                     at[2] + pitch * 0.5},
                    {pitch, (high - low) * 0.5, pitch}};
        }
        case materials::Component::broad_slide: {
            const double low = center[1] * height_step - 4 * height_step + anvil_work_height;
            // The coupled row gears turn at the native tile shaft plane and
            // clear the moving head below within this admitted volume.
            const double high = at[1] + anchor_height;
            return {{at[0] + pitch * 0.5, (low + high) * 0.5,
                     at[2] + pitch * 0.5},
                    {pitch, (high - low) * 0.5, pitch}};
        }
        case materials::Component::slide: {
            // This selected body keeps the same dimensions alone and fitted.
            // In a press its four feet meet the workbed side rails. The
            // integral shaft stays at the selected slide's own H layer.
            const double low = center[1] * height_step - 2 * height_step + anvil_work_height;
            const double high = at[1] + 0.08 * press_scale;
            return {{at[0], (low + high) * 0.5, at[2]},
                {pitch * 0.5, (high - low) * 0.5, pitch * 0.5}};
        }
        case materials::Component::cutting_edge:
            return {{at[0], at[1] - 0.015, at[2]}, {0.21, 0.12, 0.18}};
        case materials::Component::receiver_tray:
            return {{at[0], at[1] - height_step * 0.20, at[2]},
                {pitch * 0.11, height_step * 0.36, pitch * 0.124}};
        default:
            return {at, {0.14, 0.14, 0.14}};
    }
}

std::vector<Bounds> component_solids(const world::Profile& profile,
        materials::Component kind, const mechanics::Point& center) {
    if (kind == materials::Component::drill_head) {
        const double x = center[0] * height_step, y = (center[1]-1)*height_step,
            z = center[2] * height_step;
        std::vector<Bounds> out{{{x, y + pitch*.42, z}, {pitch*.33, pitch*.18, pitch*.33}},
            {{x, y + pitch*.84, z}, {pitch*.10, pitch*.425, pitch*.10}}};
        // The cutter's downward reach is real geometry. Open sides below its
        // drum expose the loose ore; the whole occupied cube is not a wall.
        for (int i=0; i<8; ++i) {
            const double a=i*std::acos(-1.0)/4;
            out.push_back({{x+std::cos(a)*pitch*.29,y+pitch*.05,z+std::sin(a)*pitch*.29},
                {pitch*.09,pitch*.30,pitch*.09}});
        }
        return out;
    }
    if (kind != materials::Component::stationary_mount)
        return {component_bounds(profile, kind, center)};
    const double x = center[0] * height_step, y = center[1] * height_step,
        z = center[2] * height_step;
    std::vector<Bounds> out;
    for (int sx : {-1, 1}) for (int sz : {-1, 1})
        out.push_back({{x+sx*pitch,y-pitch*.105,z+sz*pitch},
            {pitch*.15,pitch*.145,pitch*.15}});
    // Short stepped boxes approximate each splayed leg without filling the
    // central pickup opening or the entire reserved three-unit footprint.
    for (int sx : {-1, 1}) for (int sz : {-1, 1})
        for (int step = 0; step < 4; ++step) {
            const double t = (step + .5) / 4;
            const double reach = pitch * (1.0 - .65 * t);
            out.push_back({{x + sx * reach, y + pitch * t, z + sz * reach},
                {pitch * .15, pitch * .125, pitch * .15}});
        }
    for (int side : {-1,1}) {
        out.push_back({{x,y+pitch*.93,z+side*pitch*.35},{pitch*.425,pitch*.07,pitch*.07}});
        out.push_back({{x+side*pitch*.35,y+pitch*.93,z},{pitch*.07,pitch*.07,pitch*.425}});
    }
    return out;
}
}  // namespace factory::godot_world::component_geometry
