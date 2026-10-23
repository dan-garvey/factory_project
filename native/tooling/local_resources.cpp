#include "local_resources.hpp"

#include <algorithm>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <limits>
#include <sstream>
#include <system_error>
#include <thread>
#include <utility>

#include <sys/file.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;

namespace factory::resources {
namespace {

[[noreturn]] void system_failure(const std::string& action) {
    throw std::system_error(errno, std::generic_category(), action);
}

std::vector<char*> pointers(std::vector<std::string>& values) {
    std::vector<char*> result;
    result.reserve(values.size() + 1);
    for (auto& value : values) result.push_back(value.data());
    result.push_back(nullptr);
    return result;
}

int wait_for(pid_t pid) {
    int status = 0;
    while (::waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) system_failure("waitpid");
    }
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    throw std::runtime_error("Child has no final exit status");
}

std::uint64_t multiply(std::uint64_t amount, std::uint64_t unit) {
    if (amount > std::numeric_limits<std::uint64_t>::max() / unit)
        throw std::invalid_argument("Capacity value exceeds the supported integer range");
    return amount * unit;
}

// Descriptors for admission deliberately do not have FD_CLOEXEC: the immediate
// supervisor must keep the same open-file-description locks if this wrapper dies.
FileDescriptor locked_file(const std::filesystem::path& path, int operation,
                           bool wait, Mode mode) {
    FileDescriptor fd(::open(path.c_str(), O_RDWR | O_CREAT, 0600));
    if (fd.get() < 0) system_failure("open admission lock " + path.string());
    if (fd.get() <= STDERR_FILENO) {
        // Preserve a caller's closed standard streams instead of handing the
        // workload a lock file as stdin, stdout or stderr.
        const int elevated = ::fcntl(fd.get(), F_DUPFD, STDERR_FILENO + 1);
        if (elevated < 0) system_failure("move admission descriptor above standard streams");
        fd = FileDescriptor(elevated);
    }
    while (::flock(fd.get(), operation | (wait ? 0 : LOCK_NB)) < 0) {
        if (errno == EINTR) continue;
        if (errno == EWOULDBLOCK || errno == EAGAIN)
            throw AdmissionError(mode_name(mode) + " is busy; another wrapped command holds " + path.filename().string());
        system_failure("flock " + path.string());
    }
    return fd;
}

// Linux closes the gaps around an explicitly sorted allowlist. No unrelated
// inherited descriptor reaches Git discovery or the admitted command. This is
// done in the child, so the caller's descriptor table remains untouched.
int close_unrelated(const std::vector<int>& preserved) noexcept {
    unsigned int first = STDERR_FILENO + 1;
    for (const int fd : preserved) {
        if (fd <= STDERR_FILENO) continue;
        const auto keep = static_cast<unsigned int>(fd);
        if (first < keep && ::close_range(first, keep - 1, 0) < 0) return errno;
        first = keep + 1;
    }
    if (::close_range(first, std::numeric_limits<unsigned int>::max(), 0) < 0) return errno;
    return 0;
}

int execute(const std::vector<std::string>& command, std::uint64_t jobs,
            const std::vector<int>& admission_descriptors, bool inherit_permits) {
    // An exec failure must be distinguishable from a real command exiting 127.
    int pipe_fds[2];
    if (::pipe2(pipe_fds, O_CLOEXEC) < 0) system_failure("exec error pipe");
    FileDescriptor reader(pipe_fds[0]), writer(pipe_fds[1]);
    auto arguments = command;
    auto argv = pointers(arguments);
    const auto jobs_text = std::to_string(jobs);
    auto preserved = admission_descriptors;
    preserved.push_back(writer.get());
    std::sort(preserved.begin(),preserved.end());
    preserved.erase(std::unique(preserved.begin(),preserved.end()),preserved.end());
    const pid_t child = ::fork();
    if (child < 0) system_failure("fork command");
    if (child == 0) {
        ::close(reader.get());
        if (!inherit_permits) {
            // The immediate child owns the inherited permits even if the
            // factory-local wrapper is killed. Its command, and any server
            // that command starts, receive no admission descriptors.
            const pid_t command_child = ::fork();
            if (command_child < 0) {
                const int failure = errno;
                const auto ignored = ::write(writer.get(), &failure, sizeof(failure));
                (void)ignored;
                ::_exit(127);
            }
            if (command_child > 0) {
                writer = FileDescriptor();
                int status = 0;
                pid_t waited;
                do { waited = ::waitpid(command_child, &status, 0); } while (waited < 0 && errno == EINTR);
                if (waited != command_child) ::_exit(125);
                if (WIFEXITED(status)) ::_exit(WEXITSTATUS(status));
                if (WIFSIGNALED(status)) ::_exit(128 + WTERMSIG(status));
                ::_exit(125);
            }
        }
        int failure = close_unrelated(inherit_permits ? preserved : std::vector<int>{writer.get()});
        if (!failure) {
            for (const char* variable : {"CMAKE_BUILD_PARALLEL_LEVEL", "CARGO_BUILD_JOBS", "CTEST_PARALLEL_LEVEL"}) {
                if (::setenv(variable, jobs_text.c_str(), 1) < 0) {
                    failure = errno;
                    break;
                }
            }
        }
        if (!failure) {
            ::execvp(argv[0], argv.data());
            failure = errno;
        }
        const auto ignored = ::write(writer.get(), &failure, sizeof(failure));
        (void)ignored;
        ::_exit(127);
    }
    writer = FileDescriptor();
    int failure = 0;
    ssize_t count;
    do { count = ::read(reader.get(), &failure, sizeof(failure)); } while (count < 0 && errno == EINTR);
    const int read_failure = errno;
    const int exit = wait_for(child);
    if (count < 0) throw std::system_error(read_failure, std::generic_category(), "read exec error");
    if (count != 0) {
        if (count != static_cast<ssize_t>(sizeof(failure))) throw std::runtime_error("Incomplete command exec error");
        throw std::system_error(failure, std::generic_category(), "execute " + command.front());
    }
    return exit;
}

} // namespace

FileDescriptor::~FileDescriptor() { if (fd_ >= 0) ::close(fd_); }
FileDescriptor::FileDescriptor(FileDescriptor&& other) noexcept : fd_(other.release()) {}
FileDescriptor& FileDescriptor::operator=(FileDescriptor&& other) noexcept {
    if (this != &other) {
        if (fd_ >= 0) ::close(fd_);
        fd_ = other.release();
    }
    return *this;
}
int FileDescriptor::release() noexcept { return std::exchange(fd_, -1); }

std::string mode_name(Mode mode) {
    switch (mode) {
        case Mode::check: return "check";
        case Mode::heavy: return "heavy";
        case Mode::benchmark: return "benchmark";
    }
    throw std::invalid_argument("Unknown admission mode");
}

std::uint64_t unsigned_number(const std::string& value) {
    std::uint64_t number = 0;
    const auto parsed = std::from_chars(value.data(), value.data() + value.size(), number);
    if (value.empty() || parsed.ec != std::errc() || parsed.ptr != value.data() + value.size())
        throw std::invalid_argument("Expected a nonnegative decimal integer: " + value);
    return number;
}

Admission::Admission(const std::filesystem::path& common_dir, Mode mode, bool wait) {
    const auto directory = common_dir / "factory-local-resources";
    if (::mkdir(directory.c_str(), 0700) < 0 && errno != EEXIST)
        system_failure("create admission directory");
    // Legacy wrappers take an exclusive flock on this same inode. Sharing that
    // gate excludes them without replacing a live lock or disturbing a child.
    // Slot locks belong to the open file description, so the immediate child
    // retains its slot together with the heavy descriptor after wrapper death.
    // A waiter has no activity lock and therefore cannot prevent a benchmark.
    if (mode == Mode::heavy) {
        auto heavy = locked_file(directory / "heavy.lock", LOCK_SH, wait, mode);
        bool acquired = false;
        do {
            for (unsigned slot = 0; slot < heavy_slots; ++slot) {
                struct flock range {};
                range.l_type = F_WRLCK;
                range.l_whence = SEEK_SET;
                range.l_start = static_cast<off_t>(slot);
                range.l_len = 1;
                if (::fcntl(heavy.get(), F_OFD_SETLK, &range) == 0) {
                    acquired = true;
                    break;
                }
                if (errno != EACCES && errno != EAGAIN && errno != EINTR)
                    system_failure("lock heavy slot");
            }
            if (!acquired) {
                if (!wait) throw AdmissionError("heavy is busy; all four slots are occupied");
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        } while (!acquired);
        handles_.push_back(std::move(heavy));
    }
    handles_.push_back(locked_file(directory / "activity.lock",
        mode == Mode::benchmark ? LOCK_EX : LOCK_SH, wait, mode));
}

std::vector<int> Admission::inherited_descriptors() const {
    std::vector<int> result;
    for (const auto& handle : handles_) result.push_back(handle.get());
    return result;
}

std::uint64_t memory_available(const std::filesystem::path& path) {
    std::ifstream stream(path);
    if (!stream) throw std::runtime_error("Cannot read memory capacity: " + path.string());
    std::string line;
    while (std::getline(stream, line)) {
        if (line.rfind("MemAvailable:", 0) != 0) continue;
        std::istringstream fields(line);
        std::string label, amount, unit, extra;
        if (!(fields >> label >> amount >> unit) || fields >> extra || unit != "kB")
            throw std::runtime_error("Unexpected MemAvailable record; refusing to guess memory capacity");
        return multiply(unsigned_number(amount), 1024);
    }
    throw std::runtime_error("MemAvailable is missing; refusing to guess memory capacity");
}

static std::uint64_t disk_available(const std::filesystem::path& root) {
    struct statvfs observed {};
    if (::statvfs(root.c_str(), &observed) < 0) system_failure("read disk capacity");
    return multiply(observed.f_bavail, observed.f_frsize);
}

void enforce_capacity(Capacity observed, std::uint64_t disk_floor, std::uint64_t memory_floor) {
    if (observed.disk_available < multiply(disk_floor, gib))
        throw AdmissionError("free disk is below the " + std::to_string(disk_floor) + " GiB floor");
    if (observed.memory_available < multiply(memory_floor, gib))
        throw AdmissionError("MemAvailable is below the " + std::to_string(memory_floor) + " GiB reserve");
}

std::filesystem::path common_git_dir(const std::filesystem::path& root) {
    int pipe_fds[2];
    if (::pipe2(pipe_fds, O_CLOEXEC) < 0) system_failure("Git output pipe");
    FileDescriptor reader(pipe_fds[0]), writer(pipe_fds[1]);
    std::vector<std::string> environment;
    for (char** entry = environ; *entry; ++entry) {
        if (std::strncmp(*entry, "GIT_", 4) != 0) environment.emplace_back(*entry);
    }
    auto envp = pointers(environment);
    std::vector<std::string> args = {"git", "-C", root.string(), "rev-parse", "--path-format=absolute", "--git-common-dir"};
    auto argv = pointers(args);
    const std::vector<int> no_extra_descriptors;
    const pid_t child = ::fork();
    if (child < 0) system_failure("fork Git discovery");
    if (child == 0) {
        // A closed standard descriptor can be reused by pipe2. Do not close
        // the new stdout when the read end originally occupied fd 1. If the
        // write end already is fd 1, dup2 is a no-op and does not clear CLOEXEC.
        if (::dup2(writer.get(), STDOUT_FILENO) < 0 ||
            ::fcntl(STDOUT_FILENO, F_SETFD, 0) < 0) ::_exit(127);
        if (reader.get() != STDOUT_FILENO) ::close(reader.get());
        if (close_unrelated(no_extra_descriptors) != 0) ::_exit(127);
        ::execvpe("git", argv.data(), envp.data());
        ::_exit(127);
    }
    writer = FileDescriptor();
    std::string output;
    char buffer[4096];
    bool oversized = false;
    for (;;) {
        const auto count = ::read(reader.get(), buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) {
            const int failure = errno;
            (void)wait_for(child);
            throw std::system_error(failure, std::generic_category(), "read Git discovery");
        }
        if (count == 0) break;
        if (output.size() + static_cast<std::size_t>(count) <= 65536)
            output.append(buffer, static_cast<std::size_t>(count));
        else oversized = true;
    }
    if (wait_for(child) != 0) throw std::runtime_error("Git common-directory discovery failed");
    if (oversized) throw std::runtime_error("Git common-directory output exceeds 64 KiB");
    if (output.empty() || output.back() != '\n') throw std::runtime_error("Invalid Git common-directory output");
    output.pop_back();
    if (output.empty() || output.find('\n') != std::string::npos || output.find('\0') != std::string::npos)
        throw std::runtime_error("Invalid Git common-directory path");
    return std::filesystem::canonical(output);
}

int run(const Options& options) {
    if (options.command.empty()) throw std::invalid_argument("No command supplied");
    const auto common = common_git_dir(options.root);
    std::cerr << "local resources: waiting for " << mode_name(options.mode) << " admission\n" << std::flush;
    Admission permit(common, options.mode, options.wait);
    if (options.mode != Mode::check) {
        const auto disk = disk_available(options.root);
        // Match the existing refusal order: do not guess memory if disk has
        // already failed its floor, and never probe before acquiring admission.
        enforce_capacity({disk, 0}, options.disk_floor_gib, 0);
        enforce_capacity({disk, memory_available()}, options.disk_floor_gib, options.memory_reserve_gib);
    }
    std::cerr << "local resources: admitted " << mode_name(options.mode) << ", jobs=" << options.jobs << '\n' << std::flush;
    return execute(options.command, options.jobs, permit.inherited_descriptors(), options.inherit_permits);
}

} // namespace factory::resources
