#include "build.hpp"
#include <charconv>
#include <iostream>
#include <map>

namespace {
volatile std::sig_atomic_t cancelled = 0;
void stop(int value) { cancelled = value; }
}
int main(int argc, char** argv) {
    try {
        if (argc == 2 && std::string(argv[1]) == "--help") {
            std::cout << "factory-gameplay-build --checkout DIR --main DIR --bazel FILE --artifacts DIR --log FILE "
                         "--admission-directory DIR --launcher FILE --install-root DIR [--component startup]\n"
                         "Run through factory-local heavy once. Build the native World or startup and refresh launcher pins "
                         "only on source-matching success. No game is launched.\n";
            return 0;
        }
        std::map<std::string, std::string> args;
        for (int i = 1; i < argc; i += 2) {
            if (i + 1 == argc || !args.emplace(argv[i], argv[i + 1]).second) throw std::runtime_error("Invalid or duplicate option.");
        }
        if (args.size() != 8 && args.size() != 9)
            throw std::runtime_error("Use --help for the required options.");
        factory::gameplay_build::Options options;
        if (args.contains("--component")) {
            if (args.at("--component") != "startup") throw std::runtime_error("Unsupported build component.");
            options.component = factory::gameplay_build::Component::startup;
        }
        options.checkout = args.at("--checkout"); options.main_checkout = args.at("--main");
        options.bazel = args.at("--bazel"); options.launcher = args.at("--launcher");
        options.install_root = args.at("--install-root"); options.runner.artifacts = args.at("--artifacts");
        options.runner.log = args.at("--log"); options.runner.admission_directory = args.at("--admission-directory");
        options.runner.timeout = std::chrono::seconds(300);
        options.runner.owned_user_accounting = true;
        options.runner.cancellation = &cancelled;
        struct sigaction action{};
        action.sa_handler = stop;
        ::sigemptyset(&action.sa_mask);
        if (::sigaction(SIGINT, &action, nullptr) || ::sigaction(SIGTERM, &action, nullptr))
            throw std::runtime_error("Cannot install cancellation handlers.");
        const int exit = factory::gameplay_build::run(options);
        if (exit == 0) std::cout << "Native build and launcher installation succeeded. No game was started.\n";
        return exit;
    } catch (const std::exception& error) {
        std::cerr << "Gameplay build/install refused: " << error.what() << '\n';
        return 1;
    }
}
