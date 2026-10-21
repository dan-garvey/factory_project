#include "factory/mineral_site.hpp"

#include <algorithm>
#include <cmath>

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

Error admit(Cell cell, double collector_base, Surface surface, double maximum_depth) noexcept {
    if (!contains(cell)) return Error::outside_deposit;
    if (!std::isfinite(collector_base) || !std::isfinite(surface.low) || !std::isfinite(surface.high) ||
        !std::isfinite(maximum_depth) || maximum_depth <= 0.0 || surface.low > surface.high)
        return Error::invalid_surface;
    if (collector_base < surface.high) return Error::below_surface;
    if (collector_base - surface.low > maximum_depth) return Error::too_deep;
    return Error::none;
}
}  // namespace factory::mineral_site
