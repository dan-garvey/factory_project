#include "runner.hpp"

#include <array>
#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <limits>
#include <memory>
#include <poll.h>
#include <sched.h>
#include <spawn.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

namespace factory::build_support {
namespace {
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
struct Fd {
    int value;
    explicit Fd(int fd) : value(fd) {}
    ~Fd() { if (value >= 0) ::close(value); }
    Fd(const Fd&) = delete;
    Fd& operator=(const Fd&) = delete;
};
using Directory = std::unique_ptr<DIR, int(*)(DIR*)>;
void require(bool condition, Reason reason) { if (!condition) throw Error(reason); }
bool disappeared(int error) { return error == ENOENT || error == ENOTDIR || error == ELOOP; }
bool same(const struct stat& a, const struct stat& b) {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}
void add(std::uint64_t& total, std::uint64_t bytes, std::uint64_t limit) {
    require(bytes <= limit - total, Reason::artifacts);
    total += bytes;
}
void measure(DIR* directory, std::uint64_t& total, std::uint64_t limit,
             std::size_t& entries, unsigned depth) {
    require(depth <= 128, Reason::scan);
    while (true) {
        errno = 0;
        const auto* entry = ::readdir(directory);
        if (!entry) { require(errno == 0 || (depth > 0 && disappeared(errno)), Reason::scan); break; }
        if (std::strcmp(entry->d_name, ".") == 0 || std::strcmp(entry->d_name, "..") == 0) continue;
        require(++entries <= 1000000, Reason::scan);
        struct stat status{};
        if (::fstatat(::dirfd(directory), entry->d_name, &status, AT_SYMLINK_NOFOLLOW) < 0) {
            if (disappeared(errno)) continue;
            throw Error(Reason::scan);
        }
        if (S_ISREG(status.st_mode) || S_ISLNK(status.st_mode)) {
            require(status.st_size >= 0, Reason::scan);
            add(total, static_cast<std::uint64_t>(status.st_size), limit);
        } else if (S_ISDIR(status.st_mode)) {
            const int fd = ::openat(::dirfd(directory), entry->d_name,
                                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (fd < 0) {
                if (disappeared(errno)) continue;
                throw Error(Reason::scan);
            }
            DIR* opened = ::fdopendir(fd);
            if (!opened) { ::close(fd); throw Error(Reason::scan); }
            Directory child(opened, ::closedir);
            measure(child.get(), total, limit, entries, depth + 1);
        } else {
            // No named pipe, socket or device can hide in the owned build tree.
            throw Error(Reason::scan);
        }
    }
}
std::vector<int> descriptors() {
    Directory directory(::opendir("/proc/self/fd"), ::closedir);
    require(static_cast<bool>(directory), Reason::options);
    std::vector<int> result;
    while (true) {
        errno = 0;
        const auto* entry = ::readdir(directory.get());
        if (!entry) { require(errno == 0, Reason::options); break; }
        char* end = nullptr;
        const long value = ::strtol(entry->d_name, &end, 10);
        if (end == entry->d_name || *end || value < 3 || value > std::numeric_limits<int>::max()) continue;
        if (value != ::dirfd(directory.get())) result.push_back(static_cast<int>(value));
    }
    return result;
}
std::vector<int> permits(const fs::path& directory, const std::vector<int>& open) {
    require(directory.is_absolute() && fs::canonical(directory) == directory, Reason::options);
    std::vector<int> result;
    for (const auto* name : {"heavy.lock", "activity.lock"}) {
        struct stat expected{};
        require(::lstat((directory / name).c_str(), &expected) == 0 && S_ISREG(expected.st_mode), Reason::options);
        int found = -1;
        for (const auto fd : open) {
            struct stat actual{};
            if (::fstat(fd, &actual) == 0 && same(actual, expected)) {
                require(found < 0, Reason::options);
                found = fd;
            }
        }
        require(found >= 0, Reason::options);
        const int flags = ::fcntl(found, F_GETFD);
        require(flags >= 0 && (flags & FD_CLOEXEC) == 0, Reason::options);
        result.push_back(found);
    }
    require(result[0] != result[1], Reason::options);
    return result;
}
struct Child {
    pid_t pid;
    ~Child() {
        if (pid <= 0) return;
        ::kill(-pid, SIGTERM);
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        ::kill(-pid, SIGKILL);
        int status{};
        while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
    int finish() {
        // The leader is observed with WNOWAIT. Its identity is not reusable.
        ::kill(-pid, SIGKILL);
        int status{};
        pid_t waited;
        do { waited = ::waitpid(pid, &status, 0); } while (waited < 0 && errno == EINTR);
        require(waited == pid, Reason::wait);
        pid = -1;
        return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    }
};
void write_all(int fd, const char* bytes, std::size_t size) {
    std::size_t offset = 0;
    while (offset < size) {
        const auto count = ::write(fd, bytes + offset, size - offset);
        if (count < 0 && errno == EINTR) continue;
        require(count > 0, Reason::io);
        offset += static_cast<std::size_t>(count);
    }
}
bool below(const fs::path& root, const fs::path& path) {
    const auto relative = path.lexically_relative(root);
    return !relative.empty() && *relative.begin() != ".." && !relative.is_absolute();
}

void map_identity(const char* path, const std::string& value) {
    Fd output(::open(path, O_WRONLY | O_CLOEXEC | O_NOFOLLOW));
    require(output.value >= 0, Reason::accounting_namespace);
    std::size_t offset = 0;
    while (offset < value.size()) {
        const auto count = ::write(output.value, value.data() + offset, value.size() - offset);
        if (count < 0 && errno == EINTR) continue;
        require(count > 0, Reason::accounting_namespace);
        offset += static_cast<std::size_t>(count);
    }
}

void parent_guard(pid_t expected) {
    require(::prctl(PR_SET_PDEATHSIG, SIGKILL) == 0 && ::getppid() == expected,
            Reason::accounting_namespace);
}

std::uint64_t namespace_snapshot(const fs::path& root, std::uint64_t limit,
                                Clock::time_point deadline,
                                const volatile std::sig_atomic_t* cancellation) {
    require(::getuid() == ::geteuid() && ::getgid() == ::getegid(), Reason::options);
    const auto uid = ::getuid(), gid = ::getgid();
    Fd directory(::open(root.c_str(), O_PATH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    struct stat identity{};
    require(directory.value >= 0 && ::fstat(directory.value, &identity) == 0 &&
            identity.st_uid == uid && (identity.st_mode & 0077) == 0, Reason::scan);
    int pipe[2];
    require(::pipe2(pipe, O_CLOEXEC) == 0, Reason::io);
    Fd input(pipe[0]), output(pipe[1]);
    // Keep the result/root descriptors distinct from closed standard streams.
    for (auto* fd : {&directory, &input, &output}) {
        if (fd->value > 2) continue;
        const int moved = ::fcntl(fd->value, F_DUPFD_CLOEXEC, 3);
        require(moved >= 0, Reason::io);
        ::close(fd->value); fd->value = moved;
    }
    require(::fcntl(input.value, F_SETFL, O_NONBLOCK) == 0, Reason::io);
    struct sigaction child_signal{};
    require(::sigaction(SIGCHLD, nullptr, &child_signal) == 0 && child_signal.sa_handler != SIG_IGN &&
            (child_signal.sa_flags & SA_NOCLDWAIT) == 0, Reason::options);
    require(!cancellation || *cancellation == 0, Reason::cancelled);
    const auto expected_parent = ::getpid();
    const pid_t pid = ::fork();
    require(pid >= 0, Reason::spawn);
    if (pid == 0) {
        std::array<std::uint64_t, 2> result{};
        try {
            parent_guard(expected_parent);
            require(::setpgid(0, 0) == 0, Reason::accounting_namespace);
            for (const auto signal : {SIGINT, SIGTERM, SIGPIPE, SIGALRM})
                require(::signal(signal, SIG_DFL) != SIG_ERR, Reason::accounting_namespace);
            for (const auto fd : descriptors())
                if (fd != directory.value && fd != output.value) ::close(fd);
            for (int fd = 0; fd <= 2; ++fd) ::close(fd);
            require(::unshare(CLONE_NEWUSER) == 0, Reason::accounting_namespace);
            parent_guard(expected_parent);
            map_identity("/proc/self/setgroups", "deny\n");
            map_identity("/proc/self/uid_map", "0 " + std::to_string(uid) + " 1\n");
            map_identity("/proc/self/gid_map", "0 " + std::to_string(gid) + " 1\n");
            parent_guard(expected_parent);
            const int fd = ::openat(directory.value, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            require(fd >= 0, Reason::scan);
            DIR* opened = ::fdopendir(fd);
            if (!opened) { ::close(fd); throw Error(Reason::scan); }
            Directory scan(opened, ::closedir);
            std::size_t entries = 0;
            measure(scan.get(), result[0], limit, entries, 0);
        } catch (const Error& error) {
            result = {0, static_cast<std::uint64_t>(error.reason()) + 1};
        } catch (...) {
            result = {0, static_cast<std::uint64_t>(Reason::scan) + 1};
        }
        // Only a fixed-size count/refusal packet crosses the boundary. No raw
        // path, file content, environment, diagnostic or inherited permit does.
        try { write_all(output.value, reinterpret_cast<const char*>(result.data()), sizeof(result)); }
        catch (...) { ::_exit(2); }
        ::_exit(result[1] == 0 ? 0 : 1);
    }
    Child worker{pid};
    if (::setpgid(pid, pid) != 0 && errno != ESRCH) {
        ::kill(pid, SIGKILL); // Still our unreaped direct child.
        throw Error(Reason::spawn);
    }
    ::close(output.value); output.value = -1;
    std::array<std::uint64_t, 2> result{};
    std::size_t received = 0;
    bool exited = false;
    while (received < sizeof(result) || !exited) {
        require(!cancellation || *cancellation == 0, Reason::cancelled);
        require(Clock::now() < deadline, Reason::timeout);
        if (received < sizeof(result)) {
            auto* data = reinterpret_cast<char*>(result.data());
            const auto count = ::read(input.value, data + received, sizeof(result) - received);
            if (count > 0) received += static_cast<std::size_t>(count);
            else if (count == 0) throw Error(Reason::scan);
            else require(errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK, Reason::io);
        }
        siginfo_t info{};
        const int state = ::waitid(P_PID, static_cast<id_t>(pid), &info, WEXITED | WNOHANG | WNOWAIT);
        require(state == 0 || errno == EINTR, Reason::wait);
        exited = state == 0 && info.si_pid == pid;
        if (received < sizeof(result)) {
            pollfd ready{input.value, POLLIN, 0}; (void)::poll(&ready, 1, 5);
        } else if (!exited) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    const int code = worker.finish();
    require(code == (result[1] == 0 ? 0 : 1) &&
            result[1] <= static_cast<std::uint64_t>(Reason::accounting_namespace) + 1, Reason::scan);
    struct stat current{};
    require(::lstat(root.c_str(), &current) == 0 && same(identity, current), Reason::scan);
    if (result[1]) throw Error(static_cast<Reason>(result[1] - 1));
    require(result[0] <= limit, Reason::artifacts);
    return result[0];
}
}  // namespace

const char* reason_name(Reason reason) noexcept {
    switch (reason) {
        case Reason::options: return "options";
        case Reason::scan: return "artifact_scan";
        case Reason::artifacts: return "artifact_limit";
        case Reason::log: return "log_limit";
        case Reason::timeout: return "timeout";
        case Reason::cancelled: return "cancelled";
        case Reason::spawn: return "spawn";
        case Reason::io: return "io";
        case Reason::wait: return "wait";
        case Reason::accounting_namespace: return "accounting_namespace";
    }
    return "unknown";
}
Error::Error(Reason reason) : std::runtime_error(reason_name(reason)), reason_(reason) {}

std::uint64_t owned_bytes(const fs::path& root, std::uint64_t limit) {
    require(limit > 0 && limit <= maximum_artifacts, Reason::options);
    const int fd = ::open(root.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    require(fd >= 0, Reason::scan);
    DIR* opened = ::fdopendir(fd);
    if (!opened) { ::close(fd); throw Error(Reason::scan); }
    Directory directory(opened, ::closedir);
    std::uint64_t total = 0;
    std::size_t entries = 0;
    measure(directory.get(), total, limit, entries, 0);
    return total;
}

std::uint64_t owned_bytes_as_owner(const fs::path& root, std::uint64_t limit,
                                  std::chrono::milliseconds timeout,
                                  const volatile std::sig_atomic_t* cancellation) {
    require(root.is_absolute() && fs::canonical(root) == root &&
            limit > 0 && limit <= maximum_artifacts && timeout.count() > 0 &&
            timeout <= std::chrono::seconds(300), Reason::options);
    return namespace_snapshot(root, limit, Clock::now() + timeout, cancellation);
}

int run(const Options& options, const std::vector<std::string>& arguments) {
    const auto started = Clock::now();
    // This synchronous utility is not a multi-threaded embedding API.
    struct Mask { mode_t prior{::umask(0077)}; ~Mask() { ::umask(prior); } } mask_guard;
    const auto& root = options.artifacts;
    require(root.is_absolute() && fs::canonical(root) == root, Reason::options);
    for (const auto& component : root) require(component != ".git" && component != ".beads", Reason::options);
    require(options.log.is_absolute() && below(root, options.log) &&
            fs::canonical(options.log.parent_path()) == options.log.parent_path(), Reason::options);
    require(options.timeout.count() > 0 && options.timeout <= std::chrono::seconds(300) &&
            options.artifact_limit > 0 && options.artifact_limit <= maximum_artifacts &&
            options.log_limit > 0 && options.log_limit <= maximum_log &&
            options.jobs > 0 && options.jobs <= 8, Reason::options);
    require(!arguments.empty() && arguments.size() <= 256 && fs::path(arguments[0]).is_absolute(), Reason::options);
    std::size_t argument_bytes = 0;
    for (const auto& argument : arguments) {
        require(argument.find('\0') == std::string::npos && argument.size() <= 65536, Reason::options);
        argument_bytes += argument.size();
    }
    require(argument_bytes <= 131072, Reason::options);
    const auto open = descriptors();
    const auto keep = permits(options.admission_directory, open);
    struct stat identity{};
    require(::lstat(root.c_str(), &identity) == 0 && S_ISDIR(identity.st_mode) &&
            identity.st_uid == ::geteuid() && (identity.st_mode & 0077) == 0, Reason::options);
    const auto inspect = [&] {
        struct stat current{};
        require(::lstat(root.c_str(), &current) == 0 && same(identity, current), Reason::scan);
        if (options.owned_user_accounting) {
            const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
                started + options.timeout - Clock::now());
            require(remaining.count() > 0, Reason::timeout);
            (void)owned_bytes_as_owner(root, options.artifact_limit,
                std::min(remaining, std::chrono::milliseconds(5000)), options.cancellation);
        } else (void)owned_bytes(root, options.artifact_limit);
    };
    inspect();
    for (const auto* name : {"home", "tmp", "config", "cache"}) {
        fs::create_directories(root / name);
        require(fs::canonical(root / name) == root / name, Reason::options);
    }
    struct sigaction child_signal{};
    require(::sigaction(SIGCHLD, nullptr, &child_signal) == 0 && child_signal.sa_handler != SIG_IGN &&
            (child_signal.sa_flags & SA_NOCLDWAIT) == 0, Reason::options);
    // No ambient environment is read or forwarded, including account values.
    std::vector<std::string> environment{
        "PATH=/usr/bin:/bin", "LANG=C.UTF-8", "HOME=" + (root / "home").string(),
        "TMPDIR=" + (root / "tmp").string(), "XDG_CONFIG_HOME=" + (root / "config").string(),
        "XDG_CACHE_HOME=" + (root / "cache").string(),
        "CMAKE_BUILD_PARALLEL_LEVEL=" + std::to_string(options.jobs),
        "CTEST_PARALLEL_LEVEL=" + std::to_string(options.jobs),
        "CARGO_BUILD_JOBS=" + std::to_string(options.jobs)};
    std::vector<char*> envp;
    for (auto& entry : environment) envp.push_back(entry.data());
    envp.push_back(nullptr);
    std::vector<char*> argv;
    for (const auto& entry : arguments) argv.push_back(const_cast<char*>(entry.c_str()));
    argv.push_back(nullptr);
    Fd log(::open(options.log.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
    require(log.value >= 0, Reason::io);
    int pipe[2];
    require(::pipe2(pipe, O_CLOEXEC) == 0, Reason::io);
    Fd read_end(pipe[0]), write_end(pipe[1]);
    for (auto* descriptor : {&read_end, &write_end}) {
        if (descriptor->value > 2) continue;
        const int moved = ::fcntl(descriptor->value, F_DUPFD_CLOEXEC, 3);
        require(moved >= 0, Reason::io);
        ::close(descriptor->value);
        descriptor->value = moved;
    }
    require(::fcntl(read_end.value, F_SETFL, O_NONBLOCK) == 0, Reason::io);
    posix_spawn_file_actions_t actions;
    require(::posix_spawn_file_actions_init(&actions) == 0, Reason::spawn);
    struct Actions { posix_spawn_file_actions_t* p; ~Actions() { ::posix_spawn_file_actions_destroy(p); } } actions_guard{&actions};
    posix_spawnattr_t attributes;
    require(::posix_spawnattr_init(&attributes) == 0, Reason::spawn);
    struct Attributes { posix_spawnattr_t* p; ~Attributes() { ::posix_spawnattr_destroy(p); } } attribute_guard{&attributes};
    require(::posix_spawn_file_actions_adddup2(&actions, write_end.value, STDOUT_FILENO) == 0 &&
            ::posix_spawn_file_actions_adddup2(&actions, write_end.value, STDERR_FILENO) == 0 &&
            ::posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
            Reason::spawn);
    for (const auto fd : descriptors()) {
        if (fd == keep[0] || fd == keep[1]) continue;
        require(::posix_spawn_file_actions_addclose(&actions, fd) == 0, Reason::spawn);
    }
    sigset_t mask, defaults;
    ::sigemptyset(&mask);
    ::sigemptyset(&defaults);
    for (const auto signal : {SIGINT, SIGTERM, SIGPIPE}) ::sigaddset(&defaults, signal);
    require(::posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF) == 0 &&
            ::posix_spawnattr_setpgroup(&attributes, 0) == 0 &&
            ::posix_spawnattr_setsigmask(&attributes, &mask) == 0 &&
            ::posix_spawnattr_setsigdefault(&attributes, &defaults) == 0, Reason::spawn);
    require(!options.cancellation || *options.cancellation == 0, Reason::cancelled);
    pid_t pid{};
    require(::posix_spawn(&pid, arguments[0].c_str(), &actions, &attributes, argv.data(), envp.data()) == 0, Reason::spawn);
    Child child{pid};
    ::close(write_end.value); write_end.value = -1;
    const auto deadline = options.owned_user_accounting ? started + options.timeout
                                                     : Clock::now() + options.timeout;
    auto next_scan = Clock::now();
    std::uint64_t retained = 0;
    bool eof = false, exited = false;
    while (!eof || !exited) {
        require(!options.cancellation || *options.cancellation == 0, Reason::cancelled);
        require(Clock::now() < deadline, Reason::timeout);
        if (Clock::now() >= next_scan) { inspect(); next_scan = Clock::now() + std::chrono::milliseconds(100); }
        if (!eof) {
            std::array<char, 65536> buffer{};
            const auto count = ::read(read_end.value, buffer.data(), buffer.size());
            if (count > 0) {
                const auto bytes = static_cast<std::uint64_t>(count);
                const auto allowed = std::min(bytes, options.log_limit - retained);
                write_all(log.value, buffer.data(), static_cast<std::size_t>(allowed));
                retained += allowed;
                require(bytes == allowed, Reason::log);
            } else if (count == 0) eof = true;
            else require(errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK, Reason::io);
        }
        if (!exited) {
            siginfo_t info{};
            const int state = ::waitid(P_PID, static_cast<id_t>(pid), &info, WEXITED | WNOHANG | WNOWAIT);
            require(state == 0 || errno == EINTR, Reason::wait);
            exited = state == 0 && info.si_pid == pid;
        }
        if (eof && exited) break;
        if (eof) std::this_thread::sleep_for(std::chrono::milliseconds(5));
        else { pollfd ready{read_end.value, POLLIN, 0}; (void)::poll(&ready, 1, 5); }
    }
    const int code = child.finish();
    inspect();
    require(::fsync(log.value) == 0, Reason::io);
    return code;
}
}  // namespace factory::build_support
