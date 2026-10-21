#include "factory/waterflow.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace factory::waterflow {
namespace {
using Integer = mechanics::Integer;

std::optional<double> ground(const Terrain& terrain, double x, double z) {
    const auto& axis = terrain.axis;
    if (axis.size() < 2 || terrain.heights.size() != axis.size() * axis.size() ||
        x < axis.front() || x > axis.back() || z < axis.front() || z > axis.back()) return std::nullopt;
    const auto cell = [&](double point) {
        const auto next = std::upper_bound(axis.begin(), axis.end(), point);
        return std::min(axis.size() - 2, static_cast<std::size_t>(next - axis.begin() - (next != axis.begin())));
    };
    const auto ix = cell(x), iz = cell(z), stride = axis.size();
    const auto u = (x - axis[ix]) / (axis[ix + 1] - axis[ix]);
    const auto v = (z - axis[iz]) / (axis[iz + 1] - axis[iz]);
    const auto a = terrain.heights[iz * stride + ix];
    const auto b = terrain.heights[iz * stride + ix + 1];
    const auto c = terrain.heights[(iz + 1) * stride + ix];
    const auto d = terrain.heights[(iz + 1) * stride + ix + 1];
    return u >= v ? a * (1 - u) + b * (u - v) + d * v :
                    a * (1 - v) + d * u + c * (v - u);
}

bool clear_path(const Terrain& terrain, const Cell& from, const Cell& to) {
    const auto x0 = from.x * terrain.meters_per_step;
    const auto z0 = from.z * terrain.meters_per_step;
    const auto x1 = to.x * terrain.meters_per_step;
    const auto z1 = to.z * terrain.meters_per_step;
    for (int index = 0; index <= 16; ++index) {
        const auto t = index / 16.0;
        const auto bed = ground(terrain, x0 + (x1 - x0) * t, z0 + (z1 - z0) * t);
        const auto water = (from.surface + (to.surface - from.surface) * t) * terrain.meters_per_step / 100.0;
        if (!bed || *bed >= water) return false;
    }
    return true;
}

double wet_width(const Terrain& terrain, const Cell& cell) {
    const auto x = cell.x * terrain.meters_per_step;
    const auto z = cell.z * terrain.meters_per_step;
    const auto water = cell.surface * terrain.meters_per_step / 100.0;
    double width{};
    for (const int sign : {-1, 1}) {
        for (double offset = 0.125; offset <= 8.0; offset += 0.125) {
            const auto bed = ground(terrain, x + sign * offset, z);
            if (!bed || *bed >= water) break;
            width += 0.125;
        }
    }
    return width;
}
}  // namespace

std::optional<std::map<std::array<Integer, 2>, waterwheel::Sample>>
derive(const Terrain& terrain, const std::vector<Cell>& cells) {
    if (terrain.axis.size() < 2 || terrain.axis.size() > 200 ||
        terrain.heights.size() != terrain.axis.size() * terrain.axis.size() ||
        cells.empty() || cells.size() > 65536 || !std::isfinite(terrain.meters_per_step) ||
        terrain.meters_per_step < 0.001 || terrain.meters_per_step > 1000) return std::nullopt;
    for (std::size_t index = 0; index < terrain.axis.size(); ++index)
        if (!std::isfinite(terrain.axis[index]) ||
            (index != 0 && terrain.axis[index - 1] >= terrain.axis[index])) return std::nullopt;
    for (const auto height : terrain.heights)
        if (!std::isfinite(height) || std::abs(height * 100.0 / terrain.meters_per_step) >
            mechanics::maximum_coordinate) return std::nullopt;
    std::map<std::array<Integer, 2>, waterwheel::Sample> result;
    std::map<std::array<Integer, 2>, const Cell*> positions;
    for (const auto& cell : cells) {
        if (cell.x < -mechanics::maximum_coordinate || cell.x > mechanics::maximum_coordinate ||
            cell.z < -mechanics::maximum_coordinate || cell.z > mechanics::maximum_coordinate ||
            cell.surface < -mechanics::maximum_coordinate || cell.surface > mechanics::maximum_coordinate ||
            cell.x % 4 != 0 || cell.z % 4 != 0) return std::nullopt;
        const auto actual = ground(terrain, cell.x * terrain.meters_per_step,
                                            cell.z * terrain.meters_per_step);
        if (!actual || !std::isfinite(*actual) || *actual >= cell.surface * terrain.meters_per_step / 100.0)
            return std::nullopt;
        const auto bed = static_cast<Integer>(std::llround(*actual * 100.0 / terrain.meters_per_step));
        if (bed >= cell.surface) return std::nullopt;
        if (!result.emplace(std::array<Integer, 2>{cell.x, cell.z},
                            waterwheel::Sample{cell.surface, bed, 0, 0}).second)
            return std::nullopt;
        positions.emplace(std::array<Integer, 2>{cell.x, cell.z}, &cell);
    }
    for (const auto& cell : cells) {
        const Cell* target = nullptr;
        double best_distance = std::numeric_limits<double>::infinity();
        for (const Integer dx : {-4, 0, 4}) for (const Integer dz : {-4, 0, 4}) {
            if (dx == 0 && dz == 0) continue;
            const auto found = positions.find({cell.x + dx, cell.z + dz});
            if (found == positions.end()) continue;
            const auto& candidate = *found->second;
            if (candidate.surface >= cell.surface) continue;
            // Adjacent square cells may turn in any direction. A diagonal
            // must pass the same terrain-clearance check as an axial step.
            const auto distance = std::hypot(static_cast<double>(dx), static_cast<double>(dz));
            if (distance >= best_distance || !clear_path(terrain, cell, candidate)) continue;
            best_distance = distance;
            target = &candidate;
        }
        if (!target) continue;
        const auto width = wet_width(terrain, cell);
        const auto& sample = result.at({cell.x, cell.z});
        const auto depth = (cell.surface - sample.bed) * terrain.meters_per_step / 100.0;
        if (width <= 0 || depth <= 0) continue;
        const auto slope = (cell.surface - target->surface) / (100.0 * best_distance);
        const auto speed = std::clamp(0.45 * (1.6 / width) *
                                    std::sqrt(slope / 0.005) * std::sqrt(depth), 0.05, 1.6);
        auto& driven = result.at({cell.x, cell.z});
        driven.velocity_x = static_cast<Integer>(std::llround(speed * (target->x - cell.x) /
                                               best_distance * 100.0 / terrain.meters_per_step));
        driven.velocity_z = static_cast<Integer>(std::llround(speed * (target->z - cell.z) /
                                               best_distance * 100.0 / terrain.meters_per_step));
    }
    return result;
}

}  // namespace factory::waterflow
