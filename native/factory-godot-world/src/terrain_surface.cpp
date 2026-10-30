#include "factory/terrain_surface.hpp"

#include "physical_geometry.hpp"
#include "factory/site_geometry_contract.hpp"
#include "factory/waterflow.hpp"
#include "factory/waterwheel.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <tuple>
#include <utility>

namespace factory::godot_world::terrain_surface {
namespace {
using Array = values::Value::Array;
using Integer = values::Value::Integer;
using Object = values::Value::Object;
using Bounds = arrival_geometry::Bounds;

template<class T> const T* field(const Object& object, const char* name) {
    const auto found = object.find(name);
    return found == object.end() ? nullptr : std::get_if<T>(&found->second.storage());
}

std::optional<authority::Point> point(const Array& values) {
    if (values.size() != 3) return std::nullopt;
    authority::Point output;
    for (std::size_t index = 0; index < 3; ++index) {
        if (const auto* value = std::get_if<double>(&values[index].storage())) output[index] = *value;
        else if (const auto* value = std::get_if<Integer>(&values[index].storage())) {
            // Reject a lossy observation conversion rather than moving a body.
            constexpr Integer exact_limit = 9007199254740992;
            if (*value < -exact_limit || *value > exact_limit) return std::nullopt;
            output[index] = static_cast<double>(*value);
        } else return std::nullopt;
        if (!std::isfinite(output[index])) return std::nullopt;
    }
    return output;
}
}  // namespace

ParseResult parse(const Object& input, const world::Profile& profile) {
    const auto* axis = field<Array>(input, "axis");
    const auto* heights = field<Array>(input, "heights");
    const auto* obstacles = field<Array>(input, "obstacles");
    const auto* source_obstacle = field<Integer>(input, "source_obstacle");
    const auto* tree_obstacles = field<Object>(input, "tree_obstacles");
    const auto* water = field<Array>(input, "water");
    const auto* flow_cells = field<Array>(input, "flow_cells");
    if (input.size() != (water || flow_cells ? 4u : 3u) + (source_obstacle ? 1u : 0u) +
        (tree_obstacles ? 1u : 0u) || (water && flow_cells) ||
        !axis || !heights || !obstacles || obstacles->size() > 1024 || axis->size() < 2 || axis->size() > 200 ||
        heights->size() != axis->size() * axis->size()) return {{}, "invalid_terrain"};
    Surface surface;
    for (const auto& value : *axis) {
        const auto* number = std::get_if<double>(&value.storage());
        if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000 ||
            (!surface.axis.empty() && surface.axis.back() >= *number)) return {{}, "invalid_terrain"};
        surface.axis.push_back(*number);
    }
    for (const auto& value : *heights) {
        const auto* number = std::get_if<double>(&value.storage());
        if (!number || !std::isfinite(*number) || std::abs(*number) > 1000000) return {{}, "invalid_terrain"};
        surface.heights.push_back(*number);
    }
    for (const auto& value : *obstacles) {
        const auto* ends = std::get_if<Array>(&value.storage());
        if (!ends || ends->size() != 2) return {{}, "invalid_terrain"};
        const auto* low_array = std::get_if<Array>(&ends->at(0).storage());
        const auto* high_array = std::get_if<Array>(&ends->at(1).storage());
        const auto low = low_array ? point(*low_array) : std::nullopt;
        const auto high = high_array ? point(*high_array) : std::nullopt;
        if (!low || !high) return {{}, "invalid_terrain"};
        for (std::size_t coordinate = 0; coordinate < 3; ++coordinate)
            if ((*low)[coordinate] >= (*high)[coordinate]) return {{}, "invalid_terrain"};
        surface.obstacles.emplace_back(*low, *high);
    }
    if (input.contains("source_obstacle") && (!source_obstacle || *source_obstacle < 0 ||
        static_cast<std::size_t>(*source_obstacle) >= surface.obstacles.size())) return {{}, "invalid_terrain"};
    if (source_obstacle) {
        const auto& [low, high] = surface.obstacles[static_cast<std::size_t>(*source_obstacle)];
        const Bounds source{{(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, (low[2] + high[2]) / 2},
                            {(high[0] - low[0]) / 2, (high[1] - low[1]) / 2, (high[2] - low[2]) / 2}};
        if (!physical_geometry::overlap(source, *physical_geometry::collector_intake_bounds({0, 0, 0})) ||
            !physical_geometry::overlap(source, *physical_geometry::collector_intake_bounds({0, 0, 4})))
            return {{}, "invalid_terrain"};
        surface.source_obstacle = static_cast<std::size_t>(*source_obstacle);
    }
    if (tree_obstacles) for (const auto& [id, value] : *tree_obstacles) {
        const auto* index = std::get_if<Integer>(&value.storage());
        if (!index || *index < 0 || static_cast<std::size_t>(*index) >= surface.obstacles.size() ||
            (source_obstacle && *index == *source_obstacle) ||
            !profile.material.timber_sites.contains(id) ||
            surface.tree_obstacles.contains(static_cast<std::size_t>(*index)))
            return {{}, "invalid_terrain"};
        surface.tree_obstacles.emplace(static_cast<std::size_t>(*index), id);
    }
    auto next_profile = profile;
    if (source_obstacle && next_profile.material.manual_ore)
        next_profile.manual_ore_contact_bounds = surface.obstacles[*surface.source_obstacle];
    if (profile.ore_field) {
        for (mineral_site::Integer region = 0;
                region < mineral_site::field_region_count; ++region) {
            const auto cell = mineral_site::field_exposure_cell(region);
            if (!cell) return {{}, "invalid_terrain"};
            if (region == mineral_site::field_region({0, 0}) && source_obstacle) {
                next_profile.ore_exposures[static_cast<std::size_t>(region)] =
                    surface.obstacles[*surface.source_obstacle];
                continue;
            }
            const double x = cell->x * site_geometry::pitch;
            const double z = cell->z * site_geometry::pitch;
            const auto ground = surface.range(x, z, 0.45, 0.45);
            if (!ground) return {{}, "invalid_terrain"};
            next_profile.ore_exposures[static_cast<std::size_t>(region)] =
                std::pair<authority::Point, authority::Point>{{x - 0.55, ground->second + 0.02, z - 0.55},
                    {x + 0.55, ground->second + 0.22, z + 0.55}};
        }
    }
    if (flow_cells) {
        if (flow_cells->empty() || flow_cells->size() > 65536) return {{}, "invalid_water"};
        std::vector<waterflow::Cell> cells;
        cells.reserve(flow_cells->size());
        for (const auto& value : *flow_cells) {
            const auto* row = std::get_if<Array>(&value.storage());
            if (!row || row->size() != 3) return {{}, "invalid_water"};
            const auto* x = std::get_if<Integer>(&row->at(0).storage());
            const auto* z = std::get_if<Integer>(&row->at(1).storage());
            const auto* surface_height = std::get_if<Integer>(&row->at(2).storage());
            if (!x || !z || !surface_height) return {{}, "invalid_water"};
            cells.push_back({*x, *z, *surface_height});
        }
        const auto derived = waterflow::derive({surface.axis, surface.heights, site_geometry::height_step}, cells);
        if (!derived) return {{}, "invalid_water"};
        next_profile.water = *derived;
    }
    if (water) {
        if (water->empty() || water->size() > 65536) return {{}, "invalid_water"};
        for (const auto& value : *water) {
            const auto* row = std::get_if<Array>(&value.storage());
            if (!row || row->size() != 6) return {{}, "invalid_water"};
            std::array<Integer, 6> fields{};
            for (std::size_t index = 0; index < fields.size(); ++index) {
                const auto* number = std::get_if<Integer>(&row->at(index).storage());
                if (!number) return {{}, "invalid_water"};
                fields[index] = *number;
            }
            if (!next_profile.water.emplace(std::array<Integer, 2>{fields[0], fields[1]},
                    waterwheel::Sample{fields[2], fields[3], fields[4], fields[5]}).second)
                return {{}, "invalid_water"};
        }
    }
    return {Binding{std::move(surface), std::move(next_profile),
        water || flow_cells || profile.ore_field || (source_obstacle && profile.material.manual_ore)}, nullptr};
}

bool Surface::blocked(const authority::Point& low, const authority::Point& high,
        std::optional<std::size_t> ignored) const {
    for (std::size_t index = 0; index < obstacles.size(); ++index) {
        if (ignored == index) continue;
        const auto& obstacle = obstacles[index];
        bool overlaps = true;
        for (std::size_t coordinate = 0; coordinate < 3; ++coordinate)
            if (high[coordinate] <= obstacle.first[coordinate] ||
                low[coordinate] >= obstacle.second[coordinate]) overlaps = false;
        if (overlaps) return true;
    }
    return false;
}

std::optional<std::pair<double, double>> Surface::range(double x, double z,
        double half_x, double half_z) const {
    if (axis.empty()) return std::nullopt;
    const double left = x - half_x, right = x + half_x;
    const double near = z - half_z, far = z + half_z;
    if (left < axis.front() || right > axis.back() || near < axis.front() || far > axis.back())
        return std::nullopt;
    const auto cell = [&](double at) {
        return std::min(axis.size() - 2, static_cast<std::size_t>(
            std::upper_bound(axis.begin(), axis.end(), at) - axis.begin() - 1));
    };
    const auto vertex = [&](std::size_t gx, std::size_t gz) {
        return authority::Point{axis[gx], heights[gz * axis.size() + gx], axis[gz]};
    };
    double low = std::numeric_limits<double>::infinity(), high = -low;
    for (auto gz = cell(near); gz <= cell(far); ++gz) for (auto gx = cell(left); gx <= cell(right); ++gx) {
        const auto a = vertex(gx, gz), b = vertex(gx + 1, gz), c = vertex(gx + 1, gz + 1), d = vertex(gx, gz + 1);
        for (const auto& tri : {std::array<authority::Point, 3>{a, b, c}, std::array<authority::Point, 3>{a, c, d}}) {
            std::array<authority::Point, 8> polygon{tri[0], tri[1], tri[2]};
            std::size_t polygon_size = 3;
            // A linear triangle's extreme height is at a clipped polygon vertex.
            for (const auto& [coordinate, boundary, sign] : {std::tuple{0, left, 1.0}, {0, right, -1.0},
                    {2, near, 1.0}, {2, far, -1.0}}) {
                std::array<authority::Point, 8> clipped{};
                std::size_t clipped_size = 0;
                for (std::size_t index = 0; index < polygon_size; ++index) {
                    const auto& p = polygon[index];
                    const auto& q = polygon[(index + 1) % polygon_size];
                    const bool inside = (p[coordinate] - boundary) * sign >= 0;
                    const bool next = (q[coordinate] - boundary) * sign >= 0;
                    if (inside) clipped[clipped_size++] = p;
                    if (inside != next) {
                        const auto t = (boundary - p[coordinate]) / (q[coordinate] - p[coordinate]);
                        clipped[clipped_size++] = {p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1]),
                            p[2] + t * (q[2] - p[2])};
                    }
                }
                polygon = clipped;
                polygon_size = clipped_size;
                if (polygon_size == 0) break;
            }
            for (std::size_t index = 0; index < polygon_size; ++index) {
                low = std::min(low, polygon[index][1]);
                high = std::max(high, polygon[index][1]);
            }
        }
    }
    return std::pair{low, high};
}

}  // namespace factory::godot_world::terrain_surface
