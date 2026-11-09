#pragma once
#include "factory/terrain_surface.hpp"
#include "factory/ore_columns.hpp"
#include <array>
#include <optional>
#include <vector>

namespace factory::godot_world::excavated_terrain {
using Triangle=terrain_surface::Triangle;
using Mesh=terrain_surface::Mesh;
// Derived geometry only. The same triangles serve native floor/clearance and
// engine mesh/collision presentation. Natural terrain stays unchanged until a
// column actually loses stock; cutting exposes floor and vertical pit walls.
[[nodiscard]] std::optional<Mesh> build(const terrain_surface::Surface&,
    const world::ore_columns::Seed&,const world::ore_columns::Field&,const materials::State&);
[[nodiscard]] std::optional<std::pair<double,double>> range(const Mesh&,
    double x,double z,double half_x,double half_z);
}
