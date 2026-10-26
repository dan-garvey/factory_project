#pragma once

#include "git_reader.hpp"

#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace factory::resources { struct Options; }

namespace factory::commit_gate {

struct Plan {
    std::string tree;
    bool compile_gdscript;
    std::vector<std::string> command;
    std::vector<std::string> changed_paths;
    bool validate_native{};
};

// Capture the index before admission. The unchanged staged checker owns raw
// export, actual checks and both index guards. GitReader is an in-process test
// seam, not a command exposed by the installed executable.
Plan prepare(const std::filesystem::path& root, const GitReader&,
             const std::string& interpreter = "/usr/bin/python3");
Plan prepare(const std::filesystem::path& root,
             const std::string& interpreter = "/usr/bin/python3");

// One admission through the existing native resource library. The executable
// fixes the interpreter above; native fixtures may inject a compiled child.
int run(const std::filesystem::path& root,
        const std::string& interpreter = "/usr/bin/python3");

// The native control injects a bounded resource runner so a Bazel test inside
// an already admitted gate does not require another live host capacity probe.
using ResourceRunner = std::function<int(const resources::Options&)>;
int run_with_resources(const std::filesystem::path& root,
                       const std::string& interpreter,
                       const ResourceRunner& resource_runner);

}  // namespace factory::commit_gate
