#include "factory/index_drive.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char** argv) {
    if (argc == 2 && std::string_view(argv[1]) == "--help") {
        std::cout << "Usage: index_drive [1|-1]; use help inside the retained fixture.\n"; return 0;
    }
    if (argc > 2) return 2;
    int direction{1};
    if (argc == 2) {
        const std::string_view value(argv[1]);
        if (value == "-1") direction = -1;
        else if (value != "1") return 2;
    }
    return factory::index_drive::play(direction, std::cin, std::cout, std::cerr);
}
