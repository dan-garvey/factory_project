// Extract the column, cast collar and fasteners from Poly Haven's CC0 Drill Press 01.
// This deliberately accepts one exact source layout, not arbitrary glTF input.
#include <openssl/evp.h>
#include "components.hpp"

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
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using Point = std::array<float, 3>;
constexpr std::size_t source_vertices = 25765;
constexpr std::size_t source_indices = 93630;
constexpr std::size_t normal_offset = 309180;
constexpr std::size_t uv_offset = 618360;
constexpr std::size_t index_offset = 824480;
constexpr std::array<std::size_t, 14> seeds{
    4270, 3485, 2601, 2765, 2790, 3005, 3030, 3245, 3270, 4024, 4106, 4188, 2343, 2367};
constexpr const char* source_hash = "3c786cf21c206d1edb7df970067421fa692bbc1a941b279cd21605c33057f9ad";

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

std::string digest(const std::string& bytes) {
    std::array<unsigned char, EVP_MAX_MD_SIZE> output{};
    unsigned count = 0;
    require(EVP_Digest(bytes.data(), bytes.size(), output.data(), &count, EVP_sha256(), nullptr) == 1
                && count == 32, "Cannot hash the source.");
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (unsigned i = 0; i < count; ++i) out << std::setw(2) << unsigned(output[i]);
    return out.str();
}

std::uint32_t word(const std::string& bytes, std::size_t at) {
    require(at + 4 <= bytes.size(), "Source word exceeds the buffer.");
    std::uint32_t value = 0;
    for (unsigned i = 0; i < 4; ++i) value |= std::uint32_t(static_cast<unsigned char>(bytes[at + i])) << (8 * i);
    return value;
}

float scalar(const std::string& bytes, std::size_t at) {
    const float value = std::bit_cast<float>(word(bytes, at));
    require(std::isfinite(value), "The source has a nonfinite attribute.");
    return value;
}

void append(std::string& bytes, float value) {
    const auto bits = std::bit_cast<std::uint32_t>(value);
    for (unsigned i = 0; i < 4; ++i) bytes.push_back(static_cast<char>((bits >> (8 * i)) & 255));
}

void write(const std::filesystem::path& path, const std::string& bytes) {
    std::ofstream out(path, std::ios::binary);
    out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    out.close();
    require(bool(out), "Cannot finish the prepared asset.");
}

} // namespace

int main(int argc, char** argv) {
    try {
        require(argc == 3, "Usage: prepare-press-support SOURCE.bin FRESH_OUTPUT_DIRECTORY");
        const std::filesystem::path input(argv[1]), output(argv[2]);
        require(std::filesystem::is_regular_file(std::filesystem::symlink_status(input))
                    && std::filesystem::file_size(input) == 1911136, "Expected the exact regular source buffer.");
        std::ifstream in(input, std::ios::binary);
        const std::string bytes((std::istreambuf_iterator<char>(in)), {});
        require(digest(bytes) == source_hash, "Source SHA256 differs from the documented recipe.");
        require(!std::filesystem::exists(std::filesystem::symlink_status(output)), "The output must be fresh.");

        factory_art::Components components(source_vertices);
        std::vector<Point> positions(source_vertices);
        std::map<std::array<long long, 3>, std::size_t> welded;
        for (std::size_t i = 0; i < source_vertices; ++i) {
            std::array<long long, 3> key{};
            for (unsigned a = 0; a < 3; ++a) {
                positions[i][a] = scalar(bytes, i * 12 + a * 4);
                key[a] = std::llround(double(positions[i][a]) * 100000);
            }
            const auto [entry, fresh] = welded.emplace(key, i);
            if (!fresh) components.join(i, entry->second);
        }
        std::vector<std::size_t> indices(source_indices);
        for (std::size_t i = 0; i < source_indices; ++i) {
            const auto at = index_offset + i * 2;
            indices[i] = static_cast<unsigned char>(bytes[at]) |
                         (std::size_t(static_cast<unsigned char>(bytes[at + 1])) << 8);
            require(indices[i] < source_vertices, "A source index exceeds the vertex array.");
        }
        for (std::size_t i = 0; i < source_indices; i += 3) {
            components.join(indices[i], indices[i + 1]);
            components.join(indices[i], indices[i + 2]);
        }
        std::set<std::size_t> selected;
        for (const auto seed : seeds) selected.insert(components.root(seed));
        require(selected.size() == seeds.size(), "Source component separation changed.");
        std::vector<std::size_t> chosen;
        for (std::size_t i = 0; i < source_indices; i += 3)
            if (selected.contains(components.root(indices[i])))
                chosen.insert(chosen.end(), indices.begin() + i, indices.begin() + i + 3);
        require(chosen.size() == 2094 * 3, "The declared column, collar and fasteners changed.");
        Point column_low{100, 100, 100}, column_high{-100, -100, -100};
        double mount_y = 100;
        const auto column_root = components.root(4270), plate_root = components.root(2601);
        for (std::size_t i = 0; i < source_vertices; ++i) {
            if (components.root(i) == column_root)
                for (unsigned a = 0; a < 3; ++a) {
                    column_low[a] = std::min(column_low[a], positions[i][a]);
                    column_high[a] = std::max(column_high[a], positions[i][a]);
                }
            if (components.root(i) == plate_root) mount_y = std::min(mount_y, double(positions[i][1]));
        }
        const std::array<double, 3> origin{(double(column_low[0]) + column_high[0]) / 2,
                                         mount_y, (double(column_low[2]) + column_high[2]) / 2};
        const double source_height = double(column_high[1]) - mount_y;
        require(source_height > 0.50 && source_height < 0.54, "The source mounting interface changed.");

        std::map<std::size_t, std::uint16_t> remap;
        std::vector<std::size_t> vertices;
        for (const auto i : chosen) {
            if (remap.contains(i)) continue;
            require(vertices.size() < 65536, "The output index type cannot represent these vertices.");
            remap.emplace(i, static_cast<std::uint16_t>(vertices.size()));
            vertices.push_back(i);
        }
        const double scale = 1.16 / source_height;
        std::string data;
        Point low{100, 100, 100}, high{-100, -100, -100};
        for (const auto i : vertices) {
            const Point point{float((positions[i][0] - origin[0]) * scale),
                              float((positions[i][1] - origin[1]) * scale),
                              float((positions[i][2] - origin[2]) * scale)};
            for (unsigned a = 0; a < 3; ++a) {
                append(data, point[a]); low[a] = std::min(low[a], point[a]); high[a] = std::max(high[a], point[a]);
            }
        }
        const auto normals_at = data.size();
        for (const auto i : vertices) {
            Point normal{scalar(bytes, normal_offset + i * 12),
                         scalar(bytes, normal_offset + i * 12 + 4), scalar(bytes, normal_offset + i * 12 + 8)};
            const double length = std::sqrt(double(normal[0]) * normal[0] + double(normal[1]) * normal[1]
                                            + double(normal[2]) * normal[2]);
            require(length > 0.98 && length < 1.02, "The source normal is not usable.");
            for (const auto n : normal) append(data, float(n / length));
        }
        const auto uv_at = data.size();
        for (const auto i : vertices)
            for (unsigned a = 0; a < 2; ++a) append(data, scalar(bytes, uv_offset + i * 8 + a * 4));
        const auto indices_at = data.size();
        for (const auto i : chosen) {
            const auto index = remap.at(i);
            data.push_back(static_cast<char>(index & 255)); data.push_back(static_cast<char>(index >> 8));
        }
        const auto index_bytes = data.size() - indices_at;
        while (data.size() % 4) data.push_back('\0');
        const auto count = vertices.size();
        std::ostringstream gltf;
        gltf << std::setprecision(9)
             << "{\"asset\":{\"version\":\"2.0\",\"generator\":\"Factory CC0 cast support recipe\"},"
             << "\"scene\":0,\"scenes\":[{\"nodes\":[0]}],\"nodes\":[{\"name\":\"CastPressSupport\",\"mesh\":0}],"
             << "\"meshes\":[{\"name\":\"CastColumnWithCollar\",\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1,\"TEXCOORD_0\":2},\"indices\":3}]}],"
             << "\"buffers\":[{\"uri\":\"press_support.bin\",\"byteLength\":" << data.size() << "}],\"bufferViews\":["
             << "{\"buffer\":0,\"byteOffset\":0,\"byteLength\":" << count * 12 << ",\"target\":34962},"
             << "{\"buffer\":0,\"byteOffset\":" << normals_at << ",\"byteLength\":" << count * 12 << ",\"target\":34962},"
             << "{\"buffer\":0,\"byteOffset\":" << uv_at << ",\"byteLength\":" << count * 8 << ",\"target\":34962},"
             << "{\"buffer\":0,\"byteOffset\":" << indices_at << ",\"byteLength\":" << index_bytes << ",\"target\":34963}],"
             << "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":" << count << ",\"type\":\"VEC3\",\"min\":["
             << low[0] << ',' << low[1] << ',' << low[2] << "],\"max\":[" << high[0] << ',' << high[1] << ',' << high[2] << "]},"
             << "{\"bufferView\":1,\"componentType\":5126,\"count\":" << count << ",\"type\":\"VEC3\"},"
             << "{\"bufferView\":2,\"componentType\":5126,\"count\":" << count << ",\"type\":\"VEC2\"},"
             << "{\"bufferView\":3,\"componentType\":5123,\"count\":" << chosen.size() << ",\"type\":\"SCALAR\"}]}\n";
        require(std::filesystem::create_directory(output), "Cannot create the fresh asset directory.");
        write(output / "press_support.bin", data); write(output / "press_support.gltf", gltf.str());
        std::cout << "{\"status\":\"pass\",\"components\":" << selected.size() << ",\"vertices\":" << count
                  << ",\"triangles\":" << chosen.size() / 3 << ",\"bytes\":" << data.size()
                  << ",\"scale\":" << std::setprecision(17) << scale << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
