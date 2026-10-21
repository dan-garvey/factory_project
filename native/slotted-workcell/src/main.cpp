#include "factory/slotted_workcell_workbench.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "play")
        return factory::slotted_workcell::play(std::cin, std::cout, std::cerr);
    if (argc == 2 && std::string_view(argv[1]) == "list") {
        std::cout << "Slotted work cell: separate the tools AND clear the stationary frame.\n";
        return 0;
    }
    std::cerr << "Use slotted_workcell_workbench play|list.\n";
    return 2;
}
