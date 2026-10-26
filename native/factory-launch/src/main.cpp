#include "factory/capture.hpp"

#include <iostream>
#include <map>
#include <stdexcept>

namespace {
volatile std::sig_atomic_t cancelled = 0;
void request_stop(int signal) { cancelled = signal; }
}

int main(int argc, char** argv) {
    using namespace factory_launch;
    try {
        struct sigaction action{};
        action.sa_handler = request_stop;
        ::sigemptyset(&action.sa_mask);
        if (::sigaction(SIGINT, &action, nullptr) != 0 || ::sigaction(SIGTERM, &action, nullptr) != 0)
            throw std::runtime_error("Cannot install local cancellation handlers.");
        if (argc == 2 && std::string(argv[1]) == "--help") {
            std::cout << "factory-project-capture --repo ABSOLUTE_REPOSITORY --tree FULL_OBJECT_ID --output FRESH_EXTERNAL_DIRECTORY [--profile complete|product]\n"
                      << "Capture raw tracked Godot inputs and hashes. No compiler, import or game is run.\n";
            return 0;
        }
        std::map<std::string, std::string> options;
        for (int i = 1; i < argc; i += 2) {
            const std::string name(argv[i]);
            if (i + 1 >= argc || (name != "--repo" && name != "--tree" && name != "--output" && name != "--profile")
                || !options.emplace(name, argv[i + 1]).second)
                throw std::runtime_error("Use each documented capture option at most once.");
        }
        if (!options.count("--repo") || !options.count("--tree") || !options.count("--output"))
            throw std::runtime_error("The repository, immutable object and fresh output are required.");
        CaptureOptions::Profile profile = CaptureOptions::Profile::complete;
        if (options.count("--profile")) {
            if (options.at("--profile") == "product") profile = CaptureOptions::Profile::product;
            else if (options.at("--profile") != "complete")
                throw std::runtime_error("Choose complete or product capture explicitly.");
        }
        const auto result = capture_project({options.at("--repo"), options.at("--tree"), options.at("--output"), &cancelled, profile});
        std::cout << "{\"status\":\"captured\",\"source_tree\":" << json_string(result.tree)
                  << ",\"files\":" << result.files << ",\"scripts\":" << result.scripts
                  << ",\"source_bytes\":" << result.source_bytes
                  << ",\"profile\":" << json_string(profile == CaptureOptions::Profile::product ? "product" : "complete")
                  << ",\"manifest\":" << json_string(result.manifest.string()) << ",\"engine_runs\":0}\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "{\"status\":\"fail\",\"error\":" << json_string(error.what()) << ",\"engine_runs\":0}\n";
        return cancelled == 0 ? 1 : 128 + cancelled;
    }
}
