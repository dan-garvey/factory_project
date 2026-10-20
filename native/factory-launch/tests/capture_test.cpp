#include "factory/capture.hpp"

#include <chrono>
#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace fs = std::filesystem;
using namespace factory_launch;
using namespace std::chrono_literals;

namespace {
int checks = 0;
volatile std::sig_atomic_t interrupted = 0;
void interrupt_fixture(int signal) { interrupted = signal; }

void check(bool condition, const std::string& label) {
    if (!condition) throw std::runtime_error(label);
    ++checks;
}

std::string read(const fs::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("Cannot read the test artifact.");
    return std::string((std::istreambuf_iterator<char>(file)), {});
}

void write(const fs::path& path, const std::string& content) {
    fs::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary);
    if (!file || !file.write(content.data(), static_cast<std::streamsize>(content.size())))
        throw std::runtime_error("Cannot write the owned test fixture.");
}

void refuses(const std::function<void()>& operation, const std::string& label) {
    try { operation(); }
    catch (const std::runtime_error&) { ++checks; return; }
    throw std::runtime_error("Expected refusal: " + label);
}

std::string utility(const std::vector<std::string>& arguments) {
    const auto result = run_process(arguments, 5s, 1024 * 1024);
    check(result.exit_code == 0, "The fixture utility must succeed.");
    return result.output;
}

std::string git(const fs::path& repository, const std::vector<std::string>& tail) {
    std::vector<std::string> arguments{"/usr/bin/git", "-C", repository.string()};
    arguments.insert(arguments.end(), tail.begin(), tail.end());
    return utility(arguments);
}

std::string commit(const fs::path& repository) {
    git(repository, {"add", "-A"});
    git(repository, {"-c", "user.name=Capture fixture", "-c", "user.email=fixture@example.invalid",
                     "commit", "--quiet", "--allow-empty", "-m", "Capture fixture"});
    auto value = git(repository, {"rev-parse", "HEAD"});
    value.pop_back();
    return value;
}

void no_output_refusal(const CaptureOptions& options, const std::string& label) {
    refuses([&] { capture_project(options); }, label);
    check(!fs::exists(options.output), "A source refusal must not publish a capture directory.");
}

void closed_stream_fixture(bool close_all) {
    const pid_t child = ::fork();
    check(child >= 0, "Create the isolated closed-stream fixture.");
    if (child == 0) {
        ::close(STDOUT_FILENO);
        if (close_all) { ::close(STDIN_FILENO); ::close(STDERR_FILENO); }
        try {
            const auto result = run_process({"/usr/bin/printf", "closed-stream-output"}, 1s, 128);
            ::_exit(result.exit_code == 0 && result.output == "closed-stream-output" ? 0 : 2);
        } catch (...) { ::_exit(3); }
    }
    int status = 0;
    pid_t waited;
    do { waited = ::waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
    check(waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
          close_all ? "All closed standard streams preserve utility stdout."
                    : "Closed caller stdout preserves utility stdout.");
}
} // namespace

int main(int argc, char** argv) {
    try {
        check(argc == 2 || argc == 3, "The test requires the CLI and an explicit or Bazel-owned artifact parent.");
        const fs::path executable = fs::canonical(argv[1]);
        const char* artifact_parent = argc == 3 ? argv[2] : std::getenv("TEST_UNDECLARED_OUTPUTS_DIR");
        check(artifact_parent != nullptr && artifact_parent[0] != '\0', "The test must have an owned artifact directory.");
        // Bazel supplies an existing private writable directory. Resolve its
        // sandbox aliases before exercising the capture's canonical-path rule.
        const auto parent = argc == 2 ? fs::canonical(artifact_parent)
                                      : fs::absolute(fs::path(artifact_parent));
        const fs::path root = parent / ("first-" + std::to_string(::getpid()));
        check(!fs::exists(root), "Each native test invocation requires a fresh artifact root.");
        fs::create_directories(root);

        check(sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "Empty SHA256 vector.");
        check(sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "ABC SHA256 vector.");
        check(json_string("quote\"\\\n") == "\"quote\\\"\\\\\\u000a\"", "JSON escaping retains quotes, backslashes and controls.");
        check(utility({"/usr/bin/printf", "%s", "$(touch unsafe); literal"}) == "$(touch unsafe); literal", "Utility arguments never enter a shell.");
        const auto binary = run_process({"/usr/bin/printf", "a\\0b"}, 1s, 3);
        check(binary.exit_code == 0 && binary.output == std::string("a\0b", 3), "Binary stdout retains NUL bytes.");
        closed_stream_fixture(false);
        closed_stream_fixture(true);
        check(run_process({"/bin/false"}, 1s, 0).exit_code == 1, "A child refusal is not exit zero.");
        refuses([] { run_process({"/missing/factory-utility"}, 1s, 10); }, "Missing utility executable.");
        refuses([] { run_process({"/usr/bin/printf", "too much"}, 1s, 3); }, "Utility output bound.");
        refuses([] { run_process({"/bin/sleep", "1"}, 20ms, 10); }, "Utility timeout and owned-child cleanup.");
        struct sigaction alarm_action{}, original_alarm{};
        alarm_action.sa_handler = interrupt_fixture;
        ::sigemptyset(&alarm_action.sa_mask);
        check(::sigaction(SIGALRM, &alarm_action, &original_alarm) == 0, "Install the disposable interruption fixture.");
        ::ualarm(20000, 0);
        refuses([] { run_process({"/bin/sleep", "1"}, 2s, 10, &interrupted); }, "Interruption during an active utility.");
        ::ualarm(0, 0);
        check(interrupted == SIGALRM && ::sigaction(SIGALRM, &original_alarm, nullptr) == 0, "Retain the actual cancellation signal and restore the test handler.");

        const auto repository = root / "fixture-repository";
        fs::create_directory(repository);
        utility({"/usr/bin/git", "init", "--quiet", repository.string()});
        const auto project = repository / "experiments/engine-environment/godot";
        const std::string config = "config_version=5\n";
        const std::string script = "extends Node\nconst Worker = preload(\"res://opening/assets/worker.tscn\")\n";
        const std::string asset = "[gd_scene format=3]\n[node name=\"Worker\" type=\"Node3D\"]\n";
        const std::string bytes("\0\1\xff", 3);
        write(project / "project.godot", config);
        write(project / "opening/view.gd", script);
        write(project / "opening/assets/worker.tscn", asset);
        write(project / "opening/assets/data.bin", bytes);
        write(repository / ".gitattributes", "experiments/engine-environment/godot/opening/assets/worker.tscn export-ignore\n");
        fs::permissions(project / "opening/view.gd", fs::perms::owner_all | fs::perms::group_read
                        | fs::perms::group_exec | fs::perms::others_read | fs::perms::others_exec);
        const auto pristine = commit(repository);
        write(project / "opening/view.gd", "uncommitted replacement");
        write(project / "not-tracked.txt", "This untracked dummy is not an input.");
        fs::remove(project / "opening/assets/worker.tscn");
        const auto destination = root / "captured";
        const auto captured = capture_project({repository, pristine, destination});
        check(captured.files == 4 && captured.scripts == 1, "Every tracked resource is captured once.");
        check(captured.source_bytes == config.size() + script.size() + asset.size() + bytes.size(), "Raw source byte accounting.");
        check(read(destination / "project/opening/view.gd") == script, "Raw Git wins over modified working bytes.");
        check(read(destination / "project/opening/assets/worker.tscn") == asset, "A tracked dependency survives its working-file deletion.");
        check(read(destination / "project/opening/assets/data.bin") == bytes, "Binary asset bytes remain exact.");
        check(!fs::exists(destination / "project/not-tracked.txt"), "Untracked files are never captured.");
        const auto permissions = fs::status(destination / "project/opening/view.gd").permissions();
        check((permissions & fs::perms::owner_exec) != fs::perms::none, "Declared executable source mode is preserved.");
        const auto manifest = read(captured.manifest);
        check(manifest.find(sha256(asset)) != std::string::npos && manifest.find("\"engine_runs\": 0") != std::string::npos,
              "The manifest binds the actual asset without claiming an engine run.");
        const auto before = read(destination / "capture.json");
        refuses([&] { capture_project({repository, pristine, destination}); }, "Existing capture overwrite.");
        check(read(destination / "capture.json") == before, "Refusal preserves the original complete capture.");
        no_output_refusal({repository, "HEAD", root / "symbolic"}, "Mutable revision name.");
        no_output_refusal({repository, std::string(40, '0'), root / "missing-object"}, "Missing immutable object.");
        no_output_refusal({repository, pristine, repository / "inside"}, "Output inside a repository.");
        const auto bare = root / "bare-administration";
        utility({"/usr/bin/git", "init", "--bare", "--quiet", bare.string()});
        fs::create_directories(bare / "nested/parent");
        no_output_refusal({repository, pristine, bare / "capture"}, "Output inside another bare repository.");
        no_output_refusal({repository, pristine, bare / "nested/parent/capture"}, "Output below bare administration.");
        const auto separate = root / "separate-administration";
        const auto worktree = root / "other-worktree";
        utility({"/usr/bin/git", "init", "--quiet", "--separate-git-dir", separate.string(), worktree.string()});
        fs::create_directories(separate / "nested/parent");
        no_output_refusal({repository, pristine, separate / "capture"}, "Output inside separately named administration.");
        no_output_refusal({repository, pristine, separate / "nested/parent/capture"}, "Output below separately named administration.");
        no_output_refusal({repository, pristine, worktree / "capture"}, "Output inside another worktree.");
        write(bare / "config", "[broken configuration\n");
        no_output_refusal({repository, pristine, bare / "discovery-failure"}, "Git discovery errors fail closed.");
        fs::create_directory_symlink(root, root / "alias");
        no_output_refusal({repository, pristine, root / "alias/captured-alias"}, "Output through a symlinked parent.");
        no_output_refusal({repository, pristine, root / ".beads" / "capture"}, "Private metadata output path.");
        check(run_process({executable.string(), "--unknown", "value"}, 1s, 1024).exit_code == 1, "The CLI rejects unknown options.");
        const auto cli = run_process({executable.string(), "--repo", repository.string(), "--tree", pristine,
                                      "--output", (root / "cli-captured").string()}, 5s, 4096);
        check(cli.exit_code == 0 && read(root / "cli-captured/project/opening/assets/worker.tscn") == asset,
              "The public C++ capture entry point produces the immutable resource snapshot.");

        // The remaining commits are disclosed negative Git fixtures, never game runs.
        write(project / "opening/view.gd", script);
        write(project / "opening/assets/worker.tscn", asset);
        fs::create_symlink("view.gd", project / "opening/link.gd");
        const auto linked = commit(repository);
        no_output_refusal({repository, linked, root / "symlink-source"}, "Tracked source symlink.");
        fs::remove(project / "opening/link.gd");
        write(project / ".beads/private.json", "Dummy private fixture.");
        const auto private_tree = commit(repository);
        no_output_refusal({repository, private_tree, root / "private-source"}, "Tracked private metadata.");
        fs::remove_all(project / ".beads");
        write(project / "oversized.bin", std::string(2 * 1024 * 1024 + 1, 'x'));
        const auto oversized = commit(repository);
        no_output_refusal({repository, oversized, root / "oversized-source"}, "Source byte allowance.");
        fs::remove(project / "oversized.bin");
        for (int i = 0; i < 129; ++i) write(project / "many-scripts" / (std::to_string(i) + ".gd"), "extends Node\n");
        const auto many_scripts = commit(repository);
        no_output_refusal({repository, many_scripts, root / "many-scripts-source"}, "Script count allowance.");
        fs::remove_all(project / "many-scripts");
        for (int i = 0; i < 513; ++i) write(project / "many-files" / std::to_string(i), "");
        const auto many_files = commit(repository);
        no_output_refusal({repository, many_files, root / "many-files-source"}, "File count allowance.");
        fs::remove_all(project / "many-files");
        write(project / "odd\nname.gd", "extends Node\n");
        const auto odd_name = commit(repository);
        no_output_refusal({repository, odd_name, root / "odd-name-source"}, "Control character in a source path.");
        fs::remove(project / "odd\nname.gd");
        fs::remove(project / "project.godot");
        const auto missing_project = commit(repository);
        no_output_refusal({repository, missing_project, root / "missing-project"}, "Missing project configuration.");
        std::cout << "PASS " << checks << " native capture checks. Artifacts: " << root << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " native capture checks: " << error.what() << '\n';
        return 1;
    }
}
