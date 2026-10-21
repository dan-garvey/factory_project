#include "factory/slotted_bank_workbench.hpp"

#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    std::vector<std::string_view> args;
    for (int index = 1; index < argc; ++index) args.emplace_back(argv[index]);
    return factory::slotted_bank::workbench(args, std::cin, std::cout, std::cerr);
}
