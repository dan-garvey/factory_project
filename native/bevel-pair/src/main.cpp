#include "factory/bevel_pair_workbench.hpp"

#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    std::vector<std::string_view> arguments;
    for (int index = 1; index < argc; ++index) arguments.emplace_back(argv[index]);
    return factory::bevel_pair::workbench(arguments, std::cout, std::cerr);
}
