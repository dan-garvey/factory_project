#include "staged_tree.hpp"

#include "factory/capture.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;
namespace gate = factory::commit_gate;
using namespace std::chrono_literals;
namespace {
int checks{};
void check(bool value, const char* reason) {
    ++checks;
    if (!value) throw std::runtime_error(reason);
}
void write(const fs::path& path, const std::string& bytes) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary);
    stream.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    check(static_cast<bool>(stream), "Fixture write completed.");
}
std::string read(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    check(static_cast<bool>(stream), "Fixture file can be read.");
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}
std::string trimmed(std::string value) {
    while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) value.pop_back();
    return value;
}
gate::GitResult git(const fs::path& root, const std::vector<std::string>& tail) {
    std::vector<std::string> command{"/usr/bin/git", "-C", root.string()};
    command.insert(command.end(), tail.begin(), tail.end());
    const auto result = factory_launch::run_process(command, 10s, 65536);
    return {result.exit_code, result.output};
}
std::string required_git(const fs::path& root, const std::vector<std::string>& tail) {
    const auto result = git(root, tail);
    check(result.exit_code == 0, "Git fixture command passed.");
    return trimmed(result.output);
}
template<class Function> void refuses(Function operation, const char* reason) {
    bool failed{};
    try { operation(); } catch (const std::exception&) { failed = true; }
    check(failed, reason);
}
void case_staged_bytes(const fs::path& base) {
    const auto repo = base / "repo with spaces";
    const auto artifacts = base / "private artifacts";
    fs::create_directories(repo);
    fs::create_directories(artifacts);
    fs::permissions(artifacts, fs::perms::owner_all, fs::perm_options::replace);
    required_git(repo, {"init", "-q"});
    required_git(repo, {"config", "filter.flip.clean", "cat"});
    required_git(repo, {"config", "filter.flip.smudge", "sed s/RAW/SMUDGED/g"});
    write(repo / ".gitattributes", "filtered.txt filter=flip\n");
    write(repo / "filtered.txt", "RAW staged bytes\n");
    write(repo / "subdir/path with spaces.txt", std::string("a\0b", 3));
    write(repo / "run.sh", "#!/bin/sh\nexit 0\n");
    fs::permissions(repo / "run.sh", fs::perms::owner_all, fs::perm_options::replace);
    required_git(repo, {"add", "."});
    const auto tree = required_git(repo, {"write-tree"});
    write(repo / "filtered.txt", "mutable checkout bytes\n");
    required_git(repo, {"checkout-index", "-f", "--", "filtered.txt"});
    check(read(repo / "filtered.txt") == "SMUDGED staged bytes\n",
          "The checkout smudge filter changes working bytes.");
    const gate::GitReader reader = [&](const auto& tail) { return git(repo, tail); };
    {
        auto snapshot = gate::materialize_staged_tree(fs::canonical(repo), tree,
                                                      fs::canonical(artifacts), reader);
        check(snapshot.tree() == tree && snapshot.files() == 4 && snapshot.bytes() > 0,
              "The bounded snapshot names exactly one immutable tree and its sources.");
        check(read(snapshot.root() / "filtered.txt") == "RAW staged bytes\n",
              "Raw staged bytes win over mutable and smudged checkout bytes.");
        check(read(snapshot.root() / "subdir/path with spaces.txt") == std::string("a\0b", 3),
              "The source snapshot retains a binary blob and a path with spaces.");
        check((fs::status(snapshot.root() / "run.sh").permissions() & fs::perms::owner_exec) != fs::perms::none,
              "A staged executable remains executable.");
        refuses([&] { (void)gate::materialize_staged_tree(fs::canonical(repo), tree,
                        fs::canonical(repo / "subdir"), reader); },
                "A snapshot inside the checkout refuses.");
        fs::permissions(artifacts, fs::perms::owner_read | fs::perms::owner_exec,
                        fs::perm_options::replace);
        refuses([&] { snapshot.close(); }, "Incomplete successful-snapshot cleanup refuses.");
        fs::permissions(artifacts, fs::perms::owner_all, fs::perm_options::replace);
        snapshot.close();
    }
    check(fs::is_empty(artifacts), "A completed snapshot removes only its own private child.");

    write(repo / ".beads/private", "private\n");
    required_git(repo, {"add", "-f", ".beads/private"});
    const auto private_tree = required_git(repo, {"write-tree"});
    refuses([&] { (void)gate::materialize_staged_tree(fs::canonical(repo), private_tree,
                    fs::canonical(artifacts), reader); }, "Private staged tracker data refuses.");
    required_git(repo, {"rm", "--cached", "-qr", ".beads"});
    fs::create_symlink("filtered.txt", repo / "link");
    required_git(repo, {"add", "link"});
    const auto symlink_tree = required_git(repo, {"write-tree"});
    refuses([&] { (void)gate::materialize_staged_tree(fs::canonical(repo), symlink_tree,
                    fs::canonical(artifacts), reader); }, "A staged symlink refuses.");
    check(fs::is_empty(artifacts), "Metadata refusals leave no staged snapshot child.");

    const auto blob = required_git(repo, {"hash-object", "filtered.txt"});
    std::string conflict = "100644 blob " + blob + "\tclash";
    conflict += '\0';
    conflict += "100644 blob " + blob + "\tclash/child";
    conflict += '\0';
    const gate::GitReader malformed = [&](const auto& tail) -> gate::GitResult {
        if (tail.front() == "ls-tree") return {0, conflict};
        return reader(tail);
    };
    refuses([&] { (void)gate::materialize_staged_tree(fs::canonical(repo), tree,
                    fs::canonical(artifacts), malformed); }, "A file-directory path conflict refuses.");

    unsigned blobs{};
    const gate::GitReader missing = [&](const auto& tail) -> gate::GitResult {
        if (tail.front() == "cat-file" && ++blobs == 2) return {1, {}};
        return reader(tail);
    };
    refuses([&] { (void)gate::materialize_staged_tree(fs::canonical(repo), tree,
                    fs::canonical(artifacts), missing); }, "A missing later blob refuses.");
    check(fs::is_empty(artifacts), "A partial export cleans its own child without deleting the family.");
}
}

int main() {
    try {
        const auto* temporary = std::getenv("TEST_TMPDIR");
        check(temporary != nullptr, "Use Bazel's private test directory.");
        case_staged_bytes(fs::canonical(temporary));
        std::cout << "Staged native tree: " << checks << " checks passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Staged native tree failed: " << error.what() << '\n';
        return 1;
    }
}
