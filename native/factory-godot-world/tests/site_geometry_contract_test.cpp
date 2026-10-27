#include "factory/site_geometry_contract.hpp"

#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Provide the tracked Godot site geometry script.\n";
        return 2;
    }
    std::ifstream script(argv[1], std::ios::binary);
    if (!script) {
        std::cerr << "Cannot read the tracked Godot site geometry script.\n";
        return 1;
    }
    const std::string source(std::istreambuf_iterator<char>{script}, {});
    constexpr auto begin_marker = "# BEGIN NATIVE SITE GEOMETRY\n";
    constexpr auto end_marker = "# END NATIVE SITE GEOMETRY\n";
    const auto begin = source.find(begin_marker);
    const auto end = begin == std::string::npos ? std::string::npos :
        source.find(end_marker, begin + std::char_traits<char>::length(begin_marker));
    if (begin == std::string::npos || end == std::string::npos ||
        source.find(begin_marker, begin + 1) != std::string::npos ||
        source.find(end_marker, end + 1) != std::string::npos ||
        source.substr(begin, end - begin + std::char_traits<char>::length(end_marker)) !=
            factory::godot_world::site_geometry::gdscript_block()) {
        std::cerr << "Godot site geometry values differ from the native generated block.\n";
        return 1;
    }
    std::cout << "Native and tracked Godot site geometry values match.\n";
}
