#pragma once

#include "git_reader.hpp"

#include <cstddef>
#include <filesystem>
#include <string>

namespace factory::commit_gate {

inline constexpr std::size_t maximum_staged_blob_bytes = 64 * 1024 * 1024;
inline constexpr std::size_t maximum_staged_source_bytes = 256 * 1024 * 1024;

// The snapshot owns one fresh private child of an external artifact directory.
// Its lifetime bounds the raw staged source available to a native build.
class StagedTree {
public:
    StagedTree(std::filesystem::path root, std::string tree, std::size_t files,
               std::size_t bytes) noexcept;
    ~StagedTree();
    StagedTree(const StagedTree&) = delete;
    StagedTree& operator=(const StagedTree&) = delete;
    StagedTree(StagedTree&& other) noexcept;
    StagedTree& operator=(StagedTree&& other) = delete;

    [[nodiscard]] const std::filesystem::path& root() const noexcept { return root_; }
    [[nodiscard]] const std::string& tree() const noexcept { return tree_; }
    [[nodiscard]] std::size_t files() const noexcept { return files_; }
    [[nodiscard]] std::size_t bytes() const noexcept { return bytes_; }
    void close(); // A successful validation must report incomplete cleanup.

private:
    std::filesystem::path root_;
    std::string tree_;
    std::size_t files_{};
    std::size_t bytes_{};
    void remove() noexcept;
    friend StagedTree materialize_staged_tree(const std::filesystem::path&,
                                             const std::string&,
                                             const std::filesystem::path&,
                                             const GitReader&);
};

// Read only immutable objects named by tree. The Git reader must return raw
// stdout and a nonzero status on failure; it must bound each blob read to
// maximum_staged_blob_bytes + 1. No mutable checkout content is copied.
StagedTree materialize_staged_tree(const std::filesystem::path& checkout,
                                   const std::string& tree,
                                   const std::filesystem::path& artifact_parent,
                                   const GitReader& git);

} // namespace factory::commit_gate
