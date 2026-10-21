#pragma once

#include <array>
#include <cstddef>
#include <span>
#include <vector>

namespace factory_art::coupling {
using Point = std::array<double, 3>;
struct Vertex {
  Point position{}, normal{};
  std::array<double, 2> uv{};
};
using Triangle = std::array<Vertex, 3>;
struct Mesh {
  std::vector<Triangle> source;
  std::vector<Triangle> cut;
};

// Offline art geometry only. Keep y >= plane and close exactly two nested,
// strictly nested, star-shaped cut loops around the mounting axis.
// Preserve retained attributes; interpolate new cut vertices.
// Refuse open, branched, nonradial or nonannular boundaries rather than filling
// the shaft passage. No source file, native World or collision rule is owned.
[[nodiscard]] Mesh cut_shell(std::span<const Triangle>, double plane);

// One exact Poly Haven Modular Industrial Pipes 01 source layout and identity.
// Select the first straight member and its upper fasteners, remove the blind
// cap, normalize around an authored flange datum, then apply a uniform scale.
[[nodiscard]] Mesh prepare(std::span<const unsigned char>);
inline constexpr double source_cut = 0.39;
inline constexpr double source_datum = 0.42954;
inline constexpr double scale = 0.72;
} // namespace factory_art::coupling
