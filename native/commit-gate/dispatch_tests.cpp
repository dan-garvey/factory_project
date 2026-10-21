#include "factory/capture.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

namespace fs = std::filesystem;
namespace {
int checks{};
void check(bool value, const char* reason) {
    ++checks;
    if (!value) throw std::runtime_error(reason);
}
void write(const fs::path& path, const std::string& text) {
    std::ofstream output(path, std::ios::binary);
    output << text;
    check(static_cast<bool>(output), "An owned fixture file was written.");
}
std::string read(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    check(static_cast<bool>(input), "The expected fixture data exists.");
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
factory_launch::ProcessResult command(const std::vector<std::string>& args) {
    return factory_launch::run_process(args, std::chrono::seconds(5), 1024 * 1024, nullptr, true);
}
void git(const std::vector<std::string>& args) {
    std::vector<std::string> full{"/usr/bin/git"};
    full.insert(full.end(), args.begin(), args.end());
    check(command(full).exit_code == 0, "Fixture Git configuration succeeds.");
}
void setting(const std::string& key, const std::string& value) { git({"config", "--local", key, value}); }
void clear() {
    for (const auto* key : {"factory.commitGateExecutable", "factory.commitGateSHA256"}) {
        const auto result = command({"/usr/bin/git", "config", "--local", "--unset-all", key});
        check(result.exit_code == 0 || result.exit_code == 5, "Only the fixture's native pins are cleared.");
    }
}
void fixtures(const fs::path& root, const fs::path& hook, const fs::path& self) {
    fs::current_path(root);
    git({"init", "-q"});
    const auto executable = root / "native coordinator with spaces";
    fs::copy_file(self, executable);
    fs::permissions(executable, fs::perms::owner_all);
    const auto digest = factory_launch::sha256(read(executable));
    const auto invoke = [&] { return command({"/usr/bin/bash", hook.string()}); };
    const auto native_refusal = [&] {
        const auto result = invoke();
        check(result.exit_code == 1 && result.output.find("COMMIT CHECK FAILED:") != std::string::npos,
              "Invalid native configuration refuses without falling back to the legacy checker.");
        check(!fs::exists(root / "native-observed"), "A rejected configuration starts no native checker.");
    };
    const auto legacy = invoke();
    check(legacy.exit_code == 2 && legacy.output.find("scripts/check_commit.py") != std::string::npos,
          "Two absent local pins select the unchanged legacy command, whose fixture file is intentionally missing.");
    setting("factory.commitGateExecutable", executable.string()); native_refusal(); clear();
    setting("factory.commitGateSHA256", digest); native_refusal(); clear();
    for (const auto& malformed : {std::string{}, std::string(63, 'a'), std::string(64, 'A'), std::string(64, '0')}) {
        setting("factory.commitGateExecutable", executable.string());
        setting("factory.commitGateSHA256", malformed); native_refusal(); clear();
    }
    setting("factory.commitGateExecutable", ""); setting("factory.commitGateSHA256", digest); native_refusal(); clear();
    setting("factory.commitGateExecutable", "relative executable"); setting("factory.commitGateSHA256", digest); native_refusal(); clear();
    setting("factory.commitGateExecutable", (root / "missing executable").string()); setting("factory.commitGateSHA256", digest); native_refusal(); clear();
    fs::permissions(executable, fs::perms::owner_read | fs::perms::owner_write);
    setting("factory.commitGateExecutable", executable.string()); setting("factory.commitGateSHA256", digest); native_refusal(); clear();
    fs::permissions(executable, fs::perms::owner_all);
    const auto link = root / "linked coordinator";
    fs::create_symlink(executable, link);
    setting("factory.commitGateExecutable", link.string()); setting("factory.commitGateSHA256", digest); native_refusal(); clear();
    setting("factory.commitGateExecutable", executable.string()); setting("factory.commitGateSHA256", digest);
    write(root / "fixture-exit", "37");
    const auto index = root / "temporary index with spaces";
    const auto selected = command({"/usr/bin/env", "GIT_INDEX_FILE=" + index.string(), "/usr/bin/bash", hook.string()});
    check(selected.exit_code == 37, "The configured native exit is returned without a legacy retry.");
    const auto observed = read(root / "native-observed");
    check(observed == root.string() + '\n' + index.string(), "Quoted root argv and temporary-index environment reach the native entrypoint intact.");
    write(root / "fixture-exit", "127");
    check(invoke().exit_code == 127, "A native child exit 127 is not interpreted as permission to use the legacy path.");
    fs::remove(root / "native-observed");
    write(executable, "mutated after its pin"); native_refusal();
}
}  // namespace
int main(int argc, char** argv) {
    try {
        if (argc == 3 && std::string(argv[1]) == "--root") {
            const fs::path root(argv[2]);
            const auto* index = ::getenv("GIT_INDEX_FILE");
            write(root / "native-observed", root.string() + '\n' + (index ? index : ""));
            return std::stoi(read(root / "fixture-exit"));
        }
        check(argc == 2, "Provide the exact candidate hook fixture.");
        const auto hook = fs::canonical(argv[1]);
        const auto self = fs::canonical(argv[0]);
        const auto previous = fs::current_path();
        auto pattern = (fs::temp_directory_path() / "factory-native-hook-XXXXXX").string();
        const auto* created = ::mkdtemp(pattern.data());
        check(created != nullptr, "The hook fixture has one private owned root.");
        const fs::path root(created);
        fixtures(root, hook, self);
        fs::current_path(previous);
        fs::remove_all(root);
        std::cout << checks << " native hook dispatch controls passed; no source suite or engine was replayed.\n";
    } catch (const std::exception& error) {
        std::cerr << "Hook dispatch failed after " << checks << " controls: " << error.what() << '\n';
        return 1;
    }
}
