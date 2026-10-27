#include "factory/capture.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <vector>

namespace {
namespace fs = std::filesystem;
using namespace std::chrono_literals;
int checks{};

void check(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
    ++checks;
}

void write(const fs::path& path, const std::string& value) {
    fs::create_directories(path.parent_path());
    std::ofstream output(path, std::ios::binary);
    check(static_cast<bool>(output) && static_cast<bool>(output.write(value.data(), value.size())),
          "Cannot create the compiler fixture input.");
}

std::string read(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    check(static_cast<bool>(input), "Cannot read the compiler fixture result.");
    return {std::istreambuf_iterator<char>(input), {}};
}

std::string git(const fs::path& root, const std::vector<std::string>& tail) {
    std::vector<std::string> command{"/usr/bin/git", "-C", root.string()};
    command.insert(command.end(), tail.begin(), tail.end());
    const auto result = factory_launch::run_process(command, 10s, 65536, nullptr, true);
    check(result.exit_code == 0, "The invented Git fixture command must succeed.");
    return result.output;
}

struct Permit {
    int fd;
    Permit(const fs::path& path, int mode) : fd(::open(path.c_str(), O_RDWR | O_CREAT | O_EXCL, 0600)) {
        if (fd < 0 || ::flock(fd, mode) != 0) {
            if (fd >= 0) ::close(fd);
            throw std::runtime_error("Cannot create synthetic compiler permits.");
        }
    }
    ~Permit() { ::close(fd); }
};

fs::path result_in(const fs::path& artifacts) {
    fs::path found;
    for (const auto& item : fs::directory_iterator(artifacts)) {
        if (item.path().filename().string().starts_with("parse-") &&
                fs::is_regular_file(item.path() / "result.json")) {
            check(found.empty(), "Each compiler route keeps one result.");
            found = item.path() / "result.json";
        }
    }
    check(!found.empty(), "The compiler must retain a result for its selected route.");
    return found;
}
} // namespace

int main(int argc, char** argv) {
    try {
        check(argc == 2, "Require the compiled native checker runfile.");
        const auto compiler = fs::canonical(argv[1]);
        const char* temporary = std::getenv("TEST_TMPDIR");
        check(temporary && *temporary, "Require a Bazel-owned temporary fixture root.");
        const auto root = fs::canonical(temporary) / "gdscript-compiler";
        check(fs::create_directory(root), "Use a fresh compiler fixture root.");
        const auto repository = root / "repository";
        const auto project = repository / "experiments/engine-environment/godot";
        fs::create_directories(repository);
        git(repository, {"init", "--quiet"});
        write(project / "project.godot", "config_version=5\n");
        write(project / "opening/opening.tscn", "[gd_scene format=3]\n[node name=\"Opening\" type=\"Node\"]\n");
        write(project / "opening/first.gd", "extends Node\n");
        write(project / "opening/second.gd", "extends Node\n");
        git(repository, {"add", "-A"});
        git(repository, {"-c", "user.name=Compiler fixture", "-c", "user.email=fixture@example.invalid",
                         "commit", "--quiet", "-m", "Create two compiler fixture scripts"});
        const auto initial_tree = git(repository, {"rev-parse", "HEAD^{tree}"});
        const auto engine = root / "fake-godot";
        write(engine, "#!/bin/sh\n"
                      "if test \"$1\" = --version; then printf '%s\\n' 4.7.2.stable.official.ed1daf0bf; exit 0; fi\n"
                      "for arg in \"$@\"; do\n"
                      "  if test \"$arg\" = res://opening/bad.gd; then\n"
                      "    printf '%s\\n' 'SCRIPT ERROR: Parse Error: invented zero-exit failure.' >&2\n"
                      "    exit 0\n"
                      "  fi\n"
                      "done\n"
                      "exit 0\n");
        fs::permissions(engine, fs::perms::owner_all);
        const auto pin = factory_launch::sha256(read(engine));
        const auto admission = root / "admission";
        fs::create_directory(admission);
        Permit heavy(admission / "heavy.lock", LOCK_EX);
        Permit activity(admission / "activity.lock", LOCK_SH);
        const auto invoke = [&](const fs::path& artifacts, const std::string& tree,
                                const std::string& engine_sha) {
            fs::create_directory(artifacts);
            fs::permissions(artifacts, fs::perms::owner_all);
            return factory_launch::run_process({compiler.string(), "--repo", repository.string(),
                "--tree", tree.substr(0, 40), "--godot", engine.string(), "--sha256", engine_sha,
                "--artifacts", artifacts.string(), "--admission", admission.string()},
                30s, 65536, nullptr, true);
        };
        const auto valid = invoke(root / "valid-artifacts", initial_tree, pin);
        check(valid.exit_code == 0 && valid.output.find("Parsed 2 immutable staged GDScripts") != std::string::npos,
              "A two-script immutable capture reaches every fake compiler stage.");
        const auto valid_receipt = read(result_in(root / "valid-artifacts"));
        check(valid_receipt.find("\"status\":\"pass\"") != std::string::npos &&
                  valid_receipt.find("\"script_count\":2") != std::string::npos &&
                  valid_receipt.find("\"capture_manifest_sha256\":\"\"") == std::string::npos &&
                  valid_receipt.find("\"name\":\"script-1\",\"exit\":0") != std::string::npos,
              "The success receipt binds the raw capture, script count and final stage.");
        const auto wrong_pin = invoke(root / "wrong-pin-artifacts", initial_tree, std::string(64, '0'));
        check(wrong_pin.exit_code == 2 && fs::is_empty(root / "wrong-pin-artifacts"),
              "An unpinned engine refuses before any captured source or stage output.");
        write(project / "opening/bad.gd", "extends Node\n");
        git(repository, {"add", "-A"});
        git(repository, {"-c", "user.name=Compiler fixture", "-c", "user.email=fixture@example.invalid",
                         "commit", "--quiet", "-m", "Add a zero-exit compiler error control"});
        const auto bad_tree = git(repository, {"rev-parse", "HEAD^{tree}"});
        const auto refused = invoke(root / "error-artifacts", bad_tree, pin);
        check(refused.exit_code == 1, "A zero-exit Godot error line must fail the native checker.");
        const auto failed_receipt = read(result_in(root / "error-artifacts"));
        check(failed_receipt.find("\"status\":\"fail\"") != std::string::npos &&
                  failed_receipt.find("\"name\":\"script-0\"") != std::string::npos,
              "The failing script stage is retained without a success receipt.");
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks
                  << ",\"evidence\":\"invented_native_compiler_contract\"}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Native compiler fixture failed: " << error.what() << '\n';
        return 1;
    }
}
