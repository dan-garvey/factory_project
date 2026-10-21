#include "tuft.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <iomanip>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>

namespace factory::foliage {
namespace {
struct Profile {
    std::size_t vertices, indices, source_bytes;
    std::size_t positions_offset, normals_offset, uv_offset, indices_offset;
    float position_bound, scale;
    const char* node;
    const char* mesh;
    const char* material;
};
constexpr Profile grass{1386, 3771, 1006632, 215508, 232140, 248772, 259860,
                        0.25f, 2.0f, "GrassMedium01MidB", "grass_medium_01_mid_b_LOD0", "GrassMedium01Cutout"};
constexpr Profile fern{544, 2352, 176176, 131088, 137616, 144144, 148496,
                       0.65f, 1.0f, "Fern02A", "fern_02_a", "Fern02Cutout"};
constexpr std::size_t max_glb_bytes = 650000;

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

std::uint32_t u32(const Bytes& bytes, std::size_t at) {
    require(at + 4 <= bytes.size(), "Truncated uint32.");
    return std::uint32_t(bytes[at]) | (std::uint32_t(bytes[at + 1]) << 8) |
        (std::uint32_t(bytes[at + 2]) << 16) | (std::uint32_t(bytes[at + 3]) << 24);
}

void append_u32(Bytes& bytes, std::uint32_t value) {
    for (unsigned shift = 0; shift < 32; shift += 8)
        bytes.push_back(static_cast<std::uint8_t>(value >> shift));
}

float f32(const Bytes& bytes, std::size_t at) {
    return std::bit_cast<float>(u32(bytes, at));
}

void pad(Bytes& bytes) {
    while (bytes.size() % 4) bytes.push_back(0);
}

void png_header(const Bytes& bytes, std::uint32_t extent, bool alpha) {
    constexpr std::array<std::uint8_t, 8> signature{137, 80, 78, 71, 13, 10, 26, 10};
    require(bytes.size() >= 33 && bytes.size() <= max_glb_bytes,
            "Image is empty, truncated or exceeds the package limit.");
    require(std::equal(signature.begin(), signature.end(), bytes.begin()), "Expected PNG image.");
    require(u32(bytes, 8) == 0x0d000000 && u32(bytes, 12) == 0x52444849, "Expected PNG IHDR.");
    auto big = [&](std::size_t at) {
        return (std::uint32_t(bytes[at]) << 24) | (std::uint32_t(bytes[at + 1]) << 16) |
            (std::uint32_t(bytes[at + 2]) << 8) | bytes[at + 3];
    };
    require(big(16) == extent && big(20) == extent, "Unexpected prepared image extent.");
    require(bytes[24] == 8 && bytes[25] == (alpha ? 6 : 2), "Expected RGB8 or RGBA8 PNG.");
    // Full PNG decoding/CRC checks belong to the pinned engine preparation and
    // import controls. A valid header alone is not a claim of a decoded image.
}
Bytes pack(const Profile& profile, const Bytes& source, const Bytes& albedo, const Bytes& normal, const Bytes& arm) {
    require(source.size() == profile.source_bytes, "Unexpected pinned provider buffer length.");
    png_header(albedo, 384, true);
    png_header(normal, 256, false);
    png_header(arm, 256, false);
    std::array<float, 3> low{INFINITY, INFINITY, INFINITY};
    std::array<float, 3> high{-INFINITY, -INFINITY, -INFINITY};
    Bytes binary;
    for (std::size_t i = 0; i < profile.vertices; ++i) {
        for (std::size_t axis = 0; axis < 3; ++axis) {
            const float value = f32(source, profile.positions_offset + i * 12 + axis * 4);
            require(std::isfinite(value) && std::abs(value) < profile.position_bound, "Invalid foliage position.");
            // Source metres, with an explicit reversible uniform visual scale.
            // Catalogue-node display translations are intentionally omitted.
            const float scaled = value * profile.scale;
            low[axis] = std::min(low[axis], scaled);
            high[axis] = std::max(high[axis], scaled);
            append_u32(binary, std::bit_cast<std::uint32_t>(scaled));
        }
        float normal_length = 0;
        for (std::size_t axis = 0; axis < 3; ++axis) {
            const float value = f32(source, profile.normals_offset + i * 12 + axis * 4);
            require(std::isfinite(value), "Invalid tuft normal.");
            normal_length += value * value;
        }
        require(std::abs(normal_length - 1.0f) < 0.002f, "Nonunit source normal.");
        for (std::size_t axis = 0; axis < 2; ++axis) {
            const float value = f32(source, profile.uv_offset + i * 8 + axis * 4);
            require(std::isfinite(value) && value >= 0 && value <= 1, "Invalid tuft UV.");
        }
    }
    const auto positions_end = binary.size();
    binary.insert(binary.end(), source.begin() + profile.normals_offset,
                  source.begin() + profile.normals_offset + profile.vertices * 12);
    const auto normals_end = binary.size();
    binary.insert(binary.end(), source.begin() + profile.uv_offset,
                  source.begin() + profile.uv_offset + profile.vertices * 8);
    const auto uv_end = binary.size();
    for (std::size_t i = 0; i < profile.indices; ++i) {
        const auto at = profile.indices_offset + i * 2;
        const std::size_t index = std::uint16_t(source[at]) | (std::uint16_t(source[at + 1]) << 8);
        require(index < profile.vertices, "Index outside selected foliage vertices.");
    }
    binary.insert(binary.end(), source.begin() + profile.indices_offset,
                  source.begin() + profile.indices_offset + profile.indices * 2);
    const auto index_end = binary.size();
    std::array<std::size_t, 3> image_offsets{};
    std::array<const Bytes*, 3> images{&albedo, &normal, &arm};
    for (std::size_t i = 0; i < images.size(); ++i) {
        pad(binary);
        image_offsets[i] = binary.size();
        binary.insert(binary.end(), images[i]->begin(), images[i]->end());
    }
    pad(binary);
    std::ostringstream json;
    json.imbue(std::locale::classic());
    json << std::setprecision(std::numeric_limits<float>::max_digits10)
        << R"({"asset":{"version":"2.0","generator":"Factory bounded tuft packer","copyright":"CC0: Rico Cilliers and Rob Tuytel / Poly Haven"},)"
        << R"("scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":")" << profile.node << R"(","mesh":0}],)"
        << R"("meshes":[{"name":")" << profile.mesh << R"(","primitives":[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3,"material":0}]}],)"
        << R"("accessors":[{"bufferView":0,"componentType":5126,"count":)" << profile.vertices << R"(,"type":"VEC3","min":[)"
        << low[0] << ',' << low[1] << ',' << low[2] << "],\"max\":["
        << high[0] << ',' << high[1] << ',' << high[2] << R"(]},)"
        << R"({"bufferView":1,"componentType":5126,"count":)" << profile.vertices << R"(,"type":"VEC3"},)"
        << R"({"bufferView":2,"componentType":5126,"count":)" << profile.vertices << R"(,"type":"VEC2"},)"
        << R"({"bufferView":3,"componentType":5123,"count":)" << profile.indices << R"(,"type":"SCALAR"}],)"
        << R"("bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":)" << positions_end << R"(,"target":34962},)"
        << R"({"buffer":0,"byteOffset":)" << positions_end << R"(,"byteLength":)" << normals_end - positions_end << R"(,"target":34962},)"
        << R"({"buffer":0,"byteOffset":)" << normals_end << R"(,"byteLength":)" << uv_end - normals_end << R"(,"target":34962},)"
        << R"({"buffer":0,"byteOffset":)" << uv_end << R"(,"byteLength":)" << index_end - uv_end << R"(,"target":34963})";
    for (std::size_t i = 0; i < images.size(); ++i)
        json << R"(,{"buffer":0,"byteOffset":)" << image_offsets[i] << R"(,"byteLength":)" << images[i]->size() << '}';
    json << R"(],"buffers":[{"byteLength":)" << binary.size() << R"(}],)"
        << R"("images":[{"bufferView":4,"mimeType":"image/png"},{"bufferView":5,"mimeType":"image/png"},{"bufferView":6,"mimeType":"image/png"}],)"
        << R"("samplers":[{"magFilter":9729,"minFilter":9987,"wrapS":33071,"wrapT":33071}],"textures":[{"sampler":0,"source":0},{"sampler":0,"source":1},{"sampler":0,"source":2}],)"
        << R"("materials":[{"name":")" << profile.material << R"(","alphaMode":"MASK","alphaCutoff":0.5,"doubleSided":true,"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":1,"metallicRoughnessTexture":{"index":2}},"normalTexture":{"index":1},"occlusionTexture":{"index":2}}]})";
    auto text = json.str();
    while (text.size() % 4) text.push_back(' ');
    require(28 + text.size() + binary.size() <= max_glb_bytes, "GLB exceeds the declared source budget.");
    Bytes output;
    append_u32(output, 0x46546c67);
    append_u32(output, 2);
    append_u32(output, static_cast<std::uint32_t>(28 + text.size() + binary.size()));
    append_u32(output, static_cast<std::uint32_t>(text.size()));
    append_u32(output, 0x4e4f534a);
    output.insert(output.end(), text.begin(), text.end());
    append_u32(output, static_cast<std::uint32_t>(binary.size()));
    append_u32(output, 0x004e4942);
    output.insert(output.end(), binary.begin(), binary.end());
    return output;
}
}  // namespace

Bytes pack_tuft(const Bytes& source, const Bytes& albedo, const Bytes& normal, const Bytes& arm) {
    return pack(grass, source, albedo, normal, arm);
}

Bytes pack_fern(const Bytes& source, const Bytes& albedo, const Bytes& normal, const Bytes& arm) {
    return pack(fern, source, albedo, normal, arm);
}
}  // namespace factory::foliage
