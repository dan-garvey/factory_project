#include "factory/pulley_loop_workbench.hpp"

#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    std::vector<std::string_view> args;
    for (int index = 1; index < argc; ++index) args.emplace_back(argv[index]);
    return factory::pulley_loop::workbench(args, std::cout, std::cerr);
}
