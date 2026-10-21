#include "coordinator.hpp"

#include "native/tooling/local_resources.hpp"

#include <array>
#include <cerrno>
#include <chrono>
#include <cctype>
#include <csignal>
#include <cstdlib>
#include <dirent.h>
#include <fcntl.h>
#include <limits>
#include <memory>
#include <poll.h>
#include <spawn.h>
#include <stdexcept>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

extern char** environ;

namespace factory::commit_gate {
namespace {
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
constexpr std::size_t maximum_git_output = 2 * 1024 * 1024;
void require(bool value, const std::string& reason) {
    if (!value) throw std::runtime_error(reason);
}
struct Descriptor {
    int value;
    ~Descriptor() { if (value >= 0) ::close(value); }
};
struct Child {
    pid_t pid;
    ~Child() {
        if (pid <= 0) return;
        ::kill(-pid, SIGKILL);
        while (::waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {}
    }
    int finish() {
        ::kill(-pid, SIGKILL);
        int status{};
        pid_t result;
        do { result = ::waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
        require(result == pid, "Cannot reap the owned Git child.");
        pid = -1;
        require(WIFEXITED(status) || WIFSIGNALED(status), "Git has no terminal exit status.");
        return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    }
};

GitResult read_git(const fs::path& root, const std::vector<std::string>& tail) {
    std::vector<std::string> arguments{"/usr/bin/git", "-C", root.string()};
    arguments.insert(arguments.end(), tail.begin(), tail.end());
    std::vector<char*> argv;
    for (auto& argument : arguments) argv.push_back(argument.data());
    argv.push_back(nullptr);
    int pipe[2];
    require(::pipe2(pipe, O_CLOEXEC) == 0, "Cannot create the Git result pipe.");
    Descriptor input{pipe[0]}, output{pipe[1]};
    for (auto* fd : {&input, &output}) {
        if (fd->value > STDERR_FILENO) continue;
        const int moved = ::fcntl(fd->value, F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
        require(moved >= 0, "Cannot isolate Git result descriptors.");
        ::close(fd->value); fd->value = moved;
    }
    require(::fcntl(input.value, F_SETFL, O_NONBLOCK) == 0, "Cannot bound Git reads.");
    posix_spawn_file_actions_t actions;
    require(::posix_spawn_file_actions_init(&actions) == 0, "Cannot initialize Git actions.");
    struct Actions {
        posix_spawn_file_actions_t* value;
        ~Actions() { ::posix_spawn_file_actions_destroy(value); }
    } actions_guard{&actions};
    require(::posix_spawn_file_actions_adddup2(&actions, output.value, STDOUT_FILENO) == 0 &&
            ::posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
            "Cannot redirect Git streams.");
    using Directory = std::unique_ptr<DIR, int(*)(DIR*)>;
    Directory descriptors(::opendir("/proc/self/fd"), ::closedir);
    require(static_cast<bool>(descriptors), "Cannot enumerate inherited descriptors.");
    while (true) {
        errno = 0;
        const auto* entry = ::readdir(descriptors.get());
        if (!entry) { require(errno == 0, "Cannot read inherited descriptors."); break; }
        char* end{};
        const long fd = ::strtol(entry->d_name, &end, 10);
        if (end == entry->d_name || *end || fd <= STDERR_FILENO ||
            fd > std::numeric_limits<int>::max() || fd == ::dirfd(descriptors.get())) continue;
        require(::posix_spawn_file_actions_addclose(&actions, static_cast<int>(fd)) == 0,
                "Cannot isolate Git descriptors.");
    }
    descriptors.reset();
    posix_spawnattr_t attributes;
    require(::posix_spawnattr_init(&attributes) == 0, "Cannot initialize Git attributes.");
    struct Attributes {
        posix_spawnattr_t* value;
        ~Attributes() { ::posix_spawnattr_destroy(value); }
    } attribute_guard{&attributes};
    sigset_t mask, defaults;
    ::sigemptyset(&mask); ::sigemptyset(&defaults);
    for (const auto signal : {SIGINT, SIGTERM, SIGPIPE}) ::sigaddset(&defaults, signal);
    require(::posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF) == 0 &&
            ::posix_spawnattr_setpgroup(&attributes, 0) == 0 &&
            ::posix_spawnattr_setsigmask(&attributes, &mask) == 0 &&
            ::posix_spawnattr_setsigdefault(&attributes, &defaults) == 0,
            "Cannot configure the owned Git child.");
    pid_t pid{};
    // Keep the hook's Git context, notably a partial commit's temporary index.
    // Only resource discovery and the staged snapshot child sanitize Git env.
    require(::posix_spawn(&pid, arguments.front().c_str(), &actions, &attributes,
                          argv.data(), environ) == 0, "Cannot start Git.");
    Child child{pid};
    ::close(output.value); output.value = -1;
    const auto deadline = Clock::now() + std::chrono::seconds(5);
    std::string result;
    bool eof{}, exited{};
    while (!eof || !exited) {
        require(Clock::now() < deadline, "Git exceeded its metadata-read deadline.");
        if (!eof) {
            std::array<char, 16384> bytes{};
            const auto count = ::read(input.value, bytes.data(), bytes.size());
            if (count > 0) {
                require(static_cast<std::size_t>(count) <= maximum_git_output - result.size(),
                        "Git exceeded its metadata-output allowance.");
                result.append(bytes.data(), static_cast<std::size_t>(count));
            } else if (count == 0) eof = true;
            else require(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR,
                         "Cannot read the Git result.");
        }
        if (!exited) {
            siginfo_t info{};
            const int status = ::waitid(P_PID, static_cast<id_t>(pid), &info, WEXITED | WNOHANG | WNOWAIT);
            require(status == 0 || errno == EINTR, "Cannot observe the Git child.");
            exited = status == 0 && info.si_pid == pid;
        }
        if (eof && exited) break;
        if (eof) std::this_thread::sleep_for(std::chrono::milliseconds(1));
        else { pollfd ready{input.value, POLLIN, 0}; (void)::poll(&ready, 1, 5); }
    }
    return {child.finish(), std::move(result)};
}

std::string stripped(std::string value) {
    const auto whitespace = [](unsigned char c) { return std::isspace(c) != 0; };
    while (!value.empty() && whitespace(static_cast<unsigned char>(value.back()))) value.pop_back();
    std::size_t begin{};
    while (begin < value.size() && whitespace(static_cast<unsigned char>(value[begin]))) ++begin;
    return value.substr(begin);
}
bool object_id(const std::string& value) {
    return (value.size() == 40 || value.size() == 64) &&
           value.find_first_not_of("0123456789abcdef") == std::string::npos;
}
std::string checked(const GitReader& git, const std::vector<std::string>& arguments) {
    const auto result = git(arguments);
    require(result.exit_code == 0, "Git failed while selecting the staged candidate.");
    return result.output;
}
}  // namespace

Plan prepare(const fs::path& root, const GitReader& git, const std::string& interpreter) {
    require(root.is_absolute() && fs::path(interpreter).is_absolute(), "Use absolute checkout and interpreter paths.");
    const auto tree = stripped(checked(git, {"write-tree"}));
    require(object_id(tree), "Git did not return a complete staged tree identifier.");
    const auto head = git({"rev-parse", "--verify", "--quiet", "HEAD"});
    std::string names;
    if (head.exit_code == 0) {
        const auto revision = stripped(head.output);
        require(object_id(revision), "Git did not return a complete HEAD identifier.");
        names = checked(git, {"diff-tree", "--no-commit-id", "--name-only", "--no-renames", "-r", "-z", revision, tree});
    } else {
        require(head.exit_code == 1, "Cannot determine whether HEAD is unborn.");
        names = checked(git, {"ls-tree", "-rz", "--name-only", tree});
    }
    bool game{};
    for (std::size_t offset = 0; offset < names.size();) {
        const auto end = names.find('\0', offset);
        require(end != std::string::npos, "Git returned a truncated staged path list.");
        const auto name = names.substr(offset, end - offset);
        if (!name.empty() && fs::path(name).extension() == ".gd") {
            require(name.starts_with("experiments/engine-environment/godot/"),
                    "Staged GDScript outside the supported prototype project needs an explicit parser contract.");
            game = true;
        }
        offset = end + 1;
    }
    Plan plan{tree, game, {interpreter, "-B", (root / "scripts/check.py").string(), "--staged", "--expected-tree", tree}};
    if (game) {
        const auto local = [&](const std::string& key) {
            const auto result = git({"config", "--local", "--get", key});
            const auto value = stripped(result.output);
            require(result.exit_code == 0 && !value.empty(),
                    "Staged GDScript needs repository-local " + key + "; see CONTRIBUTING.md.");
            return value;
        };
        const auto binary = local("factory.godotExecutable");
        const auto digest = local("factory.godotSHA256");
        const auto artifacts = local("factory.godotArtifacts");
        require(digest.size() == 64 && digest.find_first_not_of("0123456789abcdef") == std::string::npos,
                "factory.godotSHA256 must pin the verified executable with 64 lowercase hex digits.");
        plan.command.insert(plan.command.end(), {"--parse-gdscript", "--godot", binary,
            "--godot-sha256", digest, "--prototype-artifacts", artifacts});
    }
    return plan;
}

Plan prepare(const fs::path& root, const std::string& interpreter) {
    return prepare(root, [&](const auto& arguments) { return read_git(root, arguments); }, interpreter);
}

int run(const fs::path& root, const std::string& interpreter) {
    require(root.is_absolute() && fs::canonical(root) == root && fs::is_directory(root),
            "Use the canonical absolute checkout root.");
    require(fs::is_regular_file(root / "scripts/check.py"), "The checkout is missing scripts/check.py.");
    const auto plan = prepare(root, interpreter);
    resources::Options options;
    options.root = root;
    options.mode = plan.compile_gdscript ? resources::Mode::heavy : resources::Mode::check;
    options.command = plan.command;
    return resources::run(options);
}
}  // namespace factory::commit_gate
