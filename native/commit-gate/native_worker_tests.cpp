#include "native_worker.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace gate = factory::commit_gate;
namespace {
int checks{};
void check(bool accepted, const char* reason) {
    ++checks;
    if (!accepted) throw std::runtime_error(reason);
}
void refuses(const std::string& events, const std::vector<std::string>& selected) {
    bool failed = false;
    try { gate::require_passing_test_events(events, selected); }
    catch (const std::exception&) { failed = true; }
    check(failed, "A missing, failed, duplicated or unselected test summary cannot pass.");
}
std::string summary(const std::string& label, const std::string& status) {
    return "{\"id\":{\"testSummary\":{\"label\":\"" + label +
        "\"}},\"testSummary\":{\"overallStatus\":\"" + status + "\"}}\n";
}
}
int main() {
    try {
        const std::vector<std::string> selected{"//native/commit-gate:coordinator_test",
                                                "//native/commit-gate:native_selection_test"};
        const auto first = summary(selected[0], "PASSED");
        const auto second = summary(selected[1], "PASSED");
        gate::require_passing_test_events(first + second, selected);
        check(true, "The complete Bazel event stream passes.");
        refuses(first, selected);
        refuses(first + summary(selected[1], "NO_STATUS"), selected);
        refuses(first + first + second, selected);
        refuses(first + summary("//native/other:unselected_test", "PASSED") + second, selected);
        refuses("", selected);
        const auto id = "{\"id\":{\"testSummary\":{\"label\":\"" + selected[1] + "\"}}";
        refuses(first + id + "\n", selected);
        refuses(first + id + ",\"unrelated\":{\"overallStatus\":\"PASSED\"}}\n", selected);
        refuses(first + id + ",\"testSummary\":{\"overallStatus\":\"FAILED\"},"
                "\"unrelated\":{\"overallStatus\":\"PASSED\"}}\n", selected);
        refuses(first + id + ",\"testSummary\":{\"overallStatus\":\"FAILED\","
                "\"overallStatus\":\"PASSED\"}}\n", selected);
        refuses(first + second.substr(0, second.size() - 3), selected);
        refuses(first + id + ",\"testSummary\":{\"overallStatus\":\"PASSED\"},"
                "\"id\":{\"testSummary\":{\"label\":\"" + selected[1] + "\"}}}\n", selected);
        const auto bazel_shape = "{\"id\":{\"testSummary\":{\"label\":\"" + selected[1] +
            "\",\"configuration\":{\"id\":\"abc\"}}},\"testSummary\":{\"totalRunCount\":1,"
            "\"passed\":[{\"uri\":\"file:///fixture/test.log\"}],\"overallStatus\":\"PASSED\","
            "\"totalRunDuration\":\"0.035s\"}}\n";
        gate::require_passing_test_events(first + bazel_shape, selected);
        check(true, "The pinned Bazel 8.4.2 test summary shape passes.");
        std::vector<std::string> many;
        for (std::size_t index = 0; index < 304; ++index) {
            const auto digits = std::to_string(index);
            many.push_back("//native/fixture:target" + std::string(3 - digits.size(), '0') + digits);
        }
        const std::vector<std::string> fixed(20, "--fixed");
        const auto batches = gate::partition_native_labels(many, fixed);
        check(batches.size() == 2 && batches.front().size() == 236,
              "A 304-target native graph fits bounded commands without dropping targets.");
        std::vector<std::string> flattened;
        for (const auto& batch : batches) flattened.insert(flattened.end(), batch.begin(), batch.end());
        check(flattened == many, "Batch order and identity cover the complete selected graph.");
        auto long_labels = many;
        for (auto& label : long_labels) label += std::string(1000, 'x');
        const auto byte_batches = gate::partition_native_labels(long_labels, fixed);
        flattened.clear();
        for (const auto& batch : byte_batches) {
            std::size_t bytes = 20 * std::string("--fixed").size();
            for (const auto& label : batch) bytes += label.size();
            check(batch.size() + fixed.size() <= 256 && bytes <= 131072,
                  "Every batch respects both runner argument bounds.");
            flattened.insert(flattened.end(), batch.begin(), batch.end());
        }
        check(flattened == long_labels && byte_batches.size() > 1,
              "Byte-limited batches still cover every native target.");
        std::cout << "Native worker summaries: " << checks << " checks passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Native worker summary failed: " << error.what() << '\n';
        return 1;
    }
}
