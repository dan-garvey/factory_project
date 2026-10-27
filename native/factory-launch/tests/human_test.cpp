#include "factory/capture.hpp"

#include <algorithm>
#include <chrono>
#include <csignal>
#include <filesystem>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/wait.h>
#include <thread>
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
            "mkdir -p \"$out/runtime/project/opening\"\n"
            "printf '%s' \"$resume\" > \"$out/fake-resume-arg\"\n"
            "exit 0\n", true);
        write(repo / "native/factory-godot-world/native-world.gdextension", "[configuration]\nentry_symbol = fake\n");
        write(repo / "experiments/engine-environment/godot/project.godot", "config_version=5\n");
        write(repo / "experiments/engine-environment/godot/opening/shared_opening.tscn", "[gd_scene]\n");
        write(repo / "experiments/engine-environment/godot/opening/parts_view_check.gd", "extends SceneTree\n");
        write(repo / "experiments/engine-environment/godot/opening/machine_body_motion_check.gd", "extends SceneTree\n");
        write(repo / "experiments/engine-environment/godot/opening/machine_visual_test.gd", "extends SceneTree\n");
        write(repo / "experiments/engine-environment/godot/opening/production_environment_check.gd",
            "extends SceneTree\n");
        write(repo / "experiments/engine-environment/godot/opening/shared_opening.gd", "extends Node\n");
        write(repo / "experiments/engine-environment/godot/opening/native_transmission_view_check.gd",
            "extends SceneTree\n");
        write(repo / "experiments/engine-environment/godot/opening-session/session.gd", "extends Node\n");
        write(repo / "experiments/engine-environment/godot/model.gd", "extends RefCounted\n");
        write(repo / "experiments/engine-environment/godot/opening/native_adapter_check.gd", "extends SceneTree\n");
        write(repo / "experiments/engine-environment/godot/opening/other_check.gd", "extends SceneTree\n");
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
        auto agent = graphical;
        agent.insert(agent.end(), {"--agent", "--test-purpose", "Ore interaction reach"});
        const auto launched = root / "agent arguments";
        write(admission, "#!/bin/sh\nprintf '%s\\n' \"$@\" > '" + launched.string() + "'\nexit 0\n", true);
        require(run(agent).exit_code == 0 && read(launched).find("--test-purpose=Ore interaction reach") != std::string::npos,
                "A labeled player session forwards the purpose unchanged to Godot.");
        fs::remove(launched);
        auto missing_agent = graphical;
        missing_agent.push_back("--agent");
        require(run(missing_agent).exit_code != 0 && !fs::exists(launched),
                "An agent player window needs an explicit purpose.");
        for (const auto& invalid : {std::string(""), std::string("   "), std::string("\xe2\x80\x8b"),
                                    std::string("\xe2\x80\x8e"), std::string("\xef\xb8\x8f"),
                                    std::string("view\xe2\x80\xae hidden"),
                                    std::string("line\nwrap"),
                                    std::string(61, 'x'), std::string("\xc0\xaf")}) {
            auto rejected = graphical;
            rejected.insert(rejected.end(), {"--agent", "--test-purpose", invalid});
            require(run(rejected).exit_code != 0 && !fs::exists(launched),
                    "Invalid agent purposes refuse before creating a visible child.");
        }
        const std::vector<std::string> window_base{fs::canonical(argv[1]).string(), "--agent-window",
            "--repo", repo.string(), "--tree", tree, "--engine", engine.string(),
            "--engine-sha256", engine_hash, "--library", library.string(),
            "--library-sha256", library_hash, "--sessions", sessions.string(),
            "--admission", admission.string()};
        auto scene_window = window_base;
        scene_window.insert(scene_window.end(), {"--scene", "res://opening/shared_opening.tscn",
            "--test-purpose", "Shared client — vérification", "--", "--session-port=13200"});
        require(run(scene_window).exit_code == 0 &&
                read(launched).find("--test-purpose=Shared client — vérification") != std::string::npos &&
                read(launched).find("--session-port=13200") != std::string::npos &&
                read(launched).find("/native/runtime/project") != std::string::npos &&
                read(launched).find("--path\n" + (repo / "experiments/engine-environment/godot").string()) == std::string::npos,
                "A shared-client window forwards Unicode purpose into a separately prepared runtime.");
        fs::remove(launched);
        auto script_window = window_base;
        script_window.insert(script_window.end(), {"--script", "res://opening/parts_view_check.gd",
            "--test-purpose", "Slide fixture"});
        require(run(script_window).exit_code == 0 &&
                read(launched).find("--script\nres://opening/parts_view_check.gd") != std::string::npos,
                "A graphical fixture uses the same labeled agent window route.");
        std::size_t installed_fixtures = 0;
        for (const auto& entry : fs::directory_iterator(sessions)) {
            const auto fixture = entry.path() / "native/runtime/project/opening/parts_view_check.gd";
            if (fs::exists(fixture)) {
                ++installed_fixtures;
                require(read(fixture) == "extends SceneTree\n",
                    "The agent runtime must carry the exact selected tracked fixture.");
                require(read(entry.path() / "native/runtime/project/opening/shared_opening.gd") ==
                    "extends Node\n", "The workbed view also needs its checked shared view class.");
            }
        }
        require(installed_fixtures == 1,
            "Only the selected fixture runtime gains its checked-main script.");
        for (const std::string fixture : {"machine_body_motion_check.gd", "machine_visual_test.gd"}) {
            auto motion_window = window_base;
            motion_window.insert(motion_window.end(), {"--script", "res://opening/" + fixture,
                "--test-purpose", "Machine motion validation"});
            require(run(motion_window).exit_code == 0,
                "Machine motion checks can exercise actual renderer readback in a labeled window.");
            std::size_t installed = 0;
            for (const auto& entry : fs::directory_iterator(sessions)) {
                const auto project = entry.path() / "native/runtime/project";
                if (!fs::exists(project / "opening" / fixture)) continue;
                ++installed;
                require(read(project / "opening" / fixture) == "extends SceneTree\n",
                    "The motion fixture comes from checked main.");
                if (fixture == "machine_body_motion_check.gd")
                    require(read(project / "opening/shared_opening.gd") == "extends Node\n",
                        "Body motion also receives its shared view dependency.");
            }
            require(installed == 1, "Only the selected runtime receives each motion fixture.");
        }
        fs::remove(launched);
        auto environment_window = window_base;
        const auto render_artifacts = root / "scenery captures with spaces";
        environment_window.insert(environment_window.end(), {"--script",
            "res://opening/production_environment_check.gd", "--test-purpose", "Scenery render check",
            "--", "--environment-case=site-render", "--artifacts=" + render_artifacts.string()});
        require(run(environment_window).exit_code == 0 &&
                read(launched).find("--script\nres://opening/production_environment_check.gd") != std::string::npos &&
                read(launched).find("--test-purpose=Scenery render check") != std::string::npos &&
                read(launched).find("--artifacts=" + render_artifacts.string()) != std::string::npos,
                "A labeled scenery case forwards its capture directory through the tracked agent window.");
        std::size_t installed_environment_fixtures = 0;
        for (const auto& entry : fs::directory_iterator(sessions)) {
            const auto fixture = entry.path() / "native/runtime/project/opening/production_environment_check.gd";
            if (!fs::exists(fixture)) continue;
            ++installed_environment_fixtures;
            require(read(fixture) == "extends SceneTree\n",
                "The scenery fixture comes from checked main rather than the source checkout.");
        }
        require(installed_environment_fixtures == 1,
            "Only the selected scenery runtime receives its checked fixture.");
        fs::remove(launched);
        auto transmission_window = window_base;
        transmission_window.insert(transmission_window.end(), {"--script",
            "res://opening/native_transmission_view_check.gd", "--test-purpose", "Broad press view"});
        require(run(transmission_window).exit_code == 0 &&
                read(launched).find("--script\nres://opening/native_transmission_view_check.gd") != std::string::npos,
                "The mechanical view fixture uses the same labeled agent window route.");
        std::size_t complete_view_runtimes = 0;
        for (const auto& entry : fs::directory_iterator(sessions)) {
            const auto project = entry.path() / "native/runtime/project";
            if (fs::exists(project / "opening/native_transmission_view_check.gd")) {
                ++complete_view_runtimes;
                require(read(project / "opening/shared_opening.gd") == "extends Node\n" &&
                        read(project / "opening-session/session.gd") == "extends Node\n" &&
                        read(project / "model.gd") == "extends RefCounted\n",
                    "The mechanical view receives its exact shared fixture dependencies.");
            }
        }
        require(complete_view_runtimes == 1,
            "Only the selected mechanical view runtime gains shared fixture dependencies.");
        fs::remove(launched);
        auto adapter_window = window_base;
        adapter_window.insert(adapter_window.end(), {"--script", "res://opening/native_adapter_check.gd",
            "--test-purpose", "First plate route", "--", "--native-check-mode=arrival-first-plate"});
        require(run(adapter_window).exit_code == 0 &&
                read(launched).find("--script\nres://opening/native_adapter_check.gd") != std::string::npos &&
                read(launched).find("--test-purpose=First plate route") != std::string::npos &&
                read(launched).find("--native-check-mode=arrival-first-plate") != std::string::npos,
                "The native first-plate fixture forwards the purpose and selected mode.");
        fs::remove(launched);
        auto missing_adapter_purpose = window_base;
        missing_adapter_purpose.insert(missing_adapter_purpose.end(),
            {"--script", "res://opening/native_adapter_check.gd"});
        require(run(missing_adapter_purpose).exit_code != 0 && !fs::exists(launched),
                "The native first-plate window refuses a missing purpose before a graphical child.");
        auto invalid_adapter_purpose = adapter_window;
        auto invalid_adapter_label = std::find(invalid_adapter_purpose.begin(), invalid_adapter_purpose.end(),
            "First plate route");
        require(invalid_adapter_label != invalid_adapter_purpose.end(), "Find the adapter label argument.");
        *invalid_adapter_label = "line\nwrap";
        require(run(invalid_adapter_purpose).exit_code != 0 && !fs::exists(launched),
                "The native first-plate window refuses a multiline purpose before a graphical child.");
        auto unsupported = window_base;
        unsupported.insert(unsupported.end(), {"--script", "res://opening/other_check.gd",
            "--test-purpose", "Unregistered fixture"});
        require(run(unsupported).exit_code != 0 && !fs::exists(launched),
                "An unregistered fixture cannot open an unlabeled agent window.");
        auto duplicate_purpose = script_window;
        duplicate_purpose.insert(duplicate_purpose.end(), {"--", "--test-purpose=second"});
        require(run(duplicate_purpose).exit_code != 0 && !fs::exists(launched),
                "A user argument cannot replace the validated window purpose.");
        auto missing_window = window_base;
        missing_window.insert(missing_window.end(), {"--scene", "res://opening/shared_opening.tscn"});
        require(run(missing_window).exit_code != 0 && !fs::exists(launched),
                "Shared and fixture agent windows need an explicit purpose.");
        for (const auto& invalid : {std::string(""), std::string("  "), std::string("line\nwrap"),
                                    std::string(61, 'x')}) {
            auto rejected = window_base;
            rejected.insert(rejected.end(), {"--scene", "res://opening/shared_opening.tscn",
                "--test-purpose", invalid});
            require(run(rejected).exit_code != 0 && !fs::exists(launched),
                    "Invalid shared or fixture purposes refuse before a visible child.");
        }
        const auto marker = root / "graphical child.pid";
        write(admission, "#!/bin/sh\nsleep 60 &\nprintf '%s' \"$!\" > '" + marker.string() +
                         "'\nwait\n", true);
        const pid_t launcher = ::fork();
        require(launcher >= 0, "Cannot start the owned cancellation fixture.");
        if (launcher == 0) {
            const int quiet = ::open("/dev/null", O_WRONLY);
            if (quiet >= 0) { ::dup2(quiet, STDOUT_FILENO); ::dup2(quiet, STDERR_FILENO); ::close(quiet); }
            std::vector<char*> arguments;
            for (auto& value : graphical) arguments.push_back(value.data());
            arguments.push_back(nullptr);
            ::execv(graphical.front().c_str(), arguments.data());
            ::_exit(127);
        }
        bool child_started = false;
        for (int attempt = 0; attempt < 120; ++attempt) {
            if (fs::exists(marker)) { child_started = true; break; }
            std::this_thread::sleep_for(50ms);
        }
        if (!child_started) { ::kill(launcher, SIGTERM); ::waitpid(launcher, nullptr, 0); }
        require(child_started, "The graphical child did not reach its owned process group.");
        const auto sleep_pid = static_cast<pid_t>(std::stoi(read(marker)));
        require(::kill(launcher, SIGTERM) == 0, "Cannot cancel the native launcher.");
        int status = 0;
        bool launcher_stopped = false;
        for (int attempt = 0; attempt < 140; ++attempt) {
            if (::waitpid(launcher, &status, WNOHANG) == launcher) { launcher_stopped = true; break; }
            std::this_thread::sleep_for(50ms);
        }
        if (!launcher_stopped) { ::kill(launcher, SIGKILL); ::waitpid(launcher, nullptr, 0); ::kill(sleep_pid, SIGTERM); }
        require(launcher_stopped && WIFEXITED(status) && WEXITSTATUS(status) == 143,
                "The cancelled native launcher did not report SIGTERM.");
        const auto child_status = fs::path("/proc") / std::to_string(sleep_pid) / "stat";
        if (fs::exists(child_status)) {
            const auto state = read(child_status);
            const auto end = state.rfind(')');
            if (end == std::string::npos || end + 2 >= state.size() || state[end + 2] != 'Z')
                ::kill(sleep_pid, SIGTERM);
            require(end != std::string::npos && end + 2 < state.size() && state[end + 2] == 'Z',
                    "A graphical descendant survived native launcher cancellation.");
        }
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
