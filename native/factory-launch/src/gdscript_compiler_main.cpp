#include "factory/capture.hpp"
#include "native/build-support/runner.hpp"

#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;
constexpr std::uint64_t artifact_limit = 128ULL * 1024 * 1024;
constexpr std::size_t script_limit = 160;
constexpr std::string_view godot_version = "4.7.2.stable.official.ed1daf0bf";

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

std::string read(const fs::path& path, std::uint64_t limit) {
    std::ifstream stream(path, std::ios::binary);
    require(static_cast<bool>(stream), "Cannot read the compiler artifact: " + path.string());
    std::string bytes;
    std::array<char, 8192> block{};
    while (stream.read(block.data(), block.size()) || stream.gcount()) {
        require(bytes.size() + static_cast<std::size_t>(stream.gcount()) <= limit,
                "The compiler log exceeds its bound.");
        bytes.append(block.data(), static_cast<std::size_t>(stream.gcount()));
    }
    require(stream.eof(), "Cannot finish reading the compiler artifact.");
    return bytes;
}

std::string digest(const fs::path& path) {
    std::ifstream stream(path, std::ios::binary);
    require(static_cast<bool>(stream), "Cannot hash the compiler input: " + path.string());
    EVP_MD_CTX* raw = EVP_MD_CTX_new();
    require(raw != nullptr, "Cannot initialize SHA-256.");
    const auto cleanup = [&] { EVP_MD_CTX_free(raw); };
    try {
        require(EVP_DigestInit_ex(raw, EVP_sha256(), nullptr) == 1, "Cannot initialize SHA-256.");
        std::array<char, 64 * 1024> block{};
        while (stream.read(block.data(), block.size()) || stream.gcount())
            require(EVP_DigestUpdate(raw, block.data(), static_cast<std::size_t>(stream.gcount())) == 1,
                    "Cannot hash the compiler input.");
        require(stream.eof(), "Cannot finish hashing the compiler input.");
        std::array<unsigned char, EVP_MAX_MD_SIZE> bytes{};
        unsigned length{};
        require(EVP_DigestFinal_ex(raw, bytes.data(), &length) == 1 && length == 32,
                "Cannot finish SHA-256.");
        constexpr char hex[] = "0123456789abcdef";
        std::string result;
        result.reserve(64);
        for (unsigned index = 0; index < length; ++index) {
            result += hex[bytes[index] >> 4];
            result += hex[bytes[index] & 15];
        }
        cleanup();
        return result;
    } catch (...) {
        cleanup();
        throw;
    }
}

std::map<std::string, std::string> source_hashes(const fs::path& project,
                                                  std::vector<std::string>& scripts) {
    std::map<std::string, std::string> hashes;
    for (const auto& entry : fs::recursive_directory_iterator(project)) {
        const auto relative = entry.path().lexically_relative(project);
        require(!entry.is_symlink(), "The captured project contains a symlink.");
        if (entry.is_directory()) continue;
        require(entry.is_regular_file() && hashes.size() < 512,
                "The captured project exceeds its regular-file allowance.");
        const auto name = relative.generic_string();
        require(relative.begin() != relative.end() && *relative.begin() != ".godot",
                "The pristine captured project contains generated cache.");
        hashes.emplace(name, digest(entry.path()));
        if (relative.extension() == ".gd") scripts.push_back(name);
    }
    std::sort(scripts.begin(), scripts.end());
    require(!scripts.empty() && scripts.size() <= script_limit,
            "Need 1..160 staged GDScript files in the supported project.");
    return hashes;
}

void verify_sources(const fs::path& project, const std::map<std::string, std::string>& hashes) {
    for (const auto& [name, expected] : hashes) {
        if (name == "project.godot") continue;
        require(fs::is_regular_file(fs::symlink_status(project / name)) &&
                    digest(project / name) == expected,
                "Godot changed a copied staged input: " + name);
    }
    for (const auto& entry : fs::recursive_directory_iterator(project)) {
        const auto relative = entry.path().lexically_relative(project);
        if (relative.begin() != relative.end() && *relative.begin() == ".godot") {
            continue;
        }
        require(!entry.is_symlink(), "Godot added a symlink outside its cache.");
        if (entry.is_directory()) continue;
        require(entry.is_regular_file(), "Godot added a nonregular file outside its cache.");
        require(relative.extension() != ".gd" || hashes.contains(relative.generic_string()),
                "Godot added a GDScript outside the immutable source roster.");
    }
}

struct Options {
    fs::path repository;
    fs::path godot;
    fs::path artifacts;
    fs::path admission;
    std::string tree;
    std::string sha256;
};

Options options(int argc, char** argv) {
    std::map<std::string, std::string> arguments;
    for (int index = 1; index < argc; index += 2) {
        require(index + 1 < argc, "Each native compiler option needs one value.");
        const std::string name(argv[index]);
        require(name == "--repo" || name == "--tree" || name == "--godot" ||
                    name == "--sha256" || name == "--artifacts" || name == "--admission",
                "Unknown native compiler option: " + name);
        require(arguments.emplace(name, argv[index + 1]).second,
                "A native compiler option was repeated: " + name);
    }
    require(arguments.size() == 6, "Require repo, tree, Godot pin, artifacts and admission directory.");
    Options result{arguments.at("--repo"), arguments.at("--godot"), arguments.at("--artifacts"),
                   arguments.at("--admission"), arguments.at("--tree"), arguments.at("--sha256")};
    require(result.repository.is_absolute() && fs::canonical(result.repository) == result.repository &&
                result.godot.is_absolute() && fs::canonical(result.godot) == result.godot &&
                fs::is_regular_file(result.godot) && result.artifacts.is_absolute() &&
                fs::canonical(result.artifacts) == result.artifacts &&
                result.admission.is_absolute() && fs::canonical(result.admission) == result.admission,
            "Use existing canonical absolute compiler inputs.");
    const auto hexadecimal = [](const std::string& value) {
        return value.find_first_not_of("0123456789abcdef") == std::string::npos;
    };
    require((result.tree.size() == 40 || result.tree.size() == 64) && hexadecimal(result.tree) &&
                result.sha256.size() == 64 && hexadecimal(result.sha256),
            "Use complete lowercase source-tree and engine SHA-256 pins.");
    struct stat status{};
    require(::lstat(result.artifacts.c_str(), &status) == 0 && S_ISDIR(status.st_mode) &&
                status.st_uid == ::geteuid() && (status.st_mode & 0077) == 0,
            "Use an owned mode-0700 external artifact directory.");
    require(fs::space(result.artifacts).available >= 22ULL * 1024 * 1024 * 1024,
            "Require 22 GiB free for the staged Godot compiler.");
    require(factory::build_support::owned_bytes(result.artifacts, artifact_limit) < artifact_limit,
            "The retained compiler artifacts already meet the 128 MiB allowance.");
    require(digest(result.godot) == result.sha256, "The installed Godot executable changed from its pin.");
    return result;
}

struct Stage {
    std::string name;
    int exit;
    std::string log_sha256;
};

void write_result(const fs::path& path, const std::string& status, const std::string& tree,
                  const std::string& engine_sha256, const std::string& manifest_sha256,
                  const std::vector<std::string>& scripts, std::size_t parsed_count,
                  const std::vector<Stage>& stages, const std::string& failed_stage,
                  const std::string& error) {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    require(static_cast<bool>(output), "Cannot retain the compiler result.");
    output << "{\"status\":" << factory_launch::json_string(status)
           << ",\"kind\":\"native_gdscript_parse_only\",\"source_tree\":"
           << factory_launch::json_string(tree) << ",\"engine_sha256\":"
           << factory_launch::json_string(engine_sha256) << ",\"capture_manifest_sha256\":"
           << factory_launch::json_string(manifest_sha256) << ",\"script_count\":" << scripts.size()
           << ",\"source_scripts\":[";
    for (std::size_t index = 0; index < scripts.size(); ++index)
        output << (index ? "," : "") << factory_launch::json_string(scripts[index]);
    output << "],\"parsed_scripts\":[";
    for (std::size_t index = 0; index < parsed_count; ++index)
        output << (index ? "," : "") << factory_launch::json_string(scripts[index]);
    output << "],\"stages\":[";
    for (std::size_t index = 0; index < stages.size(); ++index)
        output << (index ? "," : "") << "{\"name\":" << factory_launch::json_string(stages[index].name)
               << ",\"exit\":" << stages[index].exit << ",\"log_sha256\":"
               << factory_launch::json_string(stages[index].log_sha256) << '}';
    output << "],\"failed_stage\":" << factory_launch::json_string(failed_stage)
           << ",\"error\":" << factory_launch::json_string(error)
           << ",\"native_gameplay\":\"not_run\"}\n";
    require(static_cast<bool>(output), "Cannot finish the compiler result.");
}

int run(const Options& selected) {
    const auto started = Clock::now();
    const auto deadline = started + 300s;
    std::string template_path = (selected.artifacts / "parse-XXXXXX").string();
    std::vector<char> name(template_path.begin(), template_path.end());
    name.push_back('\0');
    require(::mkdtemp(name.data()) != nullptr, "Cannot create an owned compiler session.");
    const fs::path session(name.data());
    std::vector<Stage> stages;
    std::vector<std::string> scripts;
    std::string manifest_sha256;
    std::string active_stage;
    std::size_t parsed_count{};
    try {
        const auto captured = factory_launch::capture_project({selected.repository, selected.tree,
                                                                 session / "capture"});
        const auto project = captured.manifest.parent_path() / "project";
        manifest_sha256 = digest(captured.manifest);
        const auto hashes = source_hashes(project, scripts);
        require(captured.scripts == scripts.size(), "The native capture and compiler script rosters differ.");
        const auto execute = [&](const std::string& label, const std::vector<std::string>& arguments,
                                 std::chrono::milliseconds maximum) {
            active_stage = label;
            const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now());
            require(remaining.count() > 0, "The staged compiler exceeded its five-minute allowance.");
            factory::build_support::Options bounded;
            bounded.artifacts = selected.artifacts;
            bounded.log = session / (label + ".log");
            bounded.admission_directory = selected.admission;
            bounded.timeout = std::min(remaining, maximum);
            bounded.artifact_limit = artifact_limit;
            bounded.log_limit = 8 * 1024 * 1024;
            const int exit = factory::build_support::run(bounded, arguments);
            const auto log = read(bounded.log, bounded.log_limit);
            stages.push_back({label, exit, factory_launch::sha256(log)});
            require(exit == 0 && log.find("ERROR:") == std::string::npos &&
                        log.find("Parse Error") == std::string::npos &&
                        log.find("Failed to load script") == std::string::npos,
                    "The staged Godot compiler failed at " + label + "; inspect " + bounded.log.string());
            require(digest(selected.godot) == selected.sha256,
                    "The installed Godot executable changed during staged compilation.");
            active_stage.clear();
            return log;
        };
        std::string version = execute("version", {selected.godot.string(), "--version"}, 15s);
        while (!version.empty() && (version.back() == '\n' || version.back() == '\r')) version.pop_back();
        require(version == godot_version, "The pinned Godot binary has the wrong runtime version.");
        execute("import", {selected.godot.string(), "--headless", "--editor", "--path",
                           project.string(), "--import"}, 180s);
        for (std::size_t index = 0; index < scripts.size(); ++index) {
            const auto label = "script-" + std::to_string(index);
            execute(label, {selected.godot.string(), "--headless", "--path", project.string(),
                            "--check-only", "--script", "res://" + scripts[index]}, 30s);
            ++parsed_count;
        }
        verify_sources(project, hashes);
        require(Clock::now() < deadline, "The staged compiler exceeded its five-minute allowance.");
        write_result(session / "result.json", "pass", captured.tree, selected.sha256,
                     manifest_sha256, scripts, parsed_count, stages, "", "");
        std::cout << "Parsed " << scripts.size() << " immutable staged GDScripts with the native checker; "
                  << "this is not runtime/gameplay evidence\n";
        return 0;
    } catch (const std::exception& error) {
        write_result(session / "result.json", "fail", selected.tree, selected.sha256,
                     manifest_sha256, scripts, parsed_count, stages, active_stage, error.what());
        std::cerr << "Native staged GDScript compilation failed: " << error.what() << '\n';
        return 1;
    }
}
}  // namespace

int main(int argc, char** argv) {
    try { return run(options(argc, argv)); }
    catch (const std::exception& error) {
        std::cerr << "Native staged GDScript compiler refused: " << error.what() << '\n';
        return 2;
    }
}
