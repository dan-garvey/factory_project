#include "factory/fractional_slots_workbench.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "play")
        return factory::fractional_slots::play(std::cin, std::cout, std::cerr);
    if (argc == 2 && std::string_view(argv[1]) == "list") {
        std::cout << "Fractional slots: gear down, take up backlash and align the original tool.\n";
        return 0;
    }
    std::cerr << "Use fractional_slots_workbench play|list.\n";
    return 2;
}
