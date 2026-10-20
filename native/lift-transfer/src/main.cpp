#include "factory/lift_transfer.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char** argv) {
    namespace l = factory::lift;
    if (argc == 2 && std::string_view(argv[1]) == "play") return l::play(std::cin, std::cout, std::cerr);
    if (argc == 2 && std::string_view(argv[1]) == "compare") return l::compare(std::cout);
    if (argc == 2 && (std::string_view(argv[1]) == "list" || std::string_view(argv[1]) == "--help")) {
        std::cout << "Usage: lift_workbench play | compare | list\n"
                     "A fixed-cycle lift with a shared-shaft receiver cam and four retained metadata tags.\n";
        return std::cout ? 0 : 2;
    }
    std::cerr << "Usage: lift_workbench play | compare | list\n";
    return 2;
}
