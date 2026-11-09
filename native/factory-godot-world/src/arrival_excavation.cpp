#include "arrival_excavation.hpp"

#include "factory/mineral_site.hpp"
#include "factory/site_geometry_contract.hpp"
#include <algorithm>

namespace factory::godot_world::arrival_excavation {
std::optional<world::ore_columns::Seed> seed(const terrain_surface::Surface& terrain,
        materials::Quantity total) {
    // Reversible content: two-H cutting cells keep the physical ore field at
    // its authored size when the mechanical foundation grid changes scale.
    constexpr double pitch = site_geometry::height_step * 2;
    constexpr excavation::Integer scale = mineral_site::field_pitch_meters / pitch;
    static_assert(scale * pitch == mineral_site::field_pitch_meters);
    constexpr excavation::Integer width = mineral_site::field_width * scale;
    constexpr excavation::Integer count = width * width;
    constexpr excavation::Integer core_width = 8;
    constexpr excavation::Integer core_first = (width - core_width) / 2;
    constexpr excavation::Integer core_count = core_width * core_width;
    if (total < count) return std::nullopt;
    world::ore_columns::Seed result;
    result.grid = {{-mineral_site::field_pitch_meters / 2, 0, -mineral_site::field_pitch_meters / 2},
        pitch, site_geometry::height_step, 4, 4 * 4096};
    const excavation::Cell first{mineral_site::field_min.x * scale, mineral_site::field_min.z * scale};
    for (excavation::Integer z = -1; z <= width; ++z)
    for (excavation::Integer x = -1; x <= width; ++x) {
        const excavation::Cell cell{first.x + x, first.z + z};
        const auto bounds = excavation::surface(result.grid, cell, {0, 0, 0, 0});
        if (!bounds) return std::nullopt;
        const double left = bounds->min_x, back = bounds->min_z;
        auto point = terrain.natural_highest(left + result.grid.pitch / 2,
            back + result.grid.pitch / 2, result.grid.pitch / 2, result.grid.pitch / 2);
        if (!point) return std::nullopt;
        // Use the kernel's exact bound arithmetic at shared edges. Different
        // additions of pitch/2 can otherwise place a clipped corner one ULP
        // beyond its own cell. Resample that actual triangle point, not a
        // synthetic plane height or an expanded reach allowance.
        (*point)[0] = std::clamp((*point)[0], left, bounds->max_x);
        (*point)[2] = std::clamp((*point)[2], back, bounds->max_z);
        const auto actual = terrain.natural_range((*point)[0], (*point)[2], 0, 0);
        if (!actual) return std::nullopt;
        (*point)[1] = actual->second;
        // Include canonical corners explicitly. On a flat plateau the chosen
        // point must not depend on distant triangulation or clipping order.
        for (double px : {left, bounds->max_x}) for (double pz : {back, bounds->max_z}) {
            const auto height = terrain.natural_range(px,pz,0,0);
            if (!height) return std::nullopt;
            const authority::Point corner{px,height->second,pz};
            if (corner[1] > (*point)[1] || (corner[1] == (*point)[1] &&
                    std::pair{px,pz} < std::pair{(*point)[0],(*point)[2]})) point = corner;
        }
        const bool boundary = x < 0 || z < 0 || x == width || z == width;
        // Shallow stocked edges lead into a deeper core. Keep total finite
        // reserve and footprint unchanged while making deeper tool travel
        // useful. This is authored opening content, not a mining-kernel rule.
        const bool core = x >= core_first && x < core_first + core_width &&
            z >= core_first && z < core_first + core_width;
        const auto core_index = (z - core_first) * core_width + x - core_first;
        const auto remainder = total % count;
        const auto units = boundary ? 0 : total / count + (core ?
            remainder / core_count + (core_index < remainder % core_count ? 1 : 0) : 0);
        result.columns.emplace(cell, excavation::Column{units, units, (*point)[1], 0});
        result.contact_points.emplace(cell, *point);
    }
    materials::State material;
    material.initial_units = total;
    material.stock.source = total;
    return world::ore_columns::initialize(result, material) ? std::optional{std::move(result)} : std::nullopt;
}
}
