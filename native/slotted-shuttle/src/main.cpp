#include "factory/slotted_shuttle_workbench.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "play")
        return factory::slotted_shuttle::play(std::cin, std::cout, std::cerr);
    if (argc == 2 && std::string_view(argv[1]) == "list") {
        std::cout << "Slotted shuttle: make BOTH followers move within the recurring interval.\n";
        return 0;
    }
    std::cerr << "Use slotted_shuttle_workbench play|list.\n";
    return 2;
}
