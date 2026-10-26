#include "factory/capture.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <unistd.h>

namespace {
namespace fs = std::filesystem;
using namespace std::chrono_literals;

void require(bool value, const char* reason) {
    if (!value) throw std::runtime_error(reason);
}

struct Fixture {
    fs::path root;
    explicit Fixture(const fs::path& parent) {
        fs::create_directories(parent);
        std::string pattern = (parent / "launch-guard-XXXXXX").string();
        require(::mkdtemp(pattern.data()) != nullptr, "Cannot create a private launch-guard fixture.");
        root = pattern;
    }
    ~Fixture() {
        std::error_code ignored;
        fs::remove_all(root, ignored);
    }
};

factory_launch::ProcessResult exercise(const fs::path& test) {
    return factory_launch::run_process({"/usr/bin/bash", test.string()}, 30s, 65536, nullptr, true);
}
}

int main() {
    try {
        const auto* runfiles = std::getenv("TEST_SRCDIR");
        const auto* temporary = std::getenv("TEST_TMPDIR");
        require(runfiles && temporary, "Use Bazel's declared runfiles and temporary directory.");
        const auto source = fs::path(runfiles) / "_main/scripts/tests/ensure-gameplay-library.sh";
        const auto guard = fs::path(runfiles) / "_main/scripts/ensure-gameplay-library.sh";
        require(fs::is_regular_file(source) && fs::is_regular_file(guard),
                "The real launch guard and its behavioral test must be declared runfiles.");

        const auto accepted = exercise(source);
        require(accepted.exit_code == 0 &&
                accepted.output.find("Launch preparation controls passed.") != std::string::npos,
                "The real gameplay refresh guard did not pass its behavioral controls.");

        Fixture fixture(temporary);
        const auto broken_test = fixture.root / "scripts/tests/ensure-gameplay-library.sh";
        const auto broken_guard = fixture.root / "scripts/ensure-gameplay-library.sh";
        fs::create_directories(broken_test.parent_path());
        fs::copy_file(source, broken_test);
        std::ofstream file(broken_guard);
        file << "#!/usr/bin/env bash\nexit 0\n";
        file.close();
        require(static_cast<bool>(file), "Cannot write the negative-control guard.");
        fs::permissions(broken_guard, fs::perms::owner_read | fs::perms::owner_exec);
        const auto rejected = exercise(broken_test);
        require(rejected.exit_code != 0 &&
                rejected.output.find("Validation-only mode accepted a changed mineral-site dependency.") != std::string::npos,
                "The behavioral test did not reject a guard that accepts stale native inputs.");
        std::cout << "Gameplay refresh guard controls and negative control passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Gameplay refresh guard test failed: " << error.what() << '\n';
        return 1;
    }
}
