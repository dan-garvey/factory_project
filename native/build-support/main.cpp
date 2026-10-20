#include "runner.hpp"

#include <charconv>
#include <iostream>
#include <limits>

namespace bs = factory::build_support;
namespace {
volatile std::sig_atomic_t cancelled = 0;
void stop(int value) { cancelled = value; }
std::uint64_t number(const std::string& text) {
    std::uint64_t value{};
    const auto result = std::from_chars(text.data(), text.data() + text.size(), value);
    if (result.ec != std::errc{} || result.ptr != text.data() + text.size()) throw bs::Error(bs::Reason::options);
    return value;
}
}
int main(int argc, char** argv) {
    try {
        bs::Options options;
        options.cancellation = &cancelled;
        std::vector<std::string> command;
        for (int i = 1; i < argc; ++i) {
            const std::string name(argv[i]);
            if (name == "--") { while (++i < argc) command.emplace_back(argv[i]); break; }
            if (++i == argc) throw bs::Error(bs::Reason::options);
            const std::string value(argv[i]);
            if (name == "--artifacts") options.artifacts = value;
            else if (name == "--log") options.log = value;
            else if (name == "--admission-directory") options.admission_directory = value;
            else if (name == "--accounting-mode") {
                if (value != "host" && value != "owned-user") throw bs::Error(bs::Reason::options);
                options.owned_user_accounting = value == "owned-user";
            }
            else if (name == "--seconds") {
                const auto seconds = number(value);
                if (seconds == 0 || seconds > 300) throw bs::Error(bs::Reason::options);
                options.timeout = std::chrono::seconds(seconds);
            } else if (name == "--artifact-bytes") options.artifact_limit = number(value);
            else if (name == "--log-bytes") options.log_limit = number(value);
            else if (name == "--jobs") {
                const auto jobs = number(value);
                if (jobs == 0 || jobs > 8) throw bs::Error(bs::Reason::options);
                options.jobs = static_cast<unsigned>(jobs);
            } else throw bs::Error(bs::Reason::options);
        }
        struct sigaction action{};
        action.sa_handler = stop;
        ::sigemptyset(&action.sa_mask);
        if (::sigaction(SIGINT, &action, nullptr) || ::sigaction(SIGTERM, &action, nullptr)) throw bs::Error(bs::Reason::options);
        const int code = bs::run(options, command);
        std::cout << "{\"status\":\"" << (code == 0 ? "pass" : "fail") << "\",\"child_exit\":" << code << "}\n";
        return std::cout ? code : 1;
    } catch (const bs::Error& error) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"" << bs::reason_name(error.reason()) << "\"}\n";
        return error.reason() == bs::Reason::timeout ? 124 : 1;
    } catch (...) {
        std::cerr << "{\"status\":\"fail\",\"reason\":\"unexpected\"}\n";
        return 1;
    }
}
