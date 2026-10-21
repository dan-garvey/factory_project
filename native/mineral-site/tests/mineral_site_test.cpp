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
        coverage(); leveling(); invalid();
        std::cout << checks << " mineral footprint and vertical-clearance checks passed.\n";
    } catch (const std::exception& error) {
        std::cerr << "Failed after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
