#include "factory/slotted_pairs_workbench.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "play")
        return factory::slotted_pairs::play(std::cin, std::cout, std::cerr);
    if (argc == 2 && std::string_view(argv[1]) == "list") {
        std::cout << "Slotted pairs: separate the guides, spread the tools, or match the forward clearances.\n";
        return 0;
    }
    std::cerr << "Use slotted_pairs_workbench play|list.\n";
    return 2;
}
