#pragma once

#include <array>
#include <cstdint>
#include <optional>

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

// Approved Chapter 1 field direction covers a ten-by-ten foundation-unit
// square. Region boundaries are native stock addresses, not visible walls.
// The existing two-cell opening remains active until its scene and collector
// contacts can be switched together with this broader footprint.
inline constexpr Cell field_min{-1, -8};
inline constexpr Cell field_max{8, 1};
inline constexpr Integer field_width = 10;
inline constexpr Integer field_area = field_width * field_width;
inline constexpr Integer field_region_count = 6;
[[nodiscard]] bool field_contains(Cell) noexcept;
[[nodiscard]] std::optional<Integer> field_region(Cell) noexcept;
struct RegionCells {
    Cell low{};
    Cell high{};
    bool operator==(const RegionCells&) const = default;
};
[[nodiscard]] std::optional<RegionCells> field_region_cells(Integer) noexcept;
[[nodiscard]] std::optional<Cell> field_exposure_cell(Integer) noexcept;

struct Surface {
    double low{};
    double high{};
};

struct FieldStock {
    std::array<Integer, field_region_count> remaining{};
    bool operator==(const FieldStock&) const = default;
};
[[nodiscard]] std::optional<FieldStock> allocate_field(Integer total) noexcept;
[[nodiscard]] std::optional<Integer> field_total(const FieldStock&) noexcept;
[[nodiscard]] bool debit_field(FieldStock&, Cell) noexcept;

enum class Error { none, outside_deposit, invalid_surface, below_surface, too_deep };
[[nodiscard]] const char* error_name(Error) noexcept;
[[nodiscard]] bool contains(Cell) noexcept;

// The trusted terrain producer supplies the actual emitted triangle height
// range under this mineral tile. The Host supplies the machine's world-space
// base and maximum depth using the SAME global height step as foundations.
// This is extraction admission, not construction support, body collision,
// character reach, force, or permission to change the surface or source stock.
[[nodiscard]] Error admit(Cell, double collector_base, Surface, double maximum_depth) noexcept;
[[nodiscard]] Error admit_field(Cell, double collector_base, Surface,
    double maximum_depth) noexcept;
}  // namespace factory::mineral_site
