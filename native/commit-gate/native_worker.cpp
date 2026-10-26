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
#include <optional>
#include <set>
#include <stdexcept>
#include <string_view>
#include <utility>
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

namespace {
class TestSummaryEvent {
public:
    explicit TestSummaryEvent(std::string_view input) : input_(input) {}

    std::optional<std::pair<std::string_view, std::string_view>> parse() {
        value(Scope::root, 0);
        spaces();
        require(position_ == input_.size(), "Bazel returned a malformed test event.");
        if (!id_summary_ && !payload_) return std::nullopt;
        require(id_summary_ && payload_ && label_ && status_,
                "Bazel returned an incomplete test summary.");
        return std::pair{*label_, *status_};
    }

private:
    enum class Scope { other, root, id, id_summary, payload, label, status };
    std::string_view input_;
    std::size_t position_{};
    bool id_{};
    bool id_summary_{};
    bool payload_{};
    std::optional<std::string_view> label_;
    std::optional<std::string_view> status_;

    void spaces() {
        while (position_ < input_.size() &&
               (input_[position_] == ' ' || input_[position_] == '\t' ||
                input_[position_] == '\r' || input_[position_] == '\n')) ++position_;
    }

    bool take(char expected) {
        spaces();
        if (position_ < input_.size() && input_[position_] == expected) {
            ++position_;
            return true;
        }
        return false;
    }

    std::string_view quoted() {
        require(take('"'), "Bazel returned malformed JSON in a test event.");
        const auto begin = position_;
        while (position_ < input_.size()) {
            const unsigned char current = input_[position_++];
            if (current == '"') return input_.substr(begin, position_ - begin - 1);
            require(current >= 0x20, "Bazel returned a control byte in a test event.");
            if (current != '\\') continue;
            require(position_ < input_.size(), "Bazel returned a truncated JSON escape.");
            const char escaped = input_[position_++];
            if (escaped == 'u') {
                for (int digit = 0; digit < 4; ++digit) {
                    require(position_ < input_.size() &&
                            ((input_[position_] >= '0' && input_[position_] <= '9') ||
                             (input_[position_] >= 'a' && input_[position_] <= 'f') ||
                             (input_[position_] >= 'A' && input_[position_] <= 'F')),
                            "Bazel returned a malformed JSON unicode escape.");
                    ++position_;
                }
            } else {
                require(escaped == '"' || escaped == '\\' || escaped == '/' ||
                        escaped == 'b' || escaped == 'f' || escaped == 'n' ||
                        escaped == 'r' || escaped == 't',
                        "Bazel returned a malformed JSON escape.");
            }
        }
        throw std::runtime_error("Bazel returned a truncated JSON string.");
    }

    void literal(std::string_view token) {
        require(input_.substr(position_, token.size()) == token,
                "Bazel returned malformed JSON in a test event.");
        position_ += token.size();
    }

    void number() {
        if (input_[position_] == '-') ++position_;
        require(position_ < input_.size(), "Bazel returned a truncated JSON number.");
        if (input_[position_] == '0') ++position_;
        else {
            require(input_[position_] >= '1' && input_[position_] <= '9',
                    "Bazel returned a malformed JSON number.");
            while (position_ < input_.size() && input_[position_] >= '0' && input_[position_] <= '9')
                ++position_;
        }
        if (position_ < input_.size() && input_[position_] == '.') {
            ++position_;
            require(position_ < input_.size() && input_[position_] >= '0' && input_[position_] <= '9',
                    "Bazel returned a malformed JSON number.");
            while (position_ < input_.size() && input_[position_] >= '0' && input_[position_] <= '9')
                ++position_;
        }
        if (position_ < input_.size() && (input_[position_] == 'e' || input_[position_] == 'E')) {
            ++position_;
            if (position_ < input_.size() && (input_[position_] == '+' || input_[position_] == '-'))
                ++position_;
            require(position_ < input_.size() && input_[position_] >= '0' && input_[position_] <= '9',
                    "Bazel returned a malformed JSON number.");
            while (position_ < input_.size() && input_[position_] >= '0' && input_[position_] <= '9')
                ++position_;
        }
    }

    void value(Scope scope, int depth) {
        require(depth <= 64, "Bazel returned an over-nested test event.");
        spaces();
        require(position_ < input_.size(), "Bazel returned a truncated test event.");
        if (scope == Scope::label || scope == Scope::status) {
            const auto text = quoted();
            require(text.find('\\') == std::string_view::npos,
                    "Bazel escaped a test label or status unexpectedly.");
            auto& destination = scope == Scope::label ? label_ : status_;
            require(!destination, "Bazel repeated a test label or status.");
            destination = text;
        } else if (take('{')) {
            bool first = true;
            while (!take('}')) {
                require(first || take(','), "Bazel returned a malformed JSON object.");
                const auto key = quoted();
                require(take(':'), "Bazel returned a malformed JSON object.");
                Scope child = Scope::other;
                if (scope == Scope::root && key == "id") {
                    require(!id_, "Bazel repeated a test event ID.");
                    id_ = true;
                    child = Scope::id;
                }
                else if (scope == Scope::root && key == "testSummary") {
                    require(!payload_, "Bazel repeated a test summary payload.");
                    payload_ = true;
                    child = Scope::payload;
                } else if (scope == Scope::id && key == "testSummary") {
                    require(!id_summary_, "Bazel repeated a test summary ID.");
                    id_summary_ = true;
                    child = Scope::id_summary;
                } else if (scope == Scope::id_summary && key == "label") child = Scope::label;
                else if (scope == Scope::payload && key == "overallStatus") child = Scope::status;
                value(child, depth + 1);
                first = false;
            }
        } else if (scope == Scope::root || scope == Scope::id ||
                   scope == Scope::id_summary || scope == Scope::payload) {
            throw std::runtime_error("Bazel returned a malformed test summary object.");
        } else if (take('[')) {
            bool first = true;
            while (!take(']')) {
                require(first || take(','), "Bazel returned a malformed JSON array.");
                value(Scope::other, depth + 1);
                first = false;
            }
        } else if (input_[position_] == '"') (void)quoted();
        else if (input_[position_] == 't') literal("true");
        else if (input_[position_] == 'f') literal("false");
        else if (input_[position_] == 'n') literal("null");
        else number();
    }
};
} // namespace

std::vector<std::vector<std::string>> partition_native_labels(
    const std::vector<std::string>& labels,
    const std::vector<std::string>& fixed_arguments) {
    constexpr std::size_t maximum_arguments = 256;
    constexpr std::size_t maximum_argument_bytes = 131072;
    require(!labels.empty() && std::is_sorted(labels.begin(), labels.end()) &&
                std::adjacent_find(labels.begin(), labels.end()) == labels.end(),
            "The native targets must be a nonempty sorted unique selection.");
    std::size_t fixed_bytes = 0;
    for (const auto& argument : fixed_arguments) fixed_bytes += argument.size();
    require(fixed_arguments.size() < maximum_arguments && fixed_bytes < maximum_argument_bytes,
            "Native Bazel command options exceed the bounded runner allowance.");
    std::vector<std::vector<std::string>> batches;
    std::vector<std::string> current;
    std::size_t bytes = fixed_bytes;
    for (const auto& label : labels) {
        require(label.size() <= 65536 && label.size() + fixed_bytes <= maximum_argument_bytes,
                "A native target label exceeds the bounded runner allowance.");
        if (fixed_arguments.size() + current.size() == maximum_arguments ||
            bytes + label.size() > maximum_argument_bytes) {
            require(!current.empty(), "A native target could not fit a bounded command.");
            batches.push_back(std::move(current));
            current.clear();
            bytes = fixed_bytes;
        }
        current.push_back(label);
        bytes += label.size();
    }
    if (!current.empty()) batches.push_back(std::move(current));
    return batches;
}

void require_passing_test_events(std::string_view data,
                                 const std::vector<std::string>& expected) {
    require(data.size() <= 8 * 1024 * 1024 &&
                std::is_sorted(expected.begin(), expected.end()) && !expected.empty(),
            "The selected native test result is oversized or has invalid labels.");
    std::set<std::string> passed;
    for (std::size_t begin = 0; begin < data.size();) {
        const auto end = data.find('\n', begin);
        const std::string_view line(data.data() + begin,
            (end == std::string_view::npos ? data.size() : end) - begin);
        if (!line.empty()) {
            const auto event = TestSummaryEvent(line).parse();
            if (event) {
                const auto& [name, status] = *event;
                const std::string label(name);
                require(std::binary_search(expected.begin(), expected.end(), label) &&
                            status == "PASSED" && passed.insert(label).second,
                        "An affected native test was skipped, failed or summarized twice: " + label);
            }
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
    auto checker = plan.command;
    // The bounded utility runner clears Git environment variables. Restore only
    // the index selected by the outer hook, so partial commits check that tree.
    if (const char* index = std::getenv("GIT_INDEX_FILE")) {
        checker.insert(checker.begin(), "GIT_INDEX_FILE=" + std::string(index));
        checker.insert(checker.begin(), "/usr/bin/env");
    }
    const auto checked = factory_launch::run_process(checker, 300s, 8 * 1024 * 1024,
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
        const auto build_batches = partition_native_labels(build_labels, build);
        for (std::size_t index = 0; index < build_batches.size(); ++index) {
            auto command = build;
            command.insert(command.end(), build_batches[index].begin(), build_batches[index].end());
            const auto log = run / ("build-" + std::to_string(index) + ".log");
            require(bazel_stage(artifacts, admission, log, command) == 0,
                    "An affected native target batch failed to build; see " + log.string());
        }
        auto test = bazel_command(bazel, artifacts, output_base, snapshot.root(), "test");
        test.push_back("--cxxopt=-DFACTORY_GATE_TOOLCHAIN_FINGERPRINT=0x" + toolchain.substr(0, 16));
        test.insert(test.end(), {"--jobs=8", "--local_test_jobs=1", "--build_tests_only",
            "--test_output=errors"});
        auto sized_test = test;
        sized_test.push_back("--build_event_json_file=" +
            (run / ("test-events-" + std::to_string(test_labels.size()) + ".json")).string());
        const auto test_batches = partition_native_labels(test_labels, sized_test);
        for (std::size_t index = 0; index < test_batches.size(); ++index) {
            auto command = test;
            const auto events = run / ("test-events-" + std::to_string(index) + ".json");
            command.push_back("--build_event_json_file=" + events.string());
            command.insert(command.end(), test_batches[index].begin(), test_batches[index].end());
            const auto log = run / ("test-" + std::to_string(index) + ".log");
            require(bazel_stage(artifacts, admission, log, command) == 0,
                    "An affected native test batch failed; see " + log.string());
            require_passing_test_events(bounded_file(events, 8 * 1024 * 1024),
                                        test_batches[index]);
        }
    }
    snapshot.close();
    require(prepare(checkout).tree == expected_tree,
            "The staged candidate changed during native validation.");
    return 0;
}

} // namespace factory::commit_gate
