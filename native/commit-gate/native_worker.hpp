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

} // namespace factory::commit_gate
