#pragma once

#include "factory/waterwheel.hpp"

#include <array>
#include <map>
#include <optional>
#include <vector>

namespace factory::waterflow {

// A proposed water level at a world-grid cell. Bed and current are determined
// from the same emitted terrain triangles used by native placement.
struct Cell {
    mechanics::Integer x{};
    mechanics::Integer z{};
    mechanics::Integer surface{};
};

struct Terrain {
    std::vector<double> axis;
    std::vector<double> heights;
    double meters_per_step{};
};

// The bounded demo model routes local current to a connected, lower water
// cell only when the path remains below its water level. It is a stationary
// surface-flow model, not a volume-conserving fluid simulation.
[[nodiscard]] std::optional<std::map<std::array<mechanics::Integer, 2>, waterwheel::Sample>>
derive(const Terrain& terrain, const std::vector<Cell>& cells);

}  // namespace factory::waterflow
