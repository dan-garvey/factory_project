#include "tuft.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

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
        if (argc != 6) throw std::runtime_error("Usage: pack_tuft provider.bin albedo.png normal.png arm.png NEW.glb");
        if (std::filesystem::exists(argv[5])) throw std::runtime_error("Preserve the existing output; use a fresh destination.");
        const auto bytes = factory::foliage::pack_tuft(read(argv[1]), read(argv[2]), read(argv[3]), read(argv[4]));
        std::ofstream file(argv[5], std::ios::binary);
        if (!file || !file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size())))
            throw std::runtime_error("Cannot publish the validated GLB.");
        std::cout << "Packed one tuft: 1386 vertices, 1257 triangles, " << bytes.size() << " bytes.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
