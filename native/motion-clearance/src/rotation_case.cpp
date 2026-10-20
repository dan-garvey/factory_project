#include "factory/clearance.hpp"

#include <array>
#include <charconv>
#include <iostream>
#include <string_view>

namespace c = factory::clearance;

int main(int argc, char** argv) {
    c::Coordinate height{};
    if (argc > 2) return 64;
    if (argc == 2) {
        const std::string_view text(argv[1]);
        const auto parsed = std::from_chars(text.data(), text.data() + text.size(), height);
        if (parsed.ec != std::errc{} || parsed.ptr != text.data() + text.size()) return 64;
    }
    constexpr auto bound = factory::mechanics::maximum_coordinate;
    if (height < -bound + 1 || height > bound - 1) return 64;
    const c::Rotor arm{{{2, height - 1, -1}, {3, height + 1, 1}}, {0, height, 0}};
    const std::array<c::Obstacle, 1> obstacles{{{7, {{1, -1, 1}, {2, 1, 2}}}}};
    const std::array<c::Box, 4> stops{{
        arm.box, {{-1, height - 1, 2}, {1, height + 1, 3}},
        {{-3, height - 1, -1}, {-2, height + 1, 1}},
        {{-1, height - 1, -3}, {1, height + 1, -2}},
    }};
    bool stops_clear = true;
    for (const auto& box : stops) stops_clear = stops_clear && c::sweep(box, {}, obstacles).clear();
    const auto result = c::full_turn(arm, obstacles);
    if (result.error != c::Error::none) {
        std::cout << "{\"accepted\":false,\"error\":\"" << c::error_name(result.error) << "\"}\n";
        return 1;
    }
    std::cout << std::boolalpha << "{\"accepted\":true,\"height\":" << height
              << ",\"quarter_stops_clear\":" << stops_clear
              << ",\"continuous_full_turn_clear\":" << result.clear()
              << ",\"obstacle\":" << (result.hit ? result.hit->obstacle : 0)
              << ",\"world_commands\":0,\"engine_calls\":0}\n";
    return 0;
}
