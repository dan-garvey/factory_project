// Extract the wooden rotor from Poly Haven's CC0 Spinning Wheel 01.
// This deliberately accepts one exact source layout, not arbitrary glTF input.
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
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using Point = std::array<float, 3>;
constexpr std::size_t source_vertices = 35380;
constexpr std::size_t source_indices = 156069;
constexpr std::size_t normal_offset = 424560;
constexpr std::size_t uv_offset = 849120;
constexpr std::size_t index_offset = 1132160;
constexpr std::array<std::size_t, 14> seeds{
    9310, 2231, 5389, 4630, 4813, 4909, 5005, 5101, 5197, 3426, 5485, 5581, 5677, 3966};
constexpr std::array<double, 3> origin{-0.02135125920176506, 0.6647235751152039, 0.25105417519807816};
constexpr const char* source_hash = "2764af36cbfcf6ba26e5175f63ba9aa72347bb52a7b7f06ad26895d89b14f099";

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

struct Components {
    std::vector<std::size_t> parent = std::vector<std::size_t>(source_vertices);
    Components() { std::iota(parent.begin(), parent.end(), 0); }
    std::size_t root(std::size_t i) {
        while (parent[i] != i) { parent[i] = parent[parent[i]]; i = parent[i]; }
        return i;
    }
    void join(std::size_t a, std::size_t b) { a = root(a); b = root(b); if (a != b) parent[b] = a; }
};
} // namespace

int main(int argc, char** argv) {
    try {
        require(argc == 3, "Usage: prepare-waterwheel SOURCE.bin FRESH_OUTPUT_DIRECTORY");
        const std::filesystem::path input(argv[1]), output(argv[2]);
        require(std::filesystem::is_regular_file(std::filesystem::symlink_status(input))
                    && std::filesystem::file_size(input) == 1444300, "Expected the exact regular source buffer.");
        std::ifstream in(input, std::ios::binary);
        const std::string bytes((std::istreambuf_iterator<char>(in)), {});
        require(digest(bytes) == source_hash, "Source SHA256 differs from the documented recipe.");
        require(!std::filesystem::exists(std::filesystem::symlink_status(output)), "The output must be fresh.");

        Components components;
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
        require(chosen.size() == 8574 * 3, "The declared rim, hub and twelve spokes changed.");

        std::map<std::size_t, std::uint16_t> remap;
        std::vector<std::size_t> vertices;
        double source_radius = 0;
        for (const auto i : chosen) {
            if (remap.contains(i)) continue;
            require(vertices.size() < 65536, "The output index type cannot represent these vertices.");
            remap.emplace(i, static_cast<std::uint16_t>(vertices.size()));
            vertices.push_back(i);
            source_radius = std::max(source_radius, std::hypot(double(positions[i][1]) - origin[1],
                                                              double(positions[i][2]) - origin[2]));
        }
        require(source_radius > 0.29 && source_radius < 0.32, "The source rotor radius changed.");
        const double scale = 0.57 / source_radius;
        std::string data;
        Point low{100, 100, 100}, high{-100, -100, -100};
        for (const auto i : vertices) {
            const Point point{float(-(positions[i][2] - origin[2]) * scale),
                              float((positions[i][1] - origin[1]) * scale),
                              float((positions[i][0] - origin[0]) * scale)};
            for (unsigned a = 0; a < 3; ++a) {
                append(data, point[a]); low[a] = std::min(low[a], point[a]); high[a] = std::max(high[a], point[a]);
            }
        }
        const auto normals_at = data.size();
        for (const auto i : vertices) {
            Point normal{-scalar(bytes, normal_offset + i * 12 + 8),
                          scalar(bytes, normal_offset + i * 12 + 4), scalar(bytes, normal_offset + i * 12)};
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
             << "{\"asset\":{\"version\":\"2.0\",\"generator\":\"Factory CC0 rotor recipe\"},"
             << "\"scene\":0,\"scenes\":[{\"nodes\":[0]}],\"nodes\":[{\"name\":\"WheelComponent\",\"mesh\":0}],"
             << "\"meshes\":[{\"name\":\"SourcedTimberRotor\",\"primitives\":[{\"attributes\":{\"POSITION\":0,\"NORMAL\":1,\"TEXCOORD_0\":2},\"indices\":3}]}],"
             << "\"buffers\":[{\"uri\":\"rotor.bin\",\"byteLength\":" << data.size() << "}],\"bufferViews\":["
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
        write(output / "rotor.bin", data); write(output / "rotor.gltf", gltf.str());
        std::cout << "{\"status\":\"pass\",\"components\":" << selected.size() << ",\"vertices\":" << count
                  << ",\"triangles\":" << chosen.size() / 3 << ",\"bytes\":" << data.size()
                  << ",\"scale\":" << std::setprecision(17) << scale << "}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
