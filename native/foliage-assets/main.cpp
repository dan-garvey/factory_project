#include "tuft.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string_view>

namespace {
factory::foliage::Bytes read(const char* path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file || file.tellg() < 0 || file.tellg() > 8 * 1024 * 1024)
        throw std::runtime_error("Missing or oversized source file.");
    factory::foliage::Bytes bytes(static_cast<std::size_t>(file.tellg()));
    file.seekg(0);
    if (!file.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size())))
        throw std::runtime_error("Cannot read source file.");
    return bytes;
}
}  // namespace

int main(int argc, char** argv) {
    try {
        const bool fern = argc == 7 && std::string_view(argv[1]) == "--fern";
        if (argc != 6 && !fern) throw std::runtime_error("Usage: pack_tuft [--fern] provider.bin albedo.png normal.png arm.png NEW.glb");
        const int first = fern ? 2 : 1;
        if (std::filesystem::exists(argv[first + 4])) throw std::runtime_error("Preserve the existing output; use a fresh destination.");
        const auto prepare = fern ? factory::foliage::pack_fern : factory::foliage::pack_tuft;
        const auto bytes = prepare(read(argv[first]), read(argv[first + 1]), read(argv[first + 2]), read(argv[first + 3]));
        std::ofstream file(argv[first + 4], std::ios::binary);
        if (!file || !file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size())))
            throw std::runtime_error("Cannot publish the validated GLB.");
        std::cout << (fern ? "Packed one fern: 544 vertices, 784 triangles, " : "Packed one tuft: 1386 vertices, 1257 triangles, ")
                  << bytes.size() << " bytes.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
