#include "build.hpp"
#include "factory/capture.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <fcntl.h>
#include <fstream>
#include <set>
#include <sstream>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

namespace factory::gameplay_build {
namespace {
using namespace std::chrono_literals;
void require(bool value, const std::string& message) {
    if (!value) throw std::runtime_error(message);
}
struct Descriptor {
    int value;
    ~Descriptor() { if (value >= 0) ::close(value); }
};
constexpr const char* dependency_manifest = "native/gameplay-build/production-paths.txt";

std::string git(const fs::path& root, std::vector<std::string> arguments) {
    arguments.insert(arguments.begin(), {"/usr/bin/git", "-C", root.string()});
    const auto result = factory_launch::run_process(arguments, 10s, 2 * 1024 * 1024);
    require(result.exit_code == 0, "Cannot verify the build's Git source.");
    return result.output;
}
std::string revision(const fs::path& root) {
    auto value = git(root, {"rev-parse", "--verify", "HEAD^{commit}"});
    if (!value.empty() && value.back() == '\n') value.pop_back();
    require(value.size() == 40 && value.find_first_not_of("0123456789abcdef") == std::string::npos,
            "Expected a full committed SHA-1 revision.");
    return value;
}
std::vector<std::string> paths(const fs::path& root, const std::string& source, Component component) {
    const auto manifest = git(root, {"show", source + ":" + dependency_manifest});
    require(manifest.size() <= 16384 && !manifest.empty() && manifest.back() == '\n',
            "The committed production dependency manifest is invalid.");
    const std::string selected = component == Component::startup ? "startup " : "gameplay ";
    std::vector<std::string> result;
    std::set<std::string> seen;
    for (std::size_t start = 0; start < manifest.size();) {
        const auto end = manifest.find('\n', start);
        require(end != std::string::npos && end > start, "The dependency manifest has an invalid line.");
        const auto line = manifest.substr(start, end - start);
        const auto divider = line.find(' ');
        require(divider != std::string::npos && (line.substr(0, divider) == "startup" ||
                line.substr(0, divider) == "gameplay"), "The dependency manifest has an unknown component.");
        const auto path = line.substr(divider + 1);
        require(!path.empty() && path.size() <= 256 && path.find_first_not_of(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-") == std::string::npos &&
            !fs::path(path).is_absolute() && fs::path(path).lexically_normal() == fs::path(path) &&
            path.find("..") == std::string::npos && seen.insert(line).second,
            "The dependency manifest has an unsafe or duplicate path.");
        if (line.starts_with(selected)) result.push_back(path);
        start = end + 1;
    }
    require(!result.empty(), "The dependency manifest omits the selected component.");
    result.emplace_back(dependency_manifest);
    return result;
}
std::string production(const fs::path& root, const std::string& source, Component component) {
    std::vector<std::string> args{"ls-tree", "-r", "-z", "--full-tree", source, "--"};
    const auto selected = paths(root, source, component);
    args.insert(args.end(), selected.begin(), selected.end());
    return factory_launch::sha256(git(root, args));
}
void clean(const fs::path& root) {
    require(git(root, {"status", "--porcelain", "--untracked-files=normal"}).empty(),
            "Build from a clean committed checkout, without untracked source inputs.");
}
void canonical_directory(const fs::path& root) {
    struct stat st{};
    require(root.is_absolute() && fs::canonical(root) == root &&
            ::lstat(root.c_str(), &st) == 0 && S_ISDIR(st.st_mode) && st.st_uid == ::geteuid(),
            "Use a canonical owned directory without symlink components.");
}
std::string read(const fs::path& path, std::size_t maximum) {
    Descriptor fd{::open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)};
    struct stat before{}, after{};
    require(fd.value >= 0 && ::fstat(fd.value, &before) == 0 && S_ISREG(before.st_mode) &&
            before.st_uid == ::geteuid() && before.st_size >= 0 &&
            static_cast<std::uint64_t>(before.st_size) <= maximum, "Invalid, changed or excessive regular input.");
    std::string bytes;
    std::array<char, 65536> buffer{};
    while (true) {
        const auto n = ::read(fd.value, buffer.data(), buffer.size());
        if (n < 0 && errno == EINTR) continue;
        require(n >= 0, "Cannot read the regular input.");
        if (!n) break;
        require(static_cast<std::size_t>(n) <= maximum - bytes.size(), "Input grew beyond its bound.");
        bytes.append(buffer.data(), static_cast<std::size_t>(n));
    }
    require(::fstat(fd.value, &after) == 0 && before.st_size == after.st_size &&
            bytes.size() == static_cast<std::size_t>(before.st_size) &&
            before.st_mtim.tv_sec == after.st_mtim.tv_sec && before.st_mtim.tv_nsec == after.st_mtim.tv_nsec,
            "Input changed while it was read.");
    return bytes;
}
void write(const fs::path& path, const std::string& bytes, mode_t mode) {
    Descriptor fd{::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600)};
    require(fd.value >= 0, "Cannot create the fresh installation file.");
    std::size_t offset = 0;
    while (offset < bytes.size()) {
        const auto n = ::write(fd.value, bytes.data() + offset, bytes.size() - offset);
        if (n < 0 && errno == EINTR) continue;
        require(n > 0, "Cannot finish the installation file.");
        offset += static_cast<std::size_t>(n);
    }
    require(::fchmod(fd.value, mode) == 0 && ::fsync(fd.value) == 0, "Cannot retain the installation file.");
}
void sync_directory(const fs::path& path) {
    Descriptor fd{::open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC)};
    require(fd.value >= 0 && ::fsync(fd.value) == 0, "Cannot retain the installation directory.");
}
std::string quote(const std::string& value) {
    std::string result = "'";
    for (const char c : value) result += c == '\'' ? "'\"'\"'" : std::string(1, c);
    return result + "'";
}
std::string replace(const std::string& text, const std::string& name, const std::string& value) {
    std::size_t offset = 0, matched = 0;
    std::string result;
    while (offset < text.size()) {
        auto end = text.find('\n', offset);
        if (end == std::string::npos) end = text.size();
        const auto line = text.substr(offset, end - offset);
        if (line.rfind(name + "=", 0) == 0) { result += name + "=" + value; ++matched; }
        else result += line;
        if (end < text.size()) result += '\n';
        offset = end + 1;
    }
    require(matched == 1, "The launcher must have exactly one of each requested native pin.");
    return result;
}
void validate(const Options& options) {
    canonical_directory(options.checkout);
    canonical_directory(options.main_checkout);
    canonical_directory(options.install_root);
    require(options.launcher.is_absolute() && fs::canonical(options.launcher.parent_path()) == options.launcher.parent_path(),
            "Use an absolute launcher in a canonical parent directory.");
    require(options.install_root.string().find(options.checkout.string() + "/") != 0 &&
            options.install_root != options.checkout && options.install_root != options.main_checkout &&
            options.install_root.string().find(options.main_checkout.string() + "/") != 0,
            "Keep installed libraries outside source checkouts.");
    require(git(options.main_checkout, {"branch", "--show-current"}) == "main\n", "The publication checkout must be main.");
}
} // namespace

void validate_query_coverage(const std::vector<std::string>& selected, const std::string& output) {
    std::istringstream lines(output);
    std::string line;
    std::size_t local = 0;
    while (std::getline(lines, line)) {
        if (!line.starts_with("//")) continue; // External repository labels and Bazel progress.
        const auto colon = line.find(':', 2);
        require(colon != std::string::npos && line.find(':', colon + 1) == std::string::npos,
                "Bazel returned an invalid local dependency label.");
        const std::string path = colon == 2 ? line.substr(3) :
            line.substr(2, colon - 2) + "/" + line.substr(colon + 1);
        require(!path.empty() && path.find_first_not_of(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-") == std::string::npos &&
            fs::path(path).lexically_normal() == fs::path(path),
            "Bazel returned an unsafe local dependency label.");
        ++local;
        const bool covered = std::any_of(selected.begin(), selected.end(), [&](const std::string& prefix) {
            return path == prefix || path.starts_with(prefix + "/");
        });
        require(covered, "Production dependency is missing from the committed manifest: " + path);
    }
    require(local > 0, "Bazel returned no local production dependencies.");
}

Snapshot snapshot(const Options& options) {
    validate(options);
    clean(options.checkout);
    Snapshot result{revision(options.checkout), {}, read(options.launcher, 65536)};
    result.production = production(options.checkout, result.revision, options.component);
    // Validate the complete pin shape before spending time on a build.
    if (options.component == Component::startup) {
        for (const auto* name : {"startup", "startup_sha256", "startup_source"})
            (void)replace(result.launcher, name, "validation");
    } else {
        for (const auto* name : {"library", "library_sha256", "library_source"})
            (void)replace(result.launcher, name, "validation");
    }
    return result;
}

int complete(const Options& options, const Snapshot& before, int build_exit, const fs::path& library) {
    if (build_exit != 0) return build_exit;
    validate(options);
    clean(options.checkout);
    require(revision(options.checkout) == before.revision &&
            production(options.checkout, before.revision, options.component) == before.production,
            "Build source changed; the previous installed library is unchanged.");
    require(production(options.main_checkout, revision(options.main_checkout), options.component) == before.production,
            "Current main has newer production inputs; rebuild before installing.");
    const auto bytes = read(library, 64 * 1024 * 1024);
    require(bytes.size() >= 64 && bytes.compare(0, 4, "\177ELF") == 0 &&
            bytes[4] == 2 && bytes[5] == 1 && bytes[17] == 0 && bytes[18] == 62 && bytes[19] == 0 &&
            (options.component == Component::startup ? (bytes[16] == 2 || bytes[16] == 3) : bytes[16] == 3),
            "The build did not produce the expected x86-64 ELF output.");
    const auto digest = factory_launch::sha256(bytes);
    const bool startup = options.component == Component::startup;
    const auto destination = options.install_root / ((startup ? "startup-" : "") + before.revision + "-" + digest);
    const auto installed = destination / (startup ? "factory-opening-startup" : "factory-native-world.so");
    auto updated = replace(before.launcher, startup ? "startup" : "library", quote(installed.string()));
    updated = replace(updated, startup ? "startup_sha256" : "library_sha256", digest);
    updated = replace(updated, startup ? "startup_source" : "library_source", before.revision);
    Descriptor lock{::open((options.install_root / ".gameplay-install.lock").c_str(), O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600)};
    struct stat lock_stat{}, launcher_stat{};
    require(lock.value >= 0 && ::fstat(lock.value, &lock_stat) == 0 && S_ISREG(lock_stat.st_mode) &&
            lock_stat.st_uid == ::geteuid() && ::flock(lock.value, LOCK_EX | LOCK_NB) == 0,
            "Another gameplay installation owns this destination.");
    require(read(options.launcher, 65536) == before.launcher &&
            ::lstat(options.launcher.c_str(), &launcher_stat) == 0 && S_ISREG(launcher_stat.st_mode),
            "The launcher changed during the build; reconcile its pins before installation.");
    if (fs::exists(destination)) {
        canonical_directory(destination);
        require(read(installed, 64 * 1024 * 1024) == bytes, "An existing immutable installation differs.");
    } else {
        require(fs::create_directory(destination), "Cannot create a fresh versioned installation.");
        fs::permissions(destination, fs::perms::owner_all);
        write(installed, bytes, 0555);
        write(destination / "source.json", "{\"revision\":" + factory_launch::json_string(before.revision) +
            ",\"production_sha256\":" + factory_launch::json_string(before.production) +
            (startup ? ",\"startup_sha256\":" : ",\"library_sha256\":") +
            factory_launch::json_string(digest) + "}\n", 0444);
        sync_directory(destination);
        sync_directory(options.install_root);
    }
    const auto temporary = options.launcher.string() + ".gameplay-new-" + std::to_string(::getpid());
    bool temporary_created = false;
    try {
        write(temporary, updated, launcher_stat.st_mode & 0777);
        temporary_created = true;
        require(read(options.launcher, 65536) == before.launcher &&
                production(options.main_checkout, revision(options.main_checkout), options.component) == before.production,
                "Publication inputs changed; the previous launcher is unchanged.");
        require(::rename(temporary.c_str(), options.launcher.c_str()) == 0, "Cannot atomically update the launcher pins.");
        sync_directory(options.launcher.parent_path());
    } catch (...) {
        // This is our unpublished temporary file, never an old library or log.
        std::error_code ignored;
        if (temporary_created) fs::remove(temporary, ignored);
        throw;
    }
    return 0;
}

int run(const Options& options) {
    const auto before = snapshot(options);
    const auto root = options.runner.artifacts;
    canonical_directory(root);
    require(root != options.checkout && root != options.main_checkout &&
            root.string().find(options.checkout.string() + "/") != 0 &&
            root.string().find(options.main_checkout.string() + "/") != 0,
            "Keep build artifacts outside source and Git administration directories.");
    require(options.bazel.is_absolute() && fs::canonical(options.bazel) == options.bazel &&
            factory_launch::sha256(read(options.bazel, 256 * 1024 * 1024)) ==
                "4dc8e99dfa802e252dac176d08201fd15c542ae78c448c8a89974b6f387c282c",
            "Use the pinned Bazel 8.4.2 executable.");
    for (const auto* child : {"home", "tmp", "repository-cache", "action-cache", "links"}) {
        fs::create_directory(root / child);
        canonical_directory(root / child);
    }
    const std::vector<std::string> command{options.bazel.string(), "--nosystem_rc", "--nohome_rc", "--batch",
        "--host_jvm_args=-Xmx1024m", "--output_user_root=" + (root / "output").string(), "build",
        "--repository_cache=" + (root / "repository-cache").string(), "--disk_cache=" + (root / "action-cache").string(),
        "--symlink_prefix=" + (root / "links").string() + "/", "--jobs=8", "--lockfile_mode=error",
        "--repository_disable_download", "--registry=https://bcr.bazel.build",
        "--downloader_config=" + (options.checkout / "native/build-support/offline-downloader.cfg").string(),
        options.component == Component::startup ? "//native/factory-launch:factory-opening-startup" :
            "//native/factory-godot-world:factory-native-world.so"};
    const auto old_cwd = fs::current_path();
    struct Restore { fs::path path; ~Restore() { std::error_code ignored; fs::current_path(path, ignored); } } restore{old_cwd};
    fs::current_path(options.checkout);
    const auto target = options.component == Component::startup ?
        "//native/factory-launch:factory-opening-startup" :
        "//native/factory-godot-world:factory-native-world.so";
    auto query_runner = options.runner;
    query_runner.log = options.runner.log.parent_path() / "dependency-query.log";
    query_runner.timeout = std::chrono::seconds(60);
    const std::vector<std::string> query{options.bazel.string(), "--nosystem_rc", "--nohome_rc", "--batch",
        "--host_jvm_args=-Xmx1024m", "--output_user_root=" + (root / "output").string(), "query",
        "--repository_cache=" + (root / "repository-cache").string(), "--lockfile_mode=error",
        "--repository_disable_download", "--registry=https://bcr.bazel.build",
        "--downloader_config=" + (options.checkout / "native/build-support/offline-downloader.cfg").string(),
        "--output=label", "kind(\"source file\", deps(" + std::string(target) + ")) union buildfiles(deps(" +
            std::string(target) + "))"};
    const int query_exit = build_support::run(query_runner, query);
    if (query_exit != 0) return query_exit;
    validate_query_coverage(paths(options.checkout, before.revision, options.component),
        read(query_runner.log, 8 * 1024 * 1024));
    const int exit = build_support::run(options.runner, command);
    if (exit != 0) return exit;
    const auto binary = fs::canonical(root / (options.component == Component::startup ?
        "links/bin/native/factory-launch/factory-opening-startup" :
        "links/bin/native/factory-godot-world/factory-native-world.so"));
    require(binary.string().find(root.string() + "/output/") == 0, "Built output escaped its owned output family.");
    return complete(options, before, exit, binary);
}
} // namespace factory::gameplay_build
