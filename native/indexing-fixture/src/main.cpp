#include "factory/index_workbench.hpp"

#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    if (argc > 1 && std::string_view(argv[1]) == "play") {
        if (argc != 3) {
            std::cerr << "Usage: index_workbench play <puzzle>\n";
            return 2;
        }
        return factory::indexing::play(argv[2], std::cin, std::cout, std::cerr);
    }
    std::vector<std::string_view> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return factory::indexing::workbench(args, std::cout, std::cerr);
}
