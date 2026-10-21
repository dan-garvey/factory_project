#pragma once

#include <cstddef>
#include <numeric>
#include <vector>

namespace factory_art {
// Offline topology discovery only. Source UV/normal vertices remain separate.
struct Components {
    std::vector<std::size_t> parent;
    explicit Components(std::size_t count) : parent(count) { std::iota(parent.begin(), parent.end(), 0); }
    std::size_t root(std::size_t i) {
        while (parent[i] != i) { parent[i] = parent[parent[i]]; i = parent[i]; }
        return i;
    }
    void join(std::size_t a, std::size_t b) { a = root(a); b = root(b); if (a != b) parent[b] = a; }
};
}  // namespace factory_art
