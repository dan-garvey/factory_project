#pragma once

#include <cstdint>
#include <vector>

namespace factory::foliage {
using Bytes = std::vector<std::uint8_t>;

// This is deliberately one pinned source variant, not a general glTF importer.
// Source identity is checked against source.json before packaging. The writer
// independently validates the selected geometry and bounded image headers.
// Throws std::runtime_error; no output is published on validation failure.
Bytes pack_tuft(const Bytes& provider_buffer, const Bytes& albedo_alpha_png,
                const Bytes& normal_png, const Bytes& arm_png);
}  // namespace factory::foliage
