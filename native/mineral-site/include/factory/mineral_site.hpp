#pragma once

#include <array>
#include <cstdint>

namespace factory::mineral_site {
using Integer = std::int64_t;

struct Cell {
    Integer x{};
    Integer z{};
    bool operator==(const Cell&) const = default;
};

// Reversible opening content. These immutable facts never hold remaining ore;
// the existing native World's material stock remains its sole quantity owner.
inline constexpr Integer opening_reserve = 4096;
inline constexpr Integer extraction_depth_steps = 8;
inline constexpr std::array<Cell, 2> opening_cells{{{0, 0}, {0, 1}}};

struct Surface {
    double low{};
    double high{};
};

enum class Error { none, outside_deposit, invalid_surface, below_surface, too_deep };
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] bool contains(Cell) noexcept;

// The trusted terrain producer supplies the actual emitted triangle height
// range under this mineral tile. The Host supplies the machine's world-space
// base and maximum depth using the SAME global height step as foundations.
// This is extraction admission, not construction support, body collision,
// character reach, force, or permission to change the surface or source stock.
[[nodiscard]] Error admit(Cell, double collector_base, Surface, double maximum_depth) noexcept;
}  // namespace factory::mineral_site
