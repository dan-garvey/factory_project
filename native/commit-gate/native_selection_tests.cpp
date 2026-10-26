#include "native_selection.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <unistd.h>

namespace fs = std::filesystem;
namespace gate = factory::commit_gate;
namespace {
int checks{};
void check(bool value, const char* reason) {
    ++checks;
    if (!value) throw std::runtime_error(reason);
}
void write(const fs::path& path) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(path);
    stream << "# staged fixture\n";
    check(static_cast<bool>(stream), "Fixture workspace file exists.");
}
template<class Function> void refuses(Function operation, const char* reason) {
    bool failed{};
    try { operation(); } catch (const std::exception&) { failed = true; }
    check(failed, reason);
}
void cases(const fs::path& root) {
    write(root / "MODULE.bazel");
    write(root / "native/factory-core/BUILD.bazel");
    write(root / "native/factory-world/BUILD.bazel");
    write(root / "native/commit-gate/BUILD.bazel");

    const auto source = gate::select_native_changes(root, {"native/factory-core/src/materials.cpp"});
    check(source.required && !source.all && source.packages ==
              std::vector<std::string>{"//native/factory-core:all"},
          "A native source maps to its owning staged Bazel package.");
    check(source.test_query ==
              "kind(\".*_test rule\", rdeps(//native/..., set(//native/factory-core:all)))",
          "Tests are selected through Bazel transitive reverse dependencies.");
    check(source.build_query ==
              "kind(\"cc_(library|binary|test) rule\", rdeps(//native/..., set(//native/factory-core:all)))",
          "Affected libraries, binaries and tests are built.");
    const auto combined = gate::select_native_changes(root, {
        "native/factory-world/BUILD.bazel", "native/factory-core/include/factory/materials.hpp",
        "native/factory-core/src/materials.cpp"});
    check(combined.packages == std::vector<std::string>({"//native/factory-core:all", "//native/factory-world:all"}) &&
              combined.test_query.find("set(//native/factory-core:all //native/factory-world:all)") != std::string::npos,
          "Header and BUILD changes preserve distinct sorted package seeds.");
    const auto docs = gate::select_native_changes(root, {"README.md", "native/factory-core/README.md"});
    check(!docs.required && docs.build_query.empty() && docs.test_query.empty(),
          "Documentation-only changes do not force native validation.");
    for (const auto& path : {".bazelrc", ".bazelversion", "MODULE.bazel", "MODULE.bazel.lock",
                             "BUILD.bazel", "native/factory-core/defs.bzl", "native/new/src/file.cpp"}) {
        const auto all = gate::select_native_changes(root, {path});
        check(all.required && all.all && all.test_query == "kind(\".*_test rule\", //native/...)",
              "Shared Bazel inputs or a missing package select the whole native graph.");
    }
    for (const auto& path : {"../outside.cpp", "native/../outside.cpp", "/absolute.cpp",
                             "native//core/file.cpp", "native\\core\\file.cpp",
                             ".beads/private", "native/factory-core/src/bad\nname.cpp"}) {
        refuses([&] { (void)gate::select_native_changes(root, {path}); },
                (std::string("An unsafe or private staged delta refuses: ") + path).c_str());
    }
    const auto labels = gate::native_labels_from_query(
        "Loading: 0 packages loaded\n//native/factory-core:materials_test\n"
        "//native/factory-world:host_test\n//native/factory-core:materials_test\n");
    check(labels == std::vector<std::string>({"//native/factory-core:materials_test",
                                              "//native/factory-world:host_test"}),
          "A successful query yields unique first-party targets in stable order.");
    refuses([&] { (void)gate::native_labels_from_query("INFO: no tests\n"); },
            "An empty required selection cannot pass.");
    refuses([&] { (void)gate::native_labels_from_query("//native/core:bad label\n"); },
            "A malformed target cannot be accepted from a log.");
}
}

int main() {
    try {
        const auto* temporary = std::getenv("TEST_TMPDIR");
        check(temporary != nullptr, "Use Bazel's private fixture directory.");
        std::string pattern = (fs::path(temporary) / "native-selection-XXXXXX").string();
        check(::mkdtemp(pattern.data()) != nullptr, "Create an isolated staged workspace.");
        const fs::path root = fs::canonical(pattern);
        cases(root);
        fs::remove_all(root);
        std::cout << "Native selection: " << checks << " checks passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Native selection failed: " << error.what() << '\n';
        return 1;
    }
}
