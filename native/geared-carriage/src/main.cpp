#include "factory/geared_carriage_workbench.hpp"

#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    std::vector<std::string_view> arguments;
    for (int i = 1; i < argc; ++i) arguments.emplace_back(argv[i]);
    return factory::geared_carriage::workbench(arguments, std::cin, std::cout, std::cerr);
}
