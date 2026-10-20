#include "factory/clearance.hpp"

#include <array>
#include <charconv>
#include <iostream>
#include <string_view>

namespace c = factory::clearance;
int main(int argc, char** argv) {
    if (argc < 2 || argc > 3) return 64;
    const std::string_view plan(argv[1]);
    if (plan != "short" && plan != "detour") return 64;
    c::Coordinate height{};
    if (argc == 3) {
        const std::string_view text(argv[2]);
        const auto parsed = std::from_chars(text.data(), text.data() + text.size(), height);
        if (parsed.ec != std::errc{} || parsed.ptr != text.data() + text.size()) return 64;
    }
    constexpr auto bound = factory::mechanics::maximum_coordinate;
    if (height < -bound + 1 || height > bound - 1) return 64;
    c::Rotor current{{{2, height - 1, -1}, {3, height + 1, 1}}, {0, height, 0}};
    const c::Box target{{-1, height - 1, 2}, {1, height + 1, 3}};
    const std::array<c::Obstacle, 1> obstacles{{{7, {{1, -1, 1}, {2, 1, 2}}}}};
    const auto direction = plan == "short" ? c::TurnDirection::negative : c::TurnDirection::positive;
    const int requested = plan == "short" ? 1 : 3;
    int completed{};
    std::uint64_t blocker{};
    bool held_on_block = true;
    for (int step = 0; step < requested; ++step) {
        const auto before = current;
        const auto result = c::quarter_turn(current, direction, obstacles);
        if (result.error != c::Error::none) {
            std::cout << "{\"accepted\":false,\"error\":\"" << c::error_name(result.error) << "\"}\n"; return 1;
        }
        if (result.obstacle) { blocker = *result.obstacle; held_on_block = current == before; break; }
        // Only the fixture caller commits its pose after a clear proposal.
        const auto& b = before.box;
        if (direction == c::TurnDirection::positive) {
            current.box = {{b.minimum[2], b.minimum[1], -b.maximum[0]}, {b.maximum[2], b.maximum[1], -b.minimum[0]}};
        } else {
            current.box = {{-b.maximum[2], b.minimum[1], b.minimum[0]}, {-b.minimum[2], b.maximum[1], b.maximum[0]}};
        }
        ++completed;
    }
    std::cout << std::boolalpha << "{\"accepted\":true,\"plan\":\"" << plan << "\",\"height\":" << height
              << ",\"completed_quarters\":" << completed << ",\"reached_target\":" << (current.box == target)
              << ",\"held_on_block\":" << held_on_block << ",\"obstacle\":" << blocker
              << ",\"world_commands\":0,\"engine_calls\":0}\n";
    return 0;
}
