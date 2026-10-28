#include "factory/mineral_site.hpp"

#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string_view>

namespace s = factory::mineral_site;
namespace {
int checks{};
void check(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

void coverage() {
    check(s::opening_reserve == 4096, "The opening node has a larger explicitly finite reserve.");
    check(s::opening_cells.size() == 2, "The mineral surface has two shared footprint tiles.");
    for (s::Integer x = -3; x <= 3; ++x) for (s::Integer z = -4; z <= 4; ++z) {
        const bool expected = x == 0 && (z == 0 || z == 1);
        check(s::contains({x, z}) == expected, "Only the two literal mineral tiles belong to the deposit.");
        check((s::admit({x, z}, 0.0, {-0.02, -0.02}, 3.3) == s::Error::none) == expected,
              "A whole column cannot substitute for the finite mineral footprint.");
    }
    for (const auto edge : {std::numeric_limits<s::Integer>::min(), std::numeric_limits<s::Integer>::max()}) {
        check(!s::contains({edge, 0}) && !s::contains({0, edge}), "Far integer coordinates do not wrap into the deposit.");
    }
}

void approved_field_direction() {
    check(s::field_width == 10 && s::field_area == 100,
          "The approved field covers one hundred foundation-unit ground cells.");
    check(s::field_min == s::Cell{-1, -8} && s::field_max == s::Cell{8, 1},
          "The field includes the original near-bank exposure and extends inland.");
    std::array<s::Integer, s::field_region_count> cells{};
    for (s::Integer x = -2; x <= 9; ++x) for (s::Integer z = -9; z <= 2; ++z) {
        const bool inside = x >= -1 && x <= 8 && z >= -8 && z <= 1;
        check(s::field_contains({x, z}) == inside,
              "Only cells within the complete ten-by-ten square belong to the field.");
        const auto region = s::field_region({x, z});
        check(region.has_value() == inside,
              "Each mineable cell has one finite local stock address.");
        if (region) {
            check(*region >= 0 && *region < s::field_region_count,
                  "A local field address stays in the declared region set.");
            ++cells[static_cast<std::size_t>(*region)];
        }
    }
    check(cells == std::array<s::Integer, s::field_region_count>{20, 20, 15, 15, 15, 15},
          "Six local regions cover the entire square without overlap or gaps.");
    for (s::Integer index = 0; index < s::field_region_count; ++index) {
        const auto bounds = s::field_region_cells(index);
        check(bounds && s::field_region(bounds->low) == index &&
                  s::field_region(bounds->high) == index,
              "The declared region cell bounds match the cell-to-stock address.");
        const auto exposure = s::field_exposure_cell(index);
        check(exposure && s::field_region(*exposure) == index,
              "Every local stock region has an actual contact inside its footprint.");
    }
    check(!s::field_region_cells(-1) && !s::field_region_cells(s::field_region_count),
          "Unknown region indices cannot yield a valid contact area.");
    const auto initial = s::allocate_field(s::opening_reserve);
    check(initial && s::field_total(*initial) == s::opening_reserve,
          "All initial local quantities sum to the one finite native reserve.");
    check(!s::allocate_field(-1), "A negative reserve cannot become local stock.");
    auto stock = *initial;
    const auto untouched = stock.remaining[1];
    for (s::Integer n = 0; n < initial->remaining[0]; ++n)
        check(s::debit_field(stock, {-1, -8}),
              "A local region can be drawn down one unit at a time.");
    check(!s::debit_field(stock, {3, -5}) && stock.remaining[1] == untouched &&
              s::field_total(stock) == s::opening_reserve - initial->remaining[0],
          "An exhausted region cannot borrow its neighbor's finite stock.");
    const auto before = stock;
    check(!s::debit_field(stock, {-2, -8}) && stock == before,
          "A cut outside the field cannot change any local quantity.");
    stock.remaining[2] = -1;
    check(!s::field_total(stock), "Negative restored local stock is invalid.");
    stock.remaining[2] = std::numeric_limits<s::Integer>::max();
    check(!s::field_total(stock), "Overflowing restored local stock is invalid.");
}

void leveling() {
    // Literal existing global grid: pitch 1.65, four height levels per tile.
    // The Host, rather than this rule, supplies that shared scale in production.
    constexpr double step = 1.65 / 4.0;
    constexpr double maximum = s::extraction_depth_steps * step;
    check(maximum == 3.3, "Eight common height steps bound the extraction clearance.");
    check(s::admit({0, 0}, 0.0, {-0.02, -0.02}, maximum) == s::Error::none,
          "An uncovered natural deposit remains usable directly from its surface.");
    check(s::admit({0, 1}, 4 * step, {-0.3, 0.4}, maximum) == s::Error::none,
          "A full foundation block can level sloping mineral terrain without moving the ore.");
    check(s::admit({0, 0}, 8 * step, {0.0, 0.4}, maximum) == s::Error::none,
          "The declared upper extraction boundary is inclusive.");
    check(s::admit({0, 0}, 9 * step, {0.0, 0.4}, maximum) == s::Error::too_deep,
          "Another global height step does not silently extend the drill.");
    check(s::admit({0, 0}, std::nextafter(maximum, std::numeric_limits<double>::infinity()), {0.0, 0.0}, maximum) == s::Error::too_deep,
          "A next-representable height beyond the depth limit is refused without epsilon.");
    check(s::admit({0, 0}, 0.0, {-0.02, std::nextafter(0.0, 1.0)}, maximum) == s::Error::below_surface,
          "A collector below any of the covered mineral surface is refused.");
    check(s::admit({0, 1}, -2 * step, {-1.5, -1.0}, maximum) == s::Error::none,
          "Negative global elevations need no separate local foundation origin.");
    check(s::admit({0, 1}, 4 * step, {-2.0, 0.4}, maximum) == s::Error::too_deep,
          "A deep portion of a slope must also remain inside the extraction range.");
}

void invalid() {
    const auto nan = std::numeric_limits<double>::quiet_NaN();
    const auto inf = std::numeric_limits<double>::infinity();
    for (const auto value : {nan, inf, -inf}) {
        check(s::admit({0, 0}, value, {0.0, 0.0}, 3.3) == s::Error::invalid_surface, "Invalid base has no mining permission.");
        check(s::admit({0, 0}, 0.0, {value, 0.0}, 3.3) == s::Error::invalid_surface, "Invalid low sample has no mining permission.");
        check(s::admit({0, 0}, 0.0, {0.0, value}, 3.3) == s::Error::invalid_surface, "Invalid high sample has no mining permission.");
        check(s::admit({0, 0}, 0.0, {0.0, 0.0}, value) == s::Error::invalid_surface, "Invalid drill depth has no mining permission.");
    }
    check(s::admit({0, 0}, 0.0, {1.0, -1.0}, 3.3) == s::Error::invalid_surface, "An inverted terrain range is invalid.");
    check(s::admit({0, 0}, 0.0, {0.0, 0.0}, 0.0) == s::Error::invalid_surface, "A zero drill range is not valid.");
    check(s::admit({0, 0}, 0.0, {0.0, 0.0}, -1.0) == s::Error::invalid_surface, "A negative drill range is not valid.");
    check(std::string_view(s::error_name(s::Error::outside_deposit)) == "not_at_seam" &&
          std::string_view(s::error_name(s::Error::too_deep)) == "source_too_deep", "Caller refusals distinguish coverage from excessive height.");
}
}  // namespace

int main() {
    try {
        coverage(); approved_field_direction(); leveling(); invalid();
        std::cout << checks << " mineral footprint and vertical-clearance checks passed.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
