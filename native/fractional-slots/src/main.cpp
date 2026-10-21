#include "factory/fractional_slots_workbench.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "play")
        return factory::fractional_slots::play(std::cin, std::cout, std::cerr);
    if (argc == 3 && std::string_view(argv[1]) == "play")
        return factory::fractional_slots::play(std::cin, std::cout, std::cerr, argv[2]);
    if (argc == 2 && std::string_view(argv[1]) == "list") {
        std::cout << "Fractional slots: calibration aligns one tool; tandem aligns both original tools on one pin.\n"
                     "Use play calibration or play tandem.\n";
        return 0;
    }
    std::cerr << "Use fractional_slots_workbench play|list.\nOptional puzzle: play calibration|tandem.\n";
    return 2;
}
