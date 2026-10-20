#include "runner.hpp"

#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <limits>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

namespace bs = factory::build_support;
namespace fs = std::filesystem;
using namespace std::chrono_literals;
namespace {
int checks = 0;
volatile std::sig_atomic_t cancelled = 0;
void cancel(int value) { cancelled = value; }
std::vector<std::string> fixture_command(std::vector<std::string> command) {
    command.push_back(std::to_string(::getpid()));
    return command;
}
void check(bool value) { if (!value) throw std::runtime_error("A runner control failed."); ++checks; }
void refuses(const std::function<void()>& action, bs::Reason expected) {
    try { action(); }
    catch (const bs::Error& error) { check(error.reason() == expected); return; }
    throw std::runtime_error("A runner refusal was missing.");
}
void write(const fs::path& path, const std::string& value) {
    std::ofstream stream(path, std::ios::binary);
    stream.write(value.data(), static_cast<std::streamsize>(value.size()));
    if (!stream) throw std::runtime_error("Cannot write an invented fixture.");
}
std::string read(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(stream), {});
}
struct Permit {
    int fd;
    Permit(const fs::path& path, int mode) : fd(::open(path.c_str(), O_RDWR | O_CREAT | O_EXCL, 0600)) {
        if (fd < 0 || ::flock(fd, mode) < 0) {
            if (fd >= 0) ::close(fd);
            throw std::runtime_error("Cannot create invented permit files.");
        }
    }
    ~Permit() { ::close(fd); }
};
int fixture(int argc, char** argv) {
    const std::string mode(argv[2]);
    if (mode == "probe") {
        if (argc != 7) return 2;
        const int first = std::stoi(argv[3]), second = std::stoi(argv[4]), unrelated = std::stoi(argv[5]);
        int death_signal = 0;
        const bool good = !::getenv("FACTORY_RUNNER_TEST_PRIVATE") && ::getenv("PATH") &&
            ::getenv("HOME") && std::string(::getenv("HOME")) == argv[6] &&
            ::fcntl(first, F_GETFD) >= 0 && ::fcntl(second, F_GETFD) >= 0 &&
            ::fcntl(unrelated, F_GETFD) < 0 && ::getpgrp() == ::getpid() &&
            ::prctl(PR_GET_PDEATHSIG, &death_signal) == 0 && death_signal == SIGKILL;
        std::cout << "Invented environment, descriptor and process-group probe.\n";
        return good ? 0 : 2;
    }
    if (mode == "nonzero") return 7;
    if (mode == "identity") {
        if (argc != 7) return 2;
        struct stat current{};
        const bool good = ::getuid() == std::stoul(argv[3]) && ::getgid() == std::stoul(argv[4]) &&
            ::stat("/proc/self/ns/user", &current) == 0 &&
            current.st_dev == std::stoull(argv[5]) && current.st_ino == std::stoull(argv[6]);
        std::cout << "The command retains the original user namespace and identity.\n";
        return good ? 0 : 2;
    }
    if (mode == "sleep") { for (;;) ::pause(); }
    if (mode == "cancel") { ::kill(::getppid(), SIGALRM); for (;;) ::pause(); }
    if (mode == "output") { std::cout << std::string(4096, 'x'); return 0; }
    if (mode == "artifact") { write(fs::path(argv[3]) / "grown", std::string(4096, 'x')); return 0; }
    if (mode == "mutation") {
        const fs::path root(argv[3]);
        for (int i = 0; i < 8000; ++i) {
            fs::create_directory(root / "changing");
            write(root / "changing/value", "x");
            fs::rename(root / "changing", root / "retired");
            fs::remove_all(root / "retired");
        }
        std::cout << "Invented cache mutation completed.\n";
        return 0;
    }
    return 2;
}
}
int main(int argc, char** argv) {
    try {
        if (argc > 3 && std::string(argv[1]) == "--fixture") {
            // Fixture groups must not outlive an interrupted native unit parent.
            // Set the kernel guard first, then close the pre-registration race.
            const auto expected_parent = std::stol(argv[argc - 1]);
            if (expected_parent <= 0 || expected_parent > std::numeric_limits<pid_t>::max() ||
                ::prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 ||
                ::getppid() != static_cast<pid_t>(expected_parent)) return 2;
            return fixture(argc - 1, argv);
        }
        const char* temporary = ::getenv("TEST_TMPDIR");
        if (!temporary) throw std::runtime_error("Use the declared Bazel test temporary directory.");
        const auto root = fs::path(temporary) / ("runner-first-" + std::to_string(::getpid()));
        check(!fs::exists(root));
        fs::create_directories(root / "permits");
        fs::permissions(root, fs::perms::owner_all);
        Permit heavy(root / "permits/heavy.lock", LOCK_EX), activity(root / "permits/activity.lock", LOCK_SH);
        const auto self = fs::canonical("/proc/self/exe").string();
        unsigned case_number = 0;
        auto options = [&] {
            bs::Options result;
            result.artifacts = root / ("case-" + std::to_string(++case_number));
            fs::create_directory(result.artifacts);
            fs::permissions(result.artifacts, fs::perms::owner_all);
            result.log = result.artifacts / "command.log";
            result.admission_directory = root / "permits";
            result.timeout = 5s;
            return result;
        };
        const auto snapshot = root / "snapshot";
        fs::create_directory(snapshot);
        write(snapshot / "ten", "0123456789");
        check(bs::owned_bytes(snapshot, 10) == 10);
        refuses([&] { (void)bs::owned_bytes(snapshot, 9); }, bs::Reason::artifacts);
        fs::create_directory_symlink("/", snapshot / "external-link");
        check(bs::owned_bytes(snapshot, 100) == 11); // Link bytes, never its target tree.
        // A real mode-zero directory may still contain stock-sized bytes. The
        // adapter must measure them, not trust a filename or an emptiness claim.
        check(::getuid() != 0 && ::getuid() == ::geteuid() && ::getgid() == ::getegid());
        fs::permissions(snapshot, fs::perms::owner_all);
        const auto hidden = snapshot / "opaque";
        fs::create_directory(hidden);
        write(hidden / "value", "1234");
        fs::permissions(hidden / "value", fs::perms::none);
        fs::permissions(hidden, fs::perms::none);
        struct Restore {
            fs::path path;
            ~Restore() { std::error_code ignored; fs::permissions(path, fs::perms::owner_all, ignored); }
        } restore_hidden{hidden};
        struct stat before{}, after{};
        check(::lstat(hidden.c_str(), &before) == 0);
        refuses([&] { (void)bs::owned_bytes(snapshot, 100); }, bs::Reason::scan);
        check(bs::owned_bytes_as_owner(snapshot, 100, 5s) == 15);
        check(bs::owned_bytes_as_owner(snapshot, 100, 5s) == 15);
        check(::lstat(hidden.c_str(), &after) == 0 && before.st_dev == after.st_dev &&
              before.st_ino == after.st_ino && before.st_mode == after.st_mode &&
              before.st_uid == after.st_uid && before.st_gid == after.st_gid);
        check(::getuid() == ::geteuid() && ::geteuid() == before.st_uid &&
              ::getgid() == ::getegid());
        refuses([&] { (void)bs::owned_bytes_as_owner(snapshot, 14, 5s); }, bs::Reason::artifacts);
        refuses([&] { (void)bs::owned_bytes_as_owner(snapshot, 100, 0ms); }, bs::Reason::options);
        volatile std::sig_atomic_t already_cancelled = SIGTERM;
        refuses([&] { (void)bs::owned_bytes_as_owner(snapshot, 100, 5s, &already_cancelled); }, bs::Reason::cancelled);
        check(::mkfifo((snapshot / "pipe").c_str(), 0600) == 0);
        refuses([&] { (void)bs::owned_bytes_as_owner(snapshot, 100, 5s); }, bs::Reason::scan);
        fs::remove(snapshot / "pipe");
        fs::permissions(hidden, fs::perms::owner_all);
        fs::remove(hidden / "value"); fs::remove(hidden);
        const int null_fd = ::open("/dev/null", O_RDONLY | O_CLOEXEC);
        check(null_fd >= 0);
        const int unrelated = ::fcntl(null_fd, F_DUPFD, 180);
        ::close(null_fd);
        check(unrelated >= 180);
        struct Close { int fd; ~Close() { ::close(fd); } } close_unrelated{unrelated};
        check(::setenv("FACTORY_RUNNER_TEST_PRIVATE", "invented-private-marker", 1) == 0);
        auto current = options();
        const auto probe = fixture_command({self, "--fixture", "probe", std::to_string(heavy.fd),
                                           std::to_string(activity.fd), std::to_string(unrelated),
                                           (current.artifacts / "home").string()});
        check(bs::run(current, probe) == 0);
        check(read(current.log) == "Invented environment, descriptor and process-group probe.\n");
        check(::unsetenv("FACTORY_RUNNER_TEST_PRIVATE") == 0);
        current = options();
        check(bs::run(current, fixture_command({self, "--fixture", "nonzero"})) == 7);
        current = options(); current.owned_user_accounting = true;
        check(bs::run(current, fixture_command({self, "--fixture", "nonzero"})) == 7);
        struct stat user_namespace{};
        check(::stat("/proc/self/ns/user", &user_namespace) == 0);
        current = options(); current.owned_user_accounting = true;
        check(bs::run(current, fixture_command({self, "--fixture", "identity", std::to_string(::getuid()),
              std::to_string(::getgid()), std::to_string(user_namespace.st_dev),
              std::to_string(user_namespace.st_ino)})) == 0);
        check(read(current.log) == "The command retains the original user namespace and identity.\n");
        current = options();
        refuses([&] { (void)bs::run(current, {"/missing/factory-build-fixture"}); }, bs::Reason::spawn);
        current = options(); current.log_limit = 32;
        refuses([&] { (void)bs::run(current, fixture_command({self, "--fixture", "output"})); }, bs::Reason::log);
        check(fs::file_size(current.log) == 32);
        current = options(); current.artifact_limit = 1024;
        refuses([&] { (void)bs::run(current, fixture_command({self, "--fixture", "artifact", current.artifacts.string()})); }, bs::Reason::artifacts);
        current = options(); current.timeout = 40ms;
        refuses([&] { (void)bs::run(current, fixture_command({self, "--fixture", "sleep"})); }, bs::Reason::timeout);
        current = options();
        check(bs::run(current, fixture_command({self, "--fixture", "mutation", current.artifacts.string()})) == 0);
        check(read(current.log) == "Invented cache mutation completed.\n");
        current = options();
        fs::create_directory_symlink(root, current.artifacts / "tmp");
        refuses([&] { (void)bs::run(current, probe); }, bs::Reason::options);
        current = options();
        write(current.log, "original");
        refuses([&] { (void)bs::run(current, probe); }, bs::Reason::io);
        check(read(current.log) == "original");
        current = options();
        current.artifact_limit = bs::maximum_artifacts + 1;
        refuses([&] { (void)bs::run(current, probe); }, bs::Reason::options);
        struct Alarm {
            struct sigaction prior{};
            Alarm() {
                struct sigaction action{}; action.sa_handler = cancel; ::sigemptyset(&action.sa_mask);
                if (::sigaction(SIGALRM, &action, &prior)) throw std::runtime_error("Cannot install fixture alarm.");
            }
            ~Alarm() { ::sigaction(SIGALRM, &prior, nullptr); }
        };
        current = options(); current.cancellation = &cancelled;
        { Alarm alarm; refuses([&] { (void)bs::run(current, fixture_command({self, "--fixture", "cancel"})); }, bs::Reason::cancelled); }
        check(cancelled == SIGALRM);
        // No fixture child survives a successful run or an exception: run owns
        // and reaps the direct child. These are invented controls, not game proof.
        std::cout << "{\"status\":\"pass\",\"checks\":" << checks << ",\"evidence\":\"invented_runner_controls\"}\n";
        return 0;
    } catch (...) {
        std::cerr << "{\"status\":\"fail\",\"evidence\":\"invented_runner_controls\"}\n";
        return 1;
    }
}
