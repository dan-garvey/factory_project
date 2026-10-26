#pragma once
#include "native/build-support/runner.hpp"

namespace factory::gameplay_build {
namespace fs = std::filesystem;
enum class Component { gameplay, startup };
struct Options {
    fs::path checkout, main_checkout, launcher, install_root, bazel;
    build_support::Options runner;
    Component component = Component::gameplay;
};
struct Snapshot {
    std::string revision, production, launcher;
};
// Refuse a Bazel source/buildfile closure that escapes the committed production paths.
void validate_query_coverage(const std::vector<std::string>& paths, const std::string& query_output);
// Snapshot before compilation; publication checks these same source inputs.
Snapshot snapshot(const Options&);
// A failed build returns its original exit without reading or installing output.
int complete(const Options&, const Snapshot&, int build_exit, const fs::path& library);
// Exactly one bounded Bazel build, followed by complete() only on success.
int run(const Options&);
} // namespace factory::gameplay_build
