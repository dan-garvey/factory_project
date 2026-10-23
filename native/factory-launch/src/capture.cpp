#include "factory/capture.hpp"

#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <memory>
#include <poll.h>
#include <spawn.h>
#include <sstream>
#include <stdexcept>
#include <sys/stat.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

extern char** environ;

namespace factory_launch {
namespace {
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
constexpr std::size_t maximum_files = 512;
constexpr std::size_t maximum_scripts = 128;
constexpr const char* project_prefix = "experiments/engine-environment/godot/";
constexpr const char* git_executable = "/usr/bin/git";

struct Descriptor {
    int fd = -1;
    explicit Descriptor(int value = -1) : fd(value) {}
    ~Descriptor() { if (fd >= 0) ::close(fd); }
    Descriptor(const Descriptor&) = delete;
    Descriptor& operator=(const Descriptor&) = delete;
    void close() { if (fd >= 0) { ::close(fd); fd = -1; } }
};

struct Child {
    pid_t pid;
    explicit Child(pid_t value) : pid(value) {}
    ~Child() {
        if (pid <= 0) return;
        // Keep ownership of the leader until final reap, preventing PID reuse.
        ::kill(-pid, SIGTERM);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        ::kill(-pid, SIGKILL);
        int status = 0;
        while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
    int reap() {
        // The exited leader is still ours here. Stop any utility descendants
        // before releasing that identity; a completed parent cannot orphan work.
        ::kill(-pid, SIGKILL);
        int status = 0;
        pid_t result;
        do { result = ::waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
        if (result != pid) throw std::runtime_error("Cannot reap the owned utility child.");
        pid = -1;
        return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    }
};

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

bool object_id(const std::string& value) {
    return (value.size() == 40 || value.size() == 64)
        && std::all_of(value.begin(), value.end(), [](unsigned char c) {
            return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
        });
}

std::string trim_newline(std::string value) {
    if (!value.empty() && value.back() == '\n') value.pop_back();
    return value;
}

bool contains(const fs::path& parent, const fs::path& child) {
    const auto relative = child.lexically_relative(parent);
    return !relative.empty() && *relative.begin() != "..";
}

void safe_path(const fs::path& path) {
    require(path.is_absolute() && path.lexically_normal() == path,
            "Use an absolute normalized path.");
    for (unsigned char character : path.string())
        require(character >= 0x20 && character < 0x7f,
                "This first capture adapter requires printable ASCII paths.");
    for (const auto& component : path) {
        const auto value = component.string();
        require(value != ".git" && value != ".beads" && value != "..",
                "Git administration and tracker paths are excluded.");
    }
}

bool non_repository_discovery(const ProcessResult& result, const fs::path& destination_parent) {
    if (result.exit_code != 128) return false;
    if (result.output == "fatal: not a git repository (or any of the parent directories): .git\n")
        return true;

    // Git stops at a filesystem boundary unless cross-filesystem discovery is
    // enabled. Its diagnostic names the directory on the other side of that
    // boundary, so verify it against the actual canonical destination path.
    const std::string prefix = "fatal: not a git repository (or any parent up to mount point ";
    const std::string suffix = ")\nStopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).\n";
    if (result.output.size() <= prefix.size() + suffix.size()
        || result.output.compare(0, prefix.size(), prefix) != 0
        || result.output.compare(result.output.size() - suffix.size(), suffix.size(), suffix) != 0)
        return false;
    const auto reported = result.output.substr(prefix.size(), result.output.size() - prefix.size() - suffix.size());
    for (auto current = destination_parent; current != current.root_path();) {
        const auto parent = current.parent_path();
        struct stat current_status{}, parent_status{};
        if (::stat(current.c_str(), &current_status) != 0 || ::stat(parent.c_str(), &parent_status) != 0)
            return false;
        if (current_status.st_dev != parent_status.st_dev) return reported == parent.string();
        current = parent;
    }
    return false;
}

std::string file_bytes(const fs::path& path, std::size_t limit) {
    require(fs::is_regular_file(fs::symlink_status(path)), "A regular file is required.");
    const auto expected = fs::file_size(path);
    require(expected <= limit, "The input exceeds its byte allowance.");
    std::ifstream input(path, std::ios::binary);
    require(static_cast<bool>(input), "Cannot read the pinned input.");
    std::string content(static_cast<std::size_t>(expected) + 1, '\0');
    input.read(content.data(), static_cast<std::streamsize>(content.size()));
    const auto count = static_cast<std::size_t>(input.gcount());
    require(!input.bad() && count == expected, "The input changed or could not be read.");
    content.resize(count);
    return content;
}

std::string git(const fs::path& repository, const std::vector<std::string>& tail,
                std::size_t limit, std::chrono::milliseconds timeout,
                const volatile std::sig_atomic_t* cancellation) {
    std::vector<std::string> arguments{git_executable, "--no-replace-objects", "--literal-pathspecs",
                                       "-C", repository.string()};
    arguments.insert(arguments.end(), tail.begin(), tail.end());
    const auto result = run_process(arguments, timeout, limit, cancellation);
    require(result.exit_code == 0, "The raw Git read failed at " + tail.front()
            + " with exit " + std::to_string(result.exit_code) + ".");
    return result.output;
}

void write_once(const fs::path& path, const std::string& content, mode_t mode) {
    Descriptor file(::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode));
    require(file.fd >= 0, "Refuse to replace a captured file or follow a symlink.");
    std::size_t offset = 0;
    while (offset < content.size()) {
        const auto written = ::write(file.fd, content.data() + offset, content.size() - offset);
        if (written < 0 && errno == EINTR) continue;
        require(written > 0, "Cannot finish writing a captured file.");
        offset += static_cast<std::size_t>(written);
    }
    require(::fchmod(file.fd, mode) == 0, "Cannot retain the declared source mode.");
    require(::fsync(file.fd) == 0, "Cannot flush the complete captured file.");
}

struct Source {
    std::string path;
    std::string mode;
    std::string blob;
    std::string bytes;
    std::string digest;
};
} // namespace

ProcessResult run_process(const std::vector<std::string>& arguments,
                         std::chrono::milliseconds timeout, std::size_t maximum_output,
                         const volatile std::sig_atomic_t* cancellation, bool merge_stderr) {
    require(cancellation == nullptr || *cancellation == 0, "The utility was cancelled.");
    require(!arguments.empty() && fs::path(arguments.front()).is_absolute(),
            "The utility executable must be explicit and absolute.");
    require(timeout.count() > 0, "The utility deadline must be positive.");
    for (const auto& argument : arguments)
        require(argument.find('\0') == std::string::npos, "Utility arguments cannot contain NUL.");

    int descriptors[2];
    require(::pipe2(descriptors, O_CLOEXEC) == 0, "Cannot create the utility pipe.");
    Descriptor read_end(descriptors[0]), write_end(descriptors[1]);
    // The caller may have closed any standard stream. Keep pipe descriptors
    // above all three redirect targets before constructing child file actions.
    for (auto* descriptor : std::array<Descriptor*, 2>{&read_end, &write_end}) {
        if (descriptor->fd > STDERR_FILENO) continue;
        const int moved = ::fcntl(descriptor->fd, F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
        require(moved >= 0, "Cannot isolate the utility pipe descriptors.");
        descriptor->close();
        descriptor->fd = moved;
    }
    require(::fcntl(read_end.fd, F_SETFL, O_NONBLOCK) == 0, "Cannot bound utility reads.");
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    require(::posix_spawn_file_actions_init(&actions) == 0, "Cannot initialize child actions.");
    struct ActionGuard {
        posix_spawn_file_actions_t* value;
        ~ActionGuard() { ::posix_spawn_file_actions_destroy(value); }
    } action_guard{&actions};
    require(::posix_spawnattr_init(&attributes) == 0, "Cannot initialize child attributes.");
    struct AttributeGuard {
        posix_spawnattr_t* value;
        ~AttributeGuard() { ::posix_spawnattr_destroy(value); }
    } attribute_guard{&attributes};
    require(::posix_spawn_file_actions_adddup2(&actions, write_end.fd, STDOUT_FILENO) == 0
            && (merge_stderr
                ? ::posix_spawn_file_actions_adddup2(&actions, write_end.fd, STDERR_FILENO)
                : ::posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)) == 0
            && ::posix_spawn_file_actions_addclose(&actions, read_end.fd) == 0
            && ::posix_spawn_file_actions_addclose(&actions, write_end.fd) == 0
            && ::posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0
            && ::posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP) == 0
            && ::posix_spawnattr_setpgroup(&attributes, 0) == 0,
            "Cannot configure the isolated utility child.");

    std::vector<char*> argv;
    for (const auto& argument : arguments) argv.push_back(const_cast<char*>(argument.c_str()));
    argv.push_back(nullptr);
    std::vector<std::string> environment;
    for (char** item = environ; *item != nullptr; ++item) {
        const std::string value(*item);
        if (value.rfind("GIT_", 0) != 0 && value.rfind("LC_ALL=", 0) != 0)
            environment.push_back(value);
    }
    environment.emplace_back("LC_ALL=C");
    std::vector<char*> envp;
    for (auto& value : environment) envp.push_back(value.data());
    envp.push_back(nullptr);
    pid_t pid = -1;
    const int started = ::posix_spawn(&pid, arguments.front().c_str(), &actions, &attributes,
                                      argv.data(), envp.data());
    require(started == 0, "Cannot start the explicit utility executable.");
    Child child(pid);
    write_end.close();
    const auto deadline = Clock::now() + timeout;
    std::string output;
    bool eof = false;
    bool exited = false;
    while (!eof || !exited) {
        require(cancellation == nullptr || *cancellation == 0, "The utility was cancelled.");
        std::array<char, 16384> buffer{};
        if (!eof) {
            const auto count = ::read(read_end.fd, buffer.data(), buffer.size());
            if (count > 0) {
                require(static_cast<std::size_t>(count) <= maximum_output - output.size(),
                        "The utility exceeded its output allowance.");
                output.append(buffer.data(), static_cast<std::size_t>(count));
            } else if (count == 0) {
                eof = true;
            } else {
                require(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR,
                        "Cannot read the utility output.");
            }
        }
        if (!exited) {
            siginfo_t info{};
            const int status = ::waitid(P_PID, static_cast<id_t>(pid), &info, WEXITED | WNOHANG | WNOWAIT);
            require(status == 0 || errno == EINTR, "Cannot observe the owned utility child.");
            exited = status == 0 && info.si_pid == pid;
        }
        if (eof && exited) break;
        require(Clock::now() < deadline, "The utility exceeded its deadline.");
        if (eof) std::this_thread::sleep_for(std::chrono::milliseconds(1));
        else {
            pollfd ready{read_end.fd, POLLIN, 0};
            ::poll(&ready, 1, 5);
        }
    }
    return {child.reap(), std::move(output)};
}

std::string sha256(const std::string& bytes) {
    using Digest = std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)>;
    Digest digest(EVP_MD_CTX_new(), EVP_MD_CTX_free);
    require(static_cast<bool>(digest), "Cannot allocate the digest context.");
    std::array<unsigned char, EVP_MAX_MD_SIZE> result{};
    unsigned int length = 0;
    require(EVP_DigestInit_ex(digest.get(), EVP_sha256(), nullptr) == 1
            && EVP_DigestUpdate(digest.get(), bytes.data(), bytes.size()) == 1
            && EVP_DigestFinal_ex(digest.get(), result.data(), &length) == 1 && length == 32,
            "Cannot finish the SHA256 digest.");
    std::ostringstream text;
    text << std::hex << std::setfill('0');
    for (unsigned int i = 0; i < length; ++i) text << std::setw(2) << static_cast<unsigned int>(result[i]);
    return text.str();
}

std::string json_string(const std::string& value) {
    std::ostringstream text;
    text << '"';
    for (unsigned char c : value) {
        if (c == '"' || c == '\\') text << '\\' << static_cast<char>(c);
        else if (c < 0x20) text << "\\u00" << std::hex << std::setw(2) << std::setfill('0') << static_cast<unsigned int>(c);
        else text << static_cast<char>(c);
    }
    text << '"';
    return text.str();
}

CaptureResult capture_project(const CaptureOptions& options) {
    const auto not_cancelled = [&] {
        require(options.cancellation == nullptr || *options.cancellation == 0, "The capture was cancelled.");
    };
    not_cancelled();
    const auto deadline = Clock::now() + std::chrono::seconds(60);
    const auto read_git = [&](const std::vector<std::string>& tail, std::size_t limit = 1024 * 1024) {
        const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now());
        require(remaining.count() > 0, "The complete capture exceeded its deadline.");
        return git(options.repository, tail, limit, std::min(remaining, std::chrono::milliseconds(10000)), options.cancellation);
    };
    safe_path(options.repository);
    safe_path(options.output);
    require(fs::is_directory(options.repository) && fs::canonical(options.repository) == options.repository,
            "The repository must be an existing canonical directory.");
    require(object_id(options.tree), "The immutable tree or commit must be a lowercase full object ID.");
    require(!fs::exists(fs::symlink_status(options.output)), "The output must be a fresh directory.");
    require(fs::is_directory(options.output.parent_path())
            && fs::canonical(options.output.parent_path()) == options.output.parent_path(),
            "The output parent must exist without symlinks.");
    require(!contains(options.repository, options.output), "Keep captures outside the source repository.");
    for (auto parent = options.output.parent_path();; parent = parent.parent_path()) {
        require(!fs::exists(fs::symlink_status(parent / ".git")), "Keep captures outside Git worktrees and administration.");
        if (parent == parent.root_path()) break;
    }
    const auto git_digest = sha256(file_bytes(git_executable, 16 * 1024 * 1024));
    // Directory names alone do not identify bare or separately located Git
    // administration. Ask the pinned Git to discover ownership at the actual
    // canonical destination parent. Only its ordinary non-repository diagnostic
    // permits writing; malformed configuration and other failures refuse.
    const auto discovery_remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now());
    require(discovery_remaining.count() > 0, "The complete capture exceeded its deadline.");
    const auto ownership = run_process(
        {git_executable, "--no-replace-objects", "--literal-pathspecs", "-C",
         options.output.parent_path().string(), "rev-parse", "--absolute-git-dir",
         "--is-inside-work-tree", "--is-inside-git-dir"},
        std::min(discovery_remaining, std::chrono::milliseconds(10000)), 65536,
        options.cancellation, true);
    require(ownership.exit_code != 0, "Keep captures outside Git worktrees and administration.");
    require(non_repository_discovery(ownership, options.output.parent_path()),
            "Destination Git ownership discovery failed; no capture is allowed.");
    require(trim_newline(read_git({"rev-parse", "--show-toplevel"})) == options.repository.string(),
            "Select the repository root explicitly.");
    const auto tree = trim_newline(read_git({"rev-parse", "--verify", options.tree + "^{tree}"}));
    require(object_id(tree), "Git did not resolve one immutable tree.");
    const auto roster = read_git({"ls-tree", "-rz", "--full-tree", tree, "--", project_prefix});
    std::vector<Source> sources;
    std::size_t total = 0, scripts = 0, start = 0;
    bool has_project = false;
    while (start < roster.size()) {
        const auto end = roster.find('\0', start);
        require(end != std::string::npos, "The raw Git roster is incomplete.");
        const auto entry = roster.substr(start, end - start);
        const auto tab = entry.find('\t');
        require(tab != std::string::npos, "The raw Git roster is malformed.");
        std::istringstream header(entry.substr(0, tab));
        std::string mode, kind, blob, extra;
        header >> mode >> kind >> blob;
        require(!(header >> extra) && (mode == "100644" || mode == "100755")
                && kind == "blob" && object_id(blob), "Refuse symlinks, submodules or non-file source modes.");
        const auto full = entry.substr(tab + 1);
        require(full.rfind(project_prefix, 0) == 0, "The source escaped the declared project subtree.");
        const auto relative = full.substr(std::strlen(project_prefix));
        const fs::path path(relative);
        require(!relative.empty() && !path.is_absolute() && path.lexically_normal().string() == relative,
                "The source path is not a normalized project-relative name.");
        for (unsigned char character : relative)
            require(character >= 0x20 && character < 0x7f && character != '\\',
                    "This first capture adapter requires printable ASCII resource paths.");
        for (const auto& component : path)
            require(component != ".git" && component != ".beads" && component != ".godot"
                    && component != ".." && component != ".",
                    "Private metadata and generated caches are excluded.");
        require(sources.size() < maximum_files, "The project exceeds its file allowance.");
        auto bytes = read_git({"cat-file", "blob", blob}, maximum_project_source_bytes - total);
        total += bytes.size();
        if (path.extension() == ".gd") ++scripts;
        require(scripts <= maximum_scripts, "The project exceeds its script allowance.");
        has_project = has_project || relative == "project.godot";
        const auto digest = sha256(bytes);
        sources.push_back({relative, mode, blob, std::move(bytes), digest});
        start = end + 1;
    }
    require(has_project && scripts > 0, "The immutable snapshot is not the supported Godot project.");
    require(sha256(file_bytes(git_executable, 16 * 1024 * 1024)) == git_digest,
            "The Git executable changed during capture preparation.");

    not_cancelled();
    require(fs::create_directory(options.output), "Cannot create the fresh output directory.");
    fs::permissions(options.output, fs::perms::owner_all);
    const auto project = options.output / "project";
    fs::create_directory(project);
    std::ostringstream manifest;
    manifest << "{\n  \"schema\": 1,\n  \"kind\": \"immutable_project_capture\",\n"
             << "  \"status\": \"captured\",\n  \"engine_runs\": 0,\n  \"source_tree\": " << json_string(tree)
             << ",\n  \"source_object\": " << json_string(options.tree)
             << ",\n  \"git_executable\": " << json_string(git_executable)
             << ",\n  \"git_sha256\": " << json_string(git_digest)
             << ",\n  \"source_bytes\": " << total << ",\n  \"script_count\": " << scripts << ",\n  \"files\": [\n";
    for (std::size_t i = 0; i < sources.size(); ++i) {
        not_cancelled();
        require(Clock::now() < deadline, "The complete capture exceeded its deadline.");
        const auto& source = sources[i];
        const auto target = project / source.path;
        fs::create_directories(target.parent_path());
        write_once(target, source.bytes, source.mode == "100755" ? 0755 : 0644);
        require(sha256(file_bytes(target, maximum_project_source_bytes)) == source.digest,
                "The captured source differs from the immutable blob.");
        manifest << "    {\"path\": " << json_string(source.path) << ", \"mode\": " << json_string(source.mode)
                 << ", \"blob\": " << json_string(source.blob) << ", \"bytes\": " << source.bytes.size()
                 << ", \"sha256\": " << json_string(source.digest) << '}'
                 << (i + 1 == sources.size() ? "\n" : ",\n");
    }
    manifest << "  ]\n}\n";
    not_cancelled();
    require(Clock::now() < deadline, "The complete capture exceeded its deadline.");
    const auto ready = options.output / "capture.json";
    write_once(ready, manifest.str(), 0600);
    return {tree, sources.size(), scripts, total, ready};
}
} // namespace factory_launch
