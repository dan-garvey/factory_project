#include "factory/mineral_site.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace factory::mineral_site {
const char* error_name(Error error) noexcept {
    switch (error) {
        case Error::none: return "ok";
        case Error::outside_deposit: return "not_at_seam";
        case Error::invalid_surface: return "invalid_source_surface";
        case Error::below_surface: return "collector_below_source";
        case Error::too_deep: return "source_too_deep";
    }
    return "invalid_source_surface";
}

bool contains(Cell cell) noexcept {
    return std::find(opening_cells.begin(), opening_cells.end(), cell) != opening_cells.end();
}

bool field_contains(Cell cell) noexcept {
    return cell.x >= field_min.x && cell.x <= field_max.x &&
           cell.z >= field_min.z && cell.z <= field_max.z;
}

std::optional<Integer> field_region(Cell cell) noexcept {
    if (!field_contains(cell)) return std::nullopt;
    const Integer z = cell.z - field_min.z;
    const Integer row = z < 4 ? 0 : z < 7 ? 1 : 2;
    const Integer column = cell.x < 4 ? 0 : 1;
    return row * 2 + column;
}

std::optional<RegionCells> field_region_cells(Integer index) noexcept {
    if (index < 0 || index >= field_region_count) return std::nullopt;
    const Integer row = index / 2;
    const Integer column = index % 2;
    const Integer first_z = row == 0 ? -8 : row == 1 ? -4 : -1;
    const Integer last_z = row == 0 ? -5 : row == 1 ? -2 : 1;
    return RegionCells{{column * 5 - 1, first_z}, {column * 5 + 3, last_z}};
}

std::optional<Cell> field_exposure_cell(Integer index) noexcept {
    const auto bounds = field_region_cells(index);
    if (!bounds) return std::nullopt;
    // Preserve the original physical rock as the north-west exposure.
    if (index == 4) return Cell{0, 0};
    return Cell{(bounds->low.x + bounds->high.x) / 2,
        (bounds->low.z + bounds->high.z) / 2};
}

std::optional<FieldStock> allocate_field(Integer total) noexcept {
    if (total < 0) return std::nullopt;
    FieldStock stock;
    const Integer each = total / field_region_count;
    const Integer extra = total % field_region_count;
    for (Integer index = 0; index < field_region_count; ++index)
        stock.remaining[static_cast<std::size_t>(index)] = each + (index < extra ? 1 : 0);
    return stock;
}

std::optional<Integer> field_total(const FieldStock& stock) noexcept {
    Integer total = 0;
    for (const Integer amount : stock.remaining) {
        if (amount < 0 || amount > std::numeric_limits<Integer>::max() - total)
            return std::nullopt;
        total += amount;
    }
    return total;
}

bool debit_field(FieldStock& stock, Cell cell) noexcept {
    const auto index = field_region(cell);
    if (!index || stock.remaining[static_cast<std::size_t>(*index)] <= 0) return false;
    --stock.remaining[static_cast<std::size_t>(*index)];
    return true;
}

static Error admit_surface(bool inside, double collector_base, Surface surface,
        double maximum_depth) noexcept {
    if (!inside) return Error::outside_deposit;
    if (!std::isfinite(collector_base) || !std::isfinite(surface.low) || !std::isfinite(surface.high) ||
        !std::isfinite(maximum_depth) || maximum_depth <= 0.0 || surface.low > surface.high)
        return Error::invalid_surface;
    if (collector_base < surface.high) return Error::below_surface;
    if (collector_base - surface.low > maximum_depth) return Error::too_deep;
    return Error::none;
}

Error admit(Cell cell, double collector_base, Surface surface, double maximum_depth) noexcept {
    return admit_surface(contains(cell), collector_base, surface, maximum_depth);
}

Error admit_field(Cell cell, double collector_base, Surface surface,
        double maximum_depth) noexcept {
    return admit_surface(field_contains(cell), collector_base, surface, maximum_depth);
}
}  // namespace factory::mineral_site
