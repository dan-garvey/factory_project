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
    std::string original = "#!/bin/sh\nstartup=unchanged\nstartup_sha256=old\nstartup_source=old\nlibrary='old.so'\nlibrary_sha256=old\nlibrary_source=old\n# keep this footer\n";
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
        const auto* runfiles = std::getenv("TEST_SRCDIR");
        check(runfiles != nullptr, "Use declared dependency manifest test data.");
        write(options.checkout / "native/gameplay-build/production-paths.txt",
            read(fs::path(runfiles) / "_main/native/gameplay-build/production-paths.txt"));
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
    for (const auto* dependency : {"mineral-site", "waterwheel", "waterflow", "factory-assembly"})
    for (const auto* changed : {"include/profile.hpp", "src/profile.cpp", "BUILD.bazel"}) {
        Fixture f(base);
        const auto clone = f.root / "build-checkout";
        command({"/usr/bin/git", "clone", "--no-hardlinks", f.options.main_checkout.string(), clone.string()});
        f.options.checkout = clone;
        const auto before = gb::snapshot(f.options);
        write(f.options.main_checkout / "native" / dependency / changed, "changed dependency\n");
        commit(f.options.main_checkout);
        refuses([&] { gb::complete(f.options, before, 0, f.binary); },
                "A changed production dependency refuses a stale library.");
        check(read(f.options.launcher) == f.original && fs::is_empty(f.options.install_root),
              "Dependency refusal preserves the current launcher and installation.");
    }
    for (const auto* dependency : {"waterflow", "factory-assembly"}) {
        Fixture f(base);
        const auto clone = f.root / "build-checkout";
        command({"/usr/bin/git", "clone", "--no-hardlinks", f.options.main_checkout.string(), clone.string()});
        f.options.checkout = clone;
        const auto before = gb::snapshot(f.options);
        write(f.options.main_checkout / "native" / dependency / "tests/example_test.cpp", "test-only change\n");
        commit(f.options.main_checkout);
        check(gb::complete(f.options, before, 0, f.binary) == 0,
              "A dependency test-only change does not stale unchanged production.");
    }
}
void launcher_dependency_guard(const fs::path& base) {
    const auto* runfiles = std::getenv("TEST_SRCDIR");
    if (!runfiles) throw std::runtime_error("Use Bazel's declared launcher-guard data.");
    const auto script = fs::path(runfiles) / "_main/scripts/ensure-gameplay-library.sh";
    check(fs::is_regular_file(script), "The fixture uses the real declared launcher guard.");
    for (const auto* dependency : {"waterflow", "factory-assembly"})
    for (const auto* changed : {"include/profile.hpp", "src/profile.cpp", "BUILD.bazel", "tests/example_test.cpp"}) {
        Fixture f(base);
        const auto before = gb::snapshot(f.options);
        write(f.options.checkout / "native" / dependency / changed, "dependency edit\n");
        commit(f.options.checkout);
        const auto after = gb::snapshot(f.options);
        const auto result = factory_launch::run_process({"/usr/bin/bash", script.string(), "check",
            f.options.checkout.string(), before.revision, after.revision, f.binary.string(),
            factory_launch::sha256(read(f.binary))}, 10s, 65536);
        const bool test_only = std::string(changed).starts_with("tests/");
        check(result.exit_code == (test_only ? 0 : 1),
              "The real launcher guard detects dependency production edits while reusing test-only changes.");
        check(read(f.options.launcher) == f.original && fs::is_empty(f.options.install_root),
              "The check-only guard starts no build or installation.");
    }
}
void startup_install_and_guard(const fs::path& base) {
    Fixture f(base);
    f.options.component = gb::Component::startup;
    write(f.options.checkout / "native/factory-launch/src/capture.cpp", "original startup\n");
    write(f.options.checkout / "native/build-support/runner.cpp", "original runner\n");
    commit(f.options.checkout);
    auto elf = read(f.binary);
    elf[16] = 2;
    write(f.binary, elf);
    const auto before = gb::snapshot(f.options);
    check(gb::complete(f.options, before, 9, f.root / "absent") == 9,
          "A failed startup build retains its original exit.");
    check(read(f.options.launcher) == f.original && fs::is_empty(f.options.install_root),
          "A failed startup build preserves the old launcher and installation.");
    check(gb::complete(f.options, before, 0, f.binary) == 0, "A successful startup build installs.");
    const auto digest = factory_launch::sha256(elf);
    const auto destination = f.options.install_root / ("startup-" + before.revision + "-" + digest);
    check(read(destination / "factory-opening-startup") == elf,
          "The immutable startup installation matches the built executable.");
    const auto launcher = read(f.options.launcher);
    check(launcher.find("startup_source=" + before.revision) != std::string::npos &&
          launcher.find("startup_sha256=" + digest) != std::string::npos &&
          launcher.find("library='old.so'") != std::string::npos,
          "Startup publication updates only its own three pins.");
    check(gb::complete(f.options, gb::snapshot(f.options), 0, f.binary) == 0 &&
          read(f.options.launcher) == launcher, "An unchanged startup reuses its immutable installation.");
    elf[16] = 3;
    elf.back() = 1;
    write(f.binary, elf);
    check(gb::complete(f.options, gb::snapshot(f.options), 0, f.binary) == 0 &&
          read(destination / "factory-opening-startup") != elf,
          "A new valid startup output never overwrites the previous binary.");
    fs::permissions(f.binary, fs::perms::owner_all);

    const auto* runfiles = std::getenv("TEST_SRCDIR");
    if (!runfiles) throw std::runtime_error("Use Bazel's declared launcher-guard data.");
    const auto script = fs::path(runfiles) / "_main/scripts/ensure-startup-launcher.sh";
    check(fs::is_regular_file(script), "The startup guard comes from declared test data.");
    auto guard = [&](const std::string& installed_revision, const std::string& current_revision,
                     const fs::path& binary, const std::string& hash) {
        return factory_launch::run_process({"/usr/bin/bash", script.string(), "check", f.options.checkout.string(),
            installed_revision, current_revision, binary.string(), hash}, 10s, 65536).exit_code;
    };
    const auto current = gb::snapshot(f.options);
    check(guard(current.revision, current.revision, f.binary, factory_launch::sha256(read(f.binary))) == 0,
          "Check mode accepts a matching startup without building or launching.");
    write(f.options.checkout / "native/factory-launch/src/capture.cpp", "new startup source\n");
    commit(f.options.checkout);
    const auto changed = gb::snapshot(f.options);
    check(guard(current.revision, changed.revision, f.binary, factory_launch::sha256(read(f.binary))) == 1,
          "Check mode refuses a changed startup source.");
    check(read(f.options.launcher) != f.original &&
          read(destination / "factory-opening-startup") != elf,
          "A guard refusal does not mutate prior startup installations.");
    refuses([&] { gb::complete(f.options, current, 0, f.binary); },
            "A newer source revision cannot publish a stale startup build.");
}

void unknown_cli_option_refuses() {
    const auto* runfiles = std::getenv("TEST_SRCDIR");
    if (!runfiles) throw std::runtime_error("Use Bazel's declared CLI test data.");
    const auto executable = fs::path(runfiles) / "_main/native/gameplay-build/factory-gameplay-build";
    check(fs::is_regular_file(executable), "The CLI test uses its declared built executable.");
    const auto result = factory_launch::run_process({executable.string(),
        "--checkout", "/unused/checkout", "--main", "/unused/main",
        "--bazel", "/unused/bazel", "--artifacts", "/unused/artifacts",
        "--log", "/unused/log", "--admission-directory", "/unused/admission",
        "--launcher", "/unused/launcher", "--install-root", "/unused/installed",
        "--componet", "startup"}, 10s, 65536, nullptr, true);
    check(result.exit_code == 1 && result.output.find("Unknown build option: --componet") != std::string::npos,
          "A misspelled startup selector refuses during parsing before build or installation.");
}
void dependency_query_coverage() {
    const std::vector<std::string> paths{ ".bazelrc", "native/factory-world/src", "native/factory-world/BUILD.bazel" };
    gb::validate_query_coverage(paths, "INFO: queried\n//native/factory-world:BUILD.bazel\n"
        "//native/factory-world:src/world.cpp\n@@external//:ignored\n");
    ++checks;
    refuses([&] { gb::validate_query_coverage(paths,
        "//native/new-component:BUILD.bazel\n//native/factory-world:src/world.cpp\n"); },
        "A newly introduced transitive package must be declared before installation.");
    refuses([&] { gb::validate_query_coverage(paths, "//native/factory-world:../escape.cpp\n"); },
        "Unsafe dependency labels refuse installation.");
    refuses([&] { gb::validate_query_coverage(paths, "INFO: no local labels\n"); },
        "Empty local query results cannot validate the manifest.");
}
void manifest_advances(const fs::path& base) {
    Fixture f(base);
    const auto clone = f.root / "build-checkout";
    command({"/usr/bin/git", "clone", "--no-hardlinks", f.options.main_checkout.string(), clone.string()});
    f.options.checkout = clone;
    const auto before = gb::snapshot(f.options);
    const auto manifest = f.options.main_checkout / "native/gameplay-build/production-paths.txt";
    write(manifest, read(manifest) + "gameplay native/new-component/src\n");
    commit(f.options.main_checkout);
    refuses([&] { gb::complete(f.options, before, 0, f.binary); },
        "A declared dependency change on main refuses a stale build.");
    auto main_options = f.options;
    main_options.checkout = f.options.main_checkout;
    const auto guard = fs::path(std::getenv("TEST_SRCDIR")) / "_main/scripts/ensure-gameplay-library.sh";
    const auto result = factory_launch::run_process({"/usr/bin/bash", guard.string(), "check",
        f.options.main_checkout.string(), before.revision,
        gb::snapshot(main_options).revision,
        f.binary.string(), factory_launch::sha256(read(f.binary))}, 10s, 65536);
    check(result.exit_code == 1, "The launcher guard treats manifest changes as stale production.");
    fs::remove(manifest);
    commit(f.options.main_checkout);
    refuses([&] { gb::snapshot(main_options); },
        "A missing committed manifest fails closed.");
}
} // namespace
int main() {
    try {
        const auto* temp = std::getenv("TEST_TMPDIR");
        if (!temp) throw std::runtime_error("Use Bazel's private test temporary directory.");
        const auto root = fs::canonical(temp);
        success_and_failure(root); refusals(root); main_advances(root); retain_unowned_temporary(root); dependency_advances(root);
        launcher_dependency_guard(root); startup_install_and_guard(root); unknown_cli_option_refuses();
        dependency_query_coverage(); manifest_advances(root);
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << ",\"game_launches\":0}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
