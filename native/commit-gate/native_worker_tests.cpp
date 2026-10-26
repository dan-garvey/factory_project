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
        std::cout << "Native worker summaries: " << checks << " checks passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Native worker summary failed: " << error.what() << '\n';
        return 1;
    }
}
