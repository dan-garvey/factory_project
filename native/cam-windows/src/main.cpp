#include "factory/cam_windows_workbench.hpp"

#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    std::vector<std::string_view> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return factory::cam_windows::workbench(args, std::cout, std::cerr);
}
