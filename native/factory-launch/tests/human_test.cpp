#include "factory/capture.hpp"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace fs = std::filesystem;
using namespace std::chrono_literals;

void require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}
void write(const fs::path& path, const std::string& content, bool executable = false) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary);
    require(static_cast<bool>(stream), "Cannot create test input.");
    stream << content;
    stream.close();
    if (executable) require(::chmod(path.c_str(), 0700) == 0, "Cannot mark fake child executable.");
}
std::string read(const fs::path& path) {
    std::ifstream stream(path);
    require(static_cast<bool>(stream), "Missing fake child record.");
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}
factory_launch::ProcessResult run(std::vector<std::string> arguments) {
    return factory_launch::run_process(arguments, 15s, 1024 * 1024, nullptr, true);
}
std::string git(const fs::path& repo, std::vector<std::string> args) {
    std::vector<std::string> command{"/usr/bin/git", "-C", repo.string()};
    command.insert(command.end(), args.begin(), args.end());
    const auto result = run(command);
    require(result.exit_code == 0, "Test Git command failed.");
    return result.output;
}
fs::path only_session(const fs::path& root, std::size_t expected) {
    std::vector<fs::path> sessions;
    for (const auto& entry : fs::directory_iterator(root))
        if (entry.is_directory()) sessions.push_back(entry.path());
    require(sessions.size() == expected, "Unexpected number of native sessions.");
    return sessions.back();
}

int main(int argc, char** argv) {
    fs::path root;
    try {
        require(argc == 2, "Pass the startup executable.");
        std::string pattern = (fs::temp_directory_path() / "factory human launch spaces-XXXXXX").string();
        char* created = ::mkdtemp(pattern.data());
        require(created, "Cannot create isolated test family.");
        root = created;
        const auto repo = root / "repo with spaces";
        const auto sessions = root / "sessions with spaces";
        fs::create_directories(repo);
        fs::create_directories(sessions);
        const auto script = repo / "scripts/run-human-startup.sh";
        write(script,
            "#!/bin/sh\n"
            "out=; resume=\n"
            "while [ \"$#\" -gt 0 ]; do\n"
            "  case \"$1\" in --output) out=$2; shift 2;; --resume) resume=$2; shift 2;; *) shift;; esac\n"
            "done\n"
            "mkdir -p \"$out\"\n"
            "printf '%s' \"$resume\" > \"$out/fake-resume-arg\"\n"
            "exit 0\n", true);
        write(repo / "native/factory-godot-world/native-world.gdextension", "[configuration]\nentry_symbol = fake\n");
        require(run({"/usr/bin/git", "-C", repo.string(), "init", "-b", "main"}).exit_code == 0,
                "Cannot init fake repo.");
        git(repo, {"add", "."});
        git(repo, {"-c", "user.name=Factory Test", "-c", "user.email=test@factory.invalid", "commit", "-m", "fixture"});
        const auto tree = git(repo, {"rev-parse", "HEAD"}).substr(0, 40);
        const auto engine = root / "fake engine";
        const auto library = root / "fake library.so";
        const auto admission = root / "fake admission";
        write(engine, "engine", true);
        write(library, "library");
        write(admission, "#!/bin/sh\nexit 1\n", true);
        const std::string engine_hash = factory_launch::sha256("engine");
        const std::string library_hash = factory_launch::sha256("library");
        const std::vector<std::string> base{fs::canonical(argv[1]).string(), "--human-launch",
            "--repo", repo.string(), "--tree", tree, "--engine", engine.string(),
            "--engine-sha256", engine_hash, "--library", library.string(),
            "--library-sha256", library_hash, "--sessions", sessions.string(),
            "--admission", admission.string(), "--prepare-session-only"};
        require(run(base).exit_code == 0, "Fresh fake child did not finish.");
        const auto fresh = only_session(sessions, 1);
        require(read(fresh / "native/fake-resume-arg").empty(), "Fresh startup received resume input.");
        require(read(fresh / "native-world.gdextension") == "[configuration]\nentry_symbol = fake\n",
                "Tracked descriptor was not captured.");
        const auto save = root / "save with spaces.factory";
        write(save, "opaque-native-save");
        auto resumed = base;
        resumed.insert(resumed.end(), {"--resume", save.string()});
        require(run(resumed).exit_code == 0, "Resumed fake child did not finish.");
        std::size_t count = 0;
        for (const auto& entry : fs::directory_iterator(sessions)) {
            ++count;
            if (entry.path() != fresh)
                require(read(entry.path() / "native/fake-resume-arg") == save.string(),
                        "Resumed startup lost the selected native save path.");
        }
        require(count == 2, "Resume must create a separate session.");
        auto stale = base;
        const auto pin = std::find(stale.begin(), stale.end(), library_hash);
        require(pin != stale.end(), "Cannot find fake library pin.");
        *pin = std::string(64, '0');
        const auto refusal = run(stale);
        require(refusal.exit_code != 0 && refusal.output.find("Missing or changed native launch resource") != std::string::npos,
                "A stale library must refuse before startup.");
        count = 0;
        for (const auto& entry : fs::directory_iterator(sessions)) {
            (void)entry;
            ++count;
        }
        require(count == 2, "A stale library must not create a session.");
        auto graphical = base;
        graphical.pop_back();
        const auto graphical_failure = run(graphical);
        require(graphical_failure.exit_code != 0 &&
                graphical_failure.output.find("graphical engine exited 1") != std::string::npos,
                "A failed graphical child must report its exit and retain the session.");
        write(script, "#!/bin/sh\nprintf 'fake child failed\\n'\nexit 23\n", true);
        git(repo, {"add", "."});
        git(repo, {"-c", "user.name=Factory Test", "-c", "user.email=test@factory.invalid", "commit", "-m", "failure"});
        auto failed = base;
        failed[5] = git(repo, {"rev-parse", "HEAD"}).substr(0, 40);
        const auto failure = run(failed);
        require(failure.exit_code != 0 && failure.output.find("fake child failed") != std::string::npos &&
                failure.output.find("Retained session:") != std::string::npos,
                "Fake child failure must preserve its report and session path.");
        std::cout << "Human launcher fake child, space path, resume and refusal controls passed.\n";
        fs::remove_all(root);
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        if (!root.empty()) fs::remove_all(root);
        return 1;
    }
}
