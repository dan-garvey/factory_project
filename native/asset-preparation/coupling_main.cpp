#include "coupling.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {
void require(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}
void append(std::string &out, float value) {
  const auto word = std::bit_cast<std::uint32_t>(value);
  for (unsigned i = 0; i < 4; ++i)
    out.push_back(static_cast<char>((word >> (8 * i)) & 255));
}
void write(const std::filesystem::path &file, const std::string &bytes) {
  std::ofstream out(file, std::ios::binary);
  out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  out.close();
  require(bool(out), "Cannot finish the prepared fitting.");
}
} // namespace
int main(int argc, char **argv) {
  try {
    require(argc == 3,
            "Usage: prepare-coupling SOURCE.bin FRESH_ABSOLUTE_OUTPUT");
    const std::filesystem::path input(argv[1]), output(argv[2]);
    require(std::filesystem::is_regular_file(
                std::filesystem::symlink_status(input)) &&
                std::filesystem::file_size(input) == 515160,
            "Expected the exact regular source buffer.");
    require(
        output.is_absolute() &&
            !std::filesystem::exists(std::filesystem::symlink_status(output)),
        "The absolute output must be fresh.");
    std::ifstream in(input, std::ios::binary);
    const std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(in)),
                                           {});
    const auto mesh = factory_art::coupling::prepare(bytes);
    std::string data;
    std::ostringstream views, accessors, primitives;
    unsigned accessor = 0;
    for (const auto *group : {&mesh.source, &mesh.cut}) {
      const auto first = data.size(), count = group->size() * 3;
      require(count > 0 && count < 65536,
              "Unsupported prepared primitive size.");
      std::array<float, 3> low, high;
      low.fill(std::numeric_limits<float>::infinity());
      high.fill(-low[0]);
      for (const auto &face : *group)
        for (const auto &vertex : face)
          for (unsigned i = 0; i < 3; ++i) {
            const auto value = static_cast<float>(vertex.position[i]);
            append(data, value);
            low[i] = std::min(low[i], value);
            high[i] = std::max(high[i], value);
          }
      for (const auto &face : *group)
        for (const auto &vertex : face)
          for (auto value : vertex.normal)
            append(data, static_cast<float>(value));
      for (const auto &face : *group)
        for (const auto &vertex : face)
          for (auto value : vertex.uv)
            append(data, static_cast<float>(value));
      if (accessor) {
        views << ',';
        accessors << ',';
        primitives << ',';
      }
      for (unsigned i = 0; i < 3; ++i) {
        if (i) {
          views << ',';
          accessors << ',';
        }
        const auto offset = first + (i == 0   ? 0
                                     : i == 1 ? count * 12
                                              : count * 24);
        views << "{\"buffer\":0,\"byteOffset\":" << offset
              << ",\"byteLength\":" << count * (i == 2 ? 8 : 12)
              << ",\"target\":34962}";
        accessors << "{\"bufferView\":" << accessor + i
                  << ",\"componentType\":5126,\"count\":" << count
                  << ",\"type\":\"" << (i == 2 ? "VEC2" : "VEC3") << '"';
        if (i == 0)
          accessors << std::setprecision(9) << ",\"min\":[" << low[0] << ','
                    << low[1] << ',' << low[2] << "],\"max\":[" << high[0]
                    << ',' << high[1] << ',' << high[2] << ']';
        accessors << '}';
      }
      primitives << "{\"attributes\":{\"POSITION\":" << accessor
                 << ",\"NORMAL\":" << accessor + 1
                 << ",\"TEXCOORD_0\":" << accessor + 2
                 << "},\"mode\":4,\"material\":" << accessor / 3 << '}';
      accessor += 3;
    }
    std::ostringstream gltf;
    gltf << "{\"asset\":{\"version\":\"2.0\",\"generator\":\"Factory "
            "source-specific flange cut and annular "
            "closure\"},\"scene\":0,\"scenes\":[{\"nodes\":[0]}],\"nodes\":[{"
            "\"name\":\"SourcedCouplingFlange\",\"mesh\":0}],\"meshes\":[{"
            "\"primitives\":["
         << primitives.str()
         << "]}],\"materials\":[{\"name\":\"RetainedSource\"},{\"name\":"
            "\"AuthoredCut\"}],\"buffers\":[{\"uri\":\"coupling.bin\","
            "\"byteLength\":"
         << data.size() << "}],\"bufferViews\":[" << views.str()
         << "],\"accessors\":[" << accessors.str() << "]}\n";
    require(std::filesystem::create_directory(output),
            "Cannot create fresh output directory.");
    write(output / "coupling.bin", data);
    write(output / "coupling.gltf", gltf.str());
    std::cout << "{\"status\":\"PASS\",\"source_triangles\":"
              << mesh.source.size()
              << ",\"closure_triangles\":" << mesh.cut.size()
              << ",\"prepared_buffer_bytes\":" << data.size() << "}\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
