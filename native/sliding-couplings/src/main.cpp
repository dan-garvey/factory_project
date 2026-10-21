#include "factory/coupling_puzzles.hpp"

#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    std::vector<std::string_view> arguments;
    for (int i = 1; i < argc; ++i) arguments.emplace_back(argv[i]);
    return factory::coupling_puzzles::workbench(arguments, std::cin, std::cout, std::cerr);
}
