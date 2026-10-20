#include "factory/capture.hpp"
#include "factory/opening.hpp"
#include "native/build-support/runner.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <map>
#include <optional>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

namespace {
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
using factory_launch::json_string;
volatile std::sig_atomic_t cancelled = 0;
void request_stop(int signal) { cancelled = signal; }

void require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}

struct Descriptor {
    int value;
    ~Descriptor() { if (value >= 0) ::close(value); }
};

std::string read_regular(const fs::path& path, std::size_t limit) {
    Descriptor file{::open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)};
    require(file.value >= 0, "Cannot open a regular pinned input.");
    struct stat before{}, after{};
    require(::fstat(file.value, &before) == 0 && S_ISREG(before.st_mode) && before.st_size >= 0 &&
            static_cast<std::uint64_t>(before.st_size) <= limit, "The pinned input exceeds its type or byte allowance.");
    std::string result;
    result.reserve(static_cast<std::size_t>(before.st_size));
    std::array<char, 65536> buffer{};
    while (true) {
        const auto count = ::read(file.value, buffer.data(), buffer.size());
        if (count < 0 && errno == EINTR) continue;
        require(count >= 0, "Cannot read a pinned input.");
        if (count == 0) break;
        require(static_cast<std::size_t>(count) <= limit - result.size(), "A pinned input grew beyond its allowance.");
        result.append(buffer.data(), static_cast<std::size_t>(count));
    }
    require(::fstat(file.value, &after) == 0 && before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
            before.st_size == after.st_size && result.size() == static_cast<std::size_t>(before.st_size) &&
            before.st_mtim.tv_sec == after.st_mtim.tv_sec && before.st_mtim.tv_nsec == after.st_mtim.tv_nsec,
            "A pinned input changed during its read.");
    return result;
}

void write_once(const fs::path& path, const std::string& content) {
    Descriptor file{::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600)};
    require(file.value >= 0, "Cannot create the fresh opening record.");
    std::size_t offset = 0;
    while (offset < content.size()) {
        const auto count = ::write(file.value, content.data() + offset, content.size() - offset);
        if (count < 0 && errno == EINTR) continue;
        require(count > 0, "Cannot finish the opening record.");
        offset += static_cast<std::size_t>(count);
    }
    require(::fsync(file.value) == 0, "Cannot retain the opening record.");
}

std::string json_arguments(const std::vector<std::string>& arguments) {
    std::string result = "[";
    for (std::size_t i = 0; i < arguments.size(); ++i)
        result += (i ? "," : "") + json_string(arguments[i]);
    return result + "]";
}

struct Stage {
    std::string name;
    bool attempted{false};
    std::optional<int> exit;
    std::string log_sha256;
};
} // namespace

int main(int argc, char** argv) {
    using namespace factory_launch;
    using namespace std::chrono_literals;
    fs::path output;
    bool owned_output = false;
    std::array<Stage, 2> stages{{{"import", false, {}, {}}, {"startup", false, {}, {}}}};
    const auto started = Clock::now();
    std::string error, source_tree, engine_digest, capture_digest, plan_digest;
    std::optional<factory_launch::OpeningResume> resume;
    std::vector<factory_launch::OpeningExternalResource> extension;
    std::string published_digest;
    try {
        struct sigaction action{};
        action.sa_handler = request_stop;
        ::sigemptyset(&action.sa_mask);
        require(::sigaction(SIGINT, &action, nullptr) == 0 && ::sigaction(SIGTERM, &action, nullptr) == 0,
                "Cannot install cancellation handlers.");
        if (argc == 2 && std::string(argv[1]) == "--help") {
            std::cout << "factory-opening-startup --repo ABSOLUTE_REPOSITORY --tree FULL_OBJECT_ID "
                         "--output FRESH_EXTERNAL_DIRECTORY --godot ABSOLUTE_ENGINE --engine-sha256 SHA256 "
                         "--admission CANONICAL_EXISTING_ADMISSION_DIRECTORY [--resume ORIGINAL_STORE_BINARY]\n"
                         "Optional compiled bridge: --native-descriptor FILE --native-descriptor-sha256 SHA256 "
                         "--native-descriptor-relative PROJECT_PATH --native-library FILE "
                         "--native-library-sha256 SHA256 --native-library-relative PROJECT_PATH\n"
                         "Run only through the original heavy admission wrapper. This headless startup "
                         "increment does not establish rendering, input, save/resume or user play.\n";
            return 0;
        }
        std::map<std::string, std::string> options;
        const std::array<std::string, 6> extension_names{
            "--native-descriptor", "--native-descriptor-sha256", "--native-descriptor-relative",
            "--native-library", "--native-library-sha256", "--native-library-relative"};
        for (int i = 1; i < argc; i += 2) {
            const std::string name(argv[i]);
            require(i + 1 < argc && (name == "--repo" || name == "--tree" || name == "--output" ||
                    name == "--godot" || name == "--engine-sha256" || name == "--admission" || name == "--resume" ||
                    std::find(extension_names.begin(), extension_names.end(), name) != extension_names.end()) &&
                    options.emplace(name, argv[i + 1]).second, "Use each documented startup option exactly once.");
        }
        require(options.count("--repo") && options.count("--tree") && options.count("--output") &&
                options.count("--godot") && options.count("--engine-sha256") && options.count("--admission"),
                "All six startup options are required.");
        require(!options.count("--resume") || !options.at("--resume").empty(), "Resume input must be explicit.");
        const auto extension_count = std::count_if(extension_names.begin(), extension_names.end(),
            [&](const auto& name) { return options.count(name) != 0; });
        require(extension_count == 0 || extension_count == 6,
                "Provide all six compiled-extension inputs together.");
        const fs::path engine(options.at("--godot"));
        output = options.at("--output");
        engine_digest = options.at("--engine-sha256");
        require(engine_digest.size() == 64 && std::all_of(engine_digest.begin(), engine_digest.end(), [](char value) {
            return (value >= '0' && value <= '9') || (value >= 'a' && value <= 'f');
        }), "Use a complete lowercase engine SHA256.");
        require(engine.is_absolute() && fs::canonical(engine) == engine && ::access(engine.c_str(), X_OK) == 0 &&
                sha256(read_regular(engine, 512 * 1024 * 1024)) == engine_digest,
                "The selected executable differs from the explicitly sealed engine.");
        const auto captured = capture_project({options.at("--repo"), options.at("--tree"), output, &cancelled});
        owned_output = true;
        source_tree = captured.tree;
        capture_digest = sha256(read_regular(captured.manifest, 2 * 1024 * 1024));
        require(fs::create_directory(output / "runtime"), "Cannot create the fresh runtime parent.");
        const auto copy = copy_opening_project(output / "project", output / "runtime/project");
        if (options.count("--resume"))
            resume = copy_opening_resume(options.at("--resume"), output / "incoming.factory");
        if (extension_count != 0)
            extension = copy_opening_extension(copy, {
                options.at("--native-descriptor"), options.at("--native-library"),
                options.at("--native-descriptor-relative"), options.at("--native-library-relative"),
                options.at("--native-descriptor-sha256"), options.at("--native-library-sha256")});
        const auto commands = opening_commands(engine, copy.runtime, output / "worksite.factory",
                                               resume ? resume->incoming : fs::path{});
        std::ostringstream plan;
        plan << "{\"schema\":1,\"kind\":\"headless_opening_startup_plan\",\"source_tree\":" << json_string(source_tree)
             << ",\"capture_sha256\":" << json_string(capture_digest) << ",\"engine_sha256\":" << json_string(engine_digest)
             << ",\"engine_path\":" << json_string(engine.string())
             << ",\"import_argv\":" << json_arguments(commands.import) << ",\"startup_argv\":" << json_arguments(commands.startup)
             << ",\"resume_input\":" << (resume ? json_string(resume->original.string()) : "null")
             << ",\"resume_sha256\":" << (resume ? json_string(resume->sha256) : "null")
             << ",\"deadline_seconds\":300,\"artifact_limit_bytes\":268435456,\"aggregate_log_limit_bytes\":8388608,"
                "\"maximum_engine_stages\":2,\"engine_stages_attempted_before_plan\":0,\"sources\":[";
        for (std::size_t i = 0; i < copy.sources.size(); ++i) {
            const auto& source = copy.sources[i];
            plan << (i ? "," : "") << "{\"path\":" << json_string(source.relative.string())
                 << ",\"sha256\":" << json_string(source.sha256) << ",\"bytes\":" << source.bytes << '}';
        }
        plan << "],\"native_resources\":[";
        for (std::size_t i = 0; i < extension.size(); ++i) {
            const auto& resource = extension[i];
            plan << (i ? "," : "") << "{\"path\":" << json_string(resource.relative.string())
                 << ",\"original\":" << json_string(resource.original.string())
                 << ",\"sha256\":" << json_string(resource.sha256) << ",\"bytes\":" << resource.bytes << '}';
        }
        plan << "]}\n";
        write_once(output / "launch-plan.json", plan.str());
        plan_digest = sha256(plan.str());
        for (std::size_t i = 0; i < stages.size(); ++i) {
            require(cancelled == 0, "The startup was cancelled.");
            verify_opening_sources(copy);
            if (resume) verify_opening_resume(*resume);
            if (!extension.empty()) verify_opening_extension(extension);
            require(sha256(read_regular(engine, 512 * 1024 * 1024)) == engine_digest,
                    "The engine changed before an opening stage.");
            const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(started + 300s - Clock::now());
            require(remaining.count() > 0, "The complete opening startup exceeded its deadline.");
            auto& stage = stages[i];
            factory::build_support::Options run;
            run.artifacts = output;
            run.log = output / (stage.name + ".log");
            run.admission_directory = options.at("--admission");
            run.timeout = std::min(remaining, std::chrono::duration_cast<std::chrono::milliseconds>(120s));
            run.artifact_limit = 256ULL * 1024 * 1024;
            run.log_limit = 4ULL * 1024 * 1024;
            run.cancellation = &cancelled;
            stage.attempted = true;
            stage.exit = factory::build_support::run(run, i == 0 ? commands.import : commands.startup);
            const auto log = read_regular(run.log, 4 * 1024 * 1024);
            stage.log_sha256 = sha256(log);
            verify_opening_sources(copy);
            if (resume) verify_opening_resume(*resume);
            if (!extension.empty()) verify_opening_extension(extension);
            require(sha256(read_regular(engine, 512 * 1024 * 1024)) == engine_digest,
                    "The engine changed during an opening stage.");
            require(*stage.exit == 0 && log.find("ERROR:") == std::string::npos,
                    "An opening stage failed; inspect the retained original stage log.");
        }
        require(cancelled == 0 && Clock::now() < started + 300s,
                "The startup was cancelled or exceeded its complete deadline.");
        if (resume) {
            const auto published = read_regular(output / "worksite.factory", 2 * 1024 * 1024);
            require(!published.empty(), "The resumed scene did not publish its new session save.");
            published_digest = sha256(published);
        }
    } catch (const std::exception& failure) { error = failure.what(); }

    if (owned_output) {
        try {
            std::ostringstream result;
            result << "{\"schema\":1,\"kind\":\"headless_opening_startup\",\"status\":"
                   << json_string(error.empty() ? "startup_exited" : "failed") << ",\"error\":" << json_string(error)
                   << ",\"source_tree\":" << json_string(source_tree) << ",\"capture_sha256\":" << json_string(capture_digest)
                   << ",\"launch_plan_sha256\":" << json_string(plan_digest) << ",\"engine_sha256\":" << json_string(engine_digest)
                   << ",\"resume_sha256\":" << (resume ? json_string(resume->sha256) : "null")
                   << ",\"published_save_sha256\":" << (published_digest.empty() ? "null" : json_string(published_digest))
                   << ",\"native_resource_count\":" << extension.size()
                   << ",\"user_play\":\"not_assessed\",\"rendering\":\"not_assessed\",\"stages\":[";
            for (std::size_t i = 0; i < stages.size(); ++i) {
                const auto& stage = stages[i];
                result << (i ? "," : "") << "{\"name\":" << json_string(stage.name)
                       << ",\"attempted\":" << (stage.attempted ? "true" : "false") << ",\"exit\":";
                if (stage.exit) result << *stage.exit; else result << "null";
                result << ",\"log_sha256\":" << json_string(stage.log_sha256) << '}';
            }
            result << "]}\n";
            write_once(output / "startup-result.json", result.str());
        } catch (...) {
            std::cerr << "Cannot retain the final startup record; partial artifacts remain.\n";
            return 1;
        }
    }
    if (!error.empty()) {
        std::cerr << "Native opening startup failed: " << error << '\n';
        return cancelled == 0 ? 1 : 128 + cancelled;
    }
    std::cout << "Headless opening startup exited; retained evidence is " << output / "startup-result.json" << '\n';
    return 0;
}
