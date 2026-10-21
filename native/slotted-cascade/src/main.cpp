#include "factory/slotted_cascade_workbench.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "play")
        return factory::slotted_cascade::play(std::cin, std::cout, std::cerr);
    if (argc == 2 && std::string_view(argv[1]) == "list") {
        std::cout << "Slotted cascade: the first guide stops before the last tool moves.\n";
        return 0;
    }
    std::cerr << "Use slotted_cascade_workbench play|list.\n";
    return 2;
}
