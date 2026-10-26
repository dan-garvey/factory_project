#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace factory::commit_gate {

struct NativeSelection {
    bool required{};
    bool all{};
    std::vector<std::string> packages;
    std::string build_query;
    std::string test_query;
};

// Cheap path-only decision before resource admission. The full package graph
// still comes from the immutable staged snapshot after admission.
bool requires_native_validation(const std::vector<std::string>& changed_paths,
                                std::string_view root_build);

// Map the exact staged delta to Bazel package seeds. Bazel itself expands
// transitive reverse dependencies from this immutable source snapshot.
NativeSelection select_native_changes(const std::filesystem::path& staged_root,
                                      const std::vector<std::string>& changed_paths);

// Parse only first-party labels from a successful bounded Bazel query log.
// The caller must check the query process exit before accepting this result.
std::vector<std::string> native_labels_from_query(std::string_view log);

} // namespace factory::commit_gate
