#include "fixture.hpp"
#include "native/build-support/runner.hpp"

#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <iostream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {
namespace fs = std::filesystem;
namespace bs = factory::build_support;
namespace fixture = factory::godot_fixture;

struct File {
    int value{-1};
    explicit File(int descriptor) : value(descriptor) {}
    ~File() { if (value >= 0) ::close(value); }
    File(const File&) = delete;
    File& operator=(const File&) = delete;
};

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

bool printable(const std::string& value) {
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return character >= 0x20 && character < 0x7f;
    });
}

bool digest_text(const std::string& value) {
    return value.size() == 64 &&
           std::all_of(value.begin(), value.end(), [](unsigned char character) {
               return (character >= '0' && character <= '9') || (character >= 'a' && character <= 'f');
           });
}

bool same_file(const struct stat& before, const struct stat& after) {
    return before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
           before.st_size == after.st_size && before.st_mtim.tv_sec == after.st_mtim.tv_sec &&
           before.st_mtim.tv_nsec == after.st_mtim.tv_nsec;
}

std::string executable_digest(const fs::path& path) {
    require(path.is_absolute() && fs::canonical(path) == path, "Use one canonical Godot executable.");
    File file(::open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
    require(file.value >= 0, "Cannot open the pinned Godot executable.");
    struct stat before{}, after{};
    require(::fstat(file.value, &before) == 0 && S_ISREG(before.st_mode) && before.st_size > 0 &&
            before.st_size <= 256LL * 1024 * 1024 && (before.st_mode & 0111) != 0,
            "The pinned Godot input must be an executable regular file within 256 MiB.");
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);
    require(context && EVP_DigestInit_ex(context.get(), EVP_sha256(), nullptr) == 1,
            "Cannot initialize the executable digest.");
    std::array<unsigned char, 65536> buffer{};
    std::uint64_t total = 0;
    while (true) {
        const auto count = ::read(file.value, buffer.data(), buffer.size());
        if (count < 0 && errno == EINTR) continue;
        require(count >= 0, "Cannot read the pinned Godot executable.");
        if (count == 0) break;
        total += static_cast<std::uint64_t>(count);
        require(total <= static_cast<std::uint64_t>(before.st_size) &&
                EVP_DigestUpdate(context.get(), buffer.data(), static_cast<std::size_t>(count)) == 1,
                "The pinned Godot executable changed during hashing.");
    }
    require(::fstat(file.value, &after) == 0 && same_file(before, after) &&
            total == static_cast<std::uint64_t>(before.st_size),
            "The pinned Godot executable changed during hashing.");
    std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
    unsigned length = 0;
    require(EVP_DigestFinal_ex(context.get(), digest.data(), &length) == 1 && length == 32,
            "Cannot finalize the executable digest.");
    constexpr char digits[] = "0123456789abcdef";
    std::string result;
    result.reserve(64);
    for (unsigned i = 0; i < length; ++i) {
        result.push_back(digits[digest[i] >> 4]);
        result.push_back(digits[digest[i] & 15]);
    }
    return result;
}

std::string read_log(const fs::path& path) {
    File file(::open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
    require(file.value >= 0, "Cannot read the retained fixture log.");
    struct stat before{}, after{};
    require(::fstat(file.value, &before) == 0 && S_ISREG(before.st_mode) && before.st_size >= 0 &&
            before.st_size <= 2LL * 1024 * 1024 && (before.st_mode & 0077) == 0,
            "The retained fixture log exceeds its type, size or privacy bound.");
    std::string content;
    content.reserve(static_cast<std::size_t>(before.st_size));
    std::array<char, 65536> buffer{};
    while (true) {
        const auto count = ::read(file.value, buffer.data(), buffer.size());
        if (count < 0 && errno == EINTR) continue;
        require(count >= 0 && content.size() + static_cast<std::size_t>(count) <= 2 * 1024 * 1024,
                "The retained fixture log changed or exceeded its byte bound.");
        if (count == 0) break;
        content.append(buffer.data(), static_cast<std::size_t>(count));
    }
    require(::fstat(file.value, &after) == 0 && same_file(before, after) &&
            content.size() == static_cast<std::size_t>(before.st_size),
            "The retained fixture log changed during verification.");
    return content;
}

unsigned seconds(const std::string& text) {
    unsigned result = 0;
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), result);
    require(parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size() &&
            result > 0 && result <= 300, "The fixture timeout must be 1 through 300 seconds.");
    return result;
}

volatile std::sig_atomic_t cancelled = 0;
void stop(int signal) { cancelled = signal; }
}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 2 && std::string(argv[1]) == "--help") {
            std::cout << "factory-godot-fixture --godot ABSOLUTE_BINARY --godot-sha256 SHA256 "
                         "--project CANONICAL_PROJECT --script res://PATH.gd --pass-line EXACT_LINE "
                         "--artifacts PRIVATE_ROOT --log FRESH_LOG --admission CANONICAL_DIRECTORY "
                         "[--seconds 1..300] [-- USER_ARGUMENTS...]\n"
                         "Run inside one factory-local heavy admission; import resources before fixture runs.\n";
            return 0;
        }
        std::map<std::string, std::string> options;
        std::vector<std::string> user_arguments;
        bool user_tail = false;
        for (int i = 1; i < argc; ++i) {
            const std::string name(argv[i]);
            if (name == "--") { user_tail = true; while (++i < argc) user_arguments.emplace_back(argv[i]); break; }
            require(i + 1 < argc && (name == "--godot" || name == "--godot-sha256" ||
                    name == "--project" || name == "--script" || name == "--pass-line" ||
                    name == "--artifacts" || name == "--log" || name == "--admission" ||
                    name == "--seconds") && options.emplace(name, argv[++i]).second,
                    "Use each documented fixture option exactly once.");
        }
        for (const auto* name : {"--godot", "--godot-sha256", "--project", "--script",
                                 "--pass-line", "--artifacts", "--log", "--admission"})
            require(options.count(name) == 1, "A required fixture option is missing.");
        require(user_arguments.size() <= 64, "Too many fixture user arguments.");
        for (const auto& argument : user_arguments)
            require(argument.size() <= 4096 && printable(argument), "Fixture user arguments must be printable and bounded.");
        const auto& expected = options.at("--pass-line");
        require(!expected.empty() && expected.size() <= 256 && printable(expected),
                "Use one exact printable PASS line.");
        const auto& pin = options.at("--godot-sha256");
        require(digest_text(pin) && executable_digest(options.at("--godot")) == pin,
                "The Godot executable does not match its exact SHA256 pin.");
        const fs::path project(options.at("--project"));
        require(project.is_absolute() && fs::canonical(project) == project &&
                fs::is_regular_file(fs::symlink_status(project / "project.godot")),
                "Use an existing canonical Godot project.");
        const auto& script = options.at("--script");
        require(script.starts_with("res://") && script.size() > 9 && printable(script),
                "Use a project-relative GDScript fixture.");
        const fs::path relative(script.substr(6));
        require(!relative.is_absolute() && relative.lexically_normal() == relative &&
                relative.extension() == ".gd" &&
                std::none_of(relative.begin(), relative.end(), [](const fs::path& component) {
                    return component == ".." || component == ".";
                }) && fs::is_regular_file(fs::symlink_status(project / relative)) &&
                fs::canonical(project / relative) == project / relative,
                "The fixture script must be a canonical project file.");
        struct sigaction action{};
        action.sa_handler = stop;
        ::sigemptyset(&action.sa_mask);
        require(::sigaction(SIGINT, &action, nullptr) == 0 && ::sigaction(SIGTERM, &action, nullptr) == 0,
                "Cannot install fixture cancellation handlers.");
        bs::Options run;
        run.artifacts = options.at("--artifacts");
        run.log = options.at("--log");
        run.admission_directory = options.at("--admission");
        run.log_limit = 2 * 1024 * 1024;
        run.artifact_limit = 128 * 1024 * 1024;
        run.timeout = std::chrono::seconds(options.count("--seconds") ? seconds(options.at("--seconds")) : 180);
        run.cancellation = &cancelled;
        std::vector<std::string> command{options.at("--godot"), "--headless", "--path", project.string(),
                                         "--script", script};
        if (user_tail) {
            command.emplace_back("--");
            command.insert(command.end(), user_arguments.begin(), user_arguments.end());
        }
        const int code = bs::run(run, command);
        const auto verdict = fixture::inspect_log(read_log(run.log), expected);
        if (code != 0 || verdict != fixture::Verdict::pass) {
            std::cerr << "Fixture refused: child_exit=" << code << " result=" << fixture::verdict_name(verdict)
                      << "; retained log: " << run.log << '\n';
            return 1;
        }
        std::cout << "Fixture passed: " << expected << "; retained log: " << run.log << '\n';
        return 0;
    } catch (const bs::Error& error) {
        std::cerr << "Fixture runner refused: " << bs::reason_name(error.reason()) << '\n';
        return 1;
    } catch (const std::exception& error) {
        std::cerr << "Fixture refused: " << error.what() << '\n';
        return 1;
    }
}
