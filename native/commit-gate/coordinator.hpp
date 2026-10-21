#pragma once

#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace factory::commit_gate {

struct GitResult {
    int exit_code;
    std::string output;
};
using GitReader = std::function<GitResult(const std::vector<std::string>&)>;
struct Plan {
    std::string tree;
    bool compile_gdscript;
    std::vector<std::string> command;
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

}  // namespace factory::commit_gate
