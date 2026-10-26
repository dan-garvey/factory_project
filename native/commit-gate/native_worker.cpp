#include "native_worker.hpp"

#include "coordinator.hpp"
#include "native_selection.hpp"
#include "staged_tree.hpp"

#include "native/build-support/runner.hpp"
#include "native/tooling/local_resources.hpp"
#include "factory/capture.hpp"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

namespace factory::commit_gate {
namespace {
namespace fs = std::filesystem;
using namespace std::chrono_literals;

void require(bool valid, const std::string& reason) {
    if (!valid) throw std::runtime_error(reason);
}

std::string trim(std::string value) {
    while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) value.pop_back();
    return value;
}

GitResult git(const fs::path& checkout, const std::vector<std::string>& tail) {
    std::vector<std::string> arguments{"/usr/bin/git", "-C", checkout.string()};
    arguments.insert(arguments.end(), tail.begin(), tail.end());
    const auto result = factory_launch::run_process(arguments, 10s,
        maximum_staged_blob_bytes + 1);
    return {result.exit_code, result.output};
}

std::string config(const fs::path& checkout, const std::string& key,
                   bool artifacts = false) {
    if (artifacts) {
        const auto enabled = git(checkout, {"config", "--local", "--bool", "--get",
                                            "extensions.worktreeConfig"});
        const auto status = trim(enabled.output);
        require(enabled.exit_code == 1 ||
                    (enabled.exit_code == 0 && (status == "true" || status == "false")),
                "Cannot read the worktree configuration extension for native validation.");
        if (status == "true") {
            const auto local = git(checkout, {"config", "--worktree", "--get", key});
            if (local.exit_code == 0) {
                require(!trim(local.output).empty(), "The native worktree artifact setting is empty.");
                return trim(local.output);
            }
            require(local.exit_code == 1, "Cannot read the native worktree artifact setting.");
        }
    }
    const auto local = git(checkout, {"config", "--local", "--get", key});
    require(local.exit_code == 0 && !trim(local.output).empty(),
            "Native validation needs repository-local " + key + ".");
    return trim(local.output);
}

std::string file_digest(const fs::path& path) {
    require(path.is_absolute() && fs::is_regular_file(path),
            "A pinned native tool is not a regular file.");
    const auto result = factory_launch::run_process({"/usr/bin/sha256sum", path.string()},
                                                     15s, 1024);
    require(result.exit_code == 0 && result.output.size() >= 66 && result.output[64] == ' ',
            "Cannot hash a pinned native tool.");
    const auto digest = result.output.substr(0, 64);
    require(digest.find_first_not_of("0123456789abcdef") == std::string::npos,
            "A pinned native tool returned an invalid digest.");
    return digest;
}

std::string toolchain_key() {
    std::string identity;
    for (const auto* tool : {"/usr/bin/gcc-11", "/usr/bin/g++-11", "/usr/bin/ld"})
        identity += std::string(tool) + "=" + file_digest(tool) + "\n";
    const auto packages = factory_launch::run_process({"/usr/bin/dpkg-query", "-W",
        "-f=${binary:Package}=${Version}\\n", "gcc-11", "g++-11", "libstdc++-11-dev",
        "libc6-dev", "binutils", "libssl-dev"}, 15s, 16384);
    require(packages.exit_code == 0 && !packages.output.empty(),
            "Cannot identify the installed native compiler and SDK packages.");
    identity += packages.output;
    return factory_launch::sha256(identity);
}

fs::path run_directory(const fs::path& artifacts, const std::string& tree) {
    std::string pattern = (artifacts / ("gate-" + tree.substr(0, 12) + "-XXXXXX")).string();
    require(::mkdtemp(pattern.data()) != nullptr, "Cannot retain a private native gate run.");
    return pattern;
}

std::vector<std::string> bazel_command(const fs::path& binary,
                                        const fs::path& artifacts,
                                        const fs::path& output_base,
                                        const fs::path& staged,
                                        const std::string& verb) {
    return {binary.string(), "--nosystem_rc", "--nohome_rc", "--batch",
        "--host_jvm_args=-Xmx1024m", "--output_user_root=" + (artifacts / "output").string(),
        "--output_base=" + output_base.string(), verb, "--lockfile_mode=error",
        "--repository_cache=" + (artifacts / "repositories").string(),
        "--disk_cache=" + (artifacts / "actions").string(), "--distdir=" + artifacts.string(),
        "--repository_disable_download", "--registry=https://bcr.bazel.build",
        "--downloader_config=" + (staged / "native/build-support/offline-downloader.cfg").string()};
}

int bazel_stage(const fs::path& artifacts, const fs::path& admission,
                const fs::path& log, const std::vector<std::string>& command) {
    build_support::Options options;
    options.artifacts = artifacts;
    options.log = log;
    options.admission_directory = admission;
    options.timeout = 300s;
    options.owned_user_accounting = true;
    const int result = build_support::run(options, command);
    std::cout << "Native Bazel " << command[7] << " exit " << result
              << "; retained log " << log << '\n' << std::flush;
    return result;
}

std::string bounded_file(const fs::path& path, std::size_t maximum) {
    require(fs::is_regular_file(path) && fs::file_size(path) <= maximum,
            "A required native validation result is absent or oversized.");
    std::ifstream stream(path, std::ios::binary);
    require(static_cast<bool>(stream), "Cannot read a required native validation result.");
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}

} // namespace

void require_passing_test_events(std::string_view data,
                                 const std::vector<std::string>& expected) {
    require(data.size() <= 8 * 1024 * 1024 &&
                std::is_sorted(expected.begin(), expected.end()) && !expected.empty(),
            "The selected native test result is oversized or has invalid labels.");
    std::set<std::string> passed;
    constexpr std::string_view marker = "\"id\":{\"testSummary\":{\"label\":\"";
    for (std::size_t begin = 0; begin < data.size();) {
        const auto end = data.find('\n', begin);
        const std::string_view line(data.data() + begin,
            (end == std::string_view::npos ? data.size() : end) - begin);
        const auto found = line.find(marker);
        if (found != std::string_view::npos) {
            const auto name_begin = found + marker.size();
            const auto name_end = line.find('"', name_begin);
            require(name_end != std::string_view::npos, "Bazel returned an incomplete test summary.");
            const std::string label(line.substr(name_begin, name_end - name_begin));
            require(std::binary_search(expected.begin(), expected.end(), label) &&
                        line.find("\"overallStatus\":\"PASSED\"") != std::string_view::npos &&
                        passed.insert(label).second,
                    "An affected native test was skipped, failed or summarized twice: " + label);
        }
        if (end == std::string_view::npos) break;
        begin = end + 1;
    }
    require(passed.size() == expected.size(),
            "Bazel did not report a passing summary for every selected native test.");
}

namespace {
struct DirectoryRestore {
    fs::path prior = fs::current_path();
    ~DirectoryRestore() { std::error_code ignored; fs::current_path(prior, ignored); }
};
} // namespace

int run_native_worker(const fs::path& checkout, const std::string& expected_tree) {
    require(checkout.is_absolute() && fs::canonical(checkout) == checkout &&
                (expected_tree.size() == 40 || expected_tree.size() == 64) &&
                expected_tree.find_first_not_of("0123456789abcdef") == std::string::npos,
            "The native worker needs a canonical checkout and staged tree ID.");
    const auto plan = prepare(checkout);
    require(plan.tree == expected_tree && plan.validate_native,
            "The native staged candidate changed before admission.");
    const auto checked = factory_launch::run_process(plan.command, 300s, 8 * 1024 * 1024,
                                                      nullptr, true);
    std::cout << checked.output << std::flush;
    require(checked.exit_code == 0, "The staged source or GDScript checker failed.");
    require(prepare(checkout).tree == expected_tree,
            "The staged candidate changed after source validation.");

    const fs::path artifacts(config(checkout, "factory.nativeArtifacts", true));
    const fs::path output_base(config(checkout, "factory.nativeOutputBase", true));
    const fs::path bazel(config(checkout, "factory.nativeBazelExecutable"));
    const auto expected_digest = config(checkout, "factory.nativeBazelSHA256");
    require(expected_digest.size() == 64 &&
                expected_digest.find_first_not_of("0123456789abcdef") == std::string::npos &&
                file_digest(bazel) == expected_digest,
            "The configured native Bazel executable does not match its local pin.");
    const auto toolchain = toolchain_key();
    struct stat output_identity{};
    require(output_base.is_absolute() && output_base.parent_path() == artifacts / "output" &&
                fs::canonical(output_base) == output_base &&
                ::lstat(output_base.c_str(), &output_identity) == 0 &&
                S_ISDIR(output_identity.st_mode) && output_identity.st_uid == ::geteuid() &&
                (output_identity.st_mode & 0077) == 0,
            "The native Bazel output base must be a private owned child of its artifact family.");
    const auto admission = resources::common_git_dir(checkout) / "factory-local-resources";
    auto snapshot = materialize_staged_tree(checkout, expected_tree, artifacts,
        [&](const auto& args) { return git(checkout, args); });
    const auto run = run_directory(artifacts, expected_tree);
    const auto selection = select_native_changes(snapshot.root(), plan.changed_paths);
    require(selection.required, "The staged native graph lost its required changed paths.");
    std::cout << "Native candidate " << expected_tree << ", toolchain " << toolchain
              << ", staged files " << snapshot.files() << '\n' << std::flush;

    {
        DirectoryRestore restore;
        fs::current_path(snapshot.root());
        const auto query = [&](const std::string& expression, const std::string& name) {
            auto command = bazel_command(bazel, artifacts, output_base, snapshot.root(), "query");
            command.insert(command.end(), {"--noimplicit_deps", "--notool_deps", "--output=label", expression});
            const auto log = run / (name + ".log");
            require(bazel_stage(artifacts, admission, log, command) == 0,
                    "The affected native Bazel query failed; see " + log.string());
            return native_labels_from_query(bounded_file(log, build_support::maximum_log));
        };
        const auto build_labels = query(selection.build_query, "build-query");
        const auto test_labels = query(selection.test_query, "test-query");
        auto build = bazel_command(bazel, artifacts, output_base, snapshot.root(), "build");
        build.push_back("--cxxopt=-DFACTORY_GATE_TOOLCHAIN_FINGERPRINT=0x" + toolchain.substr(0, 16));
        build.push_back("--jobs=8");
        build.insert(build.end(), build_labels.begin(), build_labels.end());
        require(bazel_stage(artifacts, admission, run / "build.log", build) == 0,
                "An affected native target failed to build.");
        auto test = bazel_command(bazel, artifacts, output_base, snapshot.root(), "test");
        test.push_back("--cxxopt=-DFACTORY_GATE_TOOLCHAIN_FINGERPRINT=0x" + toolchain.substr(0, 16));
        test.insert(test.end(), {"--jobs=8", "--build_tests_only", "--test_output=errors",
            "--build_event_json_file=" + (run / "test-events.json").string()});
        test.insert(test.end(), test_labels.begin(), test_labels.end());
        require(bazel_stage(artifacts, admission, run / "test.log", test) == 0,
                "An affected native behavioral test failed.");
        require_passing_test_events(bounded_file(run / "test-events.json", 8 * 1024 * 1024),
                                    test_labels);
    }
    snapshot.close();
    require(prepare(checkout).tree == expected_tree,
            "The staged candidate changed during native validation.");
    return 0;
}

} // namespace factory::commit_gate
