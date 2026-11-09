#include "factory/surface_drill.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace factory::world::surface_drill {
using C = materials::Component;
using P = mechanics::Point;
using I = mechanics::Integer;

bool fitting(C a, const P& at, C b, const P& bt) noexcept {
    if (a == C::stationary_mount && b == C::drill_head)
        return bt == P{at[0], at[1] + 1, at[2]};
    return a == C::drill_head && b == C::stationary_mount &&
        at == P{bt[0], bt[1] + 1, bt[2]};
}

bool supported(const State& state, const P& head) {
    return std::any_of(state.placed_components.begin(), state.placed_components.end(),
        [&](const auto& entry) {
            return fitting(C::drill_head, head, entry.second.kind, entry.second.center);
        });
}

bool reserved(const P& mount, const P& center, I half_width, I half_height) noexcept {
    return std::abs(center[0] - mount[0]) < 6 + half_width &&
        std::abs(center[2] - mount[2]) < 6 + half_width &&
        center[1] + half_height > mount[1] - 2 &&
        center[1] - half_height < mount[1] + 3;
}

const char* placement_refusal(const State& state, C kind, const P& center,
        const std::string& ignored) {
    if ((kind == C::drill_head || kind == C::stationary_mount) &&
        (center[0] % 4 != 0 || center[2] % 4 != 0)) return "invalid_area_target";
    if (kind == C::drill_head && !supported(state, center)) return "support_required";
    for (const auto& [id, other] : state.placed_components) {
        if (id == ignored || fitting(kind, center, other.kind, other.center)) continue;
        if ((kind == C::stationary_mount && reserved(center, other.center,
                other.kind == C::stationary_mount ? 6 : 2)) ||
            (other.kind == C::stationary_mount && reserved(other.center, center,
                kind == C::stationary_mount ? 6 : 2))) return "mount_area_reserved";
    }
    if (kind == C::stationary_mount) {
        for (const auto& part : state.topology.parts)
            if (reserved(center, part.geometry.center)) return "mount_area_reserved";
        if (state.fabrication_hub && !state.fabrication_hub->holder &&
            reserved(center, state.fabrication_hub->center)) return "mount_area_reserved";
    }
    return nullptr;
}

bool valid(const State& state) {
    for (const auto& [id, part] : state.placed_components)
        if (placement_refusal(state, part.kind, part.center, id)) return false;
    return true;
}

std::optional<Contact> contact(const Profile& profile, const State& state, const P& head) {
    if (!profile.excavation || !state.excavation || !supported(state, head)) return std::nullopt;
    const auto& grid = profile.excavation->grid;
    const double h = profile.meters_per_grid_unit;
    const double x = head[0] * h + profile.anchor_offset[0];
    const double z = head[2] * h + profile.anchor_offset[2];
    const double floor = (head[1] - 1) * h;
    std::optional<std::pair<excavation::Cell, excavation::Surface>> selected;
    // Prefer the highest still-reachable face so a single head cuts its whole
    // 1U footprint evenly. A fixed head cannot follow a deepening hole.
    for (const auto& [cell, column] : *state.excavation) {
        if (column.remaining_units <= 0) continue;
        const auto surface = excavation::surface(grid, cell, column);
        if (!surface || surface->min_x < x - 2*h - 1e-9 || surface->max_x > x + 2*h + 1e-9 ||
            surface->min_z < z - 2*h - 1e-9 || surface->max_z > z + 2*h + 1e-9 ||
            surface->floor > floor + 1e-9 || surface->floor <= floor - h + 1e-9) continue;
        if (!selected || surface->floor > selected->second.floor)
            selected = std::pair{cell, *surface};
    }
    if (!selected) return std::nullopt;
    const auto& [cell, face] = *selected;
    const double next_floor = face.floor - grid.height_step / grid.units_per_step;
    const double cx = (face.min_x + face.max_x) / 2, cz = (face.min_z + face.max_z) / 2;
    // DropPoint is the address, not a second quantity owner. The scene seats
    // loose raw copper at the derived surface beneath this address.
    const P output{I(std::llround((cx-profile.anchor_offset[0])/h)),
        I(std::llround((next_floor-profile.anchor_offset[1])/h)),
        I(std::llround((cz-profile.anchor_offset[2])/h))};
    return Contact{{cell, excavation::Face::top, {cx, face.floor, cz},
        {grid.pitch/2, grid.pitch/2}}, output};
}

bool advance(const Profile& profile, State& state, const DrivePower& drive) {
    if (!profile.excavation) return true;
    if (!state.excavation) return false;
    for (const auto& [id, part] : state.placed_components) {
        if (part.kind != C::drill_head) continue;
        const auto motion = drive.mechanical.motion.find(id);
        if (motion == drive.mechanical.motion.end() ||
            motion->second.state != mechanics::MotionState::rotating) continue;
        const auto selected = contact(profile, state, part.center);
        if (!selected) continue;
        const auto& rate = motion->second.rate;
        if (rate.denominator <= 0 || rate.numerator == std::numeric_limits<I>::min()) return false;
        __extension__ using Wide = __int128;
        const Wide travel = static_cast<Wide>(std::abs(rate.numerator)) * materials::work_subticks_per_tick /
            rate.denominator;
        const auto work = static_cast<I>(std::min<Wide>(travel, materials::maximum_work_subticks_per_tick));
        const auto result = ore_columns::cut_to_ground(*profile.excavation, *state.excavation,
            state.material, profile.material, material_path(state.topology), selected->cut, work, selected->output);
        if (result.error != ore_columns::Error::none) return false;
        if (result.produced_units > 0) {
            // Copper already lying on this small cut settles with its floor;
            // quantizing a lower address must not leave a second floating pile.
            auto& drops = state.material.dropped_material;
            for (auto it = drops.begin(); it != drops.end();) {
                const auto& p = it->first;
                const auto& cargo = it->second;
                if (p != selected->output && p[0] == selected->output[0] &&
                    p[2] == selected->output[2] && p[1] >= selected->output[1] &&
                    p[1] <= selected->output[1] + 1 && cargo.raw_units > 0 &&
                    cargo.products == 0 && cargo.offcuts == 0 && cargo.timber == 0 &&
                    cargo.work_lots.empty() && cargo.components.empty() && cargo.sheets.empty()) {
                    drops.at(selected->output).raw_units += cargo.raw_units;
                    it = drops.erase(it);
                } else ++it;
            }
        }
    }
    return true;
}
} // namespace factory::world::surface_drill
