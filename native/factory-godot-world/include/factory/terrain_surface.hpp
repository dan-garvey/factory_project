#pragma once

#include "factory/checkpoint.hpp"

#include <cstddef>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace factory::godot_world::terrain_surface {

using Triangle = std::array<authority::Point, 3>;
// Derived from trusted terrain and native column quantities. The spatial index
// only accelerates queries; both native and scene consumers use these faces.
struct Mesh {
    std::vector<Triangle> faces;
    std::vector<double> axis;
    std::map<std::size_t, std::vector<std::size_t>> bins;
    void index(const std::vector<double>& terrain_axis);
    [[nodiscard]] std::optional<std::pair<double, double>> range(double x, double z,
        double half_x, double half_z) const;
};

// The trusted terrain producer binds exactly the vertices used by the rendered
// site. Queries clip those emitted triangles rather than approximating a cell.
struct Surface {
    std::vector<double> axis;
    std::vector<double> heights;
    std::vector<std::pair<authority::Point, authority::Point>> obstacles;
    std::optional<std::size_t> source_obstacle;
    std::map<std::size_t, std::string> tree_obstacles;
    std::shared_ptr<const Mesh> excavated{};

    [[nodiscard]] bool bound() const { return !axis.empty(); }
    [[nodiscard]] bool blocked(const authority::Point& low, const authority::Point& high,
        std::optional<std::size_t> ignored = std::nullopt) const;
    [[nodiscard]] std::optional<std::pair<double, double>> range(double x, double z,
        double half_x = 0.825, double half_z = 0.825) const;
    [[nodiscard]] std::optional<std::pair<double, double>> natural_range(double x, double z,
        double half_x, double half_z) const;
    [[nodiscard]] std::optional<authority::Point> natural_highest(double x, double z,
        double half_x, double half_z) const;
};

struct Binding {
    Surface surface;
    world::Profile profile;
    bool replace_world{};
};

struct ParseResult {
    std::optional<Binding> binding;
    const char* refusal{};
};

// Parsing is read-only. Host alone commits the profile/World replacement after
// checking the current revision, then installs this surface atomically.
[[nodiscard]] ParseResult parse(const values::Value::Object& input, const world::Profile& profile);

}  // namespace factory::godot_world::terrain_surface
