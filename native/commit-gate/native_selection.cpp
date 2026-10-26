#include "native_selection.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <set>
#include <stdexcept>

namespace factory::commit_gate {
namespace {
namespace fs = std::filesystem;

void require(bool value, const char* reason) {
    if (!value) throw std::runtime_error(reason);
}

void safe_path(const std::string& path) {
    const fs::path relative(path);
    require(!path.empty() && !relative.is_absolute() && relative.lexically_normal() == relative &&
                path.find('\0') == std::string::npos && path.find('\n') == std::string::npos &&
                path.find('\\') == std::string::npos && path.find("//") == std::string::npos,
            "The native change has an unsafe or unsupported path.");
    for (const auto& component : relative)
        require(component != "." && component != ".." && component != ".git" &&
                    component != ".beads",
                "The native change has an unsafe or private path.");
}

bool shared_build_input(const std::string& path) {
    return path == ".bazelrc" || path == ".bazelversion" ||
        path == "MODULE.bazel" || path == "MODULE.bazel.lock" ||
        path == "BUILD.bazel" ||
        (!path.starts_with("native/") && fs::path(path).filename() == "BUILD.bazel") ||
        fs::path(path).extension() == ".bzl";
}

bool root_data_path(const std::string& path, std::string_view root_build) {
    if (path.starts_with("native/")) return false;
    // Only quoted tokens in executable Starlark can reference root-package data.
    // A comment that mentions a file must not seed an undeclared Bazel label.
    for (std::size_t position = 0; position < root_build.size();) {
        const char current = root_build[position];
        if (current == '#') {
            const auto end = root_build.find('\n', position);
            position = end == std::string_view::npos ? root_build.size() : end + 1;
            continue;
        }
        if (current != '"' && current != '\'') {
            ++position;
            continue;
        }
        const auto delimiter = position + 2 < root_build.size() &&
            root_build[position + 1] == current && root_build[position + 2] == current
            ? 3u : 1u;
        position += delimiter;
        const auto begin = position;
        bool escaped = false;
        while (position < root_build.size()) {
            if (root_build[position] == '\\') {
                escaped = true;
                position += std::min<std::size_t>(2, root_build.size() - position);
            } else if (root_build[position] == current &&
                       (delimiter == 1 ||
                        (position + 2 < root_build.size() &&
                         root_build[position + 1] == current &&
                         root_build[position + 2] == current))) {
                break;
            } else ++position;
        }
        if (!escaped && root_build.substr(begin, position - begin) == path) return true;
        position += std::min<std::size_t>(delimiter, root_build.size() - position);
    }
    return false;
}

std::string staged_root_build(const fs::path& staged_root) {
    const auto path = staged_root / "BUILD.bazel";
    require(fs::is_regular_file(path) && fs::file_size(path) <= 1024 * 1024,
            "Select native data from a bounded staged root BUILD file.");
    std::ifstream input(path, std::ios::binary);
    require(static_cast<bool>(input), "Cannot read the staged root BUILD file.");
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}

std::string package_for(const fs::path& staged_root, const std::string& path) {
    auto directory = fs::path(path).parent_path();
    while (!directory.empty() && directory != ".") {
        if (fs::is_regular_file(staged_root / directory / "BUILD.bazel"))
            return "//" + directory.generic_string() + ":all";
        directory = directory.parent_path();
    }
    return {};
}

std::string rdeps(const std::set<std::string>& packages) {
    std::string seeds = "set(";
    for (const auto& package : packages) {
        if (seeds.size() > 4) seeds += ' ';
        seeds += package;
    }
    return "rdeps(//native/..., " + seeds + "))";
}

std::string kind(const char* expression, const std::string& universe) {
    return std::string("kind(\"") + expression + "\", " + universe + ")";
}
}

NativeSelection select_native_changes(const fs::path& staged_root,
                                      const std::vector<std::string>& changed_paths) {
    require(staged_root.is_absolute() && fs::canonical(staged_root) == staged_root &&
                fs::is_regular_file(staged_root / "MODULE.bazel"),
            "Select native consumers from one complete staged Bazel workspace.");
    const auto root_build = staged_root_build(staged_root);
    std::set<std::string> packages;
    bool all = false;
    for (const auto& path : changed_paths) {
        safe_path(path);
        if (shared_build_input(path)) { all = true; continue; }
        if (!path.starts_with("native/")) {
            if (root_data_path(path, root_build)) packages.insert("//:" + path);
            continue;
        }
        if (fs::path(path).extension() == ".md") continue;
        const auto package = package_for(staged_root, path);
        if (package.empty()) all = true;
        else packages.insert(package);
    }
    NativeSelection result;
    result.required = all || !packages.empty();
    result.all = all;
    if (!result.required) return result;
    result.packages.assign(packages.begin(), packages.end());
    const auto universe = all ? std::string("//native/...") : rdeps(packages);
    result.build_query = kind("cc_(library|binary|test) rule", universe);
    result.test_query = kind(".*_test rule", universe);
    return result;
}

bool requires_native_validation(const std::vector<std::string>& changed_paths,
                                std::string_view root_build) {
    bool required = false;
    for (const auto& path : changed_paths) {
        if (shared_build_input(path) ||
            (path.starts_with("native/") && fs::path(path).extension() != ".md") ||
            root_data_path(path, root_build)) {
            safe_path(path);
            required = true;
        }
    }
    return required;
}

std::vector<std::string> native_labels_from_query(std::string_view log) {
    std::set<std::string> labels;
    for (std::size_t offset = 0; offset < log.size();) {
        const auto end = log.find('\n', offset);
        const auto line = log.substr(offset, end == std::string_view::npos ? end : end - offset);
        if (line.starts_with("//native/")) {
            require(line.find(':') != std::string_view::npos &&
                        line.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:+-~") ==
                            std::string_view::npos,
                    "Bazel returned a malformed native target label.");
            labels.emplace(line);
        }
        if (end == std::string_view::npos) break;
        offset = end + 1;
    }
    require(!labels.empty(), "The affected native query selected no required targets.");
    return {labels.begin(), labels.end()};
}

} // namespace factory::commit_gate
