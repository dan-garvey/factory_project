// Read-only component inventory for the pinned CC0 Drill Press 01 body mesh.
#include "components.hpp"
#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
void require(bool good, const char* message) { if (!good) throw std::runtime_error(message); }
std::string hash(const std::string& bytes) {
    std::array<unsigned char, EVP_MAX_MD_SIZE> value{};
    unsigned count = 0;
    require(EVP_Digest(bytes.data(), bytes.size(), value.data(), &count, EVP_sha256(), nullptr) == 1 && count == 32,
            "Cannot hash the source.");
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (unsigned n = 0; n < count; ++n) out << std::setw(2) << unsigned(value[n]);
    return out.str();
}
float scalar(const std::string& bytes, std::size_t at) {
    std::uint32_t bits = 0;
    for (unsigned n = 0; n < 4; ++n) bits |= std::uint32_t(static_cast<unsigned char>(bytes[at + n])) << (8 * n);
    const float value = std::bit_cast<float>(bits);
    require(std::isfinite(value), "Nonfinite source vertex.");
    return value;
}
struct Group {
    std::size_t seed = 0, vertices = 0, triangles = 0;
    std::array<float, 3> low{100, 100, 100}, high{-100, -100, -100};
};
}  // namespace

int main(int argc, char** argv) {
    try {
        require(argc == 2, "Usage: inspect-press-components ORIGINAL.bin");
        const std::filesystem::path path(argv[1]);
        require(std::filesystem::is_regular_file(std::filesystem::symlink_status(path)) &&
                std::filesystem::file_size(path) == 1911136, "Expected the pinned regular source buffer.");
        std::ifstream in(path, std::ios::binary);
        const std::string bytes((std::istreambuf_iterator<char>(in)), {});
        require(hash(bytes) == "3c786cf21c206d1edb7df970067421fa692bbc1a941b279cd21605c33057f9ad", "The source identity changed.");
        constexpr std::size_t vertices = 25765, index_count = 93630, indices_at = 824480;
        factory_art::Components components(vertices);
        std::vector<std::array<float, 3>> points(vertices);
        std::map<std::array<long long, 3>, std::size_t> welded;
        for (std::size_t n = 0; n < vertices; ++n) {
            std::array<long long, 3> key{};
            for (unsigned axis = 0; axis < 3; ++axis) {
                points[n][axis] = scalar(bytes, n * 12 + axis * 4);
                key[axis] = std::llround(double(points[n][axis]) * 100000);
            }
            const auto [entry, fresh] = welded.emplace(key, n);
            if (!fresh) components.join(n, entry->second);
        }
        std::vector<std::size_t> indices(index_count);
        for (std::size_t n = 0; n < index_count; ++n) {
            indices[n] = static_cast<unsigned char>(bytes[indices_at + n * 2]) |
                         (std::size_t(static_cast<unsigned char>(bytes[indices_at + n * 2 + 1])) << 8);
            require(indices[n] < vertices, "The source index is invalid.");
        }
        for (std::size_t n = 0; n < index_count; n += 3) {
            components.join(indices[n], indices[n + 1]);
            components.join(indices[n], indices[n + 2]);
        }
        std::map<std::size_t, Group> groups;
        for (std::size_t n = 0; n < vertices; ++n) {
            auto& group = groups[components.root(n)];
            if (group.vertices++ == 0) group.seed = n;
            for (unsigned axis = 0; axis < 3; ++axis) {
                group.low[axis] = std::min(group.low[axis], points[n][axis]);
                group.high[axis] = std::max(group.high[axis], points[n][axis]);
            }
        }
        for (std::size_t n = 0; n < index_count; n += 3) ++groups.at(components.root(indices[n])).triangles;
        std::cout << std::setprecision(10) << "{\"status\":\"pass\",\"mesh\":\"drill_press_01\",\"components\":[";
        bool first = true;
        for (const auto& [root, group] : groups) {
            (void)root;
            if (!group.triangles) continue;
            if (!first) std::cout << ',';
            first = false;
            std::cout << "{\"seed\":" << group.seed << ",\"vertices\":" << group.vertices << ",\"triangles\":" << group.triangles
                      << ",\"min\":[" << group.low[0] << ',' << group.low[1] << ',' << group.low[2]
                      << "],\"max\":[" << group.high[0] << ',' << group.high[1] << ',' << group.high[2] << "]}";
        }
        std::cout << "]}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
