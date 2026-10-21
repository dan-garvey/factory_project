#include "build.hpp"
#include "factory/capture.hpp"
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <unistd.h>

namespace {
namespace gb = factory::gameplay_build;
namespace fs = std::filesystem;
using namespace std::chrono_literals;
int checks{};
void check(bool value, const char* why) {
    ++checks;
    if (!value) throw std::runtime_error(why);
}
void write(const fs::path& path, const std::string& bytes) {
    fs::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary);
    file << bytes;
    if (!file) throw std::runtime_error("Fixture write failed.");
}
std::string read(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}
void command(std::vector<std::string> args) {
    const auto result = factory_launch::run_process(args, 10s, 65536);
    if (result.exit_code != 0) throw std::runtime_error("Fixture utility failed: " + result.output);
}
void git(const fs::path& repo, std::vector<std::string> args) {
    args.insert(args.begin(), {"/usr/bin/git", "-C", repo.string(), "-c", "user.name=Fixture", "-c",
        "user.email=fixture@example.invalid", "-c", "core.hooksPath=/dev/null"});
    command(args);
}
void commit(const fs::path& repo) {
    git(repo, {"add", "."}); git(repo, {"commit", "-m", "fixture"});
}
template<class F> void refuses(F operation, const char* why) {
    bool caught = false;
    try { operation(); } catch (const std::exception&) { caught = true; }
    check(caught, why);
}
struct Fixture {
    fs::path root;
    gb::Options options;
    fs::path binary;
    std::string original = "#!/bin/sh\nstartup=unchanged\nlibrary='old.so'\nlibrary_sha256=old\nlibrary_source=old\n# keep this footer\n";
    explicit Fixture(const fs::path& base) {
        std::string pattern = (base / "install-XXXXXX").string();
        check(::mkdtemp(pattern.data()) != nullptr, "Private fixture directory created.");
        root = fs::canonical(pattern);
        options.checkout = options.main_checkout = root / "repo";
        options.launcher = root / "launcher.sh";
        options.install_root = root / "installed space's";
        fs::create_directory(options.checkout);
        fs::create_directory(options.install_root);
        git(options.checkout, {"init", "-b", "main"});
        write(options.checkout / "native/factory-world/src/world.cpp", "original\n");
        write(options.checkout / "native/factory-world/BUILD.bazel", "# original graph\n");
        write(options.checkout / "README.md", "documentation\n");
        commit(options.checkout);
        write(options.launcher, original);
        fs::permissions(options.launcher, fs::perms::owner_all);
        binary = root / "built.so";
        // Invented header for publication controls; never loaded or executed.
        std::string elf(128, '\0');
        elf.replace(0, 4, "\177ELF"); elf[4] = 2; elf[5] = 1; elf[16] = 3; elf[18] = 62;
        write(binary, elf);
    }
    ~Fixture() { std::error_code ignored; fs::remove_all(root, ignored); }
};
void success_and_failure(const fs::path& base) {
    Fixture f(base);
    const auto before = gb::snapshot(f.options);
    check(gb::complete(f.options, before, 17, f.root / "absent") == 17, "Build failure propagates exactly without requiring output.");
    check(read(f.options.launcher) == f.original && fs::is_empty(f.options.install_root), "Failed build changes neither launcher nor installation.");
    check(gb::complete(f.options, before, 0, f.binary) == 0, "Successful verified build installs.");
    const auto helper = read(f.options.launcher);
    const auto digest = factory_launch::sha256(read(f.binary));
    const auto directory = f.options.install_root / (before.revision + "-" + digest);
    check(read(directory / "factory-native-world.so") == read(f.binary), "Installed library is byte-exact.");
    check(helper.find("startup=unchanged") != std::string::npos && helper.ends_with("# keep this footer\n"), "Unrelated launcher content is preserved.");
    check(helper.find("library_source=" + before.revision) != std::string::npos &&
          helper.find("library_sha256=" + digest) != std::string::npos, "Both source and binary digest pins update together.");
    check(helper.find("'\"'\"'") != std::string::npos, "Installation paths with quotes are shell-escaped.");
    command({"/usr/bin/bash", "-n", f.options.launcher.string()});
    check(fs::exists(directory / "source.json"), "Each installed version retains source provenance.");
    const auto repeat = gb::snapshot(f.options);
    check(gb::complete(f.options, repeat, 0, f.binary) == 0 && read(f.options.launcher) == helper,
          "An identical build reuses the immutable installation safely.");
    auto altered = read(f.binary); altered.back() = 1; write(f.binary, altered);
    check(gb::complete(f.options, gb::snapshot(f.options), 0, f.binary) == 0, "A new successful binary creates another version.");
    check(read(directory / "factory-native-world.so") != altered, "The previous installed library is never overwritten.");
}
void refusals(const fs::path& base) {
    Fixture f(base);
    auto before = gb::snapshot(f.options);
    const auto valid = read(f.binary);
    write(f.binary, "invalid ELF");
    refuses([&] { gb::complete(f.options, before, 0, f.binary); }, "Malformed output refuses.");
    check(read(f.options.launcher) == f.original && fs::is_empty(f.options.install_root), "Malformed output leaves previous state untouched.");
    write(f.binary, valid);
    write(f.options.checkout / "native/factory-world/src/world.cpp", "dirty\n");
    refuses([&] { gb::snapshot(f.options); }, "Dirty production source refuses before compilation.");
    refuses([&] { gb::complete(f.options, before, 0, f.binary); }, "Production edits during compilation refuse publication.");
    write(f.options.checkout / "native/factory-world/src/world.cpp", "original\n");
    write(f.options.launcher, f.original + "library_source=duplicate\n");
    refuses([&] { gb::snapshot(f.options); }, "Duplicate pins refuse before compilation.");
    write(f.options.launcher, f.original + "# another owner's edit\n");
    refuses([&] { gb::complete(f.options, before, 0, f.binary); }, "Concurrent launcher changes are not overwritten.");
    write(f.options.launcher, f.original);
    fs::remove(f.binary);
    fs::create_symlink(f.options.launcher, f.binary);
    refuses([&] { gb::complete(f.options, before, 0, f.binary); }, "A substituted output symlink refuses.");
    check(read(f.options.launcher) == f.original, "Every refusal retains old launcher bytes.");
}
void main_advances(const fs::path& base) {
    Fixture f(base);
    const auto clone = f.root / "build-checkout";
    command({"/usr/bin/git", "clone", "--no-hardlinks", f.options.main_checkout.string(), clone.string()});
    f.options.checkout = clone;
    auto before = gb::snapshot(f.options);
    write(f.options.main_checkout / "README.md", "new documentation\n"); commit(f.options.main_checkout);
    check(gb::complete(f.options, before, 0, f.binary) == 0, "Unrelated documentation commits do not stale a built library.");
    before = gb::snapshot(f.options);
    const auto old_launcher = read(f.options.launcher);
    write(f.options.main_checkout / "native/factory-world/src/world.cpp", "new production\n"); commit(f.options.main_checkout);
    refuses([&] { gb::complete(f.options, before, 0, f.binary); }, "New production on main refuses a stale build.");
    check(read(f.options.launcher) == old_launcher, "A newer main leaves the last installation intact.");
    write(clone / "README.md", "new build revision\n"); commit(clone);
    refuses([&] { gb::complete(f.options, before, 0, f.binary); }, "Changing the build revision invalidates its prior seal.");
}
void retain_unowned_temporary(const fs::path& base) {
    Fixture f(base);
    const auto before = gb::snapshot(f.options);
    const auto temporary = f.options.launcher.string() + ".gameplay-new-" + std::to_string(::getpid());
    write(temporary, "pre-existing file must remain\n");
    refuses([&] { gb::complete(f.options, before, 0, f.binary); }, "A pre-existing temporary name refuses publication.");
    check(read(temporary) == "pre-existing file must remain\n" && read(f.options.launcher) == f.original,
          "Refusal never deletes a file this attempt did not create.");
}
void dependency_advances(const fs::path& base) {
    for (const auto* dependency : {"mineral-site", "waterwheel"}) {
        Fixture f(base);
        const auto clone = f.root / "build-checkout";
        command({"/usr/bin/git", "clone", "--no-hardlinks", f.options.main_checkout.string(), clone.string()});
        f.options.checkout = clone;
        const auto before = gb::snapshot(f.options);
        write(f.options.main_checkout / "native" / dependency / "include/profile.hpp", "changed dependency\n");
        commit(f.options.main_checkout);
        refuses([&] { gb::complete(f.options, before, 0, f.binary); },
                "A changed mining or waterwheel dependency refuses a stale library.");
        check(read(f.options.launcher) == f.original && fs::is_empty(f.options.install_root),
              "Dependency refusal preserves the current launcher and installation.");
    }
}
} // namespace
int main() {
    try {
        const auto* temp = std::getenv("TEST_TMPDIR");
        if (!temp) throw std::runtime_error("Use Bazel's private test temporary directory.");
        const auto root = fs::canonical(temp);
        success_and_failure(root); refusals(root); main_advances(root); retain_unowned_temporary(root); dependency_advances(root);
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << ",\"game_launches\":0}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
