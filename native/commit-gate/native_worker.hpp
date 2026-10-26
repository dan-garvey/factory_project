#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace factory::commit_gate {

// The admitted coordinator invokes this in its own pinned executable. The
// worker retains the one heavy permit while each bounded child runs.
int run_native_worker(const std::filesystem::path& checkout,
                      const std::string& expected_tree);

// Refuse a zero-exit Bazel test command unless every selected target has one
// passing Build Event Protocol summary, including cached tests.
void require_passing_test_events(std::string_view events,
                                 const std::vector<std::string>& selected_labels);

// Preserve every sorted selected target while staying within the bounded
// runner's command argument count and byte allowances.
std::vector<std::vector<std::string>> partition_native_labels(
    const std::vector<std::string>& labels,
    const std::vector<std::string>& fixed_arguments);

} // namespace factory::commit_gate
