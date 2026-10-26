#include "factory/human.hpp"
#include "factory/capture.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <spawn.h>
#include <stdexcept>
#include <string_view>
#include <sys/stat.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

extern char** environ;
namespace factory_launch {
namespace {
namespace fs = std::filesystem;
using namespace std::chrono_literals;
volatile std::sig_atomic_t cancelled = 0;
void stop(int signal) { cancelled = signal; }
void require(bool ok, const std::string& message) {
    if (!ok) throw std::runtime_error(message);
}
bool digest(const std::string& value, std::size_t size) {
    return value.size() == size && std::all_of(value.begin(), value.end(), [](unsigned char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    });
}
bool valid_purpose(std::string_view value) {
    std::size_t count = 0;
    bool visible = false;
    for (std::size_t i = 0; i < value.size();) {
        const auto first = static_cast<unsigned char>(value[i]);
        std::uint32_t point = 0;
        std::size_t width = 0;
        if (first < 0x80) { point = first; width = 1; }
        else if (first >= 0xc2 && first <= 0xdf) { point = first & 0x1f; width = 2; }
        else if (first >= 0xe0 && first <= 0xef) { point = first & 0x0f; width = 3; }
        else if (first >= 0xf0 && first <= 0xf4) { point = first & 0x07; width = 4; }
        else return false;
        if (width > value.size() - i) return false;
        for (std::size_t j = 1; j < width; ++j) {
            const auto byte = static_cast<unsigned char>(value[i + j]);
            if ((byte & 0xc0) != 0x80) return false;
            point = (point << 6) | (byte & 0x3f);
        }
        if ((width == 3 && point < 0x800) || (width == 4 && point < 0x10000) ||
            (point >= 0xd800 && point <= 0xdfff) || point > 0x10ffff ||
            point < 0x20 || (point >= 0x7f && point <= 0x9f) ||
            point == 0x2028 || point == 0x2029 || point == 0x061c ||
            point == 0x200e || point == 0x200f ||
            (point >= 0x202a && point <= 0x202e) ||
            (point >= 0x2066 && point <= 0x2069)) return false;
        const bool invisible = point == 0x20 || point == 0xa0 || point == 0x1680 ||
            (point >= 0x2000 && point <= 0x200a) || point == 0x202f ||
            point == 0x205f || point == 0x3000 ||
            point == 0xad || point == 0x034f || point == 0x180e ||
            (point >= 0x200b && point <= 0x200d) ||
            (point >= 0x2060 && point <= 0x2064) ||
            (point >= 0xfe00 && point <= 0xfe0f) || point == 0xfeff;
        visible |= !invisible;
        if (++count > 60) return false;
        i += width;
    }
    return visible;
}
void require_purpose(const std::string& value) {
    require(valid_purpose(value),
        "Usage: --test-purpose TEXT must be 1-60 single-line Unicode characters with visible text.");
}
void install_handlers() {
    struct sigaction action{};
    action.sa_handler = stop;
    ::sigemptyset(&action.sa_mask);
    require(::sigaction(SIGINT, &action, nullptr) == 0 &&
            ::sigaction(SIGTERM, &action, nullptr) == 0,
            "Cannot install launch cancellation handlers.");
}
std::string regular(const fs::path& path, std::size_t limit) {
    const int fd = ::open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    require(fd >= 0, "Cannot open the pinned native resource: " + path.string());
    struct Guard { int fd; ~Guard() { ::close(fd); } } guard{fd};
    struct stat before{}, after{};
    require(::fstat(fd, &before) == 0 && S_ISREG(before.st_mode) && before.st_size >= 0 &&
            static_cast<std::uint64_t>(before.st_size) <= limit, "Invalid pinned native resource: " + path.string());
    std::string bytes;
    bytes.reserve(static_cast<std::size_t>(before.st_size));
    std::array<char, 65536> buffer{};
    while (true) {
        const auto n = ::read(fd, buffer.data(), buffer.size());
        if (n < 0 && errno == EINTR) continue;
        require(n >= 0 && static_cast<std::size_t>(std::max<ssize_t>(n, 0)) <= limit - bytes.size(),
                "Pinned native resource changed while reading: " + path.string());
        if (n == 0) break;
        bytes.append(buffer.data(), static_cast<std::size_t>(n));
    }
    require(::fstat(fd, &after) == 0 && before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
            before.st_size == after.st_size && before.st_mtim.tv_sec == after.st_mtim.tv_sec &&
            before.st_mtim.tv_nsec == after.st_mtim.tv_nsec,
            "Pinned native resource changed while reading: " + path.string());
    return bytes;
}
void sealed(const fs::path& path, const std::string& expected, std::size_t limit, bool executable) {
    require(path.is_absolute() && digest(expected, 64) && sha256(regular(path, limit)) == expected &&
            (!executable || ::access(path.c_str(), X_OK) == 0),
            "Missing or changed native launch resource: " + path.string());
}
std::string git(const fs::path& repo, std::vector<std::string> tail, std::size_t limit = 4096) {
    std::vector<std::string> args{"/usr/bin/git", "-C", repo.string()};
    args.insert(args.end(), tail.begin(), tail.end());
    auto result = run_process(args, 10s, limit, &cancelled);
    require(result.exit_code == 0, "Cannot verify the current main source.");
    return result.output;
}
void current(const fs::path& repo, const std::string& tree) {
    require(git(repo, {"symbolic-ref", "--quiet", "--short", "HEAD"}) == "main\n" &&
            git(repo, {"rev-parse", "--verify", "HEAD"}) == tree + "\n" &&
            git(repo, {"status", "--porcelain", "--untracked-files=normal"}).empty(),
            "The main checkout changed or contains uncommitted source.");
}
void write_new(const fs::path& path, const std::string& bytes) {
    const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    require(fd >= 0, "Cannot create the new native descriptor.");
    struct Guard { int fd; ~Guard() { ::close(fd); } } guard{fd};
    std::size_t offset = 0;
    while (offset < bytes.size()) {
        const auto n = ::write(fd, bytes.data() + offset, bytes.size() - offset);
        if (n < 0 && errno == EINTR) continue;
        require(n > 0, "Cannot finish the new native descriptor.");
        offset += static_cast<std::size_t>(n);
    }
    require(::fsync(fd) == 0, "Cannot retain the new native descriptor.");
}
fs::path make_session(const fs::path& root) {
    require(root.is_absolute(), "Use an absolute owned session directory.");
    fs::create_directories(root);
    struct stat status{};
    require(fs::canonical(root) == root && ::lstat(root.c_str(), &status) == 0 &&
            S_ISDIR(status.st_mode) && status.st_uid == ::geteuid(),
            "Use a canonical owned session directory.");
    std::string pattern = (root / "run-XXXXXX").string();
    char* created = ::mkdtemp(pattern.data());
    require(created != nullptr, "Cannot create a fresh native session.");
    return fs::path(created);
}
int graphical(const std::vector<std::string>& command) {
    posix_spawnattr_t attributes;
    require(::posix_spawnattr_init(&attributes) == 0, "Cannot initialize graphical child attributes.");
    struct Attributes { posix_spawnattr_t* value; ~Attributes() { ::posix_spawnattr_destroy(value); } } guard{&attributes};
    require(::posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP) == 0 &&
            ::posix_spawnattr_setpgroup(&attributes, 0) == 0,
            "Cannot isolate the graphical child process group.");
    std::vector<char*> args;
    for (const auto& item : command) args.push_back(const_cast<char*>(item.c_str()));
    args.push_back(nullptr);
    pid_t pid = -1;
    require(::posix_spawn(&pid, command.front().c_str(), nullptr, &attributes, args.data(), environ) == 0,
            "Cannot start the admitted graphical engine.");
    struct Child {
        pid_t pid;
        ~Child() {
            if (pid <= 0) return;
            ::kill(-pid, SIGTERM);
            // The admission wrapper and engine inherit this group. Give the
            // engine its shutdown window before enforcing the final stop.
            std::this_thread::sleep_for(3s);
            ::kill(-pid, SIGKILL);
            int status = 0;
            while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        }
    } child{pid};
    const auto deadline = std::chrono::steady_clock::now() + 1800s;
    while (true) {
        require(cancelled == 0, "The graphical launch was cancelled.");
        siginfo_t info{};
        const int observed = ::waitid(P_PID, static_cast<id_t>(pid), &info, WEXITED | WNOHANG | WNOWAIT);
        require(observed == 0 || errno == EINTR, "Cannot observe the graphical engine.");
        if (observed == 0 && info.si_pid == pid) break;
        require(std::chrono::steady_clock::now() < deadline, "The graphical engine exceeded its deadline.");
        std::this_thread::sleep_for(50ms);
    }
    // Keep the leader unreaped until owned descendants have been stopped.
    ::kill(-pid, SIGKILL);
    int status = 0;
    pid_t reaped;
    do { reaped = ::waitpid(pid, &status, 0); } while (reaped < 0 && errno == EINTR);
    require(reaped == pid, "Cannot reap the graphical engine.");
    child.pid = -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
} // namespace

int human_launch(int argc, char** argv) {
    fs::path session;
    try {
        install_handlers();
        std::map<std::string, std::string> options;
        bool session_only = false;
        bool agent = false;
        for (int i = 0; i < argc; ++i) {
            const std::string name(argv[i]);
            if (name == "--prepare-session-only") {
                require(!session_only, "Use each launch option once.");
                session_only = true;
            } else if (name == "--agent") {
                require(!agent, "Use each launch option once.");
                agent = true;
            } else {
                require(i + 1 < argc && (name == "--repo" || name == "--tree" || name == "--engine" ||
                        name == "--engine-sha256" || name == "--library" || name == "--library-sha256" ||
                        name == "--sessions" || name == "--admission" || name == "--resume" ||
                        name == "--test-purpose") &&
                        options.emplace(name, argv[++i]).second, "Use each documented launch option once.");
            }
        }
        require(!agent || (!session_only && options.count("--test-purpose")),
                "Usage: graphical --agent requires --test-purpose TEXT.");
        require(agent || !options.count("--test-purpose"),
                "Use --test-purpose only with the explicit agent graphical mode.");
        if (agent) require_purpose(options.at("--test-purpose"));
        for (const auto* name : {"--repo", "--tree", "--engine", "--engine-sha256", "--library",
                                  "--library-sha256", "--sessions", "--admission"})
            require(options.count(name), std::string("Missing launch option: ") + name);
        const fs::path repo(options.at("--repo")), engine(options.at("--engine"));
        const fs::path library(options.at("--library")), admission(options.at("--admission"));
        const fs::path root(options.at("--sessions"));
        const std::string tree = options.at("--tree");
        require(repo.is_absolute() && fs::canonical(repo) == repo && digest(tree, 40),
                "Use a canonical committed main checkout.");
        require(root != repo && root.string().rfind(repo.string() + "/", 0) != 0,
                "Keep native sessions outside the source checkout.");
        require(admission.is_absolute() && fs::is_regular_file(admission) &&
                ::access(admission.c_str(), X_OK) == 0,
                "The resource admission helper is unavailable.");
        current(repo, tree);
        sealed(engine, options.at("--engine-sha256"), 512 * 1024 * 1024, true);
        sealed(library, options.at("--library-sha256"), 64 * 1024 * 1024, false);
        if (options.count("--resume"))
            require(fs::path(options.at("--resume")).is_absolute(), "Use an absolute saved session.");
        session = make_session(root);
        const auto descriptor_bytes = git(repo, {"show", tree + ":native/factory-godot-world/native-world.gdextension"},
                                          1024 * 1024);
        const auto descriptor = session / "native-world.gdextension";
        write_new(descriptor, descriptor_bytes);
        const auto descriptor_digest = sha256(descriptor_bytes);
        current(repo, tree);
        const auto admission_directory = admission.parent_path();
        const auto self = fs::canonical("/proc/self/exe");
        std::vector<std::string> startup{(repo / "scripts/run-human-startup.sh").string(),
            repo.string(), admission.string(), self.string()};
        startup.insert(startup.end(), {"--repo", repo.string(), "--tree", tree, "--output", (session / "native").string(),
            "--godot", engine.string(), "--engine-sha256", options.at("--engine-sha256"),
            "--admission", admission_directory.string(), "--native-descriptor", descriptor.string(),
            "--native-descriptor-sha256", descriptor_digest, "--native-descriptor-relative", "native-world.gdextension",
            "--native-library", library.string(), "--native-library-sha256", options.at("--library-sha256"),
            "--native-library-relative", "factory-native-world.so"});
        if (options.count("--resume"))
            startup.insert(startup.end(), {"--resume", options.at("--resume")});
        std::cout << "Preparing native session: " << session << std::endl;
        const auto result = run_process(startup, 360s, 8 * 1024 * 1024, &cancelled, true);
        std::cout << result.output << std::flush;
        require(result.exit_code == 0, "Native startup failed; inspect the retained session logs.");
        current(repo, tree);
        sealed(engine, options.at("--engine-sha256"), 512 * 1024 * 1024, true);
        sealed(library, options.at("--library-sha256"), 64 * 1024 * 1024, false);
        if (session_only) {
            std::cout << "Session prepared without opening a desktop window: " << session << '\n';
            return 0;
        }
        std::vector<std::string> command{admission.string(), "--root", repo.string(), "heavy", "--",
            engine.string(), "--path",
            (session / "native/runtime/project").string(), "res://opening/opening.tscn", "--",
            "--save-slot=" + (session / "player.factory").string()};
        if (options.count("--resume"))
            command.push_back("--resume-input=" + (session / "native/incoming.factory").string());
        if (agent) command.push_back("--test-purpose=" + options.at("--test-purpose"));
        std::cout << "Opening Factory. Session and save: " << session << std::endl;
        const int code = graphical(command);
        require(code == 0, "The graphical engine exited " + std::to_string(code) + ".");
        std::cout << "Factory closed. Session and save: " << session << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Factory could not finish launching: " << error.what() << '\n';
        if (!session.empty()) std::cerr << "Retained session: " << session << '\n';
        return cancelled ? 128 + cancelled : 1;
    }
}

int agent_window_launch(int argc, char** argv) {
    fs::path session;
    try {
        install_handlers();
        std::map<std::string, std::string> options;
        std::vector<std::string> user_arguments;
        for (int i = 0; i < argc; ++i) {
            const std::string name(argv[i]);
            if (name == "--") {
                while (++i < argc) user_arguments.emplace_back(argv[i]);
                break;
            }
            require(i + 1 < argc && (name == "--repo" || name == "--tree" ||
                    name == "--engine" || name == "--engine-sha256" ||
                    name == "--library" || name == "--library-sha256" ||
                    name == "--sessions" || name == "--admission" || name == "--test-purpose" ||
                    name == "--scene" || name == "--script") &&
                    options.emplace(name, argv[++i]).second,
                    "Usage: --agent-window needs one scene or script and --test-purpose TEXT.");
        }
        for (const auto* name : {"--repo", "--tree", "--engine", "--engine-sha256",
                                  "--library", "--library-sha256", "--sessions",
                                  "--admission", "--test-purpose"})
            require(options.count(name), "Usage: --agent-window needs source, engine and --test-purpose TEXT.");
        require(options.count("--scene") + options.count("--script") == 1,
                "Usage: --agent-window needs exactly one --scene or --script.");
        require_purpose(options.at("--test-purpose"));
        require(user_arguments.size() <= 64, "Too many agent window arguments.");
        for (const auto& argument : user_arguments)
            require(argument.size() <= 4096 && argument.find('\n') == std::string::npos &&
                    argument.find('\r') == std::string::npos &&
                    !argument.starts_with("--test-purpose="),
                    "Agent window arguments must be single-line and bounded.");
        const fs::path repo(options.at("--repo")), engine(options.at("--engine"));
        const fs::path library(options.at("--library")), admission(options.at("--admission"));
        const fs::path root(options.at("--sessions"));
        const auto tree = options.at("--tree");
        require(repo.is_absolute() && fs::canonical(repo) == repo && digest(tree, 40),
                "Use a canonical committed main checkout.");
        require(root != repo && root.string().rfind(repo.string() + "/", 0) != 0,
                "Keep native sessions outside the source checkout.");
        current(repo, tree);
        sealed(engine, options.at("--engine-sha256"), 512 * 1024 * 1024, true);
        sealed(library, options.at("--library-sha256"), 64 * 1024 * 1024, false);
        require(admission.is_absolute() && fs::is_regular_file(admission) &&
                ::access(admission.c_str(), X_OK) == 0,
                "The resource admission helper is unavailable.");
        const auto project = repo / "experiments/engine-environment/godot";
        require(fs::canonical(project) == project && fs::is_regular_file(project / "project.godot"),
                "The tracked Godot project is unavailable.");
        const bool script = options.count("--script");
        const auto target = options.at(script ? "--script" : "--scene");
        require(script ? (target == "res://opening/parts_view_check.gd" ||
                          target == "res://opening/native_adapter_check.gd" ||
                          target == "res://opening/native_transmission_view_check.gd" ||
                          target == "res://opening/worker_wardrobe_view_check.gd") :
                         target == "res://opening/shared_opening.tscn",
                "This agent window target has no verified title initialization.");
        require(target.starts_with("res://") && target.size() <= 256,
                "Use a project-relative scene or script.");
        const fs::path relative(target.substr(6));
        require(!relative.empty() && !relative.is_absolute() &&
                relative.lexically_normal() == relative &&
                relative.extension() == (script ? ".gd" : ".tscn") &&
                std::none_of(relative.begin(), relative.end(), [](const fs::path& part) {
                    return part == "." || part == "..";
                }) && fs::is_regular_file(project / relative) &&
                fs::canonical(project / relative) == project / relative,
                "The selected scene or script is not a tracked project file.");
        session = make_session(root);
        const auto descriptor_bytes = git(repo, {"show", tree + ":native/factory-godot-world/native-world.gdextension"},
                                          1024 * 1024);
        const auto descriptor = session / "native-world.gdextension";
        write_new(descriptor, descriptor_bytes);
        const auto descriptor_digest = sha256(descriptor_bytes);
        current(repo, tree);
        const auto self = fs::canonical("/proc/self/exe");
        std::vector<std::string> startup{(repo / "scripts/run-human-startup.sh").string(),
            repo.string(), admission.string(), self.string()};
        startup.insert(startup.end(), {"--repo", repo.string(), "--tree", tree,
            "--output", (session / "native").string(), "--godot", engine.string(),
            "--engine-sha256", options.at("--engine-sha256"),
            "--admission", admission.parent_path().string(),
            "--native-descriptor", descriptor.string(),
            "--native-descriptor-sha256", descriptor_digest,
            "--native-descriptor-relative", "native-world.gdextension",
            "--native-library", library.string(),
            "--native-library-sha256", options.at("--library-sha256"),
            "--native-library-relative", "factory-native-world.so"});
        std::cout << "Preparing agent window project: " << session << std::endl;
        const auto result = run_process(startup, 360s, 8 * 1024 * 1024, &cancelled, true);
        std::cout << result.output << std::flush;
        require(result.exit_code == 0, "Native startup failed; inspect the retained session logs.");
        current(repo, tree);
        sealed(engine, options.at("--engine-sha256"), 512 * 1024 * 1024, true);
        sealed(library, options.at("--library-sha256"), 64 * 1024 * 1024, false);
        if (script) {
            // The gameplay snapshot intentionally omits fixture entrypoints.
            // Copy only the selected checked-main script into this owned runtime.
            const auto source = project / relative;
            const auto tracked = git(repo, {"show", tree + ":experiments/engine-environment/godot/" +
                relative.generic_string()}, 1024 * 1024);
            require(sha256(regular(source, 1024 * 1024)) == sha256(tracked),
                "The selected fixture differs from checked main.");
            const auto runtime_target = session / "native/runtime/project" / relative;
            require(fs::is_directory(fs::symlink_status(runtime_target.parent_path())) &&
                    fs::canonical(runtime_target.parent_path()) == runtime_target.parent_path() &&
                    !fs::exists(fs::symlink_status(runtime_target)),
                "The owned runtime cannot receive the selected fixture.");
            write_new(runtime_target, tracked);
            require(sha256(regular(runtime_target, 1024 * 1024)) == sha256(tracked),
                "The runtime fixture differs from checked main.");
        }
        std::vector<std::string> command{admission.string(), "--root", repo.string(), "heavy", "--",
            engine.string(), "--path", (session / "native/runtime/project").string()};
        if (script) command.push_back("--script");
        command.insert(command.end(), {target, "--", "--test-purpose=" + options.at("--test-purpose")});
        command.insert(command.end(), user_arguments.begin(), user_arguments.end());
        std::cout << "Opening agent window: " << options.at("--test-purpose") << std::endl;
        const int code = graphical(command);
        require(code == 0, "The graphical engine exited " + std::to_string(code) + ".");
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Agent window refused: " << error.what() << '\n';
        if (!session.empty()) std::cerr << "Retained session: " << session << '\n';
        return cancelled ? 128 + cancelled : 1;
    }
}
} // namespace factory_launch
