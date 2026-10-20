#include "factory/indexed_clearance.hpp"

#include <charconv>
#include <iostream>
#include <string_view>

namespace f = factory::indexed_clearance;
int main(int argc, char** argv) {
    if (argc == 1 || (argc == 2 && std::string_view(argv[1]) == "--help")) {
        std::cout << "Usage: indexed_cycle <height 0..2> [short|detour|short_return]\n"
                     "Choose the fixed mounting height, then inspect, step or run the retained batch.\n";
        return 0;
    }
    if (argc > 3) return 2;
    f::Profile profile;
    const std::string_view height(argv[1]);
    const auto parsed = std::from_chars(height.data(), height.data() + height.size(), profile.height);
    if (parsed.ec != std::errc{} || parsed.ptr != height.data() + height.size() || profile.height < 0 || profile.height > 2) return 2;
    auto route = profile.height == 2 ? f::Route::short_path : f::Route::detour;
    if (argc == 3) {
        const std::string_view name(argv[2]);
        if (name == "short") route = f::Route::short_path;
        else if (name == "detour") route = f::Route::detour;
        else if (name == "short_return") route = f::Route::short_return;
        else return 2;
    }
    return f::play(profile, route, std::cin, std::cout, std::cerr);
}
