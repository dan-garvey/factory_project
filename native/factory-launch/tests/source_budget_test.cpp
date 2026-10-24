#include "factory/capture.hpp"
#include "factory/opening.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
namespace fs = std::filesystem;
using namespace factory_launch;
using namespace std::chrono_literals;
int checks = 0;

void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
    ++checks;
}

void write(const fs::path& path, const std::string& bytes) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary);
    if (!stream || !stream.write(bytes.data(), static_cast<std::streamsize>(bytes.size())))
        throw std::runtime_error("Cannot write the owned source-budget fixture.");
}

std::string read(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("Cannot read the owned source-budget fixture.");
    return {std::istreambuf_iterator<char>(stream), {}};
}

void refuses(const std::function<void()>& operation, const char* message) {
    try { operation(); }
    catch (const std::exception&) { ++checks; return; }
    throw std::runtime_error(message);
}

std::string git(const fs::path& repository, const std::vector<std::string>& tail) {
    std::vector<std::string> arguments{"/usr/bin/git", "-C", repository.string()};
    arguments.insert(arguments.end(), tail.begin(), tail.end());
    const auto result = run_process(arguments, 10s, 65536);
    check(result.exit_code == 0, "A disclosed Git fixture command must succeed.");
    return result.output;
}

std::string commit(const fs::path& repository) {
    git(repository, {"add", "-A"});
    git(repository, {"-c", "user.name=Budget fixture", "-c", "user.email=fixture@example.invalid",
                     "commit", "--quiet", "-m", "Source budget fixture"});
    auto revision = git(repository, {"rev-parse", "HEAD"});
    revision.pop_back();
    return revision;
}

void parser_boundary(const fs::path& root, const fs::path& parser,
                     const fs::path& bounds, std::size_t bytes, bool accepted) {
    const auto snapshot = root / "snapshot";
    const auto project = snapshot / "experiments/engine-environment/godot";
    fs::create_directories(snapshot / "scripts");
    fs::copy_file(parser, snapshot / "scripts/check_gdscript.py");
    fs::copy_file(bounds, snapshot / "scripts/check_engine_environment.py");
    const std::string configuration = "config_version=5\n";
    const std::string script = "extends Node\n";
    write(project / "project.godot", configuration);
    write(project / "fixture.gd", script);
    write(project / "asset.bin", std::string(bytes - configuration.size() - script.size(), 'p'));
    const auto fake = root / "fake-godot";
    // This utility tests input admission only. It imports no image and runs no
    // Godot code; every invocation is retained to detect premature execution.
    write(fake, "#!/bin/sh\nprintf '%s\\n' \"$1\" >> \"$0.calls\"\n"
                "if test \"$1\" = --version; then printf '%s\\n' 4.7.2.stable.official.ed1daf0bf; fi\n");
    fs::permissions(fake, fs::perms::owner_all);
    const auto artifacts = root / "parser-artifacts";
    const auto result = run_process({"/usr/bin/python3", "-B", (snapshot / "scripts/check_gdscript.py").string(),
        "--godot", fake.string(), "--sha256", sha256(read(fake)),
        "--artifacts", artifacts.string(), "--source-tree", std::string(40, 'a')}, 15s, 65536, nullptr, true);
    check((result.exit_code == 0) == accepted, "Parser admission agrees with the complete source-byte boundary.");
    fs::path receipt;
    for (const auto& entry : fs::directory_iterator(artifacts))
        if (fs::exists(entry.path() / "result.json")) receipt = entry.path() / "result.json";
    check(!receipt.empty(), "Both parser success and refusal retain a result.");
    const auto record = read(receipt);
    check(record.find(accepted ? "\"status\": \"pass\"" : "\"status\": \"fail\"") != std::string::npos,
          "The retained parser status cannot present a refused source as passing.");
    if (accepted) {
        check(read(fs::path(fake.string() + ".calls")) == "--version\n--headless\n--headless\n",
              "Accepted input reaches exactly the disclosed version/import/script utility stages.");
        check(sha256(read(receipt.parent_path() / "project/asset.bin")) == sha256(read(project / "asset.bin")),
              "The parser copies the complete binary asset unchanged.");
    } else {
        check(!fs::exists(fs::path(fake.string() + ".calls")), "Source overflow refuses before any utility stage.");
        check(record.find("64 MiB") != std::string::npos, "The refusal names the actual project-input allowance.");
    }
}
}  // namespace

int main(int argc, char** argv) {
    try {
        check(argc == 3, "Require both existing parser source runfiles.");
        const auto parser = fs::canonical(argv[1]);
        const auto bounds = fs::canonical(argv[2]);
        const auto* temporary = std::getenv("TEST_TMPDIR");
        check(temporary && *temporary, "Require the Bazel-owned disposable fixture root.");
        const auto root = fs::canonical(temporary) / "source-budget";
        check(fs::create_directory(root), "Use a fresh native fixture directory.");
        check(maximum_project_source_bytes == 64 * 1024 * 1024, "The native contract is exactly 64 MiB.");
        const auto repository = root / "repository";
        fs::create_directory(repository);
        git(repository, {"init", "--quiet"});
        const auto project = repository / "experiments/engine-environment/godot";
        const std::string config = "config_version=5\n";
        const std::string script = "extends Node\n";
        const std::string scene = "[gd_scene format=3]\n[node name=\"Opening\" type=\"Node\"]\n";
        write(project / "project.godot", config);
        write(project / "opening/fixture.gd", script);
        write(project / "opening/opening.tscn", scene);
        const auto fixed_bytes = config.size() + script.size() + scene.size();
        for (const auto bytes : {std::size_t{20 * 1024 * 1024}, maximum_project_source_bytes}) {
            const auto label = std::to_string(bytes);
            const std::string payload(bytes - fixed_bytes, 'a');
            write(project / "opening/asset.bin", payload);
            const auto revision = commit(repository);
            const auto captured = capture_project({repository, revision, root / ("capture-" + label)});
            check(captured.source_bytes == bytes, "Native capture accepts the exact complete byte count.");
            const auto original = captured.manifest.parent_path() / "project";
            check(read(original / "opening/asset.bin") == payload, "Raw Git capture preserves every asset byte.");
            const auto copy = copy_opening_project(original, root / ("runtime-" + label));
            check(read(copy.runtime / "opening/asset.bin") == payload, "Runtime copy preserves the enlarged asset byte-for-byte.");
            verify_opening_sources(copy);
            check(copy.sources.size() == 4, "No source file is skipped to obtain extra headroom.");
            parser_boundary(root / ("parser-" + label), parser, bounds, bytes, true);
        }
        write(project / "opening/asset.bin", std::string(maximum_project_source_bytes + 1 - fixed_bytes, 'a'));
        const auto overflow = commit(repository);
        const auto refused_capture = root / "capture-overflow";
        refuses([&] { capture_project({repository, overflow, refused_capture}); }, "One-byte native overflow must refuse.");
        check(!fs::exists(refused_capture), "Native overflow publishes no accepted capture.");
        refuses([&] { copy_opening_project(project, root / "runtime-overflow"); }, "One-byte runtime aggregate overflow must refuse.");
        check(!fs::exists(root / "runtime-overflow"), "Runtime source refusal publishes no output.");
        parser_boundary(root / "parser-overflow", parser, bounds, maximum_project_source_bytes + 1, false);
        write(root / "save.factory", std::string(2 * 1024 * 1024, 's'));
        const auto saved = copy_opening_resume(root / "save.factory", root / "incoming.factory");
        check(saved.bytes == 2 * 1024 * 1024, "The existing exact 2 MiB resume boundary still passes.");
        write(root / "large-save.factory", std::string(2 * 1024 * 1024 + 1, 's'));
        refuses([&] { copy_opening_resume(root / "large-save.factory", root / "large-incoming.factory"); },
                "Larger project inputs must not expand the opaque save allowance.");
        check(!fs::exists(root / "large-incoming.factory"), "Oversized saves publish no incoming copy.");
        std::cout << "PASS " << checks << " source-budget controls; real engine runs: 0.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL after " << checks << " source-budget controls: " << error.what() << '\n';
        return 1;
    }
}
